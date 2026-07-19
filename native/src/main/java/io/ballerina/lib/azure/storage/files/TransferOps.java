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
import com.azure.storage.file.share.StorageFileInputStream;
import com.azure.storage.file.share.models.ShareFileUploadRangeOptions;
import io.ballerina.runtime.api.Environment;
import io.ballerina.runtime.api.creators.ValueCreator;
import io.ballerina.runtime.api.utils.StringUtils;
import io.ballerina.runtime.api.values.BArray;
import io.ballerina.runtime.api.values.BMap;
import io.ballerina.runtime.api.values.BObject;
import io.ballerina.runtime.api.values.BString;
import io.ballerina.runtime.api.values.BXml;

import java.io.ByteArrayInputStream;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.NoSuchFileException;
import java.nio.file.Path;

/**
 * Native implementations of the {@code Client} transfer operations: local-file upload and
 * download, in-memory content upload, and the two content streams (upload from a Ballerina
 * stream, download as a Ballerina stream).
 */
public final class TransferOps {

    private TransferOps() {
    }

    /** The service's maximum size for one range write: 4 MiB. */
    private static final int MAX_RANGE_BYTES = 4 * 1024 * 1024;
    /** The chunk size handed to Ballerina byte-stream consumers. */
    private static final int READ_CHUNK_BYTES = 64 * 1024;

    public static Object uploadFile(Environment env, BObject self, BString sourcePath,
                                    BString destinationPath, Object options) {
        return Ops.invoke(env, () -> {
            Path localPath = Path.of(sourcePath.getValue());
            long size;
            try {
                size = Files.size(localPath);
            } catch (NoSuchFileException e) {
                throw FilesErrorCreator.processingError(
                        "local file not found: " + sourcePath.getValue(), e);
            } catch (IOException e) {
                throw FilesErrorCreator.processingError(Ops.describe(e), e);
            }
            ShareFileClient client = FileOps.fileClient(self, destinationPath);
            client.createWithResponse(FileOps.createOptions(size, options), null, null);
            client.uploadFromFile(localPath.toString());
            return null;
        });
    }

    public static Object uploadContent(Environment env, BObject self, Object content,
                                       BString destinationPath, Object options) {
        return Ops.invoke(env, () -> {
            byte[] bytes = contentBytes(content);
            ShareFileClient client = FileOps.fileClient(self, destinationPath);
            client.createWithResponse(FileOps.createOptions(bytes.length, options), null, null);
            if (bytes.length > 0) {
                client.upload(new ByteArrayInputStream(bytes), bytes.length, null);
            }
            return null;
        });
    }

    /** Creates the pre-allocated destination file for a stream upload. */
    public static Object prepareStreamUpload(Environment env, BObject self, BString destinationPath,
                                             long contentLength, Object options) {
        return Ops.invoke(env, () -> {
            FileOps.fileClient(self, destinationPath)
                    .createWithResponse(FileOps.createOptions(contentLength, options), null, null);
            return null;
        });
    }

    /** Writes one stream chunk at the given offset, splitting it into service-compliant ranges. */
    public static Object writeStreamChunk(Environment env, BObject self, BString destinationPath,
                                          long offset, BArray chunk) {
        return Ops.invoke(env, () -> {
            byte[] bytes = chunk.getBytes();
            ShareFileClient client = FileOps.fileClient(self, destinationPath);
            long position = offset;
            int written = 0;
            while (written < bytes.length) {
                int length = Math.min(bytes.length - written, MAX_RANGE_BYTES);
                client.uploadRangeWithResponse(new ShareFileUploadRangeOptions(
                                new ByteArrayInputStream(bytes, written, length), length)
                                .setOffset(position),
                        null, null);
                written += length;
                position += length;
            }
            return null;
        });
    }

    public static Object downloadFile(Environment env, BObject self, BString sourcePath,
                                      BString destinationPath, Object options) {
        return Ops.invoke(env, () -> {
            ShareFileClient client = FileOps.fileClient(self, sourcePath);
            Object range = null;
            if (options != null) {
                @SuppressWarnings("unchecked")
                BMap<BString, Object> record = (BMap<BString, Object>) options;
                range = record.get(Constants.RANGE);
            }
            try {
                if (range == null) {
                    client.downloadToFile(destinationPath.getValue());
                } else {
                    client.downloadToFileWithResponse(destinationPath.getValue(),
                            OptionsReader.range(range), null, null);
                }
            } catch (java.io.UncheckedIOException e) {
                throw FilesErrorCreator.processingError(
                        "cannot write local file " + destinationPath.getValue() + ": " + Ops.describe(e.getCause()),
                        e);
            }
            return null;
        });
    }

    /** Opens the file's content stream and stores it on the Ballerina stream generator object. */
    public static Object openContentStream(Environment env, BObject self, BObject generator,
                                           BString path, Object options) {
        return Ops.invoke(env, () -> {
            ShareFileClient client = FileOps.fileClient(self, path);
            Object range = null;
            if (options != null) {
                @SuppressWarnings("unchecked")
                BMap<BString, Object> record = (BMap<BString, Object>) options;
                range = record.get(Constants.RANGE);
            }
            StorageFileInputStream stream = range == null
                    ? client.openInputStream()
                    : client.openInputStream(OptionsReader.range(range));
            generator.addNativeData(Constants.NATIVE_INPUT_STREAM, stream);
            return null;
        });
    }

    /** Reads the next chunk from an open content stream; {@code null} signals the end. */
    public static Object nextContentChunk(Environment env, BObject generator) {
        return Ops.invoke(env, () -> {
            StorageFileInputStream stream =
                    (StorageFileInputStream) generator.getNativeData(Constants.NATIVE_INPUT_STREAM);
            if (stream == null) {
                return null;
            }
            try {
                byte[] buffer = new byte[READ_CHUNK_BYTES];
                int read = stream.read(buffer);
                if (read < 0) {
                    closeQuietly(generator);
                    return null;
                }
                byte[] chunk = read == buffer.length ? buffer : java.util.Arrays.copyOf(buffer, read);
                return ValueCreator.createArrayValue(chunk);
            } catch (IOException e) {
                closeQuietly(generator);
                throw FilesErrorCreator.processingError(Ops.describe(e), e);
            }
        });
    }

    /** Closes an open content stream early. */
    public static Object closeContentStream(BObject generator) {
        closeQuietly(generator);
        return null;
    }

    private static void closeQuietly(BObject generator) {
        StorageFileInputStream stream =
                (StorageFileInputStream) generator.getNativeData(Constants.NATIVE_INPUT_STREAM);
        if (stream != null) {
            generator.addNativeData(Constants.NATIVE_INPUT_STREAM, null);
            stream.close();
        }
    }

    private static byte[] contentBytes(Object content) {
        if (content instanceof BArray array) {
            return array.getBytes();
        }
        if (content instanceof BString string) {
            return string.getValue().getBytes(StandardCharsets.UTF_8);
        }
        if (content instanceof BXml xml) {
            return xml.toString().getBytes(StandardCharsets.UTF_8);
        }
        return StringUtils.getJsonString(content).getBytes(StandardCharsets.UTF_8);
    }
}
