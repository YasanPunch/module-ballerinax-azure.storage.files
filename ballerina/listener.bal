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
# positional parameter). The configuration covers the share-level concerns only; what to
# watch within the share is declared per attached service (see `Service` and `ServiceConfig`).
public type ListenerConfiguration record {|
    # The authentication configuration (see `AuthConfig`)
    AuthConfig auth;
    # How often to poll the share, in seconds. Polls never overlap: the next poll begins only
    # after the previous tick's handlers have returned, so a handler that runs longer than the
    # interval delays polling rather than triggering a concurrent dispatch of the same file
    decimal pollingInterval = 60;
|};

# Per-service watch settings, applied to a service with the `ServiceConfig` annotation.
# The watched path itself is the service's attach point (see `Service`); this record
# configures how that path is watched. A service without the annotation uses the defaults.
public type ServiceConfiguration record {|
    # Watch subdirectories under the watched path as well
    boolean recursive = true;
    # A regular expression matched against the file **name** (not the path); files that do
    # not match are never dispatched to this service. An invalid pattern fails `attach`.
    # Without a filter, non-matching files a handler never consumes will re-fire on every poll.
    string fileNamePattern?;
|};

# Configures how an attached service watches its path (recursion, file-name filtering).
public annotation ServiceConfiguration ServiceConfig on service;

# The service contract for an Azure Files listener.
#
# The service's attach point declares the share-relative path it watches: a string literal
# (`service "/invoices" on shareListener`) or an absolute resource path
# (`service /invoices on shareListener`; segments are joined with `/`). A service with no
# attach point watches the share root. Use the string-literal form for directory names a
# resource path cannot express (spaces, dots, and other special characters). Watch behaviour
# (recursion, file-name filtering) is configured per service with the `ServiceConfig`
# annotation.
#
# `onFile` fires once per file **present** in the watched path on each poll — the listener keeps
# no state between polls, so a file fires again on every poll until the handler consumes it
# (processes it, then deletes it or moves it out of the watched path via the `Caller`).
#
# Because dispatch is presence-based, a file still being written by another client (e.g. a large
# copy onto the share's SMB mount) can be dispatched at partial size. Producers should write to a
# temporary name or directory outside the watched path and rename the file into it — the rename
# is atomic, so the file appears complete or not at all.
public type Service distinct service object {
    remote function onFile(FileInfo file, Caller caller) returns error?;
};

# Listens to an Azure Files share and dispatches the files it finds to the attached services.
# Each polling tick lists the watched paths and fires `onFile` for every file present — stateless
# by design: nothing is remembered between polls, so handlers consume files (delete or move them
# out of the watched path) to stop them from re-firing on the next tick. Delivery is therefore
# at-least-once: a handler failure before consumption means the file is redelivered on the next
# poll, and because polls never overlap, redelivery is always sequential — one file is never
# processed by two handler invocations at once. For exactly-once effects, make the handler
# idempotent, or claim the file first by renaming it out of the watched path.
#
# Several services can attach to one listener, each watching its own path (the service's attach
# point). Every file is dispatched to **exactly one** service — the one with the most specific
# (longest) watched path covering it — so two handlers never receive the same file. A service's
# `fileNamePattern` applies after that routing: a file routed to a service but not matching its
# pattern is not dispatched at all. Attaching a second service with a watched path that is
# already taken fails; to handle one directory's files differently by name, attach a single
# service and branch on `FileInfo.name` in the handler.
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

    # Attaches a service to the listener. The service's attach point is the share-relative
    # path it watches; a service with no attach point watches the share root. Attaching fails
    # when another attached service already watches the same path, or when the service's
    # `ServiceConfig.fileNamePattern` is not a valid regular expression.
    #
    # + serviceRef - The service implementing the file handler
    # + name - The watched path, taken from the service declaration's attach point (a string
    #          literal, or an absolute resource path whose segments are joined with `/`);
    #          `()` watches the share root
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
