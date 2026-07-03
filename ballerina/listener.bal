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

# Configuration for the polling `Listener`. Supplied to `init` as an included record
# parameter, so its fields are passed as named arguments (the watched share is `init`'s
# positional parameter).
public type ListenerConfiguration record {|
    # The authentication method to use
    SharedKeyAuth|SasAuth|ConnectionStringAuth auth;
    # An explicit file-service endpoint URL, overriding the one derived from the auth record's
    # `accountName` (see `ClientConfiguration.endpoint`)
    string endpoint?;
    # The share-relative directory to watch; defaults to the share root
    string path = "/";
    # How often to poll the share, in seconds
    decimal pollingInterval = 60;
    # Watch subdirectories as well as the top-level `path`
    boolean recursive = true;
    # A regular expression matched against the file **name** (not the path); files that do not
    # match are never dispatched. Without a filter, remember that non-matching files a handler
    # never consumes will re-fire on every poll.
    string fileNamePattern?;
|};

# The service contract for an Azure Files listener.
#
# `onFile` fires once per file **present** in the watched path on each poll — the listener keeps
# no state between polls, so a file fires again on every poll until the handler consumes it
# (processes it, then deletes it or moves it out of the watched path via the `Caller`).
# The snapshot-diff handlers (`onFileAdd`/`onFileDelete`/`onFileModify`) are planned post-v0.1.
#
# Because dispatch is presence-based, a file still being written by another client (e.g. a large
# copy onto the share's SMB mount) can be dispatched at partial size. Producers should write to a
# temporary name or directory outside the watched path and `rename` into it — the rename is
# atomic, so the file appears complete or not at all.
public type Service distinct service object {
    remote function onFile(FileInfo file, Caller caller) returns error?;
};

# Listens to an Azure Files share and dispatches the files it finds to an attached service.
# Each polling tick lists the watched path and fires `onFile` for every file present — stateless
# by design: nothing is remembered between polls, so handlers consume files (delete or move them
# out of the watched path) to stop them from re-firing on the next tick. The post-v0.1
# snapshot-diff mode adds fired-once-per-change semantics via eTag comparison, holding its
# snapshot as `lock`-guarded private state on this class.
public isolated class Listener {

    private final string shareName;
    private final readonly & ListenerConfiguration config;

    # Initializes the listener with the given configuration. Polling begins on `start`.
    #
    # + shareName - The name of the share to watch
    # + config - The listener configuration (auth, polling behaviour), passed as named arguments
    # + return - An `Error` if the listener could not be initialized, otherwise `()`
    public isolated function init(string shareName, *ListenerConfiguration config) returns Error? {
        self.shareName = shareName;
        self.config = config.cloneReadOnly();
    }

    # Attaches a service to the listener.
    #
    # + serviceRef - The service implementing the file handler
    # + name - The optional service name(s)
    # + return - An `error` if the service could not be attached, otherwise `()`
    public isolated function attach(Service serviceRef, string[]|string? name = ()) returns error? {
        return;
    }

    # Detaches a service from the listener.
    #
    # + serviceRef - The service to detach
    # + return - An `error` if the service could not be detached, otherwise `()`
    public isolated function detach(Service serviceRef) returns error? {
        return;
    }

    # Starts the listener's polling loop.
    #
    # + return - An `error` if the listener could not be started, otherwise `()`
    public isolated function 'start() returns error? {
        return;
    }

    # Stops the listener after the in-flight poll and any dispatched handlers complete.
    #
    # + return - An `error` if the listener could not be stopped, otherwise `()`
    public isolated function gracefulStop() returns error? {
        return;
    }

    # Stops the listener immediately.
    #
    # + return - An `error` if the listener could not be stopped, otherwise `()`
    public isolated function immediateStop() returns error? {
        return;
    }
}
