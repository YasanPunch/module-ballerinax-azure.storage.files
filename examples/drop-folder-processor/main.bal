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

listener files:Listener dropListener = new (shareName, auth = {accountName, accountKey}, pollingInterval = 5);

// Watches the share's /incoming folder: .json files go to onFileJson, everything else to onFile.
service /incoming on dropListener {

    // Logs each JSON drop bound to a Person, then deletes it; a .json file that does not
    // bind is moved to "/failed" instead.
    @files:FunctionConfig {afterProcess: files:DELETE, afterError: {moveTo: "/failed"}}
    remote function onFileJson(Person person, files:FileInfo file, files:Caller caller) returns error? {
        log:printInfo("processed JSON drop", fileName = file.name, sizeBytes = file.sizeBytes,
                personName = person.name, personAge = person.age);
    }

    // Logs every other file, then moves it into "/processed".
    @files:FunctionConfig {afterProcess: {moveTo: "/processed"}}
    remote function onFile(byte[] content, files:FileInfo file, files:Caller caller) returns error? {
        log:printInfo("processed file drop", fileName = file.name, sizeBytes = content.length(),
                movedTo = "/processed");
    }

    // Logs poll failures (for example a credential or network problem) and binding failures.
    remote function onError(files:Error err) returns error? {
        log:printError("drop-folder listener reported an error", 'error = err);
    }
}
