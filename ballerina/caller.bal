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

# Passed to each `Listener` event handler, the `Caller` lets a handler act on the file that
# triggered the event (and its neighbours) without constructing a separate `Client`. It exposes a
# curated subset of `Client` operations — the ones useful from within an event handler — plus two
# helpers for inspecting the listener's context.
#
# The `Caller` is created and supplied by the `Listener`; applications never construct it directly.
public isolated client class Caller {

    private final string shareName;

    # Initializes a `Caller` bound to the listener's share. Module-private: only the `Listener`
    # constructs `Caller` instances.
    #
    # + shareName - The name of the share the listener is watching
    isolated function init(string shareName) {
        self.shareName = shareName;
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

    # Uploads a local file to the share.
    #
    # + path - The destination share-relative path
    # + source - The path of the local file to upload
    # + options - Optional upload options (headers, metadata)
    # + return - An `Error` if the upload failed, otherwise `()`
    isolated remote function upload(string path, string 'source, UploadOptions? options = ())
            returns Error? {
        return notImplemented();
    }

    # Uploads an in-memory byte array to the share.
    #
    # + path - The destination share-relative path
    # + content - The bytes to upload
    # + options - Optional upload options (headers, metadata)
    # + return - An `Error` if the upload failed, otherwise `()`
    isolated remote function uploadFromBytes(string path, byte[] content, UploadOptions? options = ())
            returns Error? {
        return notImplemented();
    }

    # Deletes a file from the share.
    #
    # + path - The share-relative path of the file to delete
    # + return - An `Error` if the file could not be deleted, otherwise `()`
    isolated remote function delete(string path) returns Error? {
        return notImplemented();
    }

    # Copies a file within the share.
    #
    # + source - The source share-relative path
    # + destination - The destination share-relative path
    # + options - Optional copy options
    # + return - The `CopyInfo` for the started copy, or an `Error`
    isolated remote function copy(string 'source, string destination, CopyOptions? options = ())
            returns CopyInfo|Error {
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

    # Renames (moves) a file within the share.
    #
    # + source - The current share-relative path of the file
    # + destination - The new share-relative path
    # + options - Optional rename options
    # + return - An `Error` if the file could not be renamed, otherwise `()`
    isolated remote function rename(string 'source, string destination, RenameOptions? options = ())
            returns Error? {
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

    # Lists the directories and files directly under a directory.
    #
    # + directoryPath - The share-relative path of the directory to list
    # + options - Optional listing options
    # + return - A stream of `FileSystemEntry`, or an `Error`
    isolated remote function listDirectoriesAndFiles(string directoryPath, ListOptions? options = ())
            returns stream<FileSystemEntry, Error?>|Error {
        return notImplemented();
    }

    # Returns the name of the share the listener is watching.
    #
    # + return - The share name
    isolated remote function getShareName() returns string {
        return self.shareName;
    }

    # Returns a snapshot of the files currently known to the listener, keyed by share-relative path.
    #
    # + return - The current file snapshot
    isolated remote function getCurrentSnapshot() returns map<FileInfo> {
        return {};
    }
}
