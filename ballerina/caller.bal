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

# The context object passed to a listener service's handlers, exposing a share-scoped
# subset of `Client` to act on the event's file.
# It cannot be instantiated by user code.
public isolated client class Caller {

    private final Client 'client;

    isolated function init(string shareName, *ClientConfiguration config) returns Error? {
        self.'client = check new (shareName, config);
    }

    # Downloads a file to a local path. An existing local file at `destinationPath` fails
    # the download.
    #
    # + sourcePath - The share-relative path of the file to download, including the file name
    # + destinationPath - The local path to write the downloaded file to (must not exist)
    # + options - Optional download options (range)
    # + return - An `Error` if the download failed, otherwise `()`
    isolated remote function downloadFile(string sourcePath, string destinationPath,
            DownloadOptions? options = ()) returns Error? {
        return self.'client->downloadFile(sourcePath, destinationPath, options);
    }

    # Retrieves a file's content in the form the target type selects: raw bytes, UTF-8
    # text, a JSON or XML value, CSV rows, a record or record array, a lazy byte stream,
    # or a lazy stream of CSV-bound records. Binding is strict. A record or record array
    # target binds per the format resolved from `GetFileOptions.fileFormat` when set,
    # else from the path's extension (`.json`, `.xml`, `.csv`).
    #
    # + path - The source share-relative path
    # + options - Optional retrieval options (range, snapshot, record binding format)
    # + targetType - The form to retrieve the content in, inferred from the assignment target
    # + return - The content in the requested form, or an `Error`
    isolated remote function getFile(string path, GetFileOptions? options = (),
            typedesc<RetrievableContent> targetType = <>) returns targetType|Error = @java:Method {
        name: "callerGetFile",
        'class: "io.ballerina.lib.azure.storage.files.client.TypedReadOps"
    } external;

    # Uploads a local file to the watched share.
    #
    # + sourcePath - The path of the local file to upload, including the file name
    # + destinationPath - The share-relative path the file is written to, including the file name
    # + options - Optional upload options (headers, metadata, permission, SMB properties)
    # + return - An `Error` if the upload failed, otherwise `()`
    isolated remote function uploadFile(string sourcePath, string destinationPath,
            UploadOptions? options = ()) returns Error? {
        return self.'client->uploadFile(sourcePath, destinationPath, options);
    }

    # Uploads in-memory content to the watched share. A `byte[]` is written as-is, a `string`
    # as raw text, `xml` as its textual form, and a `string[][]` as CSV rows. A record (which
    # includes any map of `anydata` members) or a record array is serialized per the format
    # inferred from the destination path's extension or set with `UploadContentOptions.fileFormat`:
    # a record becomes a JSON or an XML document (never CSV), and a record array becomes CSV rows.
    #
    # + content - The content to upload
    # + destinationPath - The share-relative path the content is written to, including the file name
    # + options - Optional upload options (headers, metadata, permission, SMB properties, format override)
    # + return - An `Error` if the upload failed, otherwise `()`
    isolated remote function uploadContent(UploadContent content,
            string destinationPath, UploadContentOptions? options = ()) returns Error? {
        return self.'client->uploadContent(content, destinationPath, options);
    }

    # Deletes a file from the watched share.
    #
    # + path - The share-relative path of the file to delete
    # + return - An `Error` if the file could not be deleted, otherwise `()`
    isolated remote function deleteFile(string path) returns Error? {
        return self.'client->deleteFile(path);
    }

    # Renames or moves a file within the watched share. An existing destination file is
    # overwritten only when `RenameOptions.replaceIfExists` is set.
    #
    # + sourcePath - The current share-relative path of the file
    # + destinationPath - The new share-relative path
    # + options - Optional rename options (overwrite, permission, metadata)
    # + return - An `Error` if the file could not be renamed, otherwise `()`
    isolated remote function renameFile(string sourcePath, string destinationPath,
            RenameOptions? options = ()) returns Error? {
        return self.'client->renameFile(sourcePath, destinationPath, options);
    }

    # Copies a file within the watched share. The copy is asynchronous; inspect the returned
    # `CopyInfo.copyStatus` for its state.
    #
    # + sourcePath - The source share-relative path
    # + destinationPath - The destination share-relative path
    # + options - Optional copy options (metadata, permission handling)
    # + return - The `CopyInfo` for the started copy, or an `Error`
    isolated remote function copyFile(string sourcePath, string destinationPath,
            CopyOptions? options = ()) returns CopyInfo|Error {
        return self.'client->copyFile(sourcePath, destinationPath, options);
    }

    # Checks the state of the most recent copy operation that targeted a file.
    #
    # + path - The destination share-relative path of the copy
    # + return - The `CopyStatusInfo`, `()` if the file has never been the destination of a
    #            copy operation, or an `Error`
    isolated remote function checkCopyStatus(string path) returns CopyStatusInfo?|Error {
        return self.'client->checkCopyStatus(path);
    }

    # Aborts a pending asynchronous copy operation.
    #
    # + path - The destination share-relative path of the copy
    # + copyId - The identifier of the copy to abort (from `CopyInfo.copyId`)
    # + return - An `Error` if the copy could not be aborted, otherwise `()`
    isolated remote function abortCopy(string path, string copyId) returns Error? {
        return self.'client->abortCopy(path, copyId);
    }

    # Creates a directory in the watched share.
    #
    # + directoryPath - The share-relative path of the directory to create
    # + options - Optional creation options (metadata, permission, SMB properties)
    # + return - An `Error` if the directory could not be created, otherwise `()`
    isolated remote function createDirectory(string directoryPath, DirectoryCreateOptions? options = ())
            returns Error? {
        return self.'client->createDirectory(directoryPath, options);
    }

    # Deletes a directory from the watched share. The directory must be empty.
    #
    # + directoryPath - The share-relative path of the directory to delete
    # + return - An `Error` if the directory could not be deleted, otherwise `()`
    isolated remote function deleteDirectory(string directoryPath) returns Error? {
        return self.'client->deleteDirectory(directoryPath);
    }

    # Lists the entries (files and subdirectories) under a directory of the watched share.
    #
    # + directoryPath - The share-relative path of the directory to list
    # + options - Optional listing options (prefix, recursion, extended info)
    # + return - A stream of `Entry`, or an `Error`
    isolated remote function list(string directoryPath, ListOptions? options = ())
            returns stream<Entry, Error?>|Error {
        return self.'client->list(directoryPath, options);
    }
}
