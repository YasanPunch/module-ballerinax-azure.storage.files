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

# Share-scoped client for Azure Files. Bound to a single share at initialization, it operates
# on that share and the directories and files within it. For account-level share management
# (create/list/delete shares, existence checks), use `AdminClient`.
public isolated client class Client {

    private final string shareName;

    # Initializes the client and binds it to a single share.
    # When binding, no call is made to Azure, so initializing against a share that does not
    # exist succeeds; the first operation on it fails with a `NotFoundError`. Use
    # `AdminClient.hasShare` to check up front.
    #
    # + shareName - The name of the share this client operates on
    # + config - The client configuration (authentication, retry, transport)
    # + return - An `Error` if the client could not be initialized, otherwise `()`
    public isolated function init(string shareName, *ClientConfiguration config) returns Error? {
        self.shareName = shareName;
        return initClient(self, shareName, config);
    }

    // -----------------------------------------------------------------------
    // Share operations
    // -----------------------------------------------------------------------

    # Gets the properties of the bound share.
    #
    # + return - The `ShareProperties`, or an `Error`
    isolated remote function getShareProperties() returns ShareProperties|Error = @java:Method {
        'class: "io.ballerina.lib.azure.storage.files.ShareOps"
    } external;

    # Replaces the metadata of the bound share. Metadata is free-form, user-defined annotation
    # (Azure stores and returns it verbatim; it has no service-side meaning). Violations
    # fail with an `Error` carrying Azure's error code. Read metadata back with
    # `getShareProperties`.
    #
    # + metadata - The complete metadata set (replaces all existing metadata)
    # + return - An `Error` if the metadata could not be set, otherwise `()`
    isolated remote function setShareMetadata(map<string> metadata) returns Error? = @java:Method {
        'class: "io.ballerina.lib.azure.storage.files.ShareOps"
    } external;

    # Gets the approximate amount of data stored on the bound share, in bytes.
    #
    # + return - The share usage in bytes, or an `Error`
    isolated remote function getShareUsage() returns int|Error = @java:Method {
        'class: "io.ballerina.lib.azure.storage.files.ShareOps"
    } external;

    // -----------------------------------------------------------------------
    // Directory operations
    // -----------------------------------------------------------------------

    # Creates a directory in the bound share.
    #
    # + directoryPath - The share-relative path of the directory to create
    # + options - Optional creation options (metadata, permission, SMB properties)
    # + return - An `Error` if the directory could not be created, otherwise `()`
    isolated remote function createDirectory(string directoryPath, DirectoryCreateOptions? options = ())
            returns Error? = @java:Method {
        'class: "io.ballerina.lib.azure.storage.files.DirectoryOps"
    } external;

    # Deletes a directory from the bound share. The directory must be empty.
    #
    # + directoryPath - The share-relative path of the directory to delete
    # + return - An `Error` if the directory could not be deleted, otherwise `()`
    isolated remote function deleteDirectory(string directoryPath) returns Error? = @java:Method {
        'class: "io.ballerina.lib.azure.storage.files.DirectoryOps"
    } external;

    # Checks whether a directory exists in the bound share.
    #
    # + directoryPath - The share-relative path of the directory
    # + return - `true` if the directory exists, `false` if not, or an `Error`
    isolated remote function hasDirectory(string directoryPath) returns boolean|Error = @java:Method {
        'class: "io.ballerina.lib.azure.storage.files.DirectoryOps"
    } external;

    # Gets the properties of a directory.
    #
    # + directoryPath - The share-relative path of the directory
    # + return - The `DirectoryProperties`, or an `Error`
    isolated remote function getDirectoryProperties(string directoryPath)
            returns DirectoryProperties|Error = @java:Method {
        'class: "io.ballerina.lib.azure.storage.files.DirectoryOps"
    } external;

    # Replaces the metadata of a directory. Metadata is free-form, user-defined annotation.
    # Read metadata back with `getDirectoryProperties`.
    #
    # + directoryPath - The share-relative path of the directory
    # + metadata - The complete metadata set (replaces all existing metadata)
    # + return - An `Error` if the metadata could not be set, otherwise `()`
    isolated remote function setDirectoryMetadata(string directoryPath, map<string> metadata)
            returns Error? = @java:Method {
        'class: "io.ballerina.lib.azure.storage.files.DirectoryOps"
    } external;

    # Lists the entries (files and subdirectories) under a directory. Entries stream lazily,
    # so memory stays bounded on large directories. Every `Entry` carries its full
    # share-relative `path`; filter on `Entry.isDirectory` to separate files from
    # directories. Use `ListOptions.recursive` to include subdirectory levels.
    #
    # + directoryPath - The share-relative path of the directory to list
    # + options - Optional listing options (prefix, recursion, extended info)
    # + return - A stream of `Entry`, or an `Error`
    isolated remote function list(string directoryPath, ListOptions? options = ())
            returns stream<Entry, Error?>|Error {
        EntryStreamGenerator generator = new;
        Error? result = newEntryIterator(self, generator, directoryPath, options ?: {});
        if result is Error {
            return result;
        }
        return new stream<Entry, Error?>(generator);
    }

    # Renames or moves a directory within the bound share, together with its entire contents.
    # The destination is a full share-relative path, so this also moves across parents
    # (e.g. `/X/A` to `/Y/A`), but never into the directory's own subtree. A directory can
    # never overwrite an existing directory; with `RenameOptions.replaceIfExists` it may
    # overwrite an existing file at the destination. Moving across shares is not possible.
    #
    # + sourcePath - The current share-relative path of the directory
    # + destinationPath - The new share-relative path
    # + options - Optional rename options (overwrite, permission, metadata)
    # + return - An `Error` if the directory could not be renamed, otherwise `()`
    isolated remote function renameDirectory(string sourcePath, string destinationPath,
            RenameOptions? options = ()) returns Error? = @java:Method {
        'class: "io.ballerina.lib.azure.storage.files.DirectoryOps"
    } external;

    // -----------------------------------------------------------------------
    // File basics
    // -----------------------------------------------------------------------

    # Creates an empty file of a fixed size. Azure Files pre-allocates the file at this size;
    # content is written separately via the upload or range operations.
    #
    # + path - The share-relative path of the file to create
    # + sizeInBytes - The size to provision (allocate) for the file, in bytes
    # + options - Optional creation options (headers, metadata, permission, SMB properties)
    # + return - An `Error` if the file could not be created, otherwise `()`
    isolated remote function createFile(string path, int sizeInBytes, CreateOptions? options = ())
            returns Error? = @java:Method {
        'class: "io.ballerina.lib.azure.storage.files.FileOps"
    } external;

    # Deletes a file from the bound share.
    #
    # + path - The share-relative path of the file to delete
    # + return - An `Error` if the file could not be deleted, otherwise `()`
    isolated remote function deleteFile(string path) returns Error? = @java:Method {
        'class: "io.ballerina.lib.azure.storage.files.FileOps"
    } external;

    # Checks whether a file exists in the bound share.
    #
    # + path - The share-relative path of the file
    # + return - `true` if the file exists, `false` if not, or an `Error`
    isolated remote function hasFile(string path) returns boolean|Error = @java:Method {
        'class: "io.ballerina.lib.azure.storage.files.FileOps"
    } external;

    # Gets the properties of a file.
    #
    # + path - The share-relative path of the file
    # + return - The `FileProperties`, or an `Error`
    isolated remote function getFileProperties(string path) returns FileProperties|Error = @java:Method {
        'class: "io.ballerina.lib.azure.storage.files.FileOps"
    } external;

    # Replaces the metadata of a file. Metadata is free-form, user-defined annotation.
    # Read metadata back with `getFileProperties`.
    #
    # + path - The share-relative path of the file
    # + metadata - The complete metadata set (replaces all existing metadata)
    # + return - An `Error` if the metadata could not be set, otherwise `()`
    isolated remote function setFileMetadata(string path, map<string> metadata) returns Error? = @java:Method {
        'class: "io.ballerina.lib.azure.storage.files.FileOps"
    } external;

    # Sets the content headers of a file, such as `Content-Type` and `Cache-Control`. This
    # replaces the complete content-header set: any header omitted from `headers` is cleared
    # on the file. SMB properties, permissions, and metadata are unaffected.
    #
    # + path - The share-relative path of the file
    # + headers - The full set of content headers the file should carry
    # + return - An `Error` if the headers could not be set, otherwise `()`
    isolated remote function setContentHeaders(string path, ContentHeaders headers) returns Error? = @java:Method {
        'class: "io.ballerina.lib.azure.storage.files.FileOps"
    } external;

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
    isolated remote function renameFile(string sourcePath, string destinationPath,
            RenameOptions? options = ()) returns Error? = @java:Method {
        'class: "io.ballerina.lib.azure.storage.files.FileOps"
    } external;

    // -----------------------------------------------------------------------
    // File transfer
    // -----------------------------------------------------------------------

    # Uploads a local file on disk to the bound share (use `uploadContent`/`uploadFromStream`
    # for in-memory or streamed content). Both parameters are full paths including the file
    # name. Large content is transferred internally in service-compliant chunks.
    #
    # ```ballerina
    # // ./reports/q1.pdf (local disk) --> /2026/q1/report.pdf (on the share)
    # check client->uploadFile("./reports/q1.pdf", "/2026/q1/report.pdf");
    # ```
    #
    # + sourcePath - The path of the local file to upload, including the file name
    # + destinationPath - The share-relative path the file is written to, including the file name
    # + options - Optional upload options (headers, metadata, permission, SMB properties)
    # + return - An `Error` if the upload failed, otherwise `()`
    isolated remote function uploadFile(string sourcePath, string destinationPath,
            UploadOptions? options = ()) returns Error? = @java:Method {
        'class: "io.ballerina.lib.azure.storage.files.TransferOps"
    } external;

    # Uploads in-memory content to the bound share. Dispatch is by the value's runtime type:
    # `byte[]` is written as-is, a `string` as raw text, `xml` as its textual form, and a
    # `map<json>` (including compatible records) as a JSON document:
    #
    # ```ballerina
    # check client->uploadContent({revenue: 1250000, growth: 0.12}, "/2026/q1/metrics.json");
    # ```
    #
    # To store a top-level JSON array or scalar, serialize it explicitly first (for example
    # with `toJsonString`) and pass the resulting string.
    #
    # + content - The content to upload
    # + destinationPath - The share-relative path the content is written to, including the file name
    # + options - Optional upload options (headers, metadata, permission, SMB properties)
    # + return - An `Error` if the upload failed, otherwise `()`
    isolated remote function uploadContent(byte[]|string|xml|map<json> content,
            string destinationPath, UploadOptions? options = ()) returns Error? = @java:Method {
        'class: "io.ballerina.lib.azure.storage.files.TransferOps"
    } external;

    # Uploads a byte stream to the bound share. The content length must be known up front because
    # Azure Files pre-allocates the file. The stream may complete with any `error`; a
    # source-stream error aborts the upload and is surfaced as a `ProcessingError`.
    #
    # + content - The byte stream to upload
    # + contentLength - The total length of the content, in bytes
    # + destinationPath - The share-relative path the content is written to, including the file name
    # + options - Optional upload options (headers, metadata, permission, SMB properties)
    # + return - An `Error` if the upload failed, otherwise `()`
    isolated remote function uploadFromStream(stream<byte[], error?> content,
            int contentLength, string destinationPath, UploadOptions? options = ()) returns Error? {
        check prepareStreamUpload(self, destinationPath, contentLength, options);
        int offset = 0;
        while true {
            record {|byte[] value;|}|error? chunk = content.next();
            if chunk is () {
                break;
            }
            if chunk is error {
                return error ProcessingError("the source stream failed: " + chunk.message(),
                        chunk, errorCode = "ProcessingError");
            }
            byte[] bytes = chunk.value;
            if offset + bytes.length() > contentLength {
                return error ProcessingError(
                        string `the source stream exceeded the declared contentLength of ${contentLength} bytes`,
                        errorCode = "ProcessingError");
            }
            check writeStreamChunk(self, destinationPath, offset, bytes);
            offset += bytes.length();
        }
        if offset != contentLength {
            return error ProcessingError(
                    string `the source stream ended at ${offset} bytes but contentLength is ${contentLength}`,
                    errorCode = "ProcessingError");
        }
        return;
    }

    # Downloads a file to a local path. Both parameters are full paths including the file name.
    # An existing local file at `destinationPath` fails the download with a `ProcessingError`.
    #
    # ```ballerina
    # // /2026/q1/report.pdf (on the share) --> ./reports/q1.pdf (local disk)
    # check client->downloadFile("/2026/q1/report.pdf", "./reports/q1.pdf");
    # ```
    #
    # + sourcePath - The share-relative path of the file to download, including the file name
    # + destinationPath - The local path to write the downloaded file to (must not exist)
    # + options - Optional download options (range)
    # + return - An `Error` if the download failed, otherwise `()`
    isolated remote function downloadFile(string sourcePath, string destinationPath,
            DownloadOptions? options = ()) returns Error? = @java:Method {
        'class: "io.ballerina.lib.azure.storage.files.TransferOps"
    } external;

    # Opens a file's content as a byte stream. Reading is lazy, so memory stays bounded for any
    # file size. To read the content into memory, collect the stream:
    #
    # ```ballerina
    # stream<byte[], files:Error?> contentStream = check client->getFileContent("/2026/q1/data.json");
    # byte[] content = [];
    # check contentStream.forEach(function(byte[] chunk) {
    #     content.push(...chunk);
    # });
    # ```
    #
    # + path - The source share-relative path
    # + options - Optional download options (range)
    # + return - A byte stream over the file content, or an `Error`
    isolated remote function getFileContent(string path, DownloadOptions? options = ())
            returns stream<byte[], Error?>|Error {
        ContentStreamGenerator generator = new;
        Error? result = openContentStream(self, generator, path, options);
        if result is Error {
            return result;
        }
        return new stream<byte[], Error?>(generator);
    }

    // -----------------------------------------------------------------------
    // File copy
    // -----------------------------------------------------------------------

    # Copies a file within the bound share, authorized by this client's credentials. The copy
    # is asynchronous; inspect the returned `CopyInfo.copyStatus` and, if pending, observe
    # progress with `checkCopyStatus` or cancel with `abortCopy`.
    #
    # + sourcePath - The source share-relative path
    # + destinationPath - The destination share-relative path
    # + options - Optional copy options (metadata, permission handling)
    # + return - The `CopyInfo` for the started copy, or an `Error`
    isolated remote function copyFile(string sourcePath, string destinationPath,
            CopyOptions? options = ()) returns CopyInfo|Error = @java:Method {
        'class: "io.ballerina.lib.azure.storage.files.CopyOps"
    } external;

    # Copies a file from an external URL into the bound share. A source in a different storage
    # account, or any blob source, must carry its own authorization in the URL (typically a
    # SAS token). A source file URL in the same account is authorized by this client's
    # credentials, and a public blob URL needs none.
    #
    # + sourceUrl - The URL of the source file
    # + destinationPath - The destination share-relative path
    # + options - Optional copy options (metadata, permission handling)
    # + return - The `CopyInfo` for the started copy, or an `Error`
    isolated remote function copyFileFromUrl(string sourceUrl, string destinationPath,
            CopyOptions? options = ()) returns CopyInfo|Error = @java:Method {
        'class: "io.ballerina.lib.azure.storage.files.CopyOps"
    } external;

    # Checks the state of the most recent copy operation that targeted a file. A point-in-time
    # snapshot; call again to observe the progress of a pending copy.
    #
    # + path - The destination share-relative path of the copy
    # + return - The `CopyStatusInfo`, `()` if the file has never been the destination of a
    #            copy operation, or an `Error`
    isolated remote function checkCopyStatus(string path) returns CopyStatusInfo?|Error = @java:Method {
        'class: "io.ballerina.lib.azure.storage.files.CopyOps"
    } external;

    # Aborts a pending asynchronous copy operation.
    #
    # + path - The destination share-relative path of the copy
    # + copyId - The identifier of the copy to abort (from `CopyInfo.copyId`)
    # + return - An `Error` if the copy could not be aborted, otherwise `()`
    isolated remote function abortCopy(string path, string copyId) returns Error? = @java:Method {
        'class: "io.ballerina.lib.azure.storage.files.CopyOps"
    } external;

    // -----------------------------------------------------------------------
    // File ranges
    // -----------------------------------------------------------------------

    # Writes a range of bytes into a file at a given offset. A single range write is capped at
    # 4 MiB by the service; no chunking is performed here. For content of arbitrary size, use
    # the transfer operations (`uploadFile`/`uploadContent`/`uploadFromStream`).
    #
    # + path - The share-relative path of the file
    # + offset - The zero-based byte offset at which to begin writing
    # + content - The bytes to write (at most 4 MiB)
    # + return - An `Error` if the range could not be written, otherwise `()`
    isolated remote function uploadRange(string path, int offset, byte[] content) returns Error? = @java:Method {
        'class: "io.ballerina.lib.azure.storage.files.RangeOps"
    } external;

    # Clears a range of bytes in a file, freeing the underlying storage. Storage deallocates
    # in 512-byte units: a cleared span smaller than that is zeroed but its range may still
    # appear in `listRanges` until the whole unit is cleared.
    #
    # + path - The share-relative path of the file
    # + offset - The zero-based byte offset at which to begin clearing
    # + length - The number of bytes to clear
    # + return - An `Error` if the range could not be cleared, otherwise `()`
    isolated remote function clearRange(string path, int offset, int length) returns Error? = @java:Method {
        'class: "io.ballerina.lib.azure.storage.files.RangeOps"
    } external;

    # Lists the valid (written) byte ranges of a file.
    #
    # + path - The share-relative path of the file
    # + options - Optional range-listing options
    # + return - The list of written `Range`s, or an `Error`
    isolated remote function listRanges(string path, RangeListOptions? options = ())
            returns Range[]|Error = @java:Method {
        'class: "io.ballerina.lib.azure.storage.files.RangeOps"
    } external;

    // -----------------------------------------------------------------------
    // Share snapshots
    // -----------------------------------------------------------------------

    # Creates a point-in-time, read-only snapshot of the bound share. Snapshot contents are
    # read through the regular read operations: pass the returned `snapshotId` in
    # `DownloadOptions` (`downloadFile`, `getFileContent`) or `ListOptions` (`list`) to
    # resolve the same paths inside the snapshot instead of the live share.
    #
    # + metadata - Optional metadata to set on the snapshot; when absent, the share's
    #              metadata is copied to the snapshot
    # + return - The `ShareSnapshotInfo` for the new snapshot, or an `Error`
    isolated remote function createShareSnapshot(map<string>? metadata = ())
            returns ShareSnapshotInfo|Error = @java:Method {
        'class: "io.ballerina.lib.azure.storage.files.SnapshotOps"
    } external;

    # Lists the snapshots of the bound share. Runs a service-level listing, so it needs
    # account-level credentials (an account key, a connection string carrying one, or an
    # account SAS; a share-scoped SAS is not sufficient).
    #
    # + return - The share's snapshots, or an `Error`
    isolated remote function listShareSnapshots() returns ShareSnapshotInfo[]|Error = @java:Method {
        'class: "io.ballerina.lib.azure.storage.files.SnapshotOps"
    } external;

    # Deletes one snapshot of the bound share. The live share and its other snapshots are
    # unaffected. Runs a service-level operation, so it needs account-level credentials.
    #
    # + snapshotId - The identifier of the snapshot to delete
    # + return - An `Error` if the snapshot could not be deleted, otherwise `()`
    isolated remote function deleteShareSnapshot(string snapshotId) returns Error? = @java:Method {
        'class: "io.ballerina.lib.azure.storage.files.SnapshotOps"
    } external;

    # Lists how a file's byte ranges changed since a share snapshot: which ranges were
    # written and which were cleared. Useful for incremental backup on top of snapshots.
    #
    # + path - The share-relative path of the file
    # + previousSnapshotId - The identifier of the baseline snapshot to diff against
    # + options - Optional range-listing options
    # + return - The `RangeDiff`, or an `Error`
    isolated remote function listRangesDiff(string path, string previousSnapshotId,
            RangeListOptions? options = ()) returns RangeDiff|Error = @java:Method {
        'class: "io.ballerina.lib.azure.storage.files.SnapshotOps"
    } external;

    // -----------------------------------------------------------------------
    // Leases
    // -----------------------------------------------------------------------

    # Acquires a lease on the bound share, locking it against deletion (and, for the fixed
    # tier operations, administrative changes) by anyone not holding the lease id. A share
    # lease is fixed-duration (15 to 60 seconds) or infinite (-1) and can be kept alive with
    # `renewShareLease`.
    #
    # + leaseDurationSeconds - The lease duration: 15 to 60 seconds, or -1 for an infinite lease
    # + proposedLeaseId - A proposed lease id (a UUID string); when absent, the service generates one
    # + return - The lease id to present with subsequent operations, or an `Error`
    isolated remote function acquireShareLease(int leaseDurationSeconds,
            string? proposedLeaseId = ()) returns string|Error = @java:Method {
        'class: "io.ballerina.lib.azure.storage.files.LeaseOps"
    } external;

    # Renews a fixed-duration lease on the bound share, restarting its duration.
    #
    # + leaseId - The id of the lease to renew
    # + return - An `Error` if the lease could not be renewed, otherwise `()`
    isolated remote function renewShareLease(string leaseId) returns Error? = @java:Method {
        'class: "io.ballerina.lib.azure.storage.files.LeaseOps"
    } external;

    # Releases a lease on the bound share, unlocking it immediately.
    #
    # + leaseId - The id of the lease to release
    # + return - An `Error` if the lease could not be released, otherwise `()`
    isolated remote function releaseShareLease(string leaseId) returns Error? = @java:Method {
        'class: "io.ballerina.lib.azure.storage.files.LeaseOps"
    } external;

    # Breaks the lease on the bound share without needing its id, for reclaiming a lease
    # whose holder is gone. Once broken, the lease cannot be renewed and a new lease can be
    # acquired after the break period elapses.
    #
    # + breakPeriodSeconds - How long the lease keeps running before it is broken; when
    #                        absent, the lease's own remaining time applies (0 for infinite)
    # + return - The remaining seconds until the lease is broken, or an `Error`
    isolated remote function breakShareLease(int? breakPeriodSeconds = ()) returns int|Error = @java:Method {
        'class: "io.ballerina.lib.azure.storage.files.LeaseOps"
    } external;

    # Changes the id of the active lease on the bound share.
    #
    # + leaseId - The current lease id
    # + proposedLeaseId - The new lease id (a UUID string)
    # + return - The new lease id, or an `Error`
    isolated remote function changeShareLease(string leaseId, string proposedLeaseId)
            returns string|Error = @java:Method {
        'class: "io.ballerina.lib.azure.storage.files.LeaseOps"
    } external;

    # Acquires a lease on a file, locking it against writes and deletion by anyone not
    # holding the lease id. A file lease is always infinite: it takes no duration, never
    # expires on its own, and there is no file-level renew. Release it with `releaseLease`
    # or reclaim it with `breakLease`.
    #
    # + path - The share-relative path of the file
    # + proposedLeaseId - A proposed lease id (a UUID string); when absent, the service generates one
    # + return - The lease id to present with subsequent operations, or an `Error`
    isolated remote function acquireLease(string path, string? proposedLeaseId = ())
            returns string|Error = @java:Method {
        'class: "io.ballerina.lib.azure.storage.files.LeaseOps"
    } external;

    # Releases a lease on a file, unlocking it immediately.
    #
    # + path - The share-relative path of the file
    # + leaseId - The id of the lease to release
    # + return - An `Error` if the lease could not be released, otherwise `()`
    isolated remote function releaseLease(string path, string leaseId) returns Error? = @java:Method {
        'class: "io.ballerina.lib.azure.storage.files.LeaseOps"
    } external;

    # Breaks the lease on a file without needing its id, for reclaiming a lease whose holder
    # is gone. A file lease breaks immediately (there is no break period), after which a new
    # lease can be acquired.
    #
    # + path - The share-relative path of the file
    # + return - An `Error` if the lease could not be broken, otherwise `()`
    isolated remote function breakLease(string path) returns Error? = @java:Method {
        'class: "io.ballerina.lib.azure.storage.files.LeaseOps"
    } external;

    # Changes the id of the active lease on a file.
    #
    # + path - The share-relative path of the file
    # + leaseId - The current lease id
    # + proposedLeaseId - The new lease id (a UUID string)
    # + return - The new lease id, or an `Error`
    isolated remote function changeLease(string path, string leaseId, string proposedLeaseId)
            returns string|Error = @java:Method {
        'class: "io.ballerina.lib.azure.storage.files.LeaseOps"
    } external;

    // -----------------------------------------------------------------------
    // SMB handles
    // -----------------------------------------------------------------------

    # Lists the open SMB handles on a file. Handles are opened by SMB clients (mounted
    # drives); REST operations through this connector do not hold handles.
    #
    # + path - The share-relative path of the file
    # + return - The open handles, or an `Error`
    isolated remote function listFileHandles(string path) returns HandleInfo[]|Error = @java:Method {
        'class: "io.ballerina.lib.azure.storage.files.HandleOps"
    } external;

    # Force-closes open SMB handles on a file, releasing locks whose holders are gone or
    # unresponsive. The affected SMB clients receive an error on their next operation.
    #
    # + path - The share-relative path of the file
    # + handleId - The id of one handle to close (from `listFileHandles`); when absent, all
    #              handles on the file are closed
    # + return - The `CloseHandlesInfo` (closed and failed counts), or an `Error`
    isolated remote function forceCloseFileHandles(string path, string? handleId = ())
            returns CloseHandlesInfo|Error = @java:Method {
        'class: "io.ballerina.lib.azure.storage.files.HandleOps"
    } external;

    # Lists the open SMB handles on a directory.
    #
    # + directoryPath - The share-relative path of the directory
    # + return - The open handles, or an `Error`
    isolated remote function listDirectoryHandles(string directoryPath)
            returns HandleInfo[]|Error = @java:Method {
        'class: "io.ballerina.lib.azure.storage.files.HandleOps"
    } external;

    # Force-closes open SMB handles on a directory, releasing locks whose holders are gone
    # or unresponsive. The affected SMB clients receive an error on their next operation.
    #
    # + directoryPath - The share-relative path of the directory
    # + handleId - The id of one handle to close (from `listDirectoryHandles`); when absent,
    #              all handles on the directory are closed
    # + recursive - Also close handles on the directory's files and subdirectories
    # + return - The `CloseHandlesInfo` (closed and failed counts), or an `Error`
    isolated remote function forceCloseDirectoryHandles(string directoryPath,
            string? handleId = (), boolean recursive = false)
            returns CloseHandlesInfo|Error = @java:Method {
        'class: "io.ballerina.lib.azure.storage.files.HandleOps"
    } external;

    // -----------------------------------------------------------------------
    // Property setters
    // -----------------------------------------------------------------------

    # Changes the bound share's quota or access tier. This is an administrative operation:
    # it needs account-key-level credentials (an account key or a connection string carrying
    # one), and fails with an `AuthorizationError` on SAS credentials.
    #
    # + options - The properties to change; only what is set is changed
    # + return - An `Error` if the properties could not be changed, otherwise `()`
    isolated remote function setShareProperties(ShareSetPropertiesOptions options)
            returns Error? = @java:Method {
        'class: "io.ballerina.lib.azure.storage.files.ShareOps"
    } external;

    # Updates a file's properties after creation: content headers, SMB properties, SDDL
    # permission, size, or POSIX attributes. Only what is set is changed; every omitted
    # field keeps the file's current value.
    #
    # + path - The share-relative path of the file
    # + options - The properties to change
    # + return - An `Error` if the properties could not be changed, otherwise `()`
    isolated remote function setFileProperties(string path, FileSetPropertiesOptions options)
            returns Error? = @java:Method {
        'class: "io.ballerina.lib.azure.storage.files.FileOps"
    } external;

    # Updates a directory's properties after creation: SMB properties, SDDL permission, or
    # POSIX attributes. Only what is set is changed; every omitted field keeps the
    # directory's current value.
    #
    # + directoryPath - The share-relative path of the directory
    # + options - The properties to change
    # + return - An `Error` if the properties could not be changed, otherwise `()`
    isolated remote function setDirectoryProperties(string directoryPath,
            DirectorySetPropertiesOptions options) returns Error? = @java:Method {
        'class: "io.ballerina.lib.azure.storage.files.DirectoryOps"
    } external;

    // -----------------------------------------------------------------------
    // Access policy
    // -----------------------------------------------------------------------

    # Gets the bound share's stored access policies. Share SAS tokens minted against a
    # policy (via `identifier`) inherit its validity window and permissions, so the policies
    # control those tokens retroactively.
    #
    # + return - The share's stored access policies, or an `Error`
    isolated remote function getShareAccessPolicy() returns SignedIdentifier[]|Error = @java:Method {
        'class: "io.ballerina.lib.azure.storage.files.PolicyOps"
    } external;

    # Replaces the bound share's stored access policies (at most five per share). Removing
    # or editing a policy immediately revokes or changes every SAS token minted against it.
    #
    # + identifiers - The complete set of policies the share should carry
    # + return - An `Error` if the policies could not be set, otherwise `()`
    isolated remote function setShareAccessPolicy(SignedIdentifier[] identifiers)
            returns Error? = @java:Method {
        'class: "io.ballerina.lib.azure.storage.files.PolicyOps"
    } external;

    // -----------------------------------------------------------------------
    // Permissions (SDDL)
    // -----------------------------------------------------------------------

    # Gets a security descriptor (SDDL string) from the bound share's permission store, by
    # the key found in `SmbProperties.filePermissionKey`.
    #
    # + permissionKey - The key of the stored permission
    # + return - The SDDL permission string, or an `Error`
    isolated remote function getSharePermission(string permissionKey) returns string|Error = @java:Method {
        'class: "io.ballerina.lib.azure.storage.files.PolicyOps"
    } external;

    # Stores a security descriptor (SDDL string) in the bound share's permission store and
    # returns its key, for applying the same permission to many files via
    # `SmbProperties.filePermissionKey` without repeating the descriptor.
    #
    # + sddlPermission - The SDDL (Security Descriptor Definition Language) string to store
    # + return - The key of the stored permission, or an `Error`
    isolated remote function createSharePermission(string sddlPermission) returns string|Error = @java:Method {
        'class: "io.ballerina.lib.azure.storage.files.PolicyOps"
    } external;

    // -----------------------------------------------------------------------
    // SAS generation
    // -----------------------------------------------------------------------

    # Mints a SAS (Shared Access Signature) token scoped to the bound share. Signing happens
    # locally with the account key, so no call is made to Azure; the client must be
    # authenticated with `SharedKeyConfig` (or a connection string carrying an account key).
    # Note that rotating the account key revokes every SAS minted from it.
    #
    # + values - What the SAS grants: validity window and permissions, or a stored policy reference
    # + return - The SAS token, or an `Error`
    isolated remote function generateShareSas(ShareSasSignatureValues values)
            returns string|Error = @java:Method {
        'class: "io.ballerina.lib.azure.storage.files.SasOps"
    } external;

    # Mints a SAS (Shared Access Signature) token scoped to a single file. Signing happens
    # locally with the account key, so no call is made to Azure; the client must be
    # authenticated with `SharedKeyConfig` (or a connection string carrying an account key).
    #
    # + path - The share-relative path of the file the SAS grants access to
    # + values - What the SAS grants: validity window and permissions, or a stored policy reference
    # + return - The SAS token, or an `Error`
    isolated remote function generateSas(string path, FileSasSignatureValues values)
            returns string|Error = @java:Method {
        'class: "io.ballerina.lib.azure.storage.files.SasOps"
    } external;

    # Mints a user-delegation SAS token scoped to the bound share: signed with a
    # `UserDelegationKey` (from `AdminClient.getUserDelegationKey`) instead of the account
    # key, so no storage key is ever handled. Valid at most 7 days (the key's lifetime), and
    # stored access policies do not apply.
    #
    # + values - What the SAS grants: validity window and permissions
    # + key - The user-delegation key to sign with
    # + return - The SAS token, or an `Error`
    isolated remote function generateShareUserDelegationSas(ShareSasSignatureValues values,
            UserDelegationKey key) returns string|Error = @java:Method {
        'class: "io.ballerina.lib.azure.storage.files.SasOps"
    } external;

    # Mints a user-delegation SAS token scoped to a single file: signed with a
    # `UserDelegationKey` (from `AdminClient.getUserDelegationKey`) instead of the account
    # key, so no storage key is ever handled. Valid at most 7 days (the key's lifetime), and
    # stored access policies do not apply.
    #
    # + path - The share-relative path of the file the SAS grants access to
    # + values - What the SAS grants: validity window and permissions
    # + key - The user-delegation key to sign with
    # + return - The SAS token, or an `Error`
    isolated remote function generateUserDelegationSas(string path,
            FileSasSignatureValues values, UserDelegationKey key)
            returns string|Error = @java:Method {
        'class: "io.ballerina.lib.azure.storage.files.SasOps"
    } external;

    // -----------------------------------------------------------------------
    // NFS links
    // -----------------------------------------------------------------------

    # Creates a hard link to an existing file (NFS shares only). Both paths then refer to
    # the same underlying file, and the file's `PosixProperties.linkCount` grows by one.
    #
    # + path - The share-relative path of the new link
    # + targetPath - The share-relative path of the existing file to link to
    # + return - An `Error` if the link could not be created, otherwise `()`
    isolated remote function createHardLink(string path, string targetPath) returns Error? = @java:Method {
        'class: "io.ballerina.lib.azure.storage.files.FileOps"
    } external;

    # Creates a symbolic link (NFS shares only). The link stores its target as a path,
    # resolved by the NFS client at access time; the target need not exist.
    #
    # + path - The share-relative path of the new link
    # + linkTarget - The path the link points to
    # + return - An `Error` if the link could not be created, otherwise `()`
    isolated remote function createSymbolicLink(string path, string linkTarget) returns Error? = @java:Method {
        'class: "io.ballerina.lib.azure.storage.files.FileOps"
    } external;

    # Reads the target of a symbolic link (NFS shares only).
    #
    # + path - The share-relative path of the link
    # + return - The path the link points to, or an `Error`
    isolated remote function getSymbolicLink(string path) returns string|Error = @java:Method {
        'class: "io.ballerina.lib.azure.storage.files.FileOps"
    } external;

    # Closes the client and releases any connector-owned resources. Subsequent operations on
    # a closed client fail. No call is made to Azure.
    #
    # + return - An `Error` if the client could not be closed, otherwise `()`
    public isolated function close() returns Error? {
        return closeClient(self);
    }
}
