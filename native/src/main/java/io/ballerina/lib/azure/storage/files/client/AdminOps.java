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

import com.azure.storage.file.share.ShareServiceClient;
import com.azure.storage.file.share.models.ListSharesOptions;
import com.azure.storage.file.share.models.ShareAccessTier;
import com.azure.storage.file.share.models.ShareItem;
import com.azure.storage.file.share.models.ShareProtocols;
import com.azure.storage.file.share.models.ShareRequestConditions;
import com.azure.storage.file.share.models.ShareRootSquash;
import com.azure.storage.file.share.models.ShareServiceProperties;
import com.azure.storage.file.share.models.ShareSnapshotsDeleteOptionType;
import com.azure.storage.file.share.models.UserDelegationKey;
import com.azure.storage.file.share.options.ShareCreateOptions;
import com.azure.storage.file.share.options.ShareDeleteOptions;
import io.ballerina.lib.azure.storage.files.util.BallerinaAzureClient;
import io.ballerina.lib.azure.storage.files.util.OptionsReader;
import io.ballerina.lib.azure.storage.files.util.RecordMapper;
import io.ballerina.lib.azure.storage.files.util.ValueUtils;
import io.ballerina.runtime.api.Environment;
import io.ballerina.runtime.api.values.BArray;
import io.ballerina.runtime.api.values.BMap;
import io.ballerina.runtime.api.values.BObject;
import io.ballerina.runtime.api.values.BString;

/**
 * Native implementations of the {@code AdminClient} share-management operations.
 */
public final class AdminOps {

    // The Ballerina DeleteSnapshots enum value that also deletes leased snapshots.
    private static final String DELETE_SNAPSHOTS_INCLUDE_LEASED = "include-leased";

    private AdminOps() {
    }

    /**
     * Checks whether the named share exists; {@code false} only on a confirmed 404. The SDK's
     * {@code exists()} always yields a real boolean (404 folds to false, other failures throw).
     */
    public static Object hasShare(Environment env, BObject self, BString shareName) {
        return BallerinaAzureClient.invoke(env, () -> BallerinaAzureClient.getServiceClient(self)
                .getShareClient(shareName.getValue()).exists());
    }

    /** Lists the shares in the storage account as an array of {@code ShareInfo} records. */
    public static Object listShares(Environment env, BObject self, Object options) {
        return BallerinaAzureClient.invoke(env, () -> {
            ListSharesOptions sdkOptions = new ListSharesOptions();
            if (options != null) {
                @SuppressWarnings("unchecked")
                BMap<BString, Object> record = (BMap<BString, Object>) options;
                sdkOptions.setPrefix(ValueUtils.optString(record, OptionsReader.PREFIX))
                        .setIncludeMetadata(record.getBooleanValue(OptionsReader.INCLUDE_METADATA))
                        .setIncludeSnapshots(record.getBooleanValue(OptionsReader.INCLUDE_SNAPSHOTS))
                        .setIncludeDeleted(record.getBooleanValue(OptionsReader.INCLUDE_DELETED));
            }
            BArray result = RecordMapper.recordArray(RecordMapper.RECORD_SHARE_INFO);
            for (ShareItem item : BallerinaAzureClient.getServiceClient(self).listShares(sdkOptions, null, null)) {
                result.append(RecordMapper.shareInfo(item));
            }
            return result;
        });
    }

    /** Creates a new share with the given options. */
    public static Object createShare(Environment env, BObject self, BString shareName, Object options) {
        return BallerinaAzureClient.invoke(env, () -> {
            ShareCreateOptions sdkOptions = new ShareCreateOptions();
            if (options != null) {
                @SuppressWarnings("unchecked")
                BMap<BString, Object> record = (BMap<BString, Object>) options;
                sdkOptions.setMetadata(ValueUtils.optStringMap(record, OptionsReader.METADATA));
                Object quota = record.get(OptionsReader.QUOTA_IN_GB);
                if (quota != null) {
                    sdkOptions.setQuotaInGb(Math.toIntExact((Long) quota));
                }
                String tier = ValueUtils.optString(record, OptionsReader.ACCESS_TIER);
                if (tier != null) {
                    sdkOptions.setAccessTier(ShareAccessTier.fromString(tier));
                }
                Object protocols = record.get(OptionsReader.ENABLED_PROTOCOLS);
                if (protocols != null) {
                    BArray array = (BArray) protocols;
                    ShareProtocols sdkProtocols = new ShareProtocols();
                    for (int i = 0; i < array.size(); i++) {
                        String protocol = array.getBString(i).getValue();
                        if (RecordMapper.PROTOCOL_SMB.equals(protocol)) {
                            sdkProtocols.setSmbEnabled(true);
                        } else if (RecordMapper.PROTOCOL_NFS.equals(protocol)) {
                            sdkProtocols.setNfsEnabled(true);
                        }
                    }
                    sdkOptions.setProtocols(sdkProtocols);
                }
                String rootSquash = ValueUtils.optString(record, OptionsReader.ROOT_SQUASH);
                if (rootSquash != null) {
                    sdkOptions.setRootSquash(ShareRootSquash.fromString(rootSquash));
                }
            }
            BallerinaAzureClient.getServiceClient(self)
                    .createShareWithResponse(shareName.getValue(), sdkOptions, null, null);
            return null;
        });
    }

    /** Deletes a share, one of its snapshots, or the share together with its snapshots. */
    public static Object deleteShare(Environment env, BObject self, BString shareName, Object options) {
        return BallerinaAzureClient.invoke(env, () -> {
            ShareServiceClient serviceClient = BallerinaAzureClient.getServiceClient(self);
            if (options == null) {
                serviceClient.deleteShare(shareName.getValue());
                return null;
            }
            @SuppressWarnings("unchecked")
            BMap<BString, Object> record = (BMap<BString, Object>) options;
            String snapshotId = ValueUtils.optString(record, OptionsReader.SNAPSHOT_ID);
            if (snapshotId != null) {
                serviceClient.deleteShareWithResponse(shareName.getValue(), snapshotId, null, null);
                return null;
            }
            ShareDeleteOptions sdkOptions = new ShareDeleteOptions();
            String deleteSnapshots = ValueUtils.optString(record, OptionsReader.DELETE_SNAPSHOTS);
            if (deleteSnapshots != null) {
                sdkOptions.setDeleteSnapshotsOptions(DELETE_SNAPSHOTS_INCLUDE_LEASED.equals(deleteSnapshots)
                        ? ShareSnapshotsDeleteOptionType.INCLUDE_WITH_LEASED
                        : ShareSnapshotsDeleteOptionType.INCLUDE);
            }
            String leaseId = ValueUtils.optString(record, OptionsReader.LEASE_ID);
            if (leaseId != null) {
                sdkOptions.setRequestConditions(new ShareRequestConditions().setLeaseId(leaseId));
            }
            serviceClient.getShareClient(shareName.getValue()).deleteWithResponse(sdkOptions, null, null);
            return null;
        });
    }

    /** Restores a soft-deleted share identified by its name and delete version. */
    public static Object undeleteShare(Environment env, BObject self, BString shareName, BString version) {
        return BallerinaAzureClient.invoke(env, () -> {
            BallerinaAzureClient.getServiceClient(self).undeleteShare(shareName.getValue(), version.getValue());
            return null;
        });
    }

    /** Fetches the account's file-service properties as a {@code ServiceProperties} record. */
    public static Object getServiceProperties(Environment env, BObject self) {
        return BallerinaAzureClient.invoke(env, () ->
                RecordMapper.serviceProperties(BallerinaAzureClient.getServiceClient(self).getProperties()));
    }

    /** Replaces the account's file-service properties. */
    public static Object setServiceProperties(Environment env, BObject self, BMap<BString, Object> properties) {
        return BallerinaAzureClient.invoke(env, () -> {
            ShareServiceProperties sdkProperties = OptionsReader.serviceProperties(properties);
            BallerinaAzureClient.getServiceClient(self).setProperties(sdkProperties);
            return null;
        });
    }

    /** Requests a user-delegation key valid for the given time window. */
    public static Object getUserDelegationKey(Environment env, BObject self, BArray startTime, BArray expiryTime) {
        return BallerinaAzureClient.invoke(env, () -> {
            UserDelegationKey key = BallerinaAzureClient.getServiceClient(self)
                    .getUserDelegationKey(ValueUtils.fromUtc(startTime), ValueUtils.fromUtc(expiryTime));
            return RecordMapper.userDelegationKey(key);
        });
    }
}
