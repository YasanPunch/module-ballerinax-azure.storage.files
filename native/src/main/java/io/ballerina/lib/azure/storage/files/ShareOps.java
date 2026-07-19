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

import io.ballerina.runtime.api.Environment;
import io.ballerina.runtime.api.values.BMap;
import io.ballerina.runtime.api.values.BObject;
import io.ballerina.runtime.api.values.BString;

/**
 * Native implementations of the {@code Client} operations on the bound share itself.
 */
public final class ShareOps {

    private ShareOps() {
    }

    public static Object getShareProperties(Environment env, BObject self) {
        return Ops.invoke(env, () -> RecordMapper.shareProperties(Ops.shareClient(self).getProperties()));
    }

    public static Object setShareMetadata(Environment env, BObject self, BMap<BString, BString> metadata) {
        return Ops.invoke(env, () -> {
            Ops.shareClient(self).setMetadata(ValueUtils.toStringMap(metadata));
            return null;
        });
    }

    public static Object getShareUsage(Environment env, BObject self) {
        return Ops.invoke(env, () -> Ops.shareClient(self).getStatistics().getShareUsageInBytes());
    }
}
