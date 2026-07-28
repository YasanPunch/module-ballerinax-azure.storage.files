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

import ballerina/log;

import ballerinax/azure.storage.files;

configurable string accountName = ?;
configurable string accountKey = ?;
configurable string shareName = "drop-folder-example";

// Create the share and the watched directory before the listener starts polling. Module
// initialization runs this first; the runtime starts the listener only after it completes.
function init() returns error? {
    files:AdminClient admin = check new (auth = {accountName, accountKey});
    boolean shareExists = check admin->hasShare(shareName);
    if !shareExists {
        check admin->createShare(shareName);
    }
    check admin.close();

    files:Client share = check new (shareName, auth = {accountName, accountKey});
    boolean incomingExists = check share->hasDirectory("/incoming");
    if !incomingExists {
        check share->createDirectory("/incoming");
    }
    check share.close();

    log:printInfo(string `Watching /incoming on share '${shareName}'. Drop files there to process them.`);
}

listener files:Listener dropListener = new (shareName,
    auth = {accountName, accountKey},
    pollingInterval = 5
);

// The service watches "/incoming". Files are routed to a handler by extension: a .json file goes
// to onFileJson, and everything else to onFile.
@files:ServiceConfig {path: "/incoming"}
service on dropListener {

    // Handle JSON object drops, then delete each file once it is processed. A .json file that is
    // malformed or whose root is not an object cannot bind to map<json>; afterError moves it to
    // "/failed" so it does not stay in the watched folder and re-fire on every poll.
    @files:FunctionConfig {afterProcess: files:DELETE, afterError: {moveTo: "/failed"}}
    remote function onFileJson(map<json> content, files:FileInfo file, files:Caller caller) returns error? {
        log:printInfo(string `Processed JSON ${file.name} (${file.sizeBytes} bytes): ${content.toJsonString()}`);
    }

    // Handle every other file as raw bytes, then move each into "/processed" once it is processed.
    @files:FunctionConfig {afterProcess: {moveTo: "/processed"}}
    remote function onFile(byte[] content, files:FileInfo file, files:Caller caller) returns error? {
        log:printInfo(string `Processed ${file.name} (${content.length()} bytes); moved to /processed`);
    }
}
