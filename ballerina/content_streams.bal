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

import ballerina/data.csv;
import ballerina/jballerina.java;

# Record returned from the `ContentByteStream.next()` method.
type ContentStreamEntry record {|
    # The chunk of bytes read from the file
    byte[] value;
|};

// Backs a stream content handler's byte stream: each next() reads one chunk of the watched
// file from the service, and the underlying source closes at the end of the file or on an
// explicit close(). A handler that abandons the stream early should call close().
class ContentByteStream {

    private boolean isClosed = false;

    public isolated function next() returns record {|byte[] value;|}|error? {
        return externByteStreamNext(self);
    }

    public isolated function close() returns error? {
        if !self.isClosed {
            error? closeResult = externByteStreamClose(self);
            if closeResult is () {
                self.isClosed = true;
            }
            return closeResult;
        }
        return ();
    }
}

// Backs a CSV stream content handler: wraps the file's byte stream in a data.csv row stream
// that yields one bound row per next(). A row that fails to bind surfaces as the error entry
// of that next() call, after which the stream is closed; the stream also closes itself at the
// end of the file.
class ContentCsvStream {

    private boolean isClosed = false;
    private stream<record {}|anydata[], error?> csvStream;

    public isolated function init(typedesc<record {}|anydata[]> targetType,
            stream<byte[], error?> byteStream, boolean laxDataBinding) returns error? {
        csv:ParseOptions options = csvParseOptions(laxDataBinding);
        if targetType is typedesc<record {}> {
            // A record target maps its fields through the header row (the file's first row),
            // which the data.csv default already consumes.
        } else {
            // The string array form yields every row of the file, including the first.
            options.header = ();
        }
        stream<record {}|anydata[], error?>|csv:Error parsed =
            csv:parseToStream(byteStream, options, targetType);
        if parsed is csv:Error {
            closeByteStreamQuietly(byteStream);
            return error ProcessingError("CSV stream binding could not be created: "
                    + parsed.message(), parsed, errorCode = "ProcessingError");
        }
        self.csvStream = parsed;
    }

    public isolated function next() returns record {|record {}|anydata[] value;|}|error? {
        if self.isClosed {
            return;
        }
        record {|record {}|anydata[] value;|}|error? nextEntry = trap self.csvStream.next();
        if nextEntry is () {
            self.isClosed = true;
            closeRowStreamQuietly(self.csvStream);
            return;
        }
        if nextEntry is error {
            self.isClosed = true;
            closeRowStreamQuietly(self.csvStream);
            return error ProcessingError("CSV content does not bind to the declared row type: "
                    + nextEntry.message(), nextEntry, errorCode = "ProcessingError");
        }
        return nextEntry;
    }

    public isolated function close() returns error? {
        if self.isClosed {
            return;
        }
        self.isClosed = true;
        return self.csvStream.close();
    }
}

// Constructs the CSV row stream backing on a real strand: the data.csv stream construction
// runs Ballerina code, so the native dispatcher calls in here through the runtime rather than
// constructing the object on a plain dispatch thread.
isolated function newContentCsvStream(typedesc<record {}|anydata[]> targetType,
        stream<byte[], error?> byteStream, boolean laxDataBinding) returns ContentCsvStream|error {
    return new (targetType, byteStream, laxDataBinding);
}

isolated function closeByteStreamQuietly(stream<byte[], error?> byteStream) {
    error? closed = byteStream.close();
    if closed is error {
        // Best effort cleanup.
    }
}

isolated function closeRowStreamQuietly(stream<record {}|anydata[], error?> rowStream) {
    error? closed = rowStream.close();
    if closed is error {
        // Best effort cleanup.
    }
}

isolated function externByteStreamNext(ContentByteStream iterator)
        returns record {|byte[] value;|}|error? = @java:Method {
    'class: "io.ballerina.lib.azure.storage.files.server.ContentStreamOps",
    name: "next"
} external;

isolated function externByteStreamClose(ContentByteStream iterator) returns error? = @java:Method {
    'class: "io.ballerina.lib.azure.storage.files.server.ContentStreamOps",
    name: "close"
} external;
