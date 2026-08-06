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

// The shape a dropped .json file binds to.
type Person record {|
    string name;
    int age;
|};

// The share and its /incoming directory are created in the setup steps (see the example
// description); the listener starts polling the watched path as soon as the program starts.
listener files:Listener dropListener = new (shareName,
    auth = {accountName, accountKey},
    pollingInterval = 5
);

// The service's attach point is the watched path: this service watches "/incoming". Files are
// routed to a handler by extension: a .json file goes to onFileJson, and everything else to
// onFile.
service /incoming on dropListener {

    // Handle JSON drops by binding each file to the Person record, then delete each file once
    // it is processed. A .json file that is malformed or does not match the record cannot
    // bind; afterError moves it to "/failed" so it does not stay in the watched folder and
    // re-fire on every poll.
    @files:FunctionConfig {afterProcess: files:DELETE, afterError: {moveTo: "/failed"}}
    remote function onFileJson(Person person, files:FileInfo file, files:Caller caller) returns error? {
        log:printInfo("processed JSON drop", fileName = file.name, sizeBytes = file.sizeBytes,
                personName = person.name, personAge = person.age);
    }

    // Handle every other file as raw bytes, then move each into "/processed" once it is processed.
    @files:FunctionConfig {afterProcess: {moveTo: "/processed"}}
    remote function onFile(byte[] content, files:FileInfo file, files:Caller caller) returns error? {
        log:printInfo("processed file drop", fileName = file.name, sizeBytes = content.length(),
                movedTo = "/processed");
    }

    // Notified when a poll fails (for example a credential or network problem) or a file's
    // content fails to bind to a typed handler. Purely observational: the afterError move
    // above still consumes a malformed file.
    remote function onError(files:Error err) returns error? {
        log:printError("drop-folder listener reported an error", 'error = err);
    }
}
