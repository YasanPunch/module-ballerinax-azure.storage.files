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
import ballerina/task;
import ballerina/time;

import ballerinax/azure.storage.files;

configurable string accountName = ?;
configurable string accountKey = ?;
configurable string shareName = "change-tracker-example";

// What the tracker remembers about a file between polls. The eTag changes on every write,
// so it is the precise change signal; lastModified is kept alongside as the human-readable one.
type FileState record {|
    string eTag;
    time:Utc lastModified;
|};

const CREATED = "created";
const MODIFIED = "modified";

// The change state this example owns. The connector's listener is deliberately stateless
// (it reports what is present, every poll), so deriving created, modified, and deleted
// events means keeping this snapshot on the application side.
isolated class Snapshot {
    private final map<FileState> files = {};

    // Classifies one observed file against the snapshot and records its latest state.
    // Returns () when the file is unchanged since the last observation.
    isolated function observe(string path, FileState state) returns CREATED|MODIFIED? {
        lock {
            FileState? known = self.files[path];
            self.files[path] = state.clone();
            if known is () {
                return CREATED;
            }
            return known.eTag == state.eTag ? () : MODIFIED;
        }
    }

    // Drops every tracked file that is no longer present on the share, returning the
    // removed paths: those are the deletions since the previous sweep.
    isolated function reconcile(string[] presentPaths) returns string[] {
        lock {
            map<()> present = {};
            foreach string path in presentPaths.clone() {
                present[path] = ();
            }
            string[] removed = [];
            foreach string path in self.files.keys() {
                if !present.hasKey(path) {
                    removed.push(path);
                    _ = self.files.remove(path);
                }
            }
            return removed.clone();
        }
    }
}

final Snapshot snapshot = new;

// The sweep's own client, sharing the listener's credentials.
final files:Client shareClient = check new (shareName, auth = {accountName, accountKey});

// The listener supplies presence: every poll it dispatches each file present on the share,
// and the snapshot turns those dispatches into created and modified events.
listener files:Listener tracker = new (shareName,
    auth = {accountName, accountKey},
    pollingInterval = 5
);

// A presence listener cannot observe absence, so deletions come from this second schedule:
// each tick lists the share and reconciles the snapshot against what actually exists.
listener task:Listener sweeper = new (trigger = {interval: 5});

// No attach point: the service watches the share root.
service on tracker {

    remote function onFile(byte[] content, files:FileInfo file) returns error? {
        CREATED|MODIFIED? change = snapshot.observe(file.path,
                {eTag: file.eTag, lastModified: file.lastModified});
        if change == CREATED {
            onFileCreated(file);
        } else if change == MODIFIED {
            onFileModified(file);
        }
    }

    remote function onError(files:Error err) returns error? {
        log:printError("change tracker poll failed", 'error = err);
    }
}

service on sweeper {

    isolated function execute() returns error? {
        stream<files:Entry, files:Error?>|files:Error listing = shareClient->list("/", {recursive: true});
        if listing is files:Error {
            log:printError("change tracker sweep failed", 'error = listing);
            return;
        }
        string[] present = [];
        while true {
            record {|files:Entry value;|}|files:Error? entry = listing.next();
            if entry is () {
                break;
            }
            if entry is files:Error {
                log:printError("change tracker sweep failed", 'error = entry);
                return;
            }
            if !entry.value.isDirectory {
                present.push(entry.value.path);
            }
        }
        foreach string path in snapshot.reconcile(present) {
            onFileDeleted(path);
        }
    }
}

isolated function onFileCreated(files:FileInfo file) {
    log:printInfo("file created", path = file.path, sizeBytes = file.sizeBytes, eTag = file.eTag);
}

isolated function onFileModified(files:FileInfo file) {
    log:printInfo("file modified", path = file.path, sizeBytes = file.sizeBytes, eTag = file.eTag);
}

isolated function onFileDeleted(string path) {
    log:printInfo("file deleted", path = path);
}
