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

# Configuration for the polling `Listener`.
#
# + accountName - The storage account name. Required for `SharedKeyAuth` and `SasAuth`;
#                 redundant for `ConnectionStringAuth`.
# + auth - The authentication method to use
# + shareName - The name of the share to watch
# + path - The share-relative directory to watch; defaults to the share root
# + pollingIntervalSeconds - How often to poll the share for changes, in seconds
# + recursive - Watch subdirectories as well as the top-level `path`
# + processExisting - On the first poll, fire `onFileAdd` for files that already exist. When
#                     `false`, the first poll silently establishes a baseline.
public type ListenerConfig record {|
    string accountName?;
    SharedKeyAuth|SasAuth|ConnectionStringAuth auth;
    string shareName;
    string path = "/";
    decimal pollingIntervalSeconds = 60;
    boolean recursive = true;
    boolean processExisting = false;
|};

# The service contract for an Azure Files listener. A service attached to a `Listener` implements
# any subset of the following optional remote handlers; each is dispatched by the listener when the
# corresponding change is detected between two polls:
# ```ballerina
# remote function onFileAdd(FileInfo file, Caller caller) returns error?;
# remote function onFileDelete(FileInfo file, Caller caller) returns error?;
# remote function onFileModify(FileInfo file, Caller caller) returns error?;
# ```
# `onFileModify` fires when a file's `eTag` changes between polls.
public type Service distinct service object {
};

# Listens to an Azure Files share and dispatches file-change events to an attached service.
# It works by polling the share on an interval and diffing successive listings — added, deleted,
# and modified (ETag-changed) files are surfaced to `onFileAdd`, `onFileDelete`, and `onFileModify`
# respectively.
public class Listener {

    private final ListenerConfig config;

    # The last-seen files keyed by share-relative path, compared against each fresh poll to derive
    # add/delete/modify events.
    #
    # REVIEW NOTE: this is the mutable, per-poll state the reviewer flagged. Because it changes
    # across polls, the `Listener` cannot be an `isolated` object as written — every read/write of
    # `snapshot` would need to be guarded by a `lock` statement (and the map kept from leaking) for
    # the class to be isolated and its poll loop concurrency-safe. How to structure this is an open
    # design decision to settle during implementation.
    private map<FileInfo> snapshot = {};

    # Initializes the listener with the given configuration. Polling begins on `start`.
    #
    # + config - The listener configuration (account, auth, share, polling behaviour)
    # + return - An `Error` if the listener could not be initialized, otherwise `()`
    public function init(ListenerConfig config) returns Error? {
        self.config = config;
    }

    # Attaches a service to the listener.
    #
    # + serviceRef - The service implementing the file-change handlers
    # + name - The optional service name(s)
    # + return - An `error` if the service could not be attached, otherwise `()`
    public function attach(Service serviceRef, string[]|string? name = ()) returns error? {
        return;
    }

    # Detaches a service from the listener.
    #
    # + serviceRef - The service to detach
    # + return - An `error` if the service could not be detached, otherwise `()`
    public function detach(Service serviceRef) returns error? {
        return;
    }

    # Starts the listener's polling loop.
    #
    # + return - An `error` if the listener could not be started, otherwise `()`
    public function 'start() returns error? {
        return;
    }

    # Stops the listener after the in-flight poll and any dispatched handlers complete.
    #
    # + return - An `error` if the listener could not be stopped, otherwise `()`
    public function gracefulStop() returns error? {
        return;
    }

    # Stops the listener immediately.
    #
    # + return - An `error` if the listener could not be stopped, otherwise `()`
    public function immediateStop() returns error? {
        return;
    }
}
