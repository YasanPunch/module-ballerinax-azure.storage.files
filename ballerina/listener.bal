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

# Configuration for an `azure.storage.files` `Listener`
public type ListenerConfiguration record {|
    # The authentication configuration (see `AuthConfig`)
    AuthConfig auth;
    # How often the watched path is polled, in seconds. Must be greater than zero
    decimal pollingInterval = 60;
    # Retry behaviour for service requests; omit for the service defaults
    RetryConfig retryConfig?;
    # HTTP transport settings (proxy, connection pool, TLS); omit for the defaults
    TransportConfig transportConfig?;
    # Relaxed data binding for the typed content handlers: JSON, XML, and CSV record binding
    # treat a null value as an optional field and an absent field as a nilable field
    boolean laxDataBinding = false;
|};

# Optional per-service filters, supplied through the `@files:ServiceConfig` annotation. The
# watched path itself is the service's attach point (for example `service /invoices on lsn`),
# and a service with no attach point watches the share root.
public type ServiceConfiguration record {|
    # Watch subdirectories under the watched path
    boolean recursive = true;
    # A regular expression matched against the file name (not the path); non-matching files
    # are never dispatched
    string fileNamePattern?;
    # Skip files younger than this many seconds
    decimal minFileAgeSeconds?;
|};

# Declares the optional filters of a listener service.
public annotation ServiceConfiguration ServiceConfig on service;

# The auto-consume action that deletes the file after the handler runs.
public const DELETE = "DELETE";

# The auto-consume action that moves the file after the handler runs. A move onto an
# existing same-named file replaces it.
public type Move record {|
    # The target directory the file is moved into (the file keeps its name); the directory
    # is created if it does not exist
    string moveTo;
    # Recreate the file's sub-path (relative to the watched path) under `moveTo`, on
    # recursive watches
    boolean preserveSubDirs = true;
|};

# The `Move` action's named form, used in the post-process action unions.
public type MOVE Move;

# The per-handler configuration, supplied through the `@files:FunctionConfig` annotation. It
# routes files to a handler by name pattern and auto-consumes a file after the handler runs.
# On `onError`, the consume actions apply to the content-binding failures it handles, and
# `fileNamePattern` is ignored.
public type FunctionConfiguration record {|
    # A regular expression matched against the file name that routes matching files to this handler
    string fileNamePattern?;
    # The action applied after the handler returns normally: delete the file, or move it
    DELETE|MOVE afterProcess?;
    # The action applied after the handler returns or panics with an error: delete the file, or
    # move it. Also covers a typed handler's content-binding failures when no `onError` is declared
    DELETE|MOVE afterError?;
|};

# Declares the configuration of a listener handler.
public annotation FunctionConfiguration FunctionConfig on object function;

# The service type attached to a `Listener`.
public type Service distinct service object {
};

# A polling watcher for a single Azure Files share path.
public isolated class Listener {
    private final string shareName;
    private final task:Listener taskListener;
    private task:Service? pollService = ();
    private boolean running = false;
    private boolean stopped = false;

    # Initializes the listener for a share.
    #
    # + shareName - The name of the share to watch
    # + config - The listener configuration (authentication, polling cadence, retry, transport)
    # + return - An `Error` if the listener could not be initialized, otherwise `()`
    public isolated function init(string shareName, *ListenerConfiguration config) returns Error? {
        self.shareName = shareName;
        if config.pollingInterval <= 0d {
            return error Error("pollingInterval must be greater than zero");
        }
        task:Listener|task:Error taskListener = new (trigger = {interval: config.pollingInterval});
        if taskListener is task:Error {
            return error Error("failed to initialize the polling scheduler", taskListener);
        }
        self.taskListener = taskListener;

        ClientConfiguration clientConfig = {auth: config.auth};
        RetryConfig? retryConfig = config?.retryConfig;
        if retryConfig is RetryConfig {
            clientConfig.retryConfig = retryConfig;
        }
        TransportConfig? transportConfig = config?.transportConfig;
        if transportConfig is TransportConfig {
            clientConfig.transportConfig = transportConfig;
        }

        // One connection stack per listener: the Caller's Client also backs the poller.
        Caller caller = check new (shareName, clientConfig);
        return externInit(self, shareName, config, caller);
    }

    # Attaches a service to the listener. One service attaches per listener; a second attach
    # fails.
    #
    # + serviceRef - The service to attach
    # + name - The watched path, from the service's attach point. When absent, the service watches the share root.
    # + return - An `error` if the service could not be attached, otherwise `()`
    public isolated function attach(Service serviceRef, string[]|string? name = ()) returns error? {
        check externAttach(self, serviceRef, name);
        error? attached = ();
        lock {
            task:Service pollService = createPollService(self);
            error? result = self.taskListener.attach(pollService);
            if result is () {
                self.pollService = pollService;
            }
            attached = result;
        }
        if attached is error {
            check externDetach(self, serviceRef);
            return attached;
        }
    }

    # Detaches a service from the listener.
    #
    # + serviceRef - The service to detach
    # + return - An `error` if the service could not be detached, otherwise `()`
    public isolated function detach(Service serviceRef) returns error? {
        check externDetach(self, serviceRef);
        lock {
            task:Service? pollService = self.pollService;
            if pollService is task:Service {
                check self.taskListener.detach(pollService);
                self.pollService = ();
            }
        }
    }

    # Starts polling and dispatching to the attached service.
    #
    # + return - An `error` if the listener could not start, otherwise `()`
    public isolated function 'start() returns error? {
        lock {
            if self.running {
                return error("the listener is already running");
            }
            // A stop deregisters the poll job and closes the watch for good; restarting is not
            // supported, so say so rather than start a listener that would never poll again.
            if self.stopped {
                return error("the listener has been stopped and cannot be started again");
            }
            check self.taskListener.'start();
            self.running = true;
        }
    }

    # Stops polling. In-flight handler invocations run to completion.
    #
    # + return - An `error` if the listener could not stop, otherwise `()`
    public isolated function gracefulStop() returns error? {
        return self.stopPolling(true);
    }

    # Stops polling immediately. In-flight handler invocations run to completion.
    #
    # + return - An `error` if the listener could not stop, otherwise `()`
    public isolated function immediateStop() returns error? {
        return self.stopPolling(false);
    }

    private isolated function stopPolling(boolean graceful) returns error? {
        lock {
            // Stopping a listener that never started is a no-op: marking it stopped here would
            // close the watch before it ever opened, leaving nothing to observe it.
            if !self.running {
                return ();
            }
            if graceful {
                check self.taskListener.gracefulStop();
            } else {
                check self.taskListener.immediateStop();
            }
            // Stopping the task scheduler deregisters the poll job, so a later detach
            // must not try to detach it again.
            self.pollService = ();
            self.running = false;
            self.stopped = true;
        }
        return externStop(self);
    }
}

# Creates the task service whose `execute` drives one poll of the listener. It is attached to
# the listener's task scheduler by `Listener.attach`; detaching or stopping deregisters it.
#
# + l - The listener
# + return - The task service
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

// The listener's Java side reports its diagnostics through these, so they reach the user the same
// way the poll failure above does. Calling `log` directly from Java would need an slf4j binding,
// which none of the Ballerina distributions carry, so every such line would be discarded.
isolated function logListenerWarn(string message) {
    log:printWarn(message);
}

isolated function logListenerError(string message) {
    log:printError(message);
}

isolated function logListenerDebug(string message) {
    log:printDebug(message);
}

isolated function externInit(Listener listenerObj, string shareName, ListenerConfiguration config,
        Caller caller) returns Error? = @java:Method {
    name: "initListener", 'class: "io.ballerina.lib.azure.storage.files.server.Listener"
} external;

isolated function externAttach(Listener listenerObj, Service serviceRef, string[]|string? name)
        returns error? = @java:Method {
    name: "attachService", 'class: "io.ballerina.lib.azure.storage.files.server.Listener"
} external;

isolated function externDetach(Listener listenerObj, Service serviceRef) returns error? = @java:Method {
    name: "detachService", 'class: "io.ballerina.lib.azure.storage.files.server.Listener"
} external;

isolated function externStop(Listener listenerObj) returns error? = @java:Method {
    name: "stopListener", 'class: "io.ballerina.lib.azure.storage.files.server.Listener"
} external;

isolated function poll(Listener listenerObj) returns error? = @java:Method {
    'class: "io.ballerina.lib.azure.storage.files.server.Listener"
} external;
