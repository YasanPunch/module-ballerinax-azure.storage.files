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

import ballerinax/azure.storage.files;

configurable string accountName = ?;
configurable string accountKey = ?;
configurable string shareName = "backup-example";

public function main() returns error? {
    // Create the share if this is the first run.
    files:AdminClient admin = check new (auth = {accountName, accountKey});
    boolean shareExists = check admin->hasShare(shareName);
    if !shareExists {
        check admin->createShare(shareName);
    }
    check admin.close();

    files:Client share = check new (shareName, auth = {accountName, accountKey});

    // Prepare a local folder with two files to back up.
    if !(check file:test("data", file:EXISTS)) {
        check file:createDir("data");
    }
    check io:fileWriteString("data/notes.txt", "Remember to rotate the account key.");
    check io:fileWriteString("data/inventory.csv", "item,count\nkeyboard,12\nmonitor,7\n");

    // Upload every file in the folder into a backup directory on the share.
    boolean backupDirExists = check share->hasDirectory("/daily");
    if !backupDirExists {
        check share->createDirectory("/daily");
    }
    file:MetaData[] localEntries = check file:readDir("data");
    foreach file:MetaData localEntry in localEntries {
        if !localEntry.dir {
            string name = check file:basename(localEntry.absPath);
            check share->uploadFile(localEntry.absPath, string `/daily/${name}`);
            io:println(string `Uploaded ${name}`);
        }
    }

    // List everything on the share, recursively.
    io:println("Share contents:");
    stream<files:Entry, files:Error?> listing = check share->list("/", {recursive: true});
    check listing.forEach(function(files:Entry entry) {
        io:println("  " + entry.path);
    });

    // Restore one file from the backup.
    if check file:test("restored-notes.txt", file:EXISTS) {
        check file:remove("restored-notes.txt");
    }
    check share->downloadFile("/daily/notes.txt", "restored-notes.txt");
    io:println("Restored content: ", check io:fileReadString("restored-notes.txt"));

    check share.close();
}
