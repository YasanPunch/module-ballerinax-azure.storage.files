/*
 * Copyright (c) 2026, WSO2 LLC. (https://www.wso2.com).
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

package io.ballerina.lib.azure.storage.files;

import com.azure.storage.file.share.ShareClient;
import com.azure.storage.file.share.ShareServiceClient;
import com.azure.storage.file.share.models.ShareStorageException;
import io.ballerina.runtime.api.Environment;
import io.ballerina.runtime.api.values.BError;
import io.ballerina.runtime.api.values.BObject;
import io.ballerina.runtime.api.values.BString;

import java.util.function.Supplier;

/**
 * Shared plumbing for the native operations: runs the blocking SDK call off the Ballerina
 * scheduler via {@link Environment#yieldAndRun}, converts every failure to a typed Ballerina
 * error, and fetches the SDK clients stored on the Ballerina client objects.
 */
final class Ops {

    private Ops() {
    }

    /**
     * Runs a blocking operation body and maps its outcome to a Ballerina value.
     *
     * @param env  the Ballerina runtime environment
     * @param body the operation body; its return value is passed through verbatim
     * @return the body's result, or the mapped Ballerina error on failure
     */
    static Object invoke(Environment env, Supplier<Object> body) {
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
    static String describe(Throwable t) {
        return t.getMessage() == null ? t.getClass().getSimpleName() : t.getMessage();
    }

    /**
     * Returns the {@code ShareServiceClient} stored on a client object.
     *
     * @param self the Ballerina client object
     * @return the SDK service client
     */
    static ShareServiceClient serviceClient(BObject self) {
        ensureOpen(self);
        return (ShareServiceClient) self.getNativeData(Constants.NATIVE_SERVICE_CLIENT);
    }

    /**
     * Returns the {@code ShareClient} stored on a share-bound client object.
     *
     * @param self the Ballerina client object
     * @return the SDK share client
     */
    static ShareClient shareClient(BObject self) {
        ensureOpen(self);
        return (ShareClient) self.getNativeData(Constants.NATIVE_SHARE_CLIENT);
    }

    private static void ensureOpen(BObject self) {
        if (Boolean.TRUE.equals(self.getNativeData(Constants.NATIVE_CLOSED))) {
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
    static String filePath(BString path) {
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
    static String directoryPath(BString path) {
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
