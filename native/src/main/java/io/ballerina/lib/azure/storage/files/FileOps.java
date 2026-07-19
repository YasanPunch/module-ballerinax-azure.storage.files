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

import com.azure.storage.file.share.ShareFileClient;
import com.azure.storage.file.share.models.ShareFileHttpHeaders;
import com.azure.storage.file.share.options.ShareFileCreateOptions;
import io.ballerina.runtime.api.Environment;
import io.ballerina.runtime.api.values.BMap;
import io.ballerina.runtime.api.values.BObject;
import io.ballerina.runtime.api.values.BString;

/**
 * Native implementations of the basic {@code Client} file operations.
 */
public final class FileOps {

    private FileOps() {
    }

    public static Object createFile(Environment env, BObject self, BString path, long sizeInBytes, Object options) {
        return Ops.invoke(env, () -> {
            fileClient(self, path).createWithResponse(createOptions(sizeInBytes, options), null, null);
            return null;
        });
    }

    public static Object deleteFile(Environment env, BObject self, BString path) {
        return Ops.invoke(env, () -> {
            fileClient(self, path).delete();
            return null;
        });
    }

    public static Object hasFile(Environment env, BObject self, BString path) {
        return Ops.invoke(env, () -> Boolean.TRUE.equals(fileClient(self, path).exists()));
    }

    public static Object getFileProperties(Environment env, BObject self, BString path) {
        return Ops.invoke(env, () -> RecordMapper.fileProperties(fileClient(self, path).getProperties()));
    }

    public static Object setFileMetadata(Environment env, BObject self, BString path,
                                         BMap<BString, BString> metadata) {
        return Ops.invoke(env, () -> {
            fileClient(self, path).setMetadata(ValueUtils.toStringMap(metadata));
            return null;
        });
    }

    public static Object setContentHeaders(Environment env, BObject self, BString path,
                                           BMap<BString, Object> headers) {
        return Ops.invoke(env, () -> {
            ShareFileClient client = fileClient(self, path);
            long currentSize = client.getProperties().getContentLength();
            ShareFileHttpHeaders sdkHeaders = OptionsReader.contentHeaders(headers);
            client.setProperties(currentSize, sdkHeaders, null, null);
            return null;
        });
    }

    public static Object renameFile(Environment env, BObject self, BString sourcePath,
                                    BString destinationPath, Object options) {
        return Ops.invoke(env, () -> {
            String source = Ops.filePath(sourcePath);
            String destination = Ops.filePath(destinationPath);
            Ops.shareClient(self).getFileClient(source)
                    .renameWithResponse(DirectoryOps.renameOptions(destination, options), null, null);
            return null;
        });
    }

    /** Builds the SDK create options shared by createFile and the upload operations. */
    static ShareFileCreateOptions createOptions(long sizeInBytes, Object options) {
        ShareFileCreateOptions sdkOptions = new ShareFileCreateOptions(sizeInBytes);
        if (options != null) {
            @SuppressWarnings("unchecked")
            BMap<BString, Object> record = (BMap<BString, Object>) options;
            sdkOptions.setShareFileHttpHeaders(OptionsReader.contentHeaders(record.get(Constants.CONTENT_HEADERS)))
                    .setMetadata(ValueUtils.optStringMap(record, Constants.METADATA))
                    .setFilePermission(ValueUtils.optString(record, Constants.FILE_PERMISSION))
                    .setSmbProperties(OptionsReader.smbProperties(record.get(Constants.SMB_PROPERTIES)))
                    .setPosixProperties(OptionsReader.posixProperties(record.get(Constants.POSIX_PROPERTIES)));
        }
        return sdkOptions;
    }

    /** Returns the SDK file client for a combined share-relative path. */
    static ShareFileClient fileClient(BObject self, BString path) {
        return Ops.shareClient(self).getFileClient(Ops.filePath(path));
    }
}
