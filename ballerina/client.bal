// Copyright (c) 2026, WSO2 LLC. (http://www.wso2.com).
//
// WSO2 LLC. licenses this file to you under the Apache License,
// Version 2.0 (the "License"); you may not use this file except
// in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing,
// software distributed under the License is distributed on an
// "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
// KIND, either express or implied.  See the License for the
// specific language governing permissions and limitations
// under the License.

import ballerina/jballerina.java;

# Share-scoped client for Azure Files, operating on a single share and the directories
# and files within it.
public isolated client class Client {

    private final string shareName;

    # Initializes the client and binds it to a single share.
    #
    # + shareName - The name of the share this client operates on
    # + config - The client configuration (authentication, retry, transport)
    # + return - An `Error` if the client could not be initialized, otherwise `()`
    public isolated function init(string shareName, *ClientConfiguration config) returns Error? {
        self.shareName = shareName;
        return initClient(self, shareName, config);
    }

    # Gets the properties of the bound share.
    #
    # + return - The `ShareProperties`, or an `Error`
    isolated remote function getShareProperties() returns ShareProperties|Error = @java:Method {
        'class: "io.ballerina.lib.azure.storage.files.client.ShareOps"
    } external;

    # Replaces the metadata of the bound share.
    #
    # + metadata - The complete metadata set (replaces all existing metadata)
    # + return - An `Error` if the metadata could not be set, otherwise `()`
    isolated remote function setShareMetadata(map<string> metadata) returns Error? = @java:Method {
        'class: "io.ballerina.lib.azure.storage.files.client.ShareOps"
    } external;

    # Gets the approximate amount of data stored on the bound share, in bytes.
    #
    # + return - The share usage in bytes, or an `Error`
    isolated remote function getShareUsage() returns int|Error = @java:Method {
        'class: "io.ballerina.lib.azure.storage.files.client.ShareOps"
    } external;

    # Creates a directory in the bound share.
    #
    # + directoryPath - The share-relative path of the directory to create
    # + options - Optional creation options (metadata)
    # + return - An `Error` if the directory could not be created, otherwise `()`
    isolated remote function createDirectory(string directoryPath, DirectoryCreateOptions? options = ())
            returns Error? = @java:Method {
        'class: "io.ballerina.lib.azure.storage.files.client.DirectoryOps"
    } external;

    # Deletes a directory from the bound share. The directory must be empty.
    #
    # + directoryPath - The share-relative path of the directory to delete
    # + return - An `Error` if the directory could not be deleted, otherwise `()`
    isolated remote function deleteDirectory(string directoryPath) returns Error? = @java:Method {
        'class: "io.ballerina.lib.azure.storage.files.client.DirectoryOps"
    } external;

    # Checks whether a directory exists in the bound share. Returns `false` only when Azure
    # confirms the directory is absent; an `Error` means the check itself failed.
    #
    # + directoryPath - The share-relative path of the directory
    # + return - `true` if the directory exists, `false` if not, or an `Error`
    isolated remote function hasDirectory(string directoryPath) returns boolean|Error = @java:Method {
        'class: "io.ballerina.lib.azure.storage.files.client.DirectoryOps"
    } external;

    # Gets the properties of a directory.
    #
    # + directoryPath - The share-relative path of the directory
    # + return - The `DirectoryProperties`, or an `Error`
    isolated remote function getDirectoryProperties(string directoryPath)
            returns DirectoryProperties|Error = @java:Method {
        'class: "io.ballerina.lib.azure.storage.files.client.DirectoryOps"
    } external;

    # Replaces the metadata of a directory.
    #
    # + directoryPath - The share-relative path of the directory
    # + metadata - The complete metadata set (replaces all existing metadata)
    # + return - An `Error` if the metadata could not be set, otherwise `()`
    isolated remote function setDirectoryMetadata(string directoryPath, map<string> metadata)
            returns Error? = @java:Method {
        'class: "io.ballerina.lib.azure.storage.files.client.DirectoryOps"
    } external;

    # Lists the entries (files and subdirectories) under a directory.
    #
    # + directoryPath - The share-relative path of the directory to list
    # + options - Optional listing options (prefix, recursion, extended info)
    # + return - A stream of `Entry`, or an `Error`
    isolated remote function list(string directoryPath, ListOptions? options = ()) returns stream<Entry, Error?>|Error {
        EntryStreamGenerator generator = new;
        Error? result = newEntryIterator(self, generator, directoryPath, options ?: {});
        if result is Error {
            return result;
        }
        return new stream<Entry, Error?>(generator);
    }

    # Renames or moves a directory within the bound share, together with its entire contents.
    #
    # + sourcePath - The current share-relative path of the directory
    # + destinationPath - The new share-relative path
    # + options - Optional rename options (overwrite, metadata)
    # + return - An `Error` if the directory could not be renamed, otherwise `()`
    isolated remote function renameDirectory(string sourcePath, string destinationPath,
            RenameOptions? options = ()) returns Error? = @java:Method {
        'class: "io.ballerina.lib.azure.storage.files.client.DirectoryOps"
    } external;

    # Creates an empty file of a fixed size.
    #
    # + path - The share-relative path of the file to create
    # + sizeInBytes - The size of the file, in bytes
    # + options - Optional creation options (headers, metadata)
    # + return - An `Error` if the file could not be created, otherwise `()`
    isolated remote function createFile(string path, int sizeInBytes, CreateOptions? options = ())
            returns Error? = @java:Method {
        'class: "io.ballerina.lib.azure.storage.files.client.FileOps"
    } external;

    # Deletes a file from the bound share.
    #
    # + path - The share-relative path of the file to delete
    # + return - An `Error` if the file could not be deleted, otherwise `()`
    isolated remote function deleteFile(string path) returns Error? = @java:Method {
        'class: "io.ballerina.lib.azure.storage.files.client.FileOps"
    } external;

    # Checks whether a file exists in the bound share. Returns `false` only when Azure
    # confirms the file is absent; an `Error` means the check itself failed.
    #
    # + path - The share-relative path of the file
    # + return - `true` if the file exists, `false` if not, or an `Error`
    isolated remote function hasFile(string path) returns boolean|Error = @java:Method {
        'class: "io.ballerina.lib.azure.storage.files.client.FileOps"
    } external;

    # Gets the properties of a file.
    #
    # + path - The share-relative path of the file
    # + return - The `FileProperties`, or an `Error`
    isolated remote function getFileProperties(string path) returns FileProperties|Error = @java:Method {
        'class: "io.ballerina.lib.azure.storage.files.client.FileOps"
    } external;

    # Replaces the metadata of a file.
    #
    # + path - The share-relative path of the file
    # + metadata - The complete metadata set (replaces all existing metadata)
    # + return - An `Error` if the metadata could not be set, otherwise `()`
    isolated remote function setFileMetadata(string path, map<string> metadata) returns Error? = @java:Method {
        'class: "io.ballerina.lib.azure.storage.files.client.FileOps"
    } external;

    # Sets the content headers of a file, such as `Content-Type` and `Cache-Control`.
    # Any header omitted from `headers` is cleared on the file.
    #
    # + path - The share-relative path of the file
    # + headers - The full set of content headers the file should carry
    # + return - An `Error` if the headers could not be set, otherwise `()`
    isolated remote function setContentHeaders(string path, ContentHeaders headers) returns Error? = @java:Method {
        'class: "io.ballerina.lib.azure.storage.files.client.FileOps"
    } external;

    # Renames or moves a file within the bound share. An existing destination file is
    # overwritten only when `RenameOptions.replaceIfExists` is set.
    #
    # + sourcePath - The current share-relative path of the file
    # + destinationPath - The new share-relative path
    # + options - Optional rename options (overwrite, metadata)
    # + return - An `Error` if the file could not be renamed, otherwise `()`
    isolated remote function renameFile(string sourcePath, string destinationPath,
            RenameOptions? options = ()) returns Error? = @java:Method {
        'class: "io.ballerina.lib.azure.storage.files.client.FileOps"
    } external;

    # Uploads a local file to the bound share.
    #
    # ```ballerina
    # // ./reports/q1.pdf (local disk) --> /2026/q1/report.pdf (on the share)
    # check fileClient->uploadFromFile("./reports/q1.pdf", "/2026/q1/report.pdf");
    # ```
    #
    # + sourcePath - The path of the local file to upload, including the file name
    # + destinationPath - The share-relative path the file is written to, including the file name
    # + options - Optional upload options (headers, metadata)
    # + return - An `Error` if the upload failed, otherwise `()`
    isolated remote function uploadFromFile(string sourcePath, string destinationPath,
            UploadOptions? options = ()) returns Error? = @java:Method {
        'class: "io.ballerina.lib.azure.storage.files.client.TransferOps"
    } external;

    # Uploads in-memory content to the bound share.
    #
    # ```ballerina
    # check fileClient->upload(<map<json>>{"revenue": 1250000, "growth": 0.12}, "/2026/q1/metrics.json");
    # ```
    #
    # + content - The content to upload. A record, a record array, or another `json` value is
    #             serialized per the resolved file format
    # + destinationPath - The share-relative path the content is written to, including the file name
    # + options - Optional upload options (headers, metadata, format override)
    # + return - An `Error` if the upload failed, otherwise `()`
    isolated remote function upload(UploadContent content,
            string destinationPath, UploadContentOptions? options = ()) returns Error? {
        byte[]|string|xml|string[][] payload;
        if content is record {} {
            payload = check serializeRecord(content, destinationPath, options?.fileFormat);
        } else if content is record {}[] {
            payload = check serializeRecordArray(content, destinationPath, options?.fileFormat);
        } else if content is byte[]|string|xml {
            payload = content;
        } else {
            // The compiler does not subtract the record shapes from the union here, but
            // both are handled above, so the residual json value is cast-safe.
            payload = check serializeJson(<json>content, destinationPath, options?.fileFormat);
        }
        return externUpload(self, payload, destinationPath, options);
    }

    # Uploads a byte stream to the bound share. The total content length is required. There
    # is no record stream upload, so collect records into a `record {}[]` and use `upload`.
    #
    # + content - The byte stream to upload
    # + contentLength - The total length of the content, in bytes
    # + destinationPath - The share-relative path the content is written to, including the file name
    # + options - Optional upload options (headers, metadata)
    # + return - An `Error` if the upload failed, otherwise `()`
    isolated remote function uploadFromStream(stream<byte[], error?> content,
            int contentLength, string destinationPath, UploadOptions? options = ()) returns Error? {
        if contentLength < 0 {
            closeByteStreamQuietly(content);
            return error Error(string `contentLength must not be negative: ${contentLength}`);
        }
        Error? result = self.pumpStream(content, contentLength, destinationPath, options);
        if result is Error {
            closeByteStreamQuietly(content);
        }
        return result;
    }

    // Drives the stream upload: source chunks coalesce into writes of the service's maximum
    // range size, so the request count tracks the content size rather than the source's
    // chunking. The buffer fills to at most one range per iteration with the remainder
    // carried, so memory stays bounded even when one source chunk exceeds the range size.
    private isolated function pumpStream(stream<byte[], error?> content, int contentLength,
            string destinationPath, UploadOptions? options) returns Error? {
        check prepareStreamUpload(self, destinationPath, contentLength, options);
        byte[] buffer = [];
        byte[] carry = [];
        int offset = 0;
        while true {
            byte[] bytes;
            if carry.length() > 0 {
                bytes = carry;
                carry = [];
            } else {
                ContentStreamEntry|error? chunk = content.next();
                if chunk is () {
                    break;
                }
                if chunk is error {
                    return error Error("the source stream failed: " + chunk.message(), chunk);
                }
                bytes = chunk.value;
            }
            if offset + buffer.length() + bytes.length() > contentLength {
                return error Error(
                        string `the source stream exceeded the declared contentLength of ${contentLength} bytes`);
            }
            int room = MAX_RANGE_BYTES - buffer.length();
            boolean sliced = false;
            if bytes.length() > room {
                carry = bytes.slice(room);
                bytes = bytes.slice(0, room);
                sliced = true;
            }
            if sliced && buffer.length() == 0 {
                buffer = bytes;
            } else {
                buffer.push(...bytes);
            }
            if buffer.length() >= MAX_RANGE_BYTES {
                check writeStreamChunk(self, destinationPath, offset, buffer);
                offset += buffer.length();
                buffer = [];
            }
        }
        if offset + buffer.length() != contentLength {
            int actual = offset + buffer.length();
            return error Error(string `source stream ended at ${actual} bytes but contentLength is ${contentLength}`);
        }
        if buffer.length() > 0 {
            check writeStreamChunk(self, destinationPath, offset, buffer);
        }
        return;
    }

    # Downloads a file to a local path. An existing local file at `destinationPath` fails
    # the download.
    #
    # ```ballerina
    # // /2026/q1/report.pdf (on the share) --> ./reports/q1.pdf (local disk)
    # check fileClient->download("/2026/q1/report.pdf", "./reports/q1.pdf");
    # ```
    #
    # + sourcePath - The share-relative path of the file to download, including the file name
    # + destinationPath - The local path to write the downloaded file to (must not exist)
    # + options - Optional download options (range)
    # + return - An `Error` if the download failed, otherwise `()`
    isolated remote function download(string sourcePath, string destinationPath,
            DownloadOptions? options = ()) returns Error? = @java:Method {
        'class: "io.ballerina.lib.azure.storage.files.client.TransferOps"
    } external;

    # Retrieves a file's content in the form the target type selects.
    #
    # ```ballerina
    # byte[] raw = check fileClient->getFile("/2026/q1/report.pdf");
    # Person[] people = check fileClient->getFile("/2026/q1/people.csv");
    # stream<byte[], error?> chunks = check fileClient->getFile("/2026/q1/large.bin");
    # ```
    #
    # + path - The source share-relative path
    # + options - Optional retrieval options (range, snapshot, record binding format)
    # + targetType - Expected return type (to be used for automatic data binding).
    #                Supported types:
    #                - Raw bytes (`byte[]`) or UTF-8 text (`string`)
    #                - A `json` or `xml` value
    #                - Custom records (e.g., `Person`, `Person[]`), bound per `GetFileOptions.fileFormat`,
    #                  else the path's extension (`.json`, `.xml`, `.csv`)
    #                - A lazy byte stream (`stream<byte[], error?>`)
    #                - A lazy stream of CSV-bound records (e.g., `stream<Person, error?>`)
    # + return - The content in the requested form, or an `Error` on a failed retrieval or a data binding failure
    isolated remote function getFile(string path, GetFileOptions? options = (),
            typedesc<RetrievableType> targetType = <>) returns targetType|Error = @java:Method {
        'class: "io.ballerina.lib.azure.storage.files.client.TypedReadOps"
    } external;

    # Copies a file within the bound share. The copy is asynchronous; inspect the returned
    # `CopyInfo.copyStatus` for its state.
    #
    # + sourcePath - The source share-relative path
    # + destinationPath - The destination share-relative path
    # + options - Optional copy options (metadata)
    # + return - The `CopyInfo` for the started copy, or an `Error`
    isolated remote function copyFile(string sourcePath, string destinationPath,
            CopyOptions? options = ()) returns CopyInfo|Error = @java:Method {
        'class: "io.ballerina.lib.azure.storage.files.client.CopyOps"
    } external;

    # Copies a file from an external URL into the bound share. A source outside this storage
    # account must carry its own authorization in the URL (typically a SAS token).
    #
    # + sourceUrl - The URL of the source file
    # + destinationPath - The destination share-relative path
    # + options - Optional copy options (metadata)
    # + return - The `CopyInfo` for the started copy, or an `Error`
    isolated remote function copyFileFromUrl(string sourceUrl, string destinationPath,
            CopyOptions? options = ()) returns CopyInfo|Error = @java:Method {
        'class: "io.ballerina.lib.azure.storage.files.client.CopyOps"
    } external;

    # Checks the state of the most recent copy operation that targeted a file.
    #
    # + path - The destination share-relative path of the copy
    # + return - The `CopyStatusInfo`, `()` if the file has never been the destination of a
    #            copy operation, or an `Error`
    isolated remote function checkCopyStatus(string path) returns CopyStatusInfo?|Error = @java:Method {
        'class: "io.ballerina.lib.azure.storage.files.client.CopyOps"
    } external;

    # Aborts a pending asynchronous copy operation.
    #
    # + path - The destination share-relative path of the copy
    # + copyId - The identifier of the copy to abort (from `CopyInfo.copyId`)
    # + return - An `Error` if the copy could not be aborted, otherwise `()`
    isolated remote function abortCopy(string path, string copyId) returns Error? = @java:Method {
        'class: "io.ballerina.lib.azure.storage.files.client.CopyOps"
    } external;

    # Writes a range of bytes into a file at a given offset. A single range write is capped
    # at 4 MiB by the service.
    #
    # + path - The share-relative path of the file
    # + offset - The zero-based byte offset at which to begin writing
    # + content - The bytes to write (at most 4 MiB)
    # + return - An `Error` if the range could not be written, otherwise `()`
    isolated remote function uploadRange(string path, int offset, byte[] content) returns Error? = @java:Method {
        'class: "io.ballerina.lib.azure.storage.files.client.RangeOps"
    } external;

    # Clears a range of bytes in a file.
    #
    # + path - The share-relative path of the file
    # + offset - The zero-based byte offset at which to begin clearing
    # + length - The number of bytes to clear
    # + return - An `Error` if the range could not be cleared, otherwise `()`
    isolated remote function clearRange(string path, int offset, int length) returns Error? = @java:Method {
        'class: "io.ballerina.lib.azure.storage.files.client.RangeOps"
    } external;

    # Lists the valid (written) byte ranges of a file.
    #
    # + path - The share-relative path of the file
    # + options - Optional range-listing options
    # + return - The list of written `Range`s, or an `Error`
    isolated remote function listRanges(string path, RangeListOptions? options = ())
            returns Range[]|Error = @java:Method {
        'class: "io.ballerina.lib.azure.storage.files.client.RangeOps"
    } external;

    # Creates a point-in-time, read-only snapshot of the bound share. Requires account-level
    # credentials.
    #
    # + metadata - Optional metadata to set on the snapshot; when absent, the share's
    #              metadata is copied to the snapshot
    # + return - The `ShareSnapshotInfo` for the new snapshot, or an `Error`
    isolated remote function createShareSnapshot(map<string>? metadata = ())
            returns ShareSnapshotInfo|Error = @java:Method {
        'class: "io.ballerina.lib.azure.storage.files.client.SnapshotOps"
    } external;

    # Lists the snapshots of the bound share. Requires account-level credentials.
    #
    # + return - The share's snapshots, or an `Error`
    isolated remote function listShareSnapshots() returns ShareSnapshotInfo[]|Error = @java:Method {
        'class: "io.ballerina.lib.azure.storage.files.client.SnapshotOps"
    } external;

    # Deletes one snapshot of the bound share. Requires account-level credentials.
    #
    # + snapshotId - The identifier of the snapshot to delete
    # + return - An `Error` if the snapshot could not be deleted, otherwise `()`
    isolated remote function deleteShareSnapshot(string snapshotId) returns Error? = @java:Method {
        'class: "io.ballerina.lib.azure.storage.files.client.SnapshotOps"
    } external;

    # Lists how a file's byte ranges changed since a share snapshot.
    #
    # + path - The share-relative path of the file
    # + previousSnapshotId - The identifier of the baseline snapshot to diff against
    # + options - Optional range-listing options
    # + return - The `RangeDiff`, or an `Error`
    isolated remote function listRangesDiff(string path, string previousSnapshotId,
            RangeListOptions? options = ()) returns RangeDiff|Error = @java:Method {
        'class: "io.ballerina.lib.azure.storage.files.client.SnapshotOps"
    } external;

    # Generates a SAS (Shared Access Signature) token scoped to the bound share. Requires shared key credentials.
    #
    # + values - What the SAS grants: validity window and permissions, or a stored policy reference
    # + return - The SAS token, or an `Error`
    public isolated function generateShareSas(ShareSasSignatureValues values) returns string|Error = @java:Method {
        'class: "io.ballerina.lib.azure.storage.files.client.SasOps"
    } external;

    # Generates a SAS (Shared Access Signature) token scoped to a single file. Requires shared key credentials.
    #
    # + path - The share-relative path of the file the SAS grants access to
    # + values - What the SAS grants: validity window and permissions, or a stored policy reference
    # + return - The SAS token, or an `Error`
    public isolated function generateSas(string path, FileSasSignatureValues values)
            returns string|Error = @java:Method {
        'class: "io.ballerina.lib.azure.storage.files.client.SasOps"
    } external;

    # Generates a user-delegation SAS token scoped to the bound share.
    #
    # + values - What the SAS grants: validity window and permissions
    # + key - The user-delegation key to sign with
    # + return - The SAS token, or an `Error`
    public isolated function generateShareUserDelegationSas(ShareSasSignatureValues values,
            UserDelegationKey key) returns string|Error = @java:Method {
        'class: "io.ballerina.lib.azure.storage.files.client.SasOps"
    } external;

    # Generates a user-delegation SAS token scoped to a single file.
    #
    # + path - The share-relative path of the file the SAS grants access to
    # + values - What the SAS grants: validity window and permissions
    # + key - The user-delegation key to sign with
    # + return - The SAS token, or an `Error`
    public isolated function generateUserDelegationSas(string path,
            FileSasSignatureValues values, UserDelegationKey key)
            returns string|Error = @java:Method {
        'class: "io.ballerina.lib.azure.storage.files.client.SasOps"
    } external;
}
