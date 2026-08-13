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

package io.ballerina.lib.azure.storage.files.client;

import com.azure.core.http.HttpHeaderName;
import com.azure.core.http.rest.Response;
import com.azure.core.util.Context;
import com.azure.storage.file.share.options.ShareAcquireLeaseOptions;
import com.azure.storage.file.share.options.ShareBreakLeaseOptions;
import com.azure.storage.file.share.specialized.ShareLeaseClient;
import com.azure.storage.file.share.specialized.ShareLeaseClientBuilder;
import io.ballerina.lib.azure.storage.files.util.BallerinaAzureClient;
import io.ballerina.lib.azure.storage.files.util.FilesErrorCreator;
import io.ballerina.runtime.api.Environment;
import io.ballerina.runtime.api.utils.StringUtils;
import io.ballerina.runtime.api.values.BObject;
import io.ballerina.runtime.api.values.BString;

import java.time.Duration;

/**
 * Native implementations of the {@code Client} lease operations. The SDK models leases through
 * the per-resource {@code ShareLeaseClient}, so each operation builds one around the stored
 * share or file client and the caller-supplied lease id.
 */
public final class LeaseOps {

    private LeaseOps() {
    }

    private static final HttpHeaderName LEASE_TIME = HttpHeaderName.fromString("x-ms-lease-time");
    private static final int INFINITE_LEASE = -1;

    private static ShareLeaseClient shareLease(BObject self, String leaseId) {
        return new ShareLeaseClientBuilder().shareClient(BallerinaAzureClient.getShareClient(self))
                .leaseId(leaseId).buildClient();
    }

    private static ShareLeaseClient fileLease(BObject self, BString path, String leaseId) {
        return new ShareLeaseClientBuilder()
                .fileClient(BallerinaAzureClient.getShareClient(self)
                        .getFileClient(BallerinaAzureClient.filePath(path)))
                .leaseId(leaseId)
                .buildClient();
    }

    private static String proposedId(Object proposedLeaseId) {
        return proposedLeaseId == null ? null : ((BString) proposedLeaseId).getValue();
    }

    /** Acquires a lease on the bound share and returns the lease id. */
    public static Object acquireShareLease(Environment env, BObject self, long leaseDurationSeconds,
            Object proposedLeaseId) {
        return BallerinaAzureClient.invoke(env, () -> {
            if (leaseDurationSeconds != INFINITE_LEASE && (leaseDurationSeconds < 15 || leaseDurationSeconds > 60)) {
                throw FilesErrorCreator.clientError(
                        "the lease duration must be 15 to 60 seconds, or -1 for an infinite lease", null);
            }
            String id = shareLease(self, proposedId(proposedLeaseId))
                    .acquireLeaseWithResponse(new ShareAcquireLeaseOptions()
                            .setDuration((int) leaseDurationSeconds), null, Context.NONE)
                    .getValue();
            return StringUtils.fromString(id);
        });
    }

    /** Renews a share lease. */
    public static Object renewShareLease(Environment env, BObject self, BString leaseId) {
        return BallerinaAzureClient.invoke(env, () -> {
            shareLease(self, leaseId.getValue()).renewLease();
            return null;
        });
    }

    /** Releases a share lease. */
    public static Object releaseShareLease(Environment env, BObject self, BString leaseId) {
        return BallerinaAzureClient.invoke(env, () -> {
            shareLease(self, leaseId.getValue()).releaseLease();
            return null;
        });
    }

    /** Breaks the share's lease and returns the remaining break period in seconds. */
    public static Object breakShareLease(Environment env, BObject self, Object breakPeriodSeconds) {
        return BallerinaAzureClient.invoke(env, () -> {
            ShareBreakLeaseOptions options = new ShareBreakLeaseOptions();
            if (breakPeriodSeconds != null) {
                options.setBreakPeriod(Duration.ofSeconds((Long) breakPeriodSeconds));
            }
            Response<Void> response =
                    shareLease(self, null).breakLeaseWithResponse(options, null, Context.NONE);
            String leaseTime = response.getHeaders().getValue(LEASE_TIME);
            return leaseTime == null ? 0L : Long.parseLong(leaseTime);
        });
    }

    /** Changes a share lease to the proposed id and returns the new lease id. */
    public static Object changeShareLease(Environment env, BObject self, BString leaseId, BString proposedLeaseId) {
        return BallerinaAzureClient.invoke(env, () -> {
            String changed = shareLease(self, leaseId.getValue()).changeLease(proposedLeaseId.getValue());
            return StringUtils.fromString(changed);
        });
    }

    /** Acquires an infinite lease on a file and returns the lease id. */
    public static Object acquireLease(Environment env, BObject self, BString path, Object proposedLeaseId) {
        return BallerinaAzureClient.invoke(env, () -> {
            String id = fileLease(self, path, proposedId(proposedLeaseId))
                    .acquireLeaseWithResponse(new ShareAcquireLeaseOptions()
                            .setDuration(INFINITE_LEASE), null, Context.NONE)
                    .getValue();
            return StringUtils.fromString(id);
        });
    }

    /** Releases a file lease. */
    public static Object releaseLease(Environment env, BObject self, BString path, BString leaseId) {
        return BallerinaAzureClient.invoke(env, () -> {
            fileLease(self, path, leaseId.getValue()).releaseLease();
            return null;
        });
    }

    /** Breaks a file's lease regardless of who holds it. */
    public static Object breakLease(Environment env, BObject self, BString path) {
        return BallerinaAzureClient.invoke(env, () -> {
            fileLease(self, path, null).breakLease();
            return null;
        });
    }

    /** Changes a file lease to the proposed id and returns the new lease id. */
    public static Object changeLease(Environment env, BObject self, BString path, BString leaseId,
            BString proposedLeaseId) {
        return BallerinaAzureClient.invoke(env, () -> {
            String changed = fileLease(self, path, leaseId.getValue()).changeLease(proposedLeaseId.getValue());
            return StringUtils.fromString(changed);
        });
    }
}
