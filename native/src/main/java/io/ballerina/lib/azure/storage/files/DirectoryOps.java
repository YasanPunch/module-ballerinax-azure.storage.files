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
import com.azure.storage.file.share.models.ShareFilePermission;
import com.azure.storage.file.share.options.ShareDirectoryCreateOptions;
import com.azure.storage.file.share.options.ShareDirectorySetPropertiesOptions;
import com.azure.storage.file.share.options.ShareFileRenameOptions;
import io.ballerina.runtime.api.Environment;
import io.ballerina.runtime.api.values.BMap;
import io.ballerina.runtime.api.values.BObject;
import io.ballerina.runtime.api.values.BString;

/**
 * Native implementations of the {@code Client} directory operations.
 */
public final class DirectoryOps {

    private DirectoryOps() {
    }

    public static Object createDirectory(Environment env, BObject self, BString directoryPath, Object options) {
        return Ops.invoke(env, () -> {
            ShareDirectoryCreateOptions sdkOptions = new ShareDirectoryCreateOptions();
            if (options != null) {
                @SuppressWarnings("unchecked")
                BMap<BString, Object> record = (BMap<BString, Object>) options;
                sdkOptions.setMetadata(ValueUtils.optStringMap(record, Constants.METADATA))
                        .setFilePermission(ValueUtils.optString(record, Constants.FILE_PERMISSION))
                        .setSmbProperties(OptionsReader.smbProperties(record.get(Constants.SMB_PROPERTIES)))
                        .setPosixProperties(OptionsReader.posixProperties(record.get(Constants.POSIX_PROPERTIES)));
            }
            directoryClient(self, directoryPath).createWithResponse(sdkOptions, null, null);
            return null;
        });
    }

    public static Object deleteDirectory(Environment env, BObject self, BString directoryPath) {
        return Ops.invoke(env, () -> {
            directoryClient(self, directoryPath).delete();
            return null;
        });
    }

    public static Object setDirectoryProperties(Environment env, BObject self, BString directoryPath,
            BMap<BString, Object> options) {
        return Ops.invoke(env, () -> {
            ShareDirectorySetPropertiesOptions sdkOptions = new ShareDirectorySetPropertiesOptions()
                    .setSmbProperties(OptionsReader.smbProperties(options.get(Constants.SMB_PROPERTIES)))
                    .setPosixProperties(OptionsReader.posixProperties(options.get(Constants.POSIX_PROPERTIES)));
            String permission = ValueUtils.optString(options, Constants.FILE_PERMISSION);
            if (permission != null) {
                sdkOptions.setFilePermissions(new ShareFilePermission().setPermission(permission));
            }
            directoryClient(self, directoryPath).setPropertiesWithResponse(sdkOptions, null, Context.NONE);
            return null;
        });
    }

    public static Object hasDirectory(Environment env, BObject self, BString directoryPath) {
        return Ops.invoke(env, () ->
                Boolean.TRUE.equals(directoryClient(self, directoryPath).exists()));
    }

    public static Object getDirectoryProperties(Environment env, BObject self, BString directoryPath) {
        return Ops.invoke(env, () ->
                RecordMapper.directoryProperties(directoryClient(self, directoryPath).getProperties()));
    }

    public static Object setDirectoryMetadata(Environment env, BObject self, BString directoryPath,
                                              BMap<BString, BString> metadata) {
        return Ops.invoke(env, () -> {
            directoryClient(self, directoryPath).setMetadata(ValueUtils.toStringMap(metadata));
            return null;
        });
    }

    public static Object renameDirectory(Environment env, BObject self, BString sourcePath,
                                         BString destinationPath, Object options) {
        return Ops.invoke(env, () -> {
            String source = Ops.filePath(sourcePath);
            String destination = Ops.filePath(destinationPath);
            ShareDirectoryClient client = Ops.shareClient(self).getDirectoryClient(source);
            client.renameWithResponse(renameOptions(destination, options), null, null);
            return null;
        });
    }

    /** Builds the SDK rename options shared by the file and directory renames. */
    static ShareFileRenameOptions renameOptions(String destinationPath, Object options) {
        ShareFileRenameOptions sdkOptions = new ShareFileRenameOptions(destinationPath);
        if (options != null) {
            @SuppressWarnings("unchecked")
            BMap<BString, Object> record = (BMap<BString, Object>) options;
            sdkOptions.setReplaceIfExists(record.getBooleanValue(Constants.REPLACE_IF_EXISTS))
                    .setIgnoreReadOnly(record.getBooleanValue(Constants.IGNORE_READ_ONLY))
                    .setFilePermission(ValueUtils.optString(record, Constants.FILE_PERMISSION))
                    .setMetadata(ValueUtils.optStringMap(record, Constants.METADATA));
        }
        return sdkOptions;
    }

    private static ShareDirectoryClient directoryClient(BObject self, BString directoryPath) {
        String path = Ops.directoryPath(directoryPath);
        return path.isEmpty()
                ? Ops.shareClient(self).getRootDirectoryClient()
                : Ops.shareClient(self).getDirectoryClient(path);
    }
}
