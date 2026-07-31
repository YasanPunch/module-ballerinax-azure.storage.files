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

import com.azure.core.util.Context;
import com.azure.storage.file.share.ShareFileClient;
import com.azure.storage.file.share.models.ShareFileHttpHeaders;
import com.azure.storage.file.share.models.ShareFilePermission;
import com.azure.storage.file.share.models.ShareFileProperties;
import com.azure.storage.file.share.options.ShareFileCreateOptions;
import com.azure.storage.file.share.options.ShareFileSetPropertiesOptions;
import io.ballerina.lib.azure.storage.files.util.Ops;
import io.ballerina.lib.azure.storage.files.util.OptionsReader;
import io.ballerina.lib.azure.storage.files.util.RecordMapper;
import io.ballerina.lib.azure.storage.files.util.ValueUtils;
import io.ballerina.runtime.api.Environment;
import io.ballerina.runtime.api.utils.StringUtils;
import io.ballerina.runtime.api.values.BMap;
import io.ballerina.runtime.api.values.BObject;
import io.ballerina.runtime.api.values.BString;

import java.net.URLDecoder;
import java.nio.charset.StandardCharsets;

/**
 * Native implementations of the basic {@code Client} file operations.
 */
public final class FileOps {

    // The FileSetPropertiesOptions resize field, read only here.
    private static final BString NEW_FILE_SIZE_BYTES = StringUtils.fromString("newFileSizeBytes");

    private FileOps() {
    }

    /** Creates an empty file pre-allocated to the given size. */
    public static Object createFile(Environment env, BObject self, BString path, long sizeInBytes, Object options) {
        return Ops.invoke(env, () -> {
            fileClient(self, path).createWithResponse(createOptions(sizeInBytes, options), null, null);
            return null;
        });
    }

    /** Deletes a file. */
    public static Object deleteFile(Environment env, BObject self, BString path) {
        return Ops.invoke(env, () -> {
            fileClient(self, path).delete();
            return null;
        });
    }

    /** Checks whether the file exists; {@code false} only on a confirmed 404. */
    public static Object hasFile(Environment env, BObject self, BString path) {
        return Ops.invoke(env, () -> Boolean.TRUE.equals(fileClient(self, path).exists()));
    }

    /** Fetches a file's properties as a {@code FileProperties} record. */
    public static Object getFileProperties(Environment env, BObject self, BString path) {
        return Ops.invoke(env, () -> RecordMapper.fileProperties(fileClient(self, path).getProperties()));
    }

    /** Updates a file's size, content headers, SMB, and POSIX properties. */
    public static Object setFileProperties(Environment env, BObject self, BString path,
            BMap<BString, Object> options) {
        return Ops.invoke(env, () -> {
            ShareFileClient client = fileClient(self, path);
            Object newSize = options.get(NEW_FILE_SIZE_BYTES);
            Object headers = options.get(OptionsReader.CONTENT_HEADERS);
            // The wire operation replaces the whole property set: an omitted size or content
            // header is cleared, not preserved. The current values are re-sent for whatever
            // the caller left out, honouring the only-what-is-set-changes contract.
            ShareFileProperties current = newSize == null || headers == null ? client.getProperties() : null;
            long size = newSize != null ? (Long) newSize : current.getContentLength();
            ShareFileSetPropertiesOptions sdkOptions = new ShareFileSetPropertiesOptions(size);
            if (headers != null) {
                sdkOptions.setHttpHeaders(OptionsReader.contentHeaders(headers));
            } else {
                sdkOptions.setHttpHeaders(new ShareFileHttpHeaders()
                        .setContentType(current.getContentType())
                        .setContentEncoding(current.getContentEncoding())
                        .setContentDisposition(current.getContentDisposition())
                        .setCacheControl(current.getCacheControl())
                        .setContentMd5(current.getContentMd5()));
            }
            sdkOptions.setSmbProperties(OptionsReader.smbProperties(options.get(OptionsReader.SMB_PROPERTIES)))
                    .setPosixProperties(OptionsReader.posixProperties(options.get(OptionsReader.POSIX_PROPERTIES)));
            String permission = ValueUtils.optString(options, OptionsReader.FILE_PERMISSION);
            if (permission != null) {
                sdkOptions.setFilePermissions(new ShareFilePermission().setPermission(permission));
            }
            client.setPropertiesWithResponse(sdkOptions, null, Context.NONE);
            return null;
        });
    }

    /** Replaces a file's user-defined metadata. */
    public static Object setFileMetadata(Environment env, BObject self, BString path,
                                         BMap<BString, BString> metadata) {
        return Ops.invoke(env, () -> {
            fileClient(self, path).setMetadata(ValueUtils.toStringMap(metadata));
            return null;
        });
    }

    /** Replaces a file's HTTP content headers, keeping its current size. */
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

    /** Renames or moves a file within the share. */
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
            sdkOptions.setShareFileHttpHeaders(OptionsReader.contentHeaders(record.get(OptionsReader.CONTENT_HEADERS)))
                    .setMetadata(ValueUtils.optStringMap(record, OptionsReader.METADATA))
                    .setFilePermission(ValueUtils.optString(record, OptionsReader.FILE_PERMISSION))
                    .setSmbProperties(OptionsReader.smbProperties(record.get(OptionsReader.SMB_PROPERTIES)))
                    .setPosixProperties(OptionsReader.posixProperties(record.get(OptionsReader.POSIX_PROPERTIES)));
        }
        return sdkOptions;
    }

    /** Creates an NFS hard link to an existing file. */
    public static Object createHardLink(Environment env, BObject self, BString path, BString targetPath) {
        return Ops.invoke(env, () -> {
            // The SDK sends the target verbatim in the x-ms-file-target-file header, which is
            // the share-relative path of the existing file, not including the share name.
            String target = Ops.filePath(targetPath);
            fileClient(self, path).createHardLink(target);
            return null;
        });
    }

    /** Creates an NFS symbolic link pointing at the given target. */
    public static Object createSymbolicLink(Environment env, BObject self, BString path, BString linkTarget) {
        return Ops.invoke(env, () -> {
            fileClient(self, path).createSymbolicLink(linkTarget.getValue());
            return null;
        });
    }

    /** Reads the target path stored in an NFS symbolic link. */
    public static Object getSymbolicLink(Environment env, BObject self, BString path) {
        // The service returns the link text percent-encoded. URLDecoder alone would also turn a
        // literal + into a space (form semantics), so pluses are escaped first to preserve them.
        return Ops.invoke(env, () -> StringUtils.fromString(
                URLDecoder.decode(
                        fileClient(self, path).getSymbolicLink().getLinkText().replace("+", "%2B"),
                        StandardCharsets.UTF_8)));
    }

    /** Returns the SDK file client for a combined share-relative path. */
    static ShareFileClient fileClient(BObject self, BString path) {
        return Ops.shareClient(self).getFileClient(Ops.filePath(path));
    }

    /** Returns the SDK file client for a path, bound to a share snapshot when an id is given. */
    static ShareFileClient fileClient(BObject self, BString path, String snapshotId) {
        return Ops.shareClient(self, snapshotId).getFileClient(Ops.filePath(path));
    }
}
