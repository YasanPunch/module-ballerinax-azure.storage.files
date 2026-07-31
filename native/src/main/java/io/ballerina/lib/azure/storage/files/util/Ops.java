/*
 * Copyright (c) 2026, WSO2 LLC. (http://www.wso2.com).
 *
 * WSO2 LLC. licenses this file to you under the Apache License,
 * Version 2.0 (the "License"); you may not use this file except
 * in compliance with the License.
 * You may obtain a copy of the License at
 *
 *    http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing,
 * software distributed under the License is distributed on an
 * "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
 * KIND, either express or implied. See the License for the
 * specific language governing permissions and limitations
 * under the License.
 */

package io.ballerina.lib.azure.storage.files.util;

import com.azure.core.http.HttpPipeline;
import com.azure.core.http.HttpPipelineBuilder;
import com.azure.core.http.policy.HttpPipelinePolicy;
import com.azure.core.util.UrlBuilder;
import com.azure.storage.file.share.ShareClient;
import com.azure.storage.file.share.ShareClientBuilder;
import com.azure.storage.file.share.ShareServiceClient;
import com.azure.storage.file.share.models.ShareStorageException;
import io.ballerina.runtime.api.Environment;
import io.ballerina.runtime.api.values.BError;
import io.ballerina.runtime.api.values.BObject;
import io.ballerina.runtime.api.values.BString;

import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;
import java.util.function.Supplier;

/**
 * Shared plumbing for the native operations: runs the blocking SDK call off the Ballerina
 * scheduler via {@link Environment#yieldAndRun}, converts every failure to a typed Ballerina
 * error, and fetches the SDK clients stored on the Ballerina client objects.
 */
public final class Ops {

    // Keys under which client-lifecycle state is stored on client objects.
    public static final String NATIVE_SERVICE_CLIENT = "serviceClient";
    public static final String NATIVE_SHARE_CLIENT = "shareClient";
    public static final String NATIVE_CLOSED = "closed";
    // The query parameter that addresses a share snapshot on the wire.
    private static final String SHARE_SNAPSHOT_PARAM = "sharesnapshot";

    private Ops() {
    }

    /**
     * Runs a blocking operation body and maps its outcome to a Ballerina value.
     *
     * @param env  the Ballerina runtime environment
     * @param body the operation body; its return value is passed through verbatim
     * @return the body's result, or the mapped Ballerina error on failure
     */
    public static Object invoke(Environment env, Supplier<Object> body) {
        return env.yieldAndRun(() -> {
            try {
                return body.get();
            } catch (ShareStorageException e) {
                return ErrorMapper.toBError(e);
            } catch (BError e) {
                return e;
            } catch (Exception e) {
                return FilesErrorCreator.processingError(describe(e), e);
            }
        });
    }

    /** Builds a human-readable message for an unexpected local exception. */
    public static String describe(Throwable t) {
        return t.getMessage() == null ? t.getClass().getSimpleName() : t.getMessage();
    }

    /**
     * Returns the {@code ShareServiceClient} stored on a client object.
     *
     * @param self the Ballerina client object
     * @return the SDK service client
     */
    public static ShareServiceClient serviceClient(BObject self) {
        ensureOpen(self);
        return (ShareServiceClient) self.getNativeData(NATIVE_SERVICE_CLIENT);
    }

    /**
     * Returns the {@code ShareClient} stored on a share-bound client object.
     *
     * @param self the Ballerina client object
     * @return the SDK share client
     */
    public static ShareClient shareClient(BObject self) {
        ensureOpen(self);
        return (ShareClient) self.getNativeData(NATIVE_SHARE_CLIENT);
    }

    /**
     * Returns the {@code ShareClient} for the live share, or for one of its snapshots when a
     * snapshot id is given.
     *
     * <p>The snapshot client is rebuilt with an extra pipeline policy that appends the
     * {@code sharesnapshot} query parameter to any request missing it. The SDK's download path
     * hard-codes that parameter to {@code null}, so without the policy every content read from
     * a snapshot client silently serves the live file.
     *
     * @param self       the Ballerina client object
     * @param snapshotId the snapshot to read from, or {@code null} for the live share
     * @return the SDK share client
     */
    public static ShareClient shareClient(BObject self, String snapshotId) {
        ShareClient base = shareClient(self);
        if (snapshotId == null) {
            return base;
        }
        String encodedId = URLEncoder.encode(snapshotId, StandardCharsets.UTF_8);
        HttpPipelinePolicy ensureSnapshotParam = (context, next) -> {
            UrlBuilder url = UrlBuilder.parse(context.getHttpRequest().getUrl());
            if (!url.getQuery().containsKey(SHARE_SNAPSHOT_PARAM)) {
                url.setQueryParameter(SHARE_SNAPSHOT_PARAM, encodedId);
                context.getHttpRequest().setUrl(url.toString());
            }
            return next.process();
        };
        HttpPipeline pipeline = base.getHttpPipeline();
        // The parameter must be on the URL before the credential policy signs the request
        // (shared-key signatures cover the canonicalized query), so the policy is inserted
        // ahead of the first credential policy rather than appended.
        List<HttpPipelinePolicy> policies = new ArrayList<>();
        int insertAt = -1;
        for (int i = 0; i < pipeline.getPolicyCount(); i++) {
            HttpPipelinePolicy policy = pipeline.getPolicy(i);
            if (insertAt == -1 && policy.getClass().getSimpleName().contains("Credential")) {
                insertAt = i;
            }
            policies.add(policy);
        }
        policies.add(insertAt == -1 ? policies.size() : insertAt, ensureSnapshotParam);
        return new ShareClientBuilder()
                .pipeline(new HttpPipelineBuilder()
                        .policies(policies.toArray(new HttpPipelinePolicy[0]))
                        .httpClient(pipeline.getHttpClient())
                        .build())
                .endpoint(base.getAccountUrl())
                .shareName(base.getShareName())
                .snapshot(snapshotId)
                .buildClient();
    }

    private static void ensureOpen(BObject self) {
        if (Boolean.TRUE.equals(self.getNativeData(NATIVE_CLOSED))) {
            throw FilesErrorCreator.processingError("the client is closed", null);
        }
    }

    /**
     * Normalizes a share-relative path for the SDK: strips the leading slash and rejects an
     * empty result.
     *
     * @param path the combined slash-delimited path
     * @return the SDK-form path, relative to the share root without a leading slash
     */
    public static String filePath(BString path) {
        String p = trimSlashes(path.getValue());
        if (p.isEmpty()) {
            throw FilesErrorCreator.processingError("the path must name a file, not the share root", null);
        }
        return p;
    }

    /**
     * Normalizes a directory path for the SDK. An empty path or {@code /} addresses the share
     * root directory.
     *
     * @param path the combined slash-delimited path
     * @return the SDK-form path; empty string for the share root
     */
    public static String directoryPath(BString path) {
        return trimSlashes(path.getValue());
    }

    private static String trimSlashes(String p) {
        String result = p.strip();
        while (result.startsWith("/")) {
            result = result.substring(1);
        }
        while (result.endsWith("/")) {
            result = result.substring(0, result.length() - 1);
        }
        return result;
    }
}
