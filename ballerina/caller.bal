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

# The context object passed to a listener service's handlers, exposing a curated, share-scoped
# subset of `Client` to act on the event's file. It cannot be instantiated by user code.
# Handlers name the event's file explicitly, for example `caller->deleteFile(file.path)`.
public isolated client class Caller {

    private final string shareName;

    isolated function init(string shareName) {
        self.shareName = shareName;
    }

    # Downloads a file to a local path. An existing local file at `destinationPath` fails the
    # download with a `ProcessingError`.
    #
    # + sourcePath - The share-relative path of the file to download, including the file name
    # + destinationPath - The local path to write the downloaded file to (must not exist)
    # + options - Optional download options (range)
    # + return - An `Error` if the download failed, otherwise `()`
    isolated remote function downloadFile(string sourcePath, string destinationPath,
            DownloadOptions? options = ()) returns Error? = @java:Method {
        'class: "io.ballerina.lib.azure.storage.files.TransferOps"
    } external;

    # Opens a file's content as a byte stream.
    #
    # + path - The source share-relative path
    # + options - Optional download options (range)
    # + return - A byte stream over the file content, or an `Error`
    isolated remote function getFileContent(string path, DownloadOptions? options = ())
            returns stream<byte[], Error?>|Error {
        ContentStreamGenerator generator = new;
        Error? result = openCallerContentStream(self, generator, path, options);
        if result is Error {
            return result;
        }
        return new stream<byte[], Error?>(generator);
    }

    # Uploads a local file to the watched share.
    #
    # + sourcePath - The path of the local file to upload, including the file name
    # + destinationPath - The share-relative path the file is written to, including the file name
    # + options - Optional upload options (headers, metadata, permission, SMB properties)
    # + return - An `Error` if the upload failed, otherwise `()`
    isolated remote function uploadFile(string sourcePath, string destinationPath,
            UploadOptions? options = ()) returns Error? = @java:Method {
        'class: "io.ballerina.lib.azure.storage.files.TransferOps"
    } external;

    # Uploads in-memory content to the watched share. Dispatch is by the value's runtime type:
    # `byte[]` is written as-is, a `string` as raw text, `xml` as its textual form, and a
    # `map<json>` (including compatible records) as a JSON document.
    #
    # + content - The content to upload
    # + destinationPath - The share-relative path the content is written to, including the file name
    # + options - Optional upload options (headers, metadata, permission, SMB properties)
    # + return - An `Error` if the upload failed, otherwise `()`
    isolated remote function uploadContent(byte[]|string|xml|map<json> content,
            string destinationPath, UploadOptions? options = ()) returns Error? = @java:Method {
        'class: "io.ballerina.lib.azure.storage.files.TransferOps"
    } external;

    # Deletes a file from the watched share.
    #
    # + path - The share-relative path of the file to delete
    # + return - An `Error` if the file could not be deleted, otherwise `()`
    isolated remote function deleteFile(string path) returns Error? = @java:Method {
        'class: "io.ballerina.lib.azure.storage.files.FileOps"
    } external;

    # Renames or moves a file within the watched share. An existing destination file is
    # overwritten only when `RenameOptions.replaceIfExists` is set.
    #
    # + sourcePath - The current share-relative path of the file
    # + destinationPath - The new share-relative path
    # + options - Optional rename options (overwrite, permission, metadata)
    # + return - An `Error` if the file could not be renamed, otherwise `()`
    isolated remote function renameFile(string sourcePath, string destinationPath,
            RenameOptions? options = ()) returns Error? = @java:Method {
        'class: "io.ballerina.lib.azure.storage.files.FileOps"
    } external;

    # Copies a file within the watched share. The copy is asynchronous; inspect the returned
    # `CopyInfo.copyStatus` for its state.
    #
    # + sourcePath - The source share-relative path
    # + destinationPath - The destination share-relative path
    # + options - Optional copy options (metadata, permission handling)
    # + return - The `CopyInfo` for the started copy, or an `Error`
    isolated remote function copyFile(string sourcePath, string destinationPath,
            CopyOptions? options = ()) returns CopyInfo|Error = @java:Method {
        'class: "io.ballerina.lib.azure.storage.files.CopyOps"
    } external;

    # Checks the state of the most recent copy operation that targeted a file.
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

    # Creates a directory in the watched share.
    #
    # + directoryPath - The share-relative path of the directory to create
    # + options - Optional creation options (metadata, permission, SMB properties)
    # + return - An `Error` if the directory could not be created, otherwise `()`
    isolated remote function createDirectory(string directoryPath, DirectoryCreateOptions? options = ())
            returns Error? = @java:Method {
        'class: "io.ballerina.lib.azure.storage.files.DirectoryOps"
    } external;

    # Deletes a directory from the watched share. The directory must be empty.
    #
    # + directoryPath - The share-relative path of the directory to delete
    # + return - An `Error` if the directory could not be deleted, otherwise `()`
    isolated remote function deleteDirectory(string directoryPath) returns Error? = @java:Method {
        'class: "io.ballerina.lib.azure.storage.files.DirectoryOps"
    } external;

    # Lists the entries (files and subdirectories) under a directory of the watched share.
    #
    # + directoryPath - The share-relative path of the directory to list
    # + options - Optional listing options (prefix, recursion, extended info)
    # + return - A stream of `Entry`, or an `Error`
    isolated remote function list(string directoryPath, ListOptions? options = ())
            returns stream<Entry, Error?>|Error {
        EntryStreamGenerator generator = new;
        Error? result = newCallerEntryIterator(self, generator, directoryPath, options ?: {});
        if result is Error {
            return result;
        }
        return new stream<Entry, Error?>(generator);
    }

    # Returns the name of the share this caller is bound to.
    #
    # + return - The watched share name
    public isolated function getShareName() returns string {
        return self.shareName;
    }
}

// These stream-opening natives bind to the same Java statics the `Client` streams use; the
// per-pull and close natives are shared from `natives.bal`.

isolated function newCallerEntryIterator(Caller caller, EntryStreamGenerator generator,
        string directoryPath, ListOptions options) returns Error? = @java:Method {
    name: "newEntryIterator",
    'class: "io.ballerina.lib.azure.storage.files.ListOps"
} external;

isolated function openCallerContentStream(Caller caller, ContentStreamGenerator generator,
        string path, DownloadOptions? options) returns Error? = @java:Method {
    name: "openContentStream",
    'class: "io.ballerina.lib.azure.storage.files.TransferOps"
} external;
