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

# Share-scoped client for Azure Files. Bound to a single share at initialization, it operates
# on that share and the directories and files within it. For account-level share management
# (create/list/delete shares), use `AdminClient`.
#
# The file is the default resource tier: file operations are unprefixed (`upload`, `getProperties`,
# `create`), directory operations carry a `Directory` token (`createDirectory`), and share-level
# operations carry a `Share` token (`getShareProperties`).
#
# Share-relative paths accept both the leading-slash and bare forms (`/dir/file.ext` and
# `dir/file.ext` name the same resource); documentation and event records standardize on the
# leading-slash form.
#
# The client is `isolated` and holds only immutable configuration, so its operations are safe to
# invoke concurrently.
public isolated client class Client {

    private final string shareName;

    # Initializes the client and binds it to a single share. Binding is lazy — no call is made
    # to Azure, so initializing against a share that does not exist succeeds; the first operation
    # on it fails with a `NotFoundError`. Use `shareExists` to check up front.
    #
    # + shareName - The name of the share this client operates on
    # + config - The client configuration (authentication, etc.), passed as named arguments
    # + return - An `Error` if the client could not be initialized, otherwise `()`
    public isolated function init(string shareName, *ClientConfiguration config) returns Error? {
        self.shareName = shareName;
    }

    // -----------------------------------------------------------------------
    // Share operations
    // -----------------------------------------------------------------------

    # Checks whether the bound share exists. Returns `false` only when Azure confirms the share
    # is absent (HTTP 404); an `Error` means the check itself failed (e.g. invalid credentials,
    # network failure) and the share's existence could not be determined.
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

    # Replaces the metadata of the bound share.
    #
    # + metadata - The metadata to set
    # + return - An `Error` if the metadata could not be set, otherwise `()`
    isolated remote function setShareMetadata(map<string> metadata) returns Error? {
        return notImplemented();
    }

    # Gets the approximate amount of data stored on the bound share, in bytes.
    #
    # + return - The share usage in bytes, or an `Error`
    isolated remote function getShareUsage() returns int|Error {
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

    # Lists the entries (files and subdirectories) under a directory. Entries stream lazily
    # (the service pages at 5,000 entries per round-trip), so memory stays bounded on large
    # directories. Every `Entry` carries its full share-relative `path`, so results feed
    # directly into the path-taking operations; filter on `Entry.isDirectory` to separate
    # files from directories. The service lists one directory level per call, so recursive
    # listing (`ListOptions.recursive`) is performed by the connector walking subdirectories.
    #
    # + directoryPath - The share-relative path of the directory to list
    # + options - Optional listing options (prefix, recursion, extended info)
    # + return - A stream of `Entry`, or an `Error`
    isolated remote function list(string directoryPath, ListOptions? options = ())
            returns stream<Entry, Error?>|Error {
        return notImplemented();
    }

    # Renames or moves a directory within the bound share — together with its entire contents
    # (the directory need not be empty, unlike `deleteDirectory`; files inside with open handles
    # block the rename). The destination is a full share-relative path, so this also moves across
    # parents (e.g. `/X/A` to `/Y/A`), but never into the directory's own subtree. A directory can
    # never overwrite an existing directory; with `RenameOptions.replaceIfExists` it may overwrite
    # an existing **file** at the destination. Moving across shares is not possible.
    #
    # + sourcePath - The current share-relative path of the directory
    # + destinationPath - The new share-relative path
    # + options - Optional rename options (overwrite, permission, metadata)
    # + return - An `Error` if the directory could not be renamed, otherwise `()`
    isolated remote function renameDirectory(string sourcePath, string destinationPath,
            RenameOptions? options = ()) returns Error? {
        return notImplemented();
    }

    // -----------------------------------------------------------------------
    // File basics
    // -----------------------------------------------------------------------

    # Creates an empty file of a fixed size. Content is written separately via the upload or
    # range operations.
    #
    # + path - The share-relative path of the file to create
    # + sizeBytes - The size to provision for the file, in bytes
    # + options - Optional creation options (headers, metadata, permission, SMB properties)
    # + return - An `Error` if the file could not be created, otherwise `()`
    isolated remote function create(string path, int sizeBytes, CreateOptions? options = ())
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

    # Replaces the metadata of a file. There is deliberately no matching getter: metadata
    # arrives on `getProperties` (the underlying SDK exposes no separate metadata read either),
    # so a dedicated getter would add a method with no new capability.
    #
    # + path - The share-relative path of the file
    # + metadata - The metadata to set
    # + return - An `Error` if the metadata could not be set, otherwise `()`
    isolated remote function setMetadata(string path, map<string> metadata) returns Error? {
        return notImplemented();
    }

    # Sets the content headers of a file. This **replaces the complete content-header set**:
    # any header omitted from `headers` is cleared on the file (the underlying Set File
    # Properties operation is a destructive replace, not a merge). SMB properties, permissions,
    # and metadata are unaffected.
    #
    # + path - The share-relative path of the file
    # + headers - The full set of content headers the file should carry
    # + return - An `Error` if the headers could not be set, otherwise `()`
    isolated remote function setContentHeaders(string path, ContentHeaders headers) returns Error? {
        return notImplemented();
    }

    # Renames or moves a file within the bound share. The destination is a full share-relative
    # path, so this also moves across directories (e.g. `/X/a.txt` to `/Y/a.txt`). An existing
    # destination file is overwritten only when `RenameOptions.replaceIfExists` is set; an
    # existing destination directory always fails the operation. Moving across shares is not
    # possible.
    #
    # + sourcePath - The current share-relative path of the file
    # + destinationPath - The new share-relative path
    # + options - Optional rename options (overwrite, permission, metadata)
    # + return - An `Error` if the file could not be renamed, otherwise `()`
    isolated remote function rename(string sourcePath, string destinationPath,
            RenameOptions? options = ()) returns Error? {
        return notImplemented();
    }

    // -----------------------------------------------------------------------
    // File transfer
    // -----------------------------------------------------------------------

    # Uploads a **local file on disk** to the bound share (the bare verb names the default
    # transfer medium — the local file; use `uploadContent`/`uploadFromStream` for in-memory
    # or streamed content). Large content is transferred in service-compliant chunks
    # (at most 4 MiB per range write) internally.
    #
    # + path - The destination share-relative path
    # + localPath - The path of the local file to upload
    # + options - Optional upload options (headers, metadata, permission, SMB properties)
    # + return - An `Error` if the upload failed, otherwise `()`
    isolated remote function upload(string path, string localPath, UploadOptions? options = ())
            returns Error? {
        return notImplemented();
    }

    # Uploads in-memory content to the bound share. Dispatch is by the value's **runtime** type:
    # `byte[]` is written as-is; a `string` is written as raw text, never JSON-quoted — this
    # applies even when the variable's static type is `json`, so a `json` value holding a bare
    # string produces a file that is not parseable JSON (serialize the value to a JSON string
    # explicitly, e.g. with toJsonString(), if a JSON document is intended); `xml` is serialized
    # to its textual form; all other `json` values are serialized as JSON.
    #
    # + path - The destination share-relative path
    # + content - The content to upload
    # + options - Optional upload options (headers, metadata, permission, SMB properties)
    # + return - An `Error` if the upload failed, otherwise `()`
    isolated remote function uploadContent(string path, byte[]|string|xml|json content,
            UploadOptions? options = ()) returns Error? {
        return notImplemented();
    }

    # Uploads a byte stream to the bound share. The content length must be known up front because
    # Azure Files pre-allocates the file. The stream may complete with any `error` (e.g. from a
    # transforming source such as an encrypting wrapper); a source-stream error aborts the upload
    # and is surfaced as a `ProcessingError` carrying the cause.
    #
    # + path - The destination share-relative path
    # + content - The byte stream to upload
    # + contentLength - The total length of the content, in bytes
    # + options - Optional upload options (headers, metadata, permission, SMB properties)
    # + return - An `Error` if the upload failed, otherwise `()`
    isolated remote function uploadFromStream(string path, stream<byte[], error?> content,
            int contentLength, UploadOptions? options = ()) returns Error? {
        return notImplemented();
    }

    # Downloads a file to a local path. The local file must not already exist — an existing
    # file at `localPath` fails the download with a `ProcessingError` (delete it first to
    # re-download).
    #
    # + path - The source share-relative path
    # + localPath - The local path to write the downloaded file to (must not exist)
    # + options - Optional download options (range)
    # + return - An `Error` if the download failed, otherwise `()`
    isolated remote function download(string path, string localPath, DownloadOptions? options = ())
            returns Error? {
        return notImplemented();
    }

    # Downloads a file into an in-memory byte array.
    #
    # + path - The source share-relative path
    # + options - Optional download options (range)
    # + return - The file content as bytes, or an `Error`
    isolated remote function getBytes(string path, DownloadOptions? options = ()) returns byte[]|Error {
        return notImplemented();
    }

    # Opens a file as a byte stream for reading.
    #
    # + path - The source share-relative path
    # + options - Optional download options (range)
    # + return - A byte stream over the file content, or an `Error`
    isolated remote function getStream(string path, DownloadOptions? options = ())
            returns stream<byte[], Error?>|Error {
        return notImplemented();
    }

    // -----------------------------------------------------------------------
    // File copy
    // -----------------------------------------------------------------------

    # Copies a file within the bound share. The source needs no separate authorization — a
    # same-account copy is authorized by this client's credentials. The copy is asynchronous;
    # inspect the returned `CopyInfo.copyStatus` and, if pending, poll `getProperties` or abort
    # via `abortCopy`.
    #
    # + sourcePath - The source share-relative path
    # + destinationPath - The destination share-relative path
    # + options - Optional copy options (metadata, permission handling)
    # + return - The `CopyInfo` for the started copy, or an `Error`
    isolated remote function copy(string sourcePath, string destinationPath,
            CopyOptions? options = ()) returns CopyInfo|Error {
        return notImplemented();
    }

    # Copies a file from an external URL into the bound share. A source in a **different**
    # storage account — or any blob source — must carry its own authorization in the URL
    # (typically a SAS token); a source file URL in the same account is authorized by this
    # client's credentials, and a public blob URL needs none.
    #
    # + sourceUrl - The URL of the source file
    # + destinationPath - The destination share-relative path
    # + options - Optional copy options (metadata, permission handling)
    # + return - The `CopyInfo` for the started copy, or an `Error`
    isolated remote function copyFromUrl(string sourceUrl, string destinationPath,
            CopyOptions? options = ()) returns CopyInfo|Error {
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

    # Writes a range of bytes into a file at a given offset. This is a single low-level range
    # write: the service caps one range write at **4 MiB**, and larger content is rejected with
    # HTTP 413 (`RequestBodyTooLarge`) — no chunking is performed here. For content of arbitrary
    # size, use the transfer operations (`upload`/`uploadContent`/`uploadFromStream`), which
    # chunk internally.
    #
    # + path - The share-relative path of the file
    # + offset - The zero-based byte offset at which to begin writing
    # + content - The bytes to write (at most 4 MiB)
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

    # Closes the client. Subsequent operations on a closed client fail. Releases any
    # connector-owned resources; the SDK's default HTTP transport is shared and
    # process-managed, so with the default transport this is a lifecycle guard (a
    # connector-owned transport configured post-v0.1 is torn down here).
    #
    # + return - An `Error` if the client could not be closed, otherwise `()`
    isolated remote function close() returns Error? {
        return;
    }
}
