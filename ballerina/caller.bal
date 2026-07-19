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

# Passed to each `Listener` event handler, the `Caller` is bound to the share the listener watches,
# exposing a curated subset of `Client` operations (all taking explicit paths) so a handler can act
# without constructing a separate `Client`. The file that triggered the event is identified by the
# `FileInfo` payload, not the `Caller`; the handler passes that path into whichever op it needs,
# notably `deleteFile`/`renameFile` to consume a processed file. It also exposes `getShareName`.
#
# The `Caller` is created and supplied by the `Listener` — one `Caller` serves every handler
# invocation (it holds no per-event state; the event's file identity travels in the `FileInfo`
# payload). Applications never construct it directly.
public isolated client class Caller {

    private final string shareName;

    # Initializes a `Caller` bound to the listener's share. Module-private: only the `Listener`
    # constructs `Caller` instances.
    #
    # + shareName - The name of the share the listener is watching
    isolated function init(string shareName) {
        self.shareName = shareName;
    }

    # Downloads a file to a local path. Both parameters are full paths including the file name.
    # The local file must not already exist.
    #
    # + sourcePath - The share-relative path of the file to download
    # + destinationPath - The local path to write the downloaded file to (must not exist)
    # + options - Optional download options (range)
    # + return - An `Error` if the download failed, otherwise `()`
    isolated remote function downloadFile(string sourcePath, string destinationPath,
            DownloadOptions? options = ()) returns Error? {
        return notImplemented();
    }

    # Opens a file's content as a byte stream. To read the content into memory, collect the
    # stream (see `Client.getFileContent`).
    #
    # + path - The source share-relative path
    # + options - Optional download options (range)
    # + return - A byte stream over the file content, or an `Error`
    isolated remote function getFileContent(string path, DownloadOptions? options = ())
            returns stream<byte[], Error?>|Error {
        return notImplemented();
    }

    # Uploads a local file to the share. Both parameters are full paths including the file name.
    #
    # + sourcePath - The path of the local file to upload
    # + destinationPath - The share-relative path the file is written to
    # + options - Optional upload options (headers, metadata, permission, SMB properties)
    # + return - An `Error` if the upload failed, otherwise `()`
    isolated remote function uploadFile(string sourcePath, string destinationPath,
            UploadOptions? options = ()) returns Error? {
        return notImplemented();
    }

    # Uploads in-memory content to the share. Dispatch is by the value's **runtime** type:
    # `byte[]` and `string` values are written as-is; `xml` is serialized to its textual form;
    # a `map<json>` — including records, which are subtypes — is serialized as a JSON document.
    # See `Client.uploadContent` for the full dispatch rule.
    #
    # + content - The content to upload
    # + destinationPath - The share-relative path the content is written to
    # + options - Optional upload options (headers, metadata, permission, SMB properties)
    # + return - An `Error` if the upload failed, otherwise `()`
    isolated remote function uploadContent(byte[]|string|xml|map<json> content,
            string destinationPath, UploadOptions? options = ()) returns Error? {
        return notImplemented();
    }

    # Deletes a file from the share.
    #
    # + path - The share-relative path of the file to delete
    # + return - An `Error` if the file could not be deleted, otherwise `()`
    isolated remote function deleteFile(string path) returns Error? {
        return notImplemented();
    }

    # Copies a file within the share.
    #
    # + sourcePath - The source share-relative path
    # + destinationPath - The destination share-relative path
    # + options - Optional copy options
    # + return - The `CopyInfo` for the started copy, or an `Error`
    isolated remote function copyFile(string sourcePath, string destinationPath,
            CopyOptions? options = ()) returns CopyInfo|Error {
        return notImplemented();
    }

    # Aborts a pending asynchronous copy operation.
    #
    # + path - The destination share-relative path of the copy
    # + copyId - The identifier of the copy to abort
    # + return - An `Error` if the copy could not be aborted, otherwise `()`
    isolated remote function abortCopy(string path, string copyId) returns Error? {
        return notImplemented();
    }

    # Renames (moves) a file within the share. An existing destination file is overwritten only
    # when `RenameOptions.replaceIfExists` is set; an existing destination directory always fails
    # the operation (see `Client.renameFile`).
    #
    # + sourcePath - The current share-relative path of the file
    # + destinationPath - The new share-relative path
    # + options - Optional rename options
    # + return - An `Error` if the file could not be renamed, otherwise `()`
    isolated remote function renameFile(string sourcePath, string destinationPath,
            RenameOptions? options = ()) returns Error? {
        return notImplemented();
    }

    # Creates a directory in the share.
    #
    # + directoryPath - The share-relative path of the directory to create
    # + options - Optional creation options
    # + return - An `Error` if the directory could not be created, otherwise `()`
    isolated remote function createDirectory(string directoryPath, DirectoryCreateOptions? options = ())
            returns Error? {
        return notImplemented();
    }

    # Deletes a directory from the share. The directory must be empty.
    #
    # + directoryPath - The share-relative path of the directory to delete
    # + return - An `Error` if the directory could not be deleted, otherwise `()`
    isolated remote function deleteDirectory(string directoryPath) returns Error? {
        return notImplemented();
    }

    # Lists the entries (files and subdirectories) under a directory.
    #
    # + directoryPath - The share-relative path of the directory to list
    # + options - Optional listing options
    # + return - A stream of `Entry`, or an `Error`
    isolated remote function list(string directoryPath, ListOptions? options = ())
            returns stream<Entry, Error?>|Error {
        return notImplemented();
    }

    # Returns the name of the share the listener is watching. This reads local state — no
    # network call is made, so it is an ordinary method, not a remote one.
    #
    # + return - The share name
    public isolated function getShareName() returns string {
        return self.shareName;
    }
}
