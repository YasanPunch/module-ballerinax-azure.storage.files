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
import ballerina/log;

import ballerinax/azure.storage.files;

configurable string accountName = ?;
configurable string accountKey = ?;
configurable string shareName = "backup-example";
configurable string watchedFolder = "backup";

// The client the watcher backs files up through.
final files:Client share = check new (shareName, auth = {accountName, accountKey});

// Watches the local folder; every file created in it is backed up to the share.
listener file:Listener backupWatcher = new ({path: watchedFolder});

service on backupWatcher {

    remote function onCreate(file:FileEvent event) {
        do {
            string name = check file:basename(event.name);
            check share->uploadFile(event.name, string `/${name}`);
            log:printInfo("backed up", file = name, share = shareName);
        } on fail error e {
            log:printError("backup failed", 'error = e, localPath = event.name);
        }
    }
}
