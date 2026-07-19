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

import com.azure.storage.common.sas.AccountSasPermission;
import com.azure.storage.common.sas.AccountSasResourceType;
import com.azure.storage.common.sas.AccountSasService;
import com.azure.storage.common.sas.AccountSasSignatureValues;
import com.azure.storage.common.sas.SasIpRange;
import com.azure.storage.common.sas.SasProtocol;
import com.azure.storage.file.share.models.UserDelegationKey;
import com.azure.storage.file.share.sas.ShareFileSasPermission;
import com.azure.storage.file.share.sas.ShareSasPermission;
import com.azure.storage.file.share.sas.ShareServiceSasSignatureValues;
import io.ballerina.runtime.api.Environment;
import io.ballerina.runtime.api.utils.StringUtils;
import io.ballerina.runtime.api.values.BArray;
import io.ballerina.runtime.api.values.BMap;
import io.ballerina.runtime.api.values.BObject;
import io.ballerina.runtime.api.values.BString;

/**
 * Native implementations of the SAS-generation operations. Every operation signs locally
 * (with the account key or a user-delegation key); no request reaches Azure, but signing
 * still runs through {@link Ops#invoke} so failures surface as typed errors.
 */
public final class SasOps {

    private SasOps() {
    }

    public static Object generateShareSas(Environment env, BObject self, BMap<BString, Object> values) {
        return Ops.invoke(env, () -> StringUtils.fromString(
                Ops.shareClient(self).generateSas(shareSasValues(values, true))));
    }

    public static Object generateSas(Environment env, BObject self, BString path, BMap<BString, Object> values) {
        return Ops.invoke(env, () -> StringUtils.fromString(
                FileOps.fileClient(self, path).generateSas(shareSasValues(values, false))));
    }

    public static Object generateShareUserDelegationSas(Environment env, BObject self,
            BMap<BString, Object> values, BMap<BString, Object> key) {
        return Ops.invoke(env, () -> StringUtils.fromString(
                Ops.shareClient(self).generateUserDelegationSas(shareSasValues(values, true), delegationKey(key))));
    }

    public static Object generateUserDelegationSas(Environment env, BObject self, BString path,
            BMap<BString, Object> values, BMap<BString, Object> key) {
        return Ops.invoke(env, () -> StringUtils.fromString(FileOps.fileClient(self, path)
                .generateUserDelegationSas(shareSasValues(values, false), delegationKey(key))));
    }

    public static Object generateAccountSas(Environment env, BObject self, BMap<BString, Object> values) {
        return Ops.invoke(env, () -> {
            @SuppressWarnings("unchecked")
            BMap<BString, Object> permissions = (BMap<BString, Object>) values.get(Constants.PERMISSIONS);
            AccountSasPermission sasPermission = new AccountSasPermission()
                    .setReadPermission(permissions.getBooleanValue(Constants.PERMISSION_READ))
                    .setWritePermission(permissions.getBooleanValue(Constants.PERMISSION_WRITE))
                    .setDeletePermission(permissions.getBooleanValue(Constants.PERMISSION_DELETE))
                    .setListPermission(permissions.getBooleanValue(Constants.PERMISSION_LIST))
                    .setAddPermission(permissions.getBooleanValue(Constants.PERMISSION_ADD))
                    .setCreatePermission(permissions.getBooleanValue(Constants.PERMISSION_CREATE))
                    .setUpdatePermission(permissions.getBooleanValue(Constants.PERMISSION_UPDATE))
                    .setProcessMessages(permissions.getBooleanValue(Constants.PERMISSION_PROCESS));
            @SuppressWarnings("unchecked")
            BMap<BString, Object> resourceTypes = (BMap<BString, Object>) values.get(Constants.RESOURCE_TYPES);
            AccountSasResourceType sasResourceTypes = new AccountSasResourceType()
                    .setService(resourceTypes.getBooleanValue(Constants.RESOURCE_SERVICE))
                    .setContainer(resourceTypes.getBooleanValue(Constants.RESOURCE_CONTAINER))
                    .setObject(resourceTypes.getBooleanValue(Constants.RESOURCE_OBJECT));
            // This connector is Files-scoped, so the SAS is minted for the file service alone.
            AccountSasSignatureValues sdkValues = new AccountSasSignatureValues(
                    ValueUtils.fromUtc((BArray) values.get(Constants.EXPIRY_TIME)),
                    sasPermission,
                    new AccountSasService().setFileAccess(true),
                    sasResourceTypes);
            applyCommon(values, sdkValues::setStartTime, sdkValues::setProtocol, sdkValues::setSasIpRange);
            return StringUtils.fromString(Ops.serviceClient(self).generateAccountSas(sdkValues));
        });
    }

    private static ShareServiceSasSignatureValues shareSasValues(BMap<BString, Object> values, boolean shareScope) {
        @SuppressWarnings("unchecked")
        BMap<BString, Object> permissions = (BMap<BString, Object>) values.get(Constants.PERMISSIONS);
        java.time.OffsetDateTime expiry = ValueUtils.fromUtc((BArray) values.get(Constants.EXPIRY_TIME));
        ShareServiceSasSignatureValues sdkValues;
        if (shareScope) {
            sdkValues = new ShareServiceSasSignatureValues(expiry, new ShareSasPermission()
                    .setReadPermission(permissions.getBooleanValue(Constants.PERMISSION_READ))
                    .setCreatePermission(permissions.getBooleanValue(Constants.PERMISSION_CREATE))
                    .setWritePermission(permissions.getBooleanValue(Constants.PERMISSION_WRITE))
                    .setDeletePermission(permissions.getBooleanValue(Constants.PERMISSION_DELETE))
                    .setListPermission(permissions.getBooleanValue(Constants.PERMISSION_LIST)));
        } else {
            sdkValues = new ShareServiceSasSignatureValues(expiry, new ShareFileSasPermission()
                    .setReadPermission(permissions.getBooleanValue(Constants.PERMISSION_READ))
                    .setCreatePermission(permissions.getBooleanValue(Constants.PERMISSION_CREATE))
                    .setWritePermission(permissions.getBooleanValue(Constants.PERMISSION_WRITE))
                    .setDeletePermission(permissions.getBooleanValue(Constants.PERMISSION_DELETE)));
        }
        applyCommon(values, sdkValues::setStartTime, sdkValues::setProtocol, sdkValues::setSasIpRange);
        String identifier = ValueUtils.optString(values, Constants.IDENTIFIER);
        if (identifier != null) {
            sdkValues.setIdentifier(identifier);
        }
        return sdkValues;
    }

    private static void applyCommon(BMap<BString, Object> values,
            java.util.function.Function<java.time.OffsetDateTime, ?> setStartTime,
            java.util.function.Function<SasProtocol, ?> setProtocol,
            java.util.function.Function<SasIpRange, ?> setIpRange) {
        Object startTime = values.get(Constants.START_TIME);
        if (startTime != null) {
            setStartTime.apply(ValueUtils.fromUtc((BArray) startTime));
        }
        String protocol = ValueUtils.optString(values, Constants.PROTOCOL);
        if (protocol != null) {
            setProtocol.apply("https".equals(protocol) ? SasProtocol.HTTPS_ONLY : SasProtocol.HTTPS_HTTP);
        }
        String ipRange = ValueUtils.optString(values, Constants.IP_RANGE);
        if (ipRange != null) {
            setIpRange.apply(SasIpRange.parse(ipRange));
        }
    }

    private static UserDelegationKey delegationKey(BMap<BString, Object> key) {
        return new UserDelegationKey()
                .setSignedObjectId(key.getStringValue(Constants.SIGNED_OBJECT_ID).getValue())
                .setSignedTenantId(key.getStringValue(Constants.SIGNED_TENANT_ID).getValue())
                .setSignedStart(ValueUtils.fromUtc((BArray) key.get(Constants.SIGNED_START)))
                .setSignedExpiry(ValueUtils.fromUtc((BArray) key.get(Constants.SIGNED_EXPIRY)))
                .setSignedService(key.getStringValue(Constants.SIGNED_SERVICE).getValue())
                .setSignedVersion(key.getStringValue(Constants.SIGNED_VERSION).getValue())
                .setValue(key.getStringValue(Constants.VALUE).getValue());
    }
}
