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

// Dual-mode listener and caller tests. Each test drives a real Listener: it uploads a file to a
// watched path, starts the listener, and awaits the dispatch its attached service records. The
// services are anonymous service objects (not service declarations), so the listener compiler
// plugin skips them and the tests control the handler shapes directly. These are the first tests
// to exercise the native dispatch path end to end (poll, content binding, handler invocation,
// the Caller, and the post-process actions).

import ballerina/file;
import ballerina/io;
import ballerina/test;

// Records handler dispatches so a test can await and assert them across the listener's dispatch
// threads. Isolated: the map state is only touched under the object lock.
isolated class Recorder {
    private final map<int> hits = {};
    private final map<string> payloads = {};

    isolated function hit(string key) {
        lock {
            self.hits[key] = (self.hits[key] ?: 0) + 1;
        }
    }

    isolated function put(string key, string payload) {
        lock {
            self.hits[key] = (self.hits[key] ?: 0) + 1;
            self.payloads[key] = payload;
        }
    }

    isolated function count(string key) returns int {
        lock {
            return self.hits[key] ?: 0;
        }
    }

    isolated function payload(string key) returns string {
        lock {
            return self.payloads[key] ?: "";
        }
    }
}

// Creates (once) the test's share and its watched "/incoming" directory, and returns a client
// bound to the share for uploads and assertions.
function setupWatchedShare(string base) returns [Client, string]|error {
    string share = testShare(base);
    AdminClient admin = check newAdmin();
    boolean shareExists = check admin->hasShare(share);
    if !shareExists {
        check admin->createShare(share);
    }
    check admin.close();
    Client shareClient = check newShareClient(share);
    boolean dirExists = check shareClient->hasDirectory("/incoming");
    if !dirExists {
        check shareClient->createDirectory("/incoming");
    }
    return [shareClient, share];
}

@test:Config {}
function testListenerOnFileDispatch() returns error? {
    [Client, string] setup = check setupWatchedShare("lsn-onfile");
    Client shareClient = setup[0];
    string share = setup[1];
    check shareClient->uploadContent("payload-onfile", "/incoming/note.dat");

    final Recorder recorder = new;
    Listener lsn = check newListener(share);
    Service svc = @ServiceConfig {path: "/incoming"} service object {
        remote function onFile(byte[] content, FileInfo info, Caller caller) returns error? {
            recorder.put("onfile", check string:fromBytes(content));
            check caller->deleteFile(info.path);
        }
    };
    check lsn.attach(svc);
    check lsn.'start();
    check await(() => recorder.count("onfile") >= 1);
    check lsn.gracefulStop();
    check lsn.detach(svc);

    test:assertEquals(recorder.payload("onfile"), "payload-onfile");
    check shareClient.close();
}

@test:Config {}
function testAttachRejectsSecondService() returns error? {
    string share = testShare("lsn-attach2");
    Listener lsn = check newListener(share);
    Service first = @ServiceConfig {path: "/incoming"} service object {
        remote function onFile(byte[] content) returns error? {
        }
    };
    Service second = @ServiceConfig {path: "/incoming"} service object {
        remote function onFile(byte[] content) returns error? {
        }
    };
    check lsn.attach(first);
    error? rejected = lsn.attach(second);
    test:assertTrue(rejected is error, "a second attach must be rejected");
    if rejected is error {
        test:assertTrue(rejected.message().includes("one service per listener"), rejected.message());
    }
}

@test:Config {}
function testStartTwiceRejected() returns error? {
    [Client, string] setup = check setupWatchedShare("lsn-start2");
    Client shareClient = setup[0];
    string share = setup[1];
    Listener lsn = check newListener(share);
    Service svc = @ServiceConfig {path: "/incoming"} service object {
        remote function onFile(byte[] content) returns error? {
        }
    };
    check lsn.attach(svc);
    check lsn.'start();
    error? second = lsn.'start();
    test:assertTrue(second is error, "a second start must be rejected");
    if second is error {
        test:assertTrue(second.message().includes("already running"), second.message());
    }
    check lsn.gracefulStop();
    check lsn.detach(svc);
    check shareClient.close();
}

@test:Config {}
function testDetachWrongServiceRejected() returns error? {
    string share = testShare("lsn-detach2");
    Listener lsn = check newListener(share);
    Service attached = @ServiceConfig {path: "/incoming"} service object {
        remote function onFile(byte[] content) returns error? {
        }
    };
    Service other = @ServiceConfig {path: "/incoming"} service object {
        remote function onFile(byte[] content) returns error? {
        }
    };
    check lsn.attach(attached);
    error? mismatch = lsn.detach(other);
    test:assertTrue(mismatch is error, "detaching a service that is not attached must fail");
    if mismatch is error {
        test:assertTrue(mismatch.message().includes("not attached"), mismatch.message());
    }
    check lsn.detach(attached);
}

@test:Config {}
function testTypedJsonRouting() returns error? {
    [Client, string] setup = check setupWatchedShare("lsn-json");
    Client shareClient = setup[0];
    string share = setup[1];
    map<json> document = {name: "widget", qty: 5};
    check shareClient->uploadContent(document, "/incoming/item.json");

    final Recorder recorder = new;
    Listener lsn = check newListener(share);
    Service svc = @ServiceConfig {path: "/incoming"} service object {
        remote function onFileJson(map<json> content, FileInfo info, Caller caller) returns error? {
            recorder.put("json", content.toJsonString());
            check caller->deleteFile(info.path);
        }

        remote function onFile(byte[] content, FileInfo info, Caller caller) returns error? {
            recorder.hit("fallback");
        }
    };
    check lsn.attach(svc);
    check lsn.'start();
    check await(() => recorder.count("json") >= 1);
    check lsn.gracefulStop();
    check lsn.detach(svc);

    test:assertEquals(recorder.count("fallback"), 0, "a .json file must route to onFileJson, not onFile");
    test:assertTrue(recorder.payload("json").includes("widget"), recorder.payload("json"));
    check shareClient.close();
}

@test:Config {}
function testUnmappedExtensionFallsBackToOnFile() returns error? {
    [Client, string] setup = check setupWatchedShare("lsn-fallback");
    Client shareClient = setup[0];
    string share = setup[1];
    check shareClient->uploadContent("raw-bytes", "/incoming/blob.bin");

    final Recorder recorder = new;
    Listener lsn = check newListener(share);
    Service svc = @ServiceConfig {path: "/incoming"} service object {
        remote function onFileJson(map<json> content, FileInfo info, Caller caller) returns error? {
            recorder.hit("json");
        }

        remote function onFile(byte[] content, FileInfo info, Caller caller) returns error? {
            recorder.put("onfile", check string:fromBytes(content));
            check caller->deleteFile(info.path);
        }
    };
    check lsn.attach(svc);
    check lsn.'start();
    check await(() => recorder.count("onfile") >= 1);
    check lsn.gracefulStop();
    check lsn.detach(svc);

    test:assertEquals(recorder.count("json"), 0, "an unmapped extension must not reach a typed handler");
    test:assertEquals(recorder.payload("onfile"), "raw-bytes");
    check shareClient.close();
}

@test:Config {}
function testMalformedJsonTriggersAfterError() returns error? {
    [Client, string] setup = check setupWatchedShare("lsn-malformed");
    Client shareClient = setup[0];
    string share = setup[1];
    // Not a JSON object at the root, so binding to map<json> fails: a content-binding error, which
    // triggers afterError (here a DELETE), and never falls through to onFile.
    check shareClient->uploadContent("this is not json", "/incoming/broken.json");

    final Recorder recorder = new;
    Listener lsn = check newListener(share);
    Service svc = @ServiceConfig {path: "/incoming"} service object {
        @FunctionConfig {afterError: DELETE}
        remote function onFileJson(map<json> content, FileInfo info, Caller caller) returns error? {
            recorder.hit("json");
        }

        remote function onFile(byte[] content, FileInfo info, Caller caller) returns error? {
            recorder.hit("fallback");
        }
    };
    check lsn.attach(svc);
    check lsn.'start();
    // The malformed file is consumed by afterError; wait for it to disappear.
    check await(function() returns boolean|error {
        boolean present = check shareClient->hasFile("/incoming/broken.json");
        return !present;
    });
    check lsn.gracefulStop();
    check lsn.detach(svc);

    test:assertEquals(recorder.count("json"), 0, "malformed content must not invoke the typed handler body");
    test:assertEquals(recorder.count("fallback"), 0, "a content-binding error must not fall through to onFile");
    check shareClient.close();
}

// A closed record that an onFileJson handler can bind directly from an object-root JSON file.
type OrderDoc record {|
    string sku;
    int qty;
|};

@test:Config {}
function testOnFileJsonRecordBinding() returns error? {
    [Client, string] setup = check setupWatchedShare("lsn-json-record");
    Client shareClient = setup[0];
    string share = setup[1];
    map<json> document = {sku: "A1", qty: 5};
    check shareClient->uploadContent(document, "/incoming/order.json");

    final Recorder recorder = new;
    Listener lsn = check newListener(share);
    Service svc = @ServiceConfig {path: "/incoming"} service object {
        remote function onFileJson(OrderDoc content, FileInfo info, Caller caller) returns error? {
            recorder.put("record", content.sku + ":" + content.qty.toString());
            check caller->deleteFile(info.path);
        }
    };
    check lsn.attach(svc);
    check lsn.'start();
    check await(() => recorder.count("record") >= 1);
    check lsn.gracefulStop();
    check lsn.detach(svc);

    test:assertEquals(recorder.payload("record"), "A1:5");
    check shareClient.close();
}

@test:Config {}
function testOnFileJsonArrayRootBindingError() returns error? {
    [Client, string] setup = check setupWatchedShare("lsn-json-array");
    Client shareClient = setup[0];
    string share = setup[1];
    // A JSON array at the root parses, but binding to map<json> fails: a content-binding error,
    // which triggers afterError (here a DELETE), and never falls through to onFile.
    check shareClient->uploadContent("[1, 2, 3]", "/incoming/list.json");

    final Recorder recorder = new;
    Listener lsn = check newListener(share);
    Service svc = @ServiceConfig {path: "/incoming"} service object {
        @FunctionConfig {afterError: DELETE}
        remote function onFileJson(map<json> content, FileInfo info, Caller caller) returns error? {
            recorder.hit("json");
        }

        remote function onFile(byte[] content, FileInfo info, Caller caller) returns error? {
            recorder.hit("fallback");
        }
    };
    check lsn.attach(svc);
    check lsn.'start();
    // The array-root file is consumed by afterError; wait for it to disappear.
    check await(function() returns boolean|error {
        boolean present = check shareClient->hasFile("/incoming/list.json");
        return !present;
    });
    check lsn.gracefulStop();
    check lsn.detach(svc);

    test:assertEquals(recorder.count("json"), 0, "an array-root JSON must not invoke the map<json> handler body");
    test:assertEquals(recorder.count("fallback"), 0, "a content-binding error must not fall through to onFile");
    check shareClient.close();
}

@test:Config {}
function testOnFileJsonMapArrayBinding() returns error? {
    [Client, string] setup = check setupWatchedShare("lsn-json-maparr");
    Client shareClient = setup[0];
    string share = setup[1];
    check shareClient->uploadContent("[{\"sku\": \"A1\"}, {\"sku\": \"B2\"}]", "/incoming/batch.json");

    final Recorder recorder = new;
    Listener lsn = check newListener(share);
    Service svc = @ServiceConfig {path: "/incoming"} service object {
        remote function onFileJson(map<json>[] content, FileInfo info, Caller caller) returns error? {
            string[] skus = [];
            foreach map<json> item in content {
                skus.push(check item["sku"].ensureType(string));
            }
            recorder.put("maparr", string:'join(",", ...skus));
            check caller->deleteFile(info.path);
        }
    };
    check lsn.attach(svc);
    check lsn.'start();
    check await(() => recorder.count("maparr") >= 1);
    check lsn.gracefulStop();
    check lsn.detach(svc);

    test:assertEquals(recorder.payload("maparr"), "A1,B2");
    check shareClient.close();
}

@test:Config {}
function testOnFileJsonRecordArrayBinding() returns error? {
    [Client, string] setup = check setupWatchedShare("lsn-json-recarr");
    Client shareClient = setup[0];
    string share = setup[1];
    check shareClient->uploadContent("[{\"sku\": \"A1\", \"qty\": 2}, {\"sku\": \"B2\", \"qty\": 7}]",
            "/incoming/orders.json");

    final Recorder recorder = new;
    Listener lsn = check newListener(share);
    Service svc = @ServiceConfig {path: "/incoming"} service object {
        remote function onFileJson(OrderDoc[] content, FileInfo info, Caller caller) returns error? {
            string[] parts = [];
            foreach OrderDoc item in content {
                parts.push(item.sku + ":" + item.qty.toString());
            }
            recorder.put("recarr", string:'join(",", ...parts));
            check caller->deleteFile(info.path);
        }
    };
    check lsn.attach(svc);
    check lsn.'start();
    check await(() => recorder.count("recarr") >= 1);
    check lsn.gracefulStop();
    check lsn.detach(svc);

    test:assertEquals(recorder.payload("recarr"), "A1:2,B2:7");
    check shareClient.close();
}

@test:Config {}
function testOnFileJsonArrayTargetObjectRootBindingError() returns error? {
    [Client, string] setup = check setupWatchedShare("lsn-json-arrmismatch");
    Client shareClient = setup[0];
    string share = setup[1];
    // An object root cannot bind to an array-typed handler: a content-binding error, which
    // triggers afterError (here a DELETE), and never invokes the handler body.
    map<json> document = {sku: "A1"};
    check shareClient->uploadContent(document, "/incoming/single.json");

    final Recorder recorder = new;
    Listener lsn = check newListener(share);
    Service svc = @ServiceConfig {path: "/incoming"} service object {
        @FunctionConfig {afterError: DELETE}
        remote function onFileJson(map<json>[] content, FileInfo info, Caller caller) returns error? {
            recorder.hit("maparr");
        }
    };
    check lsn.attach(svc);
    check lsn.'start();
    // The mismatched file is consumed by afterError; wait for it to disappear.
    check await(function() returns boolean|error {
        boolean present = check shareClient->hasFile("/incoming/single.json");
        return !present;
    });
    check lsn.gracefulStop();
    check lsn.detach(svc);

    test:assertEquals(recorder.count("maparr"), 0, "an object-root JSON must not invoke an array-typed handler body");
    check shareClient.close();
}

@test:Config {}
function testFunctionConfigDeleteConsumes() returns error? {
    [Client, string] setup = check setupWatchedShare("lsn-delete");
    Client shareClient = setup[0];
    string share = setup[1];
    check shareClient->uploadContent("consume-me", "/incoming/temp.dat");

    final Recorder recorder = new;
    Listener lsn = check newListener(share);
    Service svc = @ServiceConfig {path: "/incoming"} service object {
        @FunctionConfig {afterProcess: DELETE}
        remote function onFile(byte[] content, FileInfo info, Caller caller) returns error? {
            recorder.hit("delete");
        }
    };
    check lsn.attach(svc);
    check lsn.'start();
    check await(() => recorder.count("delete") >= 1);
    check await(function() returns boolean|error {
        boolean present = check shareClient->hasFile("/incoming/temp.dat");
        return !present;
    });
    check lsn.gracefulStop();
    check lsn.detach(svc);
    check shareClient.close();
}

@test:Config {}
function testFunctionConfigMoveConsumes() returns error? {
    [Client, string] setup = check setupWatchedShare("lsn-move");
    Client shareClient = setup[0];
    string share = setup[1];
    // The post-process Move creates the destination directory if it is absent, so it is not
    // pre-created here.
    check shareClient->uploadContent("move-me", "/incoming/report.dat");

    final Recorder recorder = new;
    Listener lsn = check newListener(share);
    Service svc = @ServiceConfig {path: "/incoming"} service object {
        @FunctionConfig {afterProcess: {moveTo: "/processed"}}
        remote function onFile(byte[] content, FileInfo info, Caller caller) returns error? {
            recorder.hit("move");
        }
    };
    check lsn.attach(svc);
    check lsn.'start();
    check await(() => recorder.count("move") >= 1);
    check await(function() returns boolean|error {
        boolean atSource = check shareClient->hasFile("/incoming/report.dat");
        boolean atDestination = check shareClient->hasFile("/processed/report.dat");
        return !atSource && atDestination;
    });
    check lsn.gracefulStop();
    check lsn.detach(svc);
    check shareClient.close();
}

@test:Config {}
function testCallerOperations() returns error? {
    [Client, string] setup = check setupWatchedShare("lsn-caller");
    Client shareClient = setup[0];
    string share = setup[1];
    check shareClient->uploadContent("trigger", "/incoming/go.dat");

    final Recorder recorder = new;
    Listener lsn = check newListener(share);
    Service svc = @ServiceConfig {path: "/incoming"} service object {
        remote function onFile(byte[] content, FileInfo info, Caller caller) returns error? {
            recorder.put("shareName", caller.getShareName());

            check caller->createDirectory("/work");
            check caller->uploadContent("alpha", "/work/a.txt");

            stream<Entry, Error?> entries = check caller->list("/work");
            int listed = 0;
            check entries.forEach(function(Entry entry) {
                listed += 1;
            });
            recorder.put("listed", listed.toString());

            stream<byte[], Error?> chunks = check caller->getFileContent("/work/a.txt");
            byte[] gathered = [];
            check chunks.forEach(function(byte[] chunk) {
                gathered.push(...chunk);
            });
            recorder.put("downloaded", check string:fromBytes(gathered));

            CopyInfo copy = check caller->copyFile("/work/a.txt", "/work/b.txt");
            CopyStatusInfo? copyState = check caller->checkCopyStatus("/work/b.txt");
            if copyState is CopyStatusInfo && copyState.copyId == copy.copyId {
                recorder.hit("copy-status-seen");
            }
            // A completed copy cannot be aborted; tolerated, the call still exercises the binding.
            error? aborted = caller->abortCopy("/work/b.txt", copy.copyId);
            if aborted is error {
                recorder.hit("abort-rejected");
            }
            check caller->renameFile("/work/b.txt", "/work/c.txt");

            check caller->deleteFile("/work/a.txt");
            check caller->deleteFile("/work/c.txt");
            check caller->deleteDirectory("/work");

            check caller->deleteFile(info.path);
            recorder.hit("done");
        }
    };
    check lsn.attach(svc);
    check lsn.'start();
    check await(() => recorder.count("done") >= 1, timeoutSeconds = 90);
    check lsn.immediateStop();
    check lsn.detach(svc);

    test:assertEquals(recorder.payload("shareName"), share);
    test:assertEquals(recorder.payload("downloaded"), "alpha");
    test:assertTrue(recorder.count("copy-status-seen") >= 1);
    test:assertTrue(recorder.count("done") >= 1);
    check shareClient.close();
}

@test:Config {}
function testCallerFileTransfer() returns error? {
    [Client, string] setup = check setupWatchedShare("lsn-transfer");
    Client shareClient = setup[0];
    string share = setup[1];
    check shareClient->uploadContent("go", "/incoming/start.dat");

    string tempDir = check file:createTempDir();
    string localUpload = check file:joinPath(tempDir, "upload.txt");
    string localDownload = check file:joinPath(tempDir, "download.txt");
    check io:fileWriteString(localUpload, "beta");

    final Recorder recorder = new;
    final string localUploadPath = localUpload;
    final string localDownloadPath = localDownload;
    Listener lsn = check newListener(share);
    Service svc = @ServiceConfig {path: "/incoming"} service object {
        remote function onFile(byte[] content, FileInfo info, Caller caller) returns error? {
            check caller->createDirectory("/work");
            check caller->uploadFile(localUploadPath, "/work/uploaded.txt");
            check caller->downloadFile("/work/uploaded.txt", localDownloadPath);
            recorder.put("roundtrip", check io:fileReadString(localDownloadPath));
            check caller->deleteFile("/work/uploaded.txt");
            check caller->deleteFile(info.path);
            recorder.hit("done");
        }
    };
    check lsn.attach(svc);
    check lsn.'start();
    check await(() => recorder.count("done") >= 1, timeoutSeconds = 90);
    check lsn.gracefulStop();
    check lsn.detach(svc);

    test:assertEquals(recorder.payload("roundtrip"), "beta");
    check shareClient.close();
}
