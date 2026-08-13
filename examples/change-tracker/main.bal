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

import ballerina/file;
import ballerina/io;
import ballerina/log;

import ballerinax/azure.storage.files;

configurable string accountName = ?;
configurable string accountKey = ?;
configurable string shareName = "change-tracker-example";
configurable string snapshotFile = "snapshot.json";

public function main() returns error? {
    files:Client fileShare = check new (shareName, auth = {accountName, accountKey});

    // The previous run's view of the share: file path -> entity tag.
    map<string> previous = {};
    if check file:test(snapshotFile, file:EXISTS) {
        json stored = check io:fileReadJson(snapshotFile);
        previous = check stored.cloneWithType();
    }

    // The share's current files, each with its entity tag (a new tag on every write).
    map<string> current = {};
    stream<files:Entry, files:Error?> entries = check fileShare->list("/",
            {recursive: true, includeExtendedInfo: true});
    check entries.forEach(function(files:Entry entry) {
        if !entry.isDirectory {
            current[entry.path] = entry.eTag ?: "";
        }
    });

    // Report every difference since the previous run.
    foreach [string, string] [path, eTag] in current.entries() {
        string? known = previous[path];
        if known is () {
            log:printInfo("file created", path = path);
        } else if known != eTag {
            log:printInfo("file modified", path = path);
        }
    }
    foreach string path in previous.keys() {
        if !current.hasKey(path) {
            log:printInfo("file deleted", path = path);
        }
    }

    // Save the current view for the next run.
    check io:fileWriteJson(snapshotFile, current);
}
