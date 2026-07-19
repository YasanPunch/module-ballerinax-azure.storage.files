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

import com.azure.storage.file.share.models.ShareAccessPolicy;
import com.azure.storage.file.share.models.ShareSignedIdentifier;
import io.ballerina.runtime.api.Environment;
import io.ballerina.runtime.api.utils.StringUtils;
import io.ballerina.runtime.api.values.BArray;
import io.ballerina.runtime.api.values.BMap;
import io.ballerina.runtime.api.values.BObject;
import io.ballerina.runtime.api.values.BString;

import java.util.ArrayList;
import java.util.List;

/**
 * Native implementations of the {@code Client} stored-access-policy and SDDL-permission
 * operations on the bound share.
 */
public final class PolicyOps {

    private PolicyOps() {
    }

    public static Object getShareAccessPolicy(Environment env, BObject self) {
        return Ops.invoke(env, () -> {
            BArray result = RecordMapper.recordArray(Constants.RECORD_SIGNED_IDENTIFIER);
            for (ShareSignedIdentifier identifier : Ops.shareClient(self).getAccessPolicy()) {
                result.append(RecordMapper.signedIdentifier(identifier));
            }
            return result;
        });
    }

    public static Object setShareAccessPolicy(Environment env, BObject self, BArray identifiers) {
        return Ops.invoke(env, () -> {
            List<ShareSignedIdentifier> sdkIdentifiers = new ArrayList<>();
            for (int i = 0; i < identifiers.size(); i++) {
                @SuppressWarnings("unchecked")
                BMap<BString, Object> record = (BMap<BString, Object>) identifiers.get(i);
                @SuppressWarnings("unchecked")
                BMap<BString, Object> policy = (BMap<BString, Object>) record.get(Constants.ACCESS_POLICY);
                ShareAccessPolicy sdkPolicy = new ShareAccessPolicy()
                        .setPermissions(record(policy, Constants.PERMISSIONS));
                Object startsOn = policy.get(Constants.STARTS_ON);
                if (startsOn != null) {
                    sdkPolicy.setStartsOn(ValueUtils.fromUtc((BArray) startsOn));
                }
                Object expiresOn = policy.get(Constants.EXPIRES_ON);
                if (expiresOn != null) {
                    sdkPolicy.setExpiresOn(ValueUtils.fromUtc((BArray) expiresOn));
                }
                sdkIdentifiers.add(new ShareSignedIdentifier()
                        .setId(record.getStringValue(Constants.ID).getValue())
                        .setAccessPolicy(sdkPolicy));
            }
            Ops.shareClient(self).setAccessPolicy(sdkIdentifiers);
            return null;
        });
    }

    public static Object getSharePermission(Environment env, BObject self, BString permissionKey) {
        return Ops.invoke(env, () ->
                StringUtils.fromString(Ops.shareClient(self).getPermission(permissionKey.getValue())));
    }

    public static Object createSharePermission(Environment env, BObject self, BString sddlPermission) {
        return Ops.invoke(env, () ->
                StringUtils.fromString(Ops.shareClient(self).createPermission(sddlPermission.getValue())));
    }

    private static String record(BMap<BString, Object> map, BString key) {
        BString value = map.getStringValue(key);
        return value == null ? null : value.getValue();
    }
}
