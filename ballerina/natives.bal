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

// ---------------------------------------------------------------------------
// Client lifecycle
// ---------------------------------------------------------------------------

isolated function initAdminClient(AdminClient adminClient, ClientConfiguration config)
        returns Error? = @java:Method {
    'class: "io.ballerina.lib.azure.storage.files.util.ClientInit"
} external;

isolated function initClient(Client fileClient, string shareName, ClientConfiguration config)
        returns Error? = @java:Method {
    'class: "io.ballerina.lib.azure.storage.files.util.ClientInit"
} external;

// Writes already-serialized upload content; record content is serialized in Ballerina
// before reaching this call (see Client.uploadContent).
isolated function externUploadContent(Client fileClient, byte[]|string|xml|string[][] content,
        string destinationPath, UploadContentOptions? options) returns Error? = @java:Method {
    'class: "io.ballerina.lib.azure.storage.files.client.TransferOps",
    name: "uploadContent"
} external;

// ---------------------------------------------------------------------------
// Stream upload plumbing
// ---------------------------------------------------------------------------

// The Azure Files service caps one range write at 4 MiB — Put Range returns HTTP 413 above
// it (learn.microsoft.com/rest/api/storageservices/put-range) and the SDK exposes no public
// constant for it (mirrored by TransferOps.MAX_RANGE_BYTES). Buffered source chunks flush
// at this size.
const int MAX_RANGE_BYTES = 4 * 1024 * 1024;

isolated function prepareStreamUpload(Client fileClient, string destinationPath, int contentLength,
        UploadOptions? options) returns Error? = @java:Method {
    'class: "io.ballerina.lib.azure.storage.files.client.TransferOps"
} external;

isolated function writeStreamChunk(Client fileClient, string destinationPath, int offset,
        byte[] chunk) returns Error? = @java:Method {
    'class: "io.ballerina.lib.azure.storage.files.client.TransferOps"
} external;

// ---------------------------------------------------------------------------
// Entry listing stream
// ---------------------------------------------------------------------------

# One entry of the listing stream returned by `Client.list`.
type ListStreamEntry record {|
    # The listed entry
    Entry value;
|};

# Backs the lazy stream returned by `Client.list`, pulling one entry per pull.
isolated class EntryStreamGenerator {

    # Pulls the next listed entry from the service-backed iterator.
    #
    # + return - The next `Entry`, `()` when the listing is exhausted, or an `Error`
    public isolated function next() returns ListStreamEntry|Error? {
        Entry|Error? entry = nextEntry(self);
        if entry is Entry {
            return {value: entry};
        }
        return entry;
    }

    # Stops the listing early and releases its state.
    #
    # + return - An `Error` if the listing could not be closed, otherwise `()`
    public isolated function close() returns Error? {
        return closeEntryIterator(self);
    }
}

isolated function newEntryIterator(Client fileClient, EntryStreamGenerator generator,
        string directoryPath, ListOptions options) returns Error? = @java:Method {
    'class: "io.ballerina.lib.azure.storage.files.client.ListOps"
} external;

isolated function nextEntry(EntryStreamGenerator generator) returns Entry|Error? = @java:Method {
    'class: "io.ballerina.lib.azure.storage.files.client.ListOps"
} external;

isolated function closeEntryIterator(EntryStreamGenerator generator) returns Error? = @java:Method {
    'class: "io.ballerina.lib.azure.storage.files.client.ListOps"
} external;

// ---------------------------------------------------------------------------
// Content download stream
// ---------------------------------------------------------------------------

# Backs the lazy byte stream returned by `Client.getFileContent`.
isolated class ContentStreamGenerator {

    # Reads the next chunk of the file content.
    #
    # + return - The next chunk, `()` at the end of the content, or an `Error`
    public isolated function next() returns ContentStreamEntry|Error? {
        byte[]|Error? chunk = nextContentChunk(self);
        if chunk is byte[] {
            return {value: chunk};
        }
        return chunk;
    }

    # Closes the content stream early.
    #
    # + return - An `Error` if the stream could not be closed, otherwise `()`
    public isolated function close() returns Error? {
        return closeContentStream(self);
    }
}

isolated function nextContentChunk(ContentStreamGenerator generator) returns byte[]|Error? = @java:Method {
    'class: "io.ballerina.lib.azure.storage.files.client.TransferOps"
} external;

isolated function closeContentStream(ContentStreamGenerator generator) returns Error? = @java:Method {
    'class: "io.ballerina.lib.azure.storage.files.client.TransferOps"
} external;
