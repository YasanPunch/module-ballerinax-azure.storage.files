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

import ballerina/jballerina.java;
import ballerina/log;
import ballerina/task;

# Configuration for an `azure.storage.files` `Listener`: the credentials and polling cadence.
# What to watch is declared per service through the `@ServiceConfig` annotation.
public type ListenerConfiguration record {|
    # The authentication configuration (see `AuthConfig`)
    AuthConfig auth;
    # How often the watched path is polled, in seconds
    decimal pollingInterval = 60;
    # Retry behaviour for service requests; omit for the service defaults
    RetryConfig retryConfig?;
    # HTTP transport settings (proxy, connection pool, TLS); omit for the defaults
    TransportConfig transportConfig?;
    # Relaxed data binding for the typed content handlers: JSON, XML, and CSV record binding
    # treat a null value as an optional field and an absent field as a nilable field
    boolean laxDataBinding = false;
    # Fail safe CSV processing: a malformed CSV record is skipped and appended to an error
    # log file named after the source file in the current directory, instead of failing the
    # whole binding. Applies to the materialized CSV handler forms, not the stream forms
    FailSafeOptions csvFailSafe?;
|};

# Configuration for fail safe CSV content processing.
public type FailSafeOptions record {|
    # What each skipped CSV record's error log entry carries
    ErrorLogContentType contentType = METADATA;
|};

# The content of a fail safe CSV error log entry.
public enum ErrorLogContentType {
    # Log only the metadata of the failure (position and message)
    METADATA,
    # Log only the raw content that caused the failure
    RAW,
    # Log both the raw content and the metadata
    RAW_AND_METADATA
}

# The per-service watch configuration, supplied through the `@files:ServiceConfig` annotation.
# It declares which share-relative path a service watches and how.
public type ServiceConfiguration record {|
    # The share-relative path this service watches (required; `/` is the share root)
    string path;
    # Watch subdirectories under the path
    boolean recursive = true;
    # A regular expression matched against the file name (not the path); non-matching files
    # are never dispatched
    string fileNamePattern?;
    # Skip files younger than this many seconds
    decimal minFileAgeSeconds?;
|};

# Declares the watch configuration of a listener service.
public annotation ServiceConfiguration ServiceConfig on service;

# The auto-consume action that deletes the file after the handler runs.
public const DELETE = "DELETE";

# The auto-consume action that moves the file after the handler runs.
public type Move record {|
    # The target directory the file is moved into (the file keeps its name); the directory
    # is created if it does not exist
    string moveTo;
    # Recreate the file's sub-path (relative to the watched path) under `moveTo`, on
    # recursive watches
    boolean preserveSubDirs = true;
|};

# The per-handler configuration, supplied through the `@files:FunctionConfig` annotation. It
# routes files to a handler by name pattern and auto-consumes a file after the handler runs.
public type FunctionConfiguration record {|
    # A regular expression matched against the file name that routes matching files to this
    # handler, overriding the extension-based routing
    string fileNamePattern?;
    # The action applied after the handler returns normally: delete the file, or move it
    DELETE|Move afterProcess?;
    # The action applied after the handler returns or panics with an error (including a
    # content-binding failure for a typed handler): delete the file, or move it
    DELETE|Move afterError?;
|};

# Declares the routing and auto-consume configuration of a listener handler.
public annotation FunctionConfiguration FunctionConfig on object function;

# The service type attached to a `Listener`. Declare at least one content handler (`onFile` or a
# typed `onFileText`/`onFileJson`/`onFileXml`/`onFileCsv` variant), and optionally an `onError`
# handler (`remote function onError(files:Error err, files:Caller caller?) returns error?`) that
# is notified when a poll fails or a typed handler's content binding fails.
public type Service distinct service object {
};

# A polling watcher for a single Azure Files share path. It dispatches each present file to the
# attached service's matching content handler, redelivering an unconsumed file on later polls
# until a handler consumes it (deletes or moves it out of the watched path).
public isolated class Listener {

    private final string shareName;
    private final task:Listener taskListener;
    private boolean running = false;

    # Initializes the listener for a share.
    #
    # + shareName - The name of the share to watch
    # + config - The listener configuration (authentication, polling cadence, retry, transport)
    # + return - An `Error` if the listener could not be initialized, otherwise `()`
    public isolated function init(string shareName, *ListenerConfiguration config) returns Error? {
        self.shareName = shareName;
        // The waiting policy is pinned so scan pacing cannot shift with a future change to the
        // task module's default.
        task:Listener|task:Error taskListener = new (trigger = {
            interval: config.pollingInterval,
            taskPolicy: {waitingPolicy: task:WAIT}
        });
        if taskListener is task:Error {
            return error ProcessingError("failed to initialize the polling scheduler", taskListener,
                    errorCode = "ProcessingError");
        }
        self.taskListener = taskListener;
        return externInit(self, shareName, config);
    }

    # Attaches a service to the listener. One service attaches per listener; a second attach fails.
    #
    # + serviceRef - The service to attach
    # + name - The standard listener-contract argument; unused
    # + return - An `error` if the service could not be attached, otherwise `()`
    public isolated function attach(Service serviceRef, string[]|string? name = ()) returns error? {
        return externAttach(self, serviceRef);
    }

    # Detaches a service from the listener.
    #
    # + serviceRef - The service to detach
    # + return - An `error` if the service could not be detached, otherwise `()`
    public isolated function detach(Service serviceRef) returns error? {
        return externDetach(self, serviceRef);
    }

    # Starts polling and dispatching to the attached service.
    #
    # + return - An `error` if the listener could not start, otherwise `()`
    public isolated function 'start() returns error? {
        lock {
            if self.running {
                return error("the listener is already running");
            }
            check self.taskListener.attach(createPollService(self));
            check self.taskListener.'start();
            self.running = true;
        }
    }

    # Stops polling, letting any in-flight handler invocation finish.
    #
    # + return - An `error` if the listener could not stop, otherwise `()`
    public isolated function gracefulStop() returns error? {
        return self.stopPolling(true);
    }

    # Stops polling immediately.
    #
    # + return - An `error` if the listener could not stop, otherwise `()`
    public isolated function immediateStop() returns error? {
        return self.stopPolling(false);
    }

    private isolated function stopPolling(boolean graceful) returns error? {
        lock {
            if self.running {
                check self.taskListener.gracefulStop();
                self.running = false;
            }
        }
        return externStop(self, graceful);
    }
}

# Creates the task service whose `execute` drives one poll of the listener. It is attached to the
# listener's task scheduler by `Listener.start`; stopping the scheduler deregisters it.
isolated function createPollService(Listener l) returns task:Service {
    return isolated service object {
        isolated function execute() returns error? {
            error? e = trap poll(l);
            if e is error {
                log:printError("azure.storage.files listener poll failed", 'error = e);
            }
        }
    };
}

isolated function externInit(Listener listenerObj, string shareName, ListenerConfiguration config)
        returns Error? = @java:Method {
    name: "initListener",
    'class: "io.ballerina.lib.azure.storage.files.server.ShareListenerAdaptor"
} external;

isolated function externAttach(Listener listenerObj, Service serviceRef) returns error? = @java:Method {
    name: "attachService",
    'class: "io.ballerina.lib.azure.storage.files.server.ShareListenerAdaptor"
} external;

isolated function externDetach(Listener listenerObj, Service serviceRef) returns error? = @java:Method {
    name: "detachService",
    'class: "io.ballerina.lib.azure.storage.files.server.ShareListenerAdaptor"
} external;

isolated function externStop(Listener listenerObj, boolean graceful) returns error? = @java:Method {
    name: "stopListener",
    'class: "io.ballerina.lib.azure.storage.files.server.ShareListenerAdaptor"
} external;

isolated function poll(Listener listenerObj) returns error? = @java:Method {
    'class: "io.ballerina.lib.azure.storage.files.server.ShareListenerAdaptor"
} external;
