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

    isolated function init(Client 'client) {
        self.'client = 'client;
    }

    # Downloads a file to a local path. An existing local file at `destinationPath` fails the
    # download with a `ProcessingError`.
    #
    # + sourcePath - The share-relative path of the file to download, including the file name
    # + destinationPath - The local path to write the downloaded file to (must not exist)
    # + options - Optional download options (range)
    # + return - An `Error` if the download failed, otherwise `()`
    isolated remote function downloadFile(string sourcePath, string destinationPath,
            DownloadOptions? options = ()) returns Error? {
        return self.'client->downloadFile(sourcePath, destinationPath, options);
    }

    # Opens a file's content as a byte stream.
    #
    # + path - The source share-relative path
    # + options - Optional download options (range)
    # + return - A byte stream over the file content, or an `Error`
    isolated remote function getFileContent(string path, DownloadOptions? options = ())
            returns stream<byte[], Error?>|Error {
        return self.'client->getFileContent(path, options);
    }

    # Reads a file's full content as UTF-8 text.
    #
    # + path - The source share-relative path
    # + options - Optional download options (range, snapshot)
    # + return - The file content as a string, or an `Error`
    isolated remote function getFileText(string path, DownloadOptions? options = ())
            returns string|Error {
        return self.'client->getFileText(path, options);
    }

    # Reads a file's full content and binds it as JSON to the target type. Binding is strict:
    # the content must match the target type exactly.
    #
    # + path - The source share-relative path
    # + options - Optional download options (range, snapshot)
    # + targetType - The type to bind the content to, a `json` form or a record
    # + return - The bound value, or an `Error`
    isolated remote function getFileJson(string path, DownloadOptions? options = (),
            typedesc<json|record {}> targetType = <>) returns targetType|Error = @java:Method {
        name: "callerGetFileJson",
        'class: "io.ballerina.lib.azure.storage.files.client.TypedReadOps"
    } external;

    # Reads a file's full content and binds it as XML: to an `xml` value, or to a record
    # projected from the document. Binding is strict.
    #
    # + path - The source share-relative path
    # + options - Optional download options (range, snapshot)
    # + targetType - The type to bind the content to, `xml` or a record
    # + return - The bound value, or an `Error`
    isolated remote function getFileXml(string path, DownloadOptions? options = (),
            typedesc<xml|record {}> targetType = <>) returns targetType|Error = @java:Method {
        name: "callerGetFileXml",
        'class: "io.ballerina.lib.azure.storage.files.client.TypedReadOps"
    } external;

    # Reads a file's full content and binds it as CSV: to `string[][]` rows, or to a record
    # array whose field names are taken from the header row. Binding is strict.
    #
    # + path - The source share-relative path
    # + options - Optional download options (range, snapshot)
    # + targetType - The type to bind the content to, `string[][]` or a record array
    # + return - The bound value, or an `Error`
    isolated remote function getFileCsv(string path, DownloadOptions? options = (),
            typedesc<string[][]|record {}[]> targetType = <>) returns targetType|Error = @java:Method {
        name: "callerGetFileCsv",
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

    # Uploads in-memory content to the watched share. Dispatch is by the value's runtime type:
    # `byte[]` is written as-is, a `string` as raw text, `xml` as its textual form, a
    # `map<json>` (including compatible records) as a JSON document, and a `string[][]` as
    # CSV rows.
    #
    # + content - The content to upload
    # + destinationPath - The share-relative path the content is written to, including the file name
    # + options - Optional upload options (headers, metadata, permission, SMB properties)
    # + return - An `Error` if the upload failed, otherwise `()`
    isolated remote function uploadContent(byte[]|string|xml|map<json>|string[][] content,
            string destinationPath, UploadOptions? options = ()) returns Error? {
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
