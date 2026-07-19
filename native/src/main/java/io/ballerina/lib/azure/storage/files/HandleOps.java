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

import com.azure.core.util.Context;
import com.azure.storage.file.share.ShareDirectoryClient;
import com.azure.storage.file.share.ShareFileClient;
import com.azure.storage.file.share.models.CloseHandlesInfo;
import com.azure.storage.file.share.models.HandleItem;
import io.ballerina.runtime.api.Environment;
import io.ballerina.runtime.api.values.BArray;
import io.ballerina.runtime.api.values.BObject;
import io.ballerina.runtime.api.values.BString;

/**
 * Native implementations of the {@code Client} SMB-handle operations.
 */
public final class HandleOps {

    private HandleOps() {
    }

    public static Object listFileHandles(Environment env, BObject self, BString path) {
        return Ops.invoke(env, () -> {
            BArray result = RecordMapper.recordArray(Constants.RECORD_HANDLE_INFO);
            for (HandleItem item : FileOps.fileClient(self, path).listHandles()) {
                result.append(RecordMapper.handleInfo(item));
            }
            return result;
        });
    }

    public static Object forceCloseFileHandles(Environment env, BObject self, BString path, Object handleId) {
        return Ops.invoke(env, () -> {
            ShareFileClient client = FileOps.fileClient(self, path);
            CloseHandlesInfo info = handleId == null
                    ? client.forceCloseAllHandles(null, Context.NONE)
                    : client.forceCloseHandle(((BString) handleId).getValue());
            return RecordMapper.closeHandlesInfo(info);
        });
    }

    public static Object listDirectoryHandles(Environment env, BObject self, BString directoryPath) {
        return Ops.invoke(env, () -> {
            BArray result = RecordMapper.recordArray(Constants.RECORD_HANDLE_INFO);
            for (HandleItem item : directoryClient(self, directoryPath)
                    .listHandles(null, false, null, Context.NONE)) {
                result.append(RecordMapper.handleInfo(item));
            }
            return result;
        });
    }

    public static Object forceCloseDirectoryHandles(Environment env, BObject self, BString directoryPath,
            Object handleId, boolean recursive) {
        return Ops.invoke(env, () -> {
            ShareDirectoryClient client = directoryClient(self, directoryPath);
            CloseHandlesInfo info = handleId == null
                    ? client.forceCloseAllHandles(recursive, null, Context.NONE)
                    : client.forceCloseHandle(((BString) handleId).getValue());
            return RecordMapper.closeHandlesInfo(info);
        });
    }

    private static ShareDirectoryClient directoryClient(BObject self, BString directoryPath) {
        String path = Ops.directoryPath(directoryPath);
        return path.isEmpty()
                ? Ops.shareClient(self).getRootDirectoryClient()
                : Ops.shareClient(self).getDirectoryClient(path);
    }
}
