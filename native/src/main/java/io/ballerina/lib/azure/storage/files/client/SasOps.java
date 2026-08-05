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
import io.ballerina.lib.azure.storage.files.util.RecordMapper;
import io.ballerina.lib.azure.storage.files.util.SdkInvoker;
import io.ballerina.lib.azure.storage.files.util.ValueUtils;
import io.ballerina.runtime.api.Environment;
import io.ballerina.runtime.api.utils.StringUtils;
import io.ballerina.runtime.api.values.BArray;
import io.ballerina.runtime.api.values.BMap;
import io.ballerina.runtime.api.values.BObject;
import io.ballerina.runtime.api.values.BString;

import java.time.OffsetDateTime;
import java.util.function.Function;

/**
 * Native implementations of the SAS-generation operations. Every operation signs locally
 * (with the account key or a user-delegation key); no request reaches Azure, but signing
 * still runs through {@link SdkInvoker#invoke} so failures surface as typed errors.
 */
public final class SasOps {

    // The Ballerina SasProtocol enum value selecting HTTPS-only access.
    private static final String SAS_PROTOCOL_HTTPS = "https";

    // Field names of the SAS signature-values and permission records (read only here).
    private static final BString EXPIRY_TIME = StringUtils.fromString("expiryTime");
    private static final BString START_TIME = StringUtils.fromString("startTime");
    private static final BString IP_RANGE = StringUtils.fromString("ipRange");
    private static final BString IDENTIFIER = StringUtils.fromString("identifier");
    private static final BString RESOURCE_TYPES = StringUtils.fromString("resourceTypes");
    private static final BString PERMISSION_READ = StringUtils.fromString("read");
    private static final BString PERMISSION_WRITE = StringUtils.fromString("write");
    private static final BString PERMISSION_DELETE = StringUtils.fromString("delete");
    private static final BString PERMISSION_LIST = StringUtils.fromString("list");
    private static final BString PERMISSION_ADD = StringUtils.fromString("add");
    private static final BString PERMISSION_CREATE = StringUtils.fromString("create");
    private static final BString PERMISSION_UPDATE = StringUtils.fromString("update");
    private static final BString PERMISSION_PROCESS = StringUtils.fromString("process");
    private static final BString RESOURCE_SERVICE = StringUtils.fromString("service");
    private static final BString RESOURCE_CONTAINER = StringUtils.fromString("container");
    private static final BString RESOURCE_OBJECT = StringUtils.fromString("object");

    private SasOps() {
    }

    /** Generates a service SAS token scoped to the bound share. */
    public static Object generateShareSas(Environment env, BObject self, BMap<BString, Object> values) {
        return SdkInvoker.invoke(env, () -> StringUtils.fromString(
                SdkInvoker.shareClient(self).generateSas(shareSasValues(values, true))));
    }

    /** Generates a service SAS token scoped to one file. */
    public static Object generateSas(Environment env, BObject self, BString path, BMap<BString, Object> values) {
        return SdkInvoker.invoke(env, () -> StringUtils.fromString(
                FileOps.fileClient(self, path).generateSas(shareSasValues(values, false))));
    }

    /** Generates a user-delegation SAS token scoped to the bound share. */
    public static Object generateShareUserDelegationSas(Environment env, BObject self,
            BMap<BString, Object> values, BMap<BString, Object> key) {
        return SdkInvoker.invoke(env, () -> StringUtils.fromString(
                SdkInvoker.shareClient(self).generateUserDelegationSas(shareSasValues(values, true),
                        delegationKey(key))));
    }

    /** Generates a user-delegation SAS token scoped to one file. */
    public static Object generateUserDelegationSas(Environment env, BObject self, BString path,
            BMap<BString, Object> values, BMap<BString, Object> key) {
        return SdkInvoker.invoke(env, () -> StringUtils.fromString(FileOps.fileClient(self, path)
                .generateUserDelegationSas(shareSasValues(values, false), delegationKey(key))));
    }

    /** Generates an account SAS token for the file service. */
    public static Object generateAccountSas(Environment env, BObject self, BMap<BString, Object> values) {
        return SdkInvoker.invoke(env, () -> {
            @SuppressWarnings("unchecked")
            BMap<BString, Object> permissions = (BMap<BString, Object>) values.get(RecordMapper.PERMISSIONS);
            AccountSasPermission sasPermission = new AccountSasPermission()
                    .setReadPermission(permissions.getBooleanValue(PERMISSION_READ))
                    .setWritePermission(permissions.getBooleanValue(PERMISSION_WRITE))
                    .setDeletePermission(permissions.getBooleanValue(PERMISSION_DELETE))
                    .setListPermission(permissions.getBooleanValue(PERMISSION_LIST))
                    .setAddPermission(permissions.getBooleanValue(PERMISSION_ADD))
                    .setCreatePermission(permissions.getBooleanValue(PERMISSION_CREATE))
                    .setUpdatePermission(permissions.getBooleanValue(PERMISSION_UPDATE))
                    .setProcessMessages(permissions.getBooleanValue(PERMISSION_PROCESS));
            @SuppressWarnings("unchecked")
            BMap<BString, Object> resourceTypes = (BMap<BString, Object>) values.get(RESOURCE_TYPES);
            AccountSasResourceType sasResourceTypes = new AccountSasResourceType()
                    .setService(resourceTypes.getBooleanValue(RESOURCE_SERVICE))
                    .setContainer(resourceTypes.getBooleanValue(RESOURCE_CONTAINER))
                    .setObject(resourceTypes.getBooleanValue(RESOURCE_OBJECT));
            // This connector is Files-scoped, so the SAS is minted for the file service alone.
            AccountSasSignatureValues sdkValues = new AccountSasSignatureValues(
                    ValueUtils.fromUtc((BArray) values.get(EXPIRY_TIME)),
                    sasPermission,
                    new AccountSasService().setFileAccess(true),
                    sasResourceTypes);
            applyCommon(values, sdkValues::setStartTime, sdkValues::setProtocol, sdkValues::setSasIpRange);
            return StringUtils.fromString(SdkInvoker.serviceClient(self).generateAccountSas(sdkValues));
        });
    }

    private static ShareServiceSasSignatureValues shareSasValues(BMap<BString, Object> values, boolean shareScope) {
        @SuppressWarnings("unchecked")
        BMap<BString, Object> permissions = (BMap<BString, Object>) values.get(RecordMapper.PERMISSIONS);
        OffsetDateTime expiry = ValueUtils.fromUtc((BArray) values.get(EXPIRY_TIME));
        ShareServiceSasSignatureValues sdkValues;
        if (shareScope) {
            sdkValues = new ShareServiceSasSignatureValues(expiry, new ShareSasPermission()
                    .setReadPermission(permissions.getBooleanValue(PERMISSION_READ))
                    .setCreatePermission(permissions.getBooleanValue(PERMISSION_CREATE))
                    .setWritePermission(permissions.getBooleanValue(PERMISSION_WRITE))
                    .setDeletePermission(permissions.getBooleanValue(PERMISSION_DELETE))
                    .setListPermission(permissions.getBooleanValue(PERMISSION_LIST)));
        } else {
            sdkValues = new ShareServiceSasSignatureValues(expiry, new ShareFileSasPermission()
                    .setReadPermission(permissions.getBooleanValue(PERMISSION_READ))
                    .setCreatePermission(permissions.getBooleanValue(PERMISSION_CREATE))
                    .setWritePermission(permissions.getBooleanValue(PERMISSION_WRITE))
                    .setDeletePermission(permissions.getBooleanValue(PERMISSION_DELETE)));
        }
        applyCommon(values, sdkValues::setStartTime, sdkValues::setProtocol, sdkValues::setSasIpRange);
        String identifier = ValueUtils.optString(values, IDENTIFIER);
        if (identifier != null) {
            sdkValues.setIdentifier(identifier);
        }
        return sdkValues;
    }

    private static void applyCommon(BMap<BString, Object> values,
            Function<OffsetDateTime, ?> setStartTime,
            Function<SasProtocol, ?> setProtocol,
            Function<SasIpRange, ?> setIpRange) {
        Object startTime = values.get(START_TIME);
        if (startTime != null) {
            setStartTime.apply(ValueUtils.fromUtc((BArray) startTime));
        }
        String protocol = ValueUtils.optString(values, RecordMapper.PROTOCOL);
        if (protocol != null) {
            setProtocol.apply(SAS_PROTOCOL_HTTPS.equals(protocol) ? SasProtocol.HTTPS_ONLY : SasProtocol.HTTPS_HTTP);
        }
        String ipRange = ValueUtils.optString(values, IP_RANGE);
        if (ipRange != null) {
            setIpRange.apply(SasIpRange.parse(ipRange));
        }
    }

    private static UserDelegationKey delegationKey(BMap<BString, Object> key) {
        return new UserDelegationKey()
                .setSignedObjectId(key.getStringValue(RecordMapper.SIGNED_OBJECT_ID).getValue())
                .setSignedTenantId(key.getStringValue(RecordMapper.SIGNED_TENANT_ID).getValue())
                .setSignedStart(ValueUtils.fromUtc((BArray) key.get(RecordMapper.SIGNED_START)))
                .setSignedExpiry(ValueUtils.fromUtc((BArray) key.get(RecordMapper.SIGNED_EXPIRY)))
                .setSignedService(key.getStringValue(RecordMapper.SIGNED_SERVICE).getValue())
                .setSignedVersion(key.getStringValue(RecordMapper.SIGNED_VERSION).getValue())
                .setValue(key.getStringValue(RecordMapper.VALUE).getValue());
    }
}
