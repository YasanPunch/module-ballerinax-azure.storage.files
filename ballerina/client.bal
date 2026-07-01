// Copyright (c) 2026 WSO2 LLC. (https://www.wso2.com) All Rights Reserved.
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

import ballerina/io;

# Share-scoped client for Azure Files. Bound to a single share at initialization, it operates
# on that share and the directories and files within it. For account-level share management
# (create/list/delete shares), use `AdminClient`.
#
# The file is the default resource tier: file operations are unprefixed (`upload`, `getProperties`,
# `create`), directory operations carry a `Directory` token (`createDirectory`), and share-level
# operations carry a `Share` token (`getShareProperties`).
#
# The client is `isolated` and holds only immutable configuration, so its operations are safe to
# invoke concurrently.
public isolated client class Client {

    private final string shareName;

    # Initializes the client and binds it to a single share.
    #
    # + config - The connection configuration (account name and authentication)
    # + shareName - The name of the share this client operates on
    # + return - An `Error` if the client could not be initialized, otherwise `()`
    public isolated function init(ConnectionConfig config, string shareName) returns Error? {
        self.shareName = shareName;
    }

    // -----------------------------------------------------------------------
    // Share operations
    // -----------------------------------------------------------------------

    # Checks whether the bound share exists.
    #
    # + return - `true` if the share exists, `false` if not, or an `Error`
    isolated remote function shareExists() returns boolean|Error {
        return notImplemented();
    }

    # Gets the properties of the bound share.
    #
    # + return - The `ShareProperties`, or an `Error`
    isolated remote function getShareProperties() returns ShareProperties|Error {
        return notImplemented();
    }

    # Sets properties on the bound share.
    #
    # + options - The properties to set (quota, tier, lease id)
    # + return - An `Error` if the properties could not be set, otherwise `()`
    isolated remote function setShareProperties(ShareSetPropertiesOptions options) returns Error? {
        return notImplemented();
    }

    # Replaces the metadata of the bound share.
    #
    # + metadata - The metadata to set
    # + return - An `Error` if the metadata could not be set, otherwise `()`
    isolated remote function setShareMetadata(map<string> metadata) returns Error? {
        return notImplemented();
    }

    # Gets usage statistics for the bound share.
    #
    # + return - The `ShareStatistics`, or an `Error`
    isolated remote function getShareStatistics() returns ShareStatistics|Error {
        return notImplemented();
    }

    # Generates a share-scoped Shared Access Signature (SAS) token for the bound share.
    #
    # + values - The SAS signature values (expiry, permissions, etc.)
    # + return - The SAS token string, or an `Error`
    isolated remote function generateShareSas(ShareSasSignatureValues values) returns string|Error {
        return notImplemented();
    }

    // -----------------------------------------------------------------------
    // Directory operations
    // -----------------------------------------------------------------------

    # Creates a directory in the bound share.
    #
    # + directoryPath - The share-relative path of the directory to create
    # + options - Optional creation options (metadata, permission, SMB properties)
    # + return - An `Error` if the directory could not be created, otherwise `()`
    isolated remote function createDirectory(string directoryPath, DirectoryCreateOptions? options = ())
            returns Error? {
        return notImplemented();
    }

    # Deletes a directory from the bound share. The directory must be empty.
    #
    # + directoryPath - The share-relative path of the directory to delete
    # + return - An `Error` if the directory could not be deleted, otherwise `()`
    isolated remote function deleteDirectory(string directoryPath) returns Error? {
        return notImplemented();
    }

    # Checks whether a directory exists in the bound share.
    #
    # + directoryPath - The share-relative path of the directory
    # + return - `true` if the directory exists, `false` if not, or an `Error`
    isolated remote function directoryExists(string directoryPath) returns boolean|Error {
        return notImplemented();
    }

    # Gets the properties of a directory.
    #
    # + directoryPath - The share-relative path of the directory
    # + return - The `DirectoryProperties`, or an `Error`
    isolated remote function getDirectoryProperties(string directoryPath)
            returns DirectoryProperties|Error {
        return notImplemented();
    }

    # Replaces the metadata of a directory.
    #
    # + directoryPath - The share-relative path of the directory
    # + metadata - The metadata to set
    # + return - An `Error` if the metadata could not be set, otherwise `()`
    isolated remote function setDirectoryMetadata(string directoryPath, map<string> metadata)
            returns Error? {
        return notImplemented();
    }

    # Lists the directories and files directly under a directory.
    #
    # + directoryPath - The share-relative path of the directory to list
    # + options - Optional listing options (prefix, recursion, extended info)
    # + return - A stream of `FileSystemEntry`, or an `Error`
    isolated remote function listDirectoriesAndFiles(string directoryPath, ListOptions? options = ())
            returns stream<FileSystemEntry, Error?>|Error {
        return notImplemented();
    }

    # Renames (moves) a directory within the bound share.
    #
    # + source - The current share-relative path of the directory
    # + destination - The new share-relative path
    # + options - Optional rename options (overwrite, permission, metadata)
    # + return - An `Error` if the directory could not be renamed, otherwise `()`
    isolated remote function renameDirectory(string 'source, string destination, RenameOptions? options = ())
            returns Error? {
        return notImplemented();
    }

    // -----------------------------------------------------------------------
    // File basics
    // -----------------------------------------------------------------------

    # Creates an empty file of a fixed size. Content is written separately via the upload or
    # range operations.
    #
    # + path - The share-relative path of the file to create
    # + fileSizeBytes - The size to provision for the file, in bytes
    # + options - Optional creation options (headers, metadata, permission, SMB properties)
    # + return - An `Error` if the file could not be created, otherwise `()`
    isolated remote function create(string path, int fileSizeBytes, CreateOptions? options = ())
            returns Error? {
        return notImplemented();
    }

    # Deletes a file from the bound share.
    #
    # + path - The share-relative path of the file to delete
    # + return - An `Error` if the file could not be deleted, otherwise `()`
    isolated remote function delete(string path) returns Error? {
        return notImplemented();
    }

    # Checks whether a file exists in the bound share.
    #
    # + path - The share-relative path of the file
    # + return - `true` if the file exists, `false` if not, or an `Error`
    isolated remote function exists(string path) returns boolean|Error {
        return notImplemented();
    }

    # Gets the properties of a file.
    #
    # + path - The share-relative path of the file
    # + return - The `Properties`, or an `Error`
    isolated remote function getProperties(string path) returns Properties|Error {
        return notImplemented();
    }

    # Replaces the metadata of a file.
    #
    # + path - The share-relative path of the file
    # + metadata - The metadata to set
    # + return - An `Error` if the metadata could not be set, otherwise `()`
    isolated remote function setMetadata(string path, map<string> metadata) returns Error? {
        return notImplemented();
    }

    # Sets the content headers of a file.
    #
    # + path - The share-relative path of the file
    # + headers - The content headers to set
    # + return - An `Error` if the headers could not be set, otherwise `()`
    isolated remote function setHttpHeaders(string path, HttpHeaders headers) returns Error? {
        return notImplemented();
    }

    # Renames (moves) a file within the bound share.
    #
    # + source - The current share-relative path of the file
    # + destination - The new share-relative path
    # + options - Optional rename options (overwrite, permission, metadata)
    # + return - An `Error` if the file could not be renamed, otherwise `()`
    isolated remote function rename(string 'source, string destination, RenameOptions? options = ())
            returns Error? {
        return notImplemented();
    }

    // -----------------------------------------------------------------------
    // File transfer
    // -----------------------------------------------------------------------

    # Uploads a local file to the bound share.
    #
    # + path - The destination share-relative path
    # + source - The path of the local file to upload
    # + options - Optional upload options (headers, metadata)
    # + return - An `Error` if the upload failed, otherwise `()`
    isolated remote function upload(string path, string 'source, UploadOptions? options = ())
            returns Error? {
        return notImplemented();
    }

    # Uploads an in-memory byte array to the bound share.
    #
    # + path - The destination share-relative path
    # + content - The bytes to upload
    # + options - Optional upload options (headers, metadata)
    # + return - An `Error` if the upload failed, otherwise `()`
    isolated remote function uploadFromBytes(string path, byte[] content, UploadOptions? options = ())
            returns Error? {
        return notImplemented();
    }

    # Uploads a byte stream to the bound share. The content length must be known up front because
    # Azure Files pre-allocates the file.
    #
    # + path - The destination share-relative path
    # + content - The byte stream to upload
    # + contentLength - The total length of the content, in bytes
    # + options - Optional upload options (headers, metadata)
    # + return - An `Error` if the upload failed, otherwise `()`
    isolated remote function uploadFromStream(string path, stream<byte[], io:Error?> content,
            int contentLength, UploadOptions? options = ()) returns Error? {
        return notImplemented();
    }

    # Uploads structured content (`string`, `xml`, or `json`) to the bound share. The value is
    # serialized to bytes before upload.
    #
    # + path - The destination share-relative path
    # + content - The content to upload
    # + options - Optional upload options (headers, metadata)
    # + return - An `Error` if the upload failed, otherwise `()`
    isolated remote function uploadContent(string path, string|xml|json content, UploadOptions? options = ())
            returns Error? {
        return notImplemented();
    }

    # Downloads a file to a local path.
    #
    # + path - The source share-relative path
    # + destination - The local path to write the downloaded file to
    # + options - Optional download options (range, MD5)
    # + return - An `Error` if the download failed, otherwise `()`
    isolated remote function download(string path, string destination, DownloadOptions? options = ())
            returns Error? {
        return notImplemented();
    }

    # Downloads a file into an in-memory byte array.
    #
    # + path - The source share-relative path
    # + options - Optional download options (range, MD5)
    # + return - The file content as bytes, or an `Error`
    isolated remote function getBytes(string path, DownloadOptions? options = ()) returns byte[]|Error {
        return notImplemented();
    }

    # Opens a file as a byte stream for reading.
    #
    # + path - The source share-relative path
    # + return - A byte stream over the file content, or an `Error`
    isolated remote function getStream(string path) returns stream<byte[], io:Error?>|Error {
        return notImplemented();
    }

    // -----------------------------------------------------------------------
    // File copy
    // -----------------------------------------------------------------------

    # Copies a file within the bound share. The copy is asynchronous; inspect the returned
    # `CopyInfo.copyStatus` and, if pending, poll `getProperties` or abort via `abortCopy`.
    #
    # + source - The source share-relative path
    # + destination - The destination share-relative path
    # + options - Optional copy options (metadata, permission handling)
    # + return - The `CopyInfo` for the started copy, or an `Error`
    isolated remote function copy(string 'source, string destination, CopyOptions? options = ())
            returns CopyInfo|Error {
        return notImplemented();
    }

    # Copies a file from an external URL into the bound share.
    #
    # + sourceUrl - The URL of the source file
    # + destination - The destination share-relative path
    # + options - Optional copy options (metadata, permission handling)
    # + return - The `CopyInfo` for the started copy, or an `Error`
    isolated remote function copyFromUrl(string sourceUrl, string destination, CopyOptions? options = ())
            returns CopyInfo|Error {
        return notImplemented();
    }

    # Aborts a pending asynchronous copy operation.
    #
    # + path - The destination share-relative path of the copy
    # + copyId - The identifier of the copy to abort (from `CopyInfo.copyId`)
    # + return - An `Error` if the copy could not be aborted, otherwise `()`
    isolated remote function abortCopy(string path, string copyId) returns Error? {
        return notImplemented();
    }

    // -----------------------------------------------------------------------
    // File ranges
    // -----------------------------------------------------------------------

    # Writes a range of bytes into a file at a given offset.
    #
    # + path - The share-relative path of the file
    # + offset - The zero-based byte offset at which to begin writing
    # + content - The bytes to write
    # + return - An `Error` if the range could not be written, otherwise `()`
    isolated remote function uploadRange(string path, int offset, byte[] content) returns Error? {
        return notImplemented();
    }

    # Clears a range of bytes in a file, freeing the underlying storage.
    #
    # + path - The share-relative path of the file
    # + offset - The zero-based byte offset at which to begin clearing
    # + length - The number of bytes to clear
    # + return - An `Error` if the range could not be cleared, otherwise `()`
    isolated remote function clearRange(string path, int offset, int length) returns Error? {
        return notImplemented();
    }

    # Lists the valid (written) byte ranges of a file.
    #
    # + path - The share-relative path of the file
    # + options - Optional range-listing options
    # + return - The list of written `Range`s, or an `Error`
    isolated remote function listRanges(string path, RangeListOptions? options = ()) returns Range[]|Error {
        return notImplemented();
    }

    # Lists the byte ranges of a file that changed relative to a previous snapshot.
    #
    # + path - The share-relative path of the file
    # + previousSnapshotId - The identifier of the baseline snapshot to diff against
    # + options - Optional range-listing options
    # + return - The `RangeDiff` between the snapshots, or an `Error`
    isolated remote function listRangesDiff(string path, string previousSnapshotId,
            RangeListOptions? options = ()) returns RangeDiff|Error {
        return notImplemented();
    }

    # Closes the client and releases any underlying resources.
    #
    # + return - An `Error` if the client could not be closed, otherwise `()`
    isolated remote function close() returns Error? {
        return;
    }
}
