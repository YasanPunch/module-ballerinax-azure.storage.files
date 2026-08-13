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
import ballerina/lang.runtime;
import ballerina/test;
import ballerina/time;

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
    Service svc = service object {
        remote function onFile(byte[] content, FileInfo info, Caller caller) returns error? {
            recorder.put("onfile", check string:fromBytes(content));
            check caller->deleteFile(info.path);
        }
    };
    check lsn.attach(svc, "/incoming");
    check lsn.'start();
    check await(() => recorder.count("onfile") >= 1);
    check lsn.gracefulStop();
    check lsn.detach(svc);

    test:assertEquals(recorder.payload("onfile"), "payload-onfile");
}

@test:Config {}
function testAttachRejectsSecondService() returns error? {
    string share = testShare("lsn-attach2");
    Listener lsn = check newListener(share);
    Service first = service object {
        remote function onFile(byte[] content) returns error? {
        }
    };
    Service second = service object {
        remote function onFile(byte[] content) returns error? {
        }
    };
    check lsn.attach(first, "/incoming");
    error? rejected = lsn.attach(second, "/incoming");
    test:assertTrue(rejected is error, "a second attach must be rejected");
    if rejected is error {
        test:assertTrue(rejected.message().includes("Only one service can be attached"), rejected.message());
    }
}

@test:Config {}
function testStartTwiceRejected() returns error? {
    [Client, string] setup = check setupWatchedShare("lsn-start2");
    string share = setup[1];
    Listener lsn = check newListener(share);
    Service svc = service object {
        remote function onFile(byte[] content) returns error? {
        }
    };
    check lsn.attach(svc, "/incoming");
    check lsn.'start();
    error? second = lsn.'start();
    test:assertTrue(second is error, "a second start must be rejected");
    if second is error {
        test:assertTrue(second.message().includes("already running"), second.message());
    }
    check lsn.gracefulStop();
    check lsn.detach(svc);
}

@test:Config {}
function testDetachWrongServiceRejected() returns error? {
    string share = testShare("lsn-detach2");
    Listener lsn = check newListener(share);
    Service attached = service object {
        remote function onFile(byte[] content) returns error? {
        }
    };
    Service other = service object {
        remote function onFile(byte[] content) returns error? {
        }
    };
    check lsn.attach(attached, "/incoming");
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
    Service svc = service object {
        remote function onFileJson(map<json> content, FileInfo info, Caller caller) returns error? {
            recorder.put("json", content.toJsonString());
            check caller->deleteFile(info.path);
        }

        remote function onFile(byte[] content, FileInfo info, Caller caller) returns error? {
            recorder.hit("fallback");
        }
    };
    check lsn.attach(svc, "/incoming");
    check lsn.'start();
    check await(() => recorder.count("json") >= 1);
    check lsn.gracefulStop();
    check lsn.detach(svc);

    test:assertEquals(recorder.count("fallback"), 0, "a .json file must route to onFileJson, not onFile");
    test:assertTrue(recorder.payload("json").includes("widget"), recorder.payload("json"));
}

@test:Config {}
function testUnmappedExtensionFallsBackToOnFile() returns error? {
    [Client, string] setup = check setupWatchedShare("lsn-fallback");
    Client shareClient = setup[0];
    string share = setup[1];
    check shareClient->uploadContent("raw-bytes", "/incoming/blob.bin");

    final Recorder recorder = new;
    Listener lsn = check newListener(share);
    Service svc = service object {
        remote function onFileJson(map<json> content, FileInfo info, Caller caller) returns error? {
            recorder.hit("json");
        }

        remote function onFile(byte[] content, FileInfo info, Caller caller) returns error? {
            recorder.put("onfile", check string:fromBytes(content));
            check caller->deleteFile(info.path);
        }
    };
    check lsn.attach(svc, "/incoming");
    check lsn.'start();
    check await(() => recorder.count("onfile") >= 1);
    check lsn.gracefulStop();
    check lsn.detach(svc);

    test:assertEquals(recorder.count("json"), 0, "an unmapped extension must not reach a typed handler");
    test:assertEquals(recorder.payload("onfile"), "raw-bytes");
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
    Service svc = service object {
        @FunctionConfig {afterError: DELETE}
        remote function onFileJson(map<json> content, FileInfo info, Caller caller) returns error? {
            recorder.hit("json");
        }

        remote function onFile(byte[] content, FileInfo info, Caller caller) returns error? {
            recorder.hit("fallback");
        }
    };
    check lsn.attach(svc, "/incoming");
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
    Service svc = service object {
        remote function onFileJson(OrderDoc content, FileInfo info, Caller caller) returns error? {
            recorder.put("record", content.sku + ":" + content.qty.toString());
            check caller->deleteFile(info.path);
        }
    };
    check lsn.attach(svc, "/incoming");
    check lsn.'start();
    check await(() => recorder.count("record") >= 1);
    check lsn.gracefulStop();
    check lsn.detach(svc);

    test:assertEquals(recorder.payload("record"), "A1:5");
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
    Service svc = service object {
        @FunctionConfig {afterError: DELETE}
        remote function onFileJson(map<json> content, FileInfo info, Caller caller) returns error? {
            recorder.hit("json");
        }

        remote function onFile(byte[] content, FileInfo info, Caller caller) returns error? {
            recorder.hit("fallback");
        }
    };
    check lsn.attach(svc, "/incoming");
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
}

@test:Config {}
function testOnFileJsonMapArrayBinding() returns error? {
    [Client, string] setup = check setupWatchedShare("lsn-json-maparr");
    Client shareClient = setup[0];
    string share = setup[1];
    check shareClient->uploadContent("[{\"sku\": \"A1\"}, {\"sku\": \"B2\"}]", "/incoming/batch.json");

    final Recorder recorder = new;
    Listener lsn = check newListener(share);
    Service svc = service object {
        remote function onFileJson(map<json>[] content, FileInfo info, Caller caller) returns error? {
            string[] skus = [];
            foreach map<json> item in content {
                skus.push(check item["sku"].ensureType(string));
            }
            recorder.put("maparr", string:'join(",", ...skus));
            check caller->deleteFile(info.path);
        }
    };
    check lsn.attach(svc, "/incoming");
    check lsn.'start();
    check await(() => recorder.count("maparr") >= 1);
    check lsn.gracefulStop();
    check lsn.detach(svc);

    test:assertEquals(recorder.payload("maparr"), "A1,B2");
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
    Service svc = service object {
        remote function onFileJson(OrderDoc[] content, FileInfo info, Caller caller) returns error? {
            string[] parts = [];
            foreach OrderDoc item in content {
                parts.push(item.sku + ":" + item.qty.toString());
            }
            recorder.put("recarr", string:'join(",", ...parts));
            check caller->deleteFile(info.path);
        }
    };
    check lsn.attach(svc, "/incoming");
    check lsn.'start();
    check await(() => recorder.count("recarr") >= 1);
    check lsn.gracefulStop();
    check lsn.detach(svc);

    test:assertEquals(recorder.payload("recarr"), "A1:2,B2:7");
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
    Service svc = service object {
        @FunctionConfig {afterError: DELETE}
        remote function onFileJson(map<json>[] content, FileInfo info, Caller caller) returns error? {
            recorder.hit("maparr");
        }
    };
    check lsn.attach(svc, "/incoming");
    check lsn.'start();
    // The mismatched file is consumed by afterError; wait for it to disappear.
    check await(function() returns boolean|error {
        boolean present = check shareClient->hasFile("/incoming/single.json");
        return !present;
    });
    check lsn.gracefulStop();
    check lsn.detach(svc);

    test:assertEquals(recorder.count("maparr"), 0, "an object-root JSON must not invoke an array-typed handler body");
}

@test:Config {}
function testFunctionConfigDeleteConsumes() returns error? {
    [Client, string] setup = check setupWatchedShare("lsn-delete");
    Client shareClient = setup[0];
    string share = setup[1];
    check shareClient->uploadContent("consume-me", "/incoming/temp.dat");

    final Recorder recorder = new;
    Listener lsn = check newListener(share);
    Service svc = service object {
        @FunctionConfig {afterProcess: DELETE}
        remote function onFile(byte[] content, FileInfo info, Caller caller) returns error? {
            recorder.hit("delete");
        }
    };
    check lsn.attach(svc, "/incoming");
    check lsn.'start();
    check await(() => recorder.count("delete") >= 1);
    check await(function() returns boolean|error {
        boolean present = check shareClient->hasFile("/incoming/temp.dat");
        return !present;
    });
    check lsn.gracefulStop();
    check lsn.detach(svc);
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
    Service svc = service object {
        @FunctionConfig {afterProcess: {moveTo: "/processed"}}
        remote function onFile(byte[] content, FileInfo info, Caller caller) returns error? {
            recorder.hit("move");
        }
    };
    check lsn.attach(svc, "/incoming");
    check lsn.'start();
    check await(() => recorder.count("move") >= 1);
    check await(function() returns boolean|error {
        boolean atSource = check shareClient->hasFile("/incoming/report.dat");
        boolean atDestination = check shareClient->hasFile("/processed/report.dat");
        return !atSource && atDestination;
    });
    check lsn.gracefulStop();
    check lsn.detach(svc);
}

@test:Config {}
function testCallerOperations() returns error? {
    [Client, string] setup = check setupWatchedShare("lsn-caller");
    Client shareClient = setup[0];
    string share = setup[1];
    check shareClient->uploadContent("trigger", "/incoming/go.dat");

    final Recorder recorder = new;
    Listener lsn = check newListener(share);
    Service svc = service object {
        remote function onFile(byte[] content, FileInfo info, Caller caller) returns error? {
            recorder.put("shareName", info.shareName);

            check caller->createDirectory("/work");
            check caller->uploadContent("alpha", "/work/a.txt");

            // The Caller mirrors the Client's record upload contract by delegation.
            check caller->uploadContent({"kind": "caller"}, "/work/meta.json");
            string metaJson = check caller->getFileText("/work/meta.json");
            recorder.put("recordUpload", metaJson);
            check caller->deleteFile("/work/meta.json");

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
            // The copy is asynchronous; wait for it to complete before aborting and renaming.
            check await(function() returns boolean|error {
                CopyStatusInfo? copyState = check caller->checkCopyStatus("/work/b.txt");
                return copyState is CopyStatusInfo && copyState.copyId == copy.copyId
                        && copyState.copyStatus == SUCCESS;
            });
            recorder.hit("copy-status-seen");
            // A completed copy cannot be aborted, so the rejection is the expected outcome.
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
    check lsn.attach(svc, "/incoming");
    check lsn.'start();
    check await(() => recorder.count("done") >= 1, timeoutSeconds = 90);
    check lsn.immediateStop();
    check lsn.detach(svc);

    test:assertEquals(recorder.payload("shareName"), share);
    test:assertEquals(recorder.payload("downloaded"), "alpha");
    test:assertEquals(recorder.payload("recordUpload"), "{\"kind\":\"caller\"}");
    test:assertTrue(recorder.count("copy-status-seen") >= 1);
    test:assertTrue(recorder.count("abort-rejected") >= 1, "abortCopy on a completed copy must fail");
    test:assertTrue(recorder.count("done") >= 1);
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
    Service svc = service object {
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
    check lsn.attach(svc, "/incoming");
    check lsn.'start();
    check await(() => recorder.count("done") >= 1, timeoutSeconds = 90);
    check lsn.gracefulStop();
    check lsn.detach(svc);

    test:assertEquals(recorder.payload("roundtrip"), "beta");
}

@test:Config {}
function testTypedTextRouting() returns error? {
    [Client, string] setup = check setupWatchedShare("lsn-text");
    Client shareClient = setup[0];
    string share = setup[1];
    check shareClient->uploadContent("hello text", "/incoming/note.txt");

    final Recorder recorder = new;
    Listener lsn = check newListener(share);
    Service svc = service object {
        remote function onFileText(string content, FileInfo info, Caller caller) returns error? {
            recorder.put("text", content);
            check caller->deleteFile(info.path);
        }
    };
    check lsn.attach(svc, "/incoming");
    check lsn.'start();
    check await(() => recorder.count("text") >= 1);
    check lsn.gracefulStop();
    check lsn.detach(svc);

    test:assertEquals(recorder.payload("text"), "hello text");
}

@test:Config {}
function testTypedXmlRouting() returns error? {
    [Client, string] setup = check setupWatchedShare("lsn-xml");
    Client shareClient = setup[0];
    string share = setup[1];
    check shareClient->uploadContent("<doc><v>7</v></doc>", "/incoming/item.xml");

    final Recorder recorder = new;
    Listener lsn = check newListener(share);
    Service svc = service object {
        remote function onFileXml(xml content, FileInfo info, Caller caller) returns error? {
            recorder.put("xml", content.toString());
            check caller->deleteFile(info.path);
        }
    };
    check lsn.attach(svc, "/incoming");
    check lsn.'start();
    check await(() => recorder.count("xml") >= 1);
    check lsn.gracefulStop();
    check lsn.detach(svc);

    test:assertTrue(recorder.payload("xml").includes("<v>7</v>"), recorder.payload("xml"));
}

@test:Config {}
function testTypedCsvRouting() returns error? {
    [Client, string] setup = check setupWatchedShare("lsn-csv");
    Client shareClient = setup[0];
    string share = setup[1];
    check shareClient->uploadContent("a,b\nc,d", "/incoming/rows.csv");

    final Recorder recorder = new;
    Listener lsn = check newListener(share);
    Service svc = service object {
        remote function onFileCsv(string[][] content, FileInfo info, Caller caller) returns error? {
            string[] rows = [];
            foreach string[] row in content {
                rows.push(string:'join(",", ...row));
            }
            recorder.put("csv", string:'join(";", ...rows));
            check caller->deleteFile(info.path);
        }
    };
    check lsn.attach(svc, "/incoming");
    check lsn.'start();
    check await(() => recorder.count("csv") >= 1);
    check lsn.gracefulStop();
    check lsn.detach(svc);

    test:assertEquals(recorder.payload("csv"), "a,b;c,d");
}

@test:Config {}
function testMinFileAgeSkipsYoungFiles() returns error? {
    [Client, string] setup = check setupWatchedShare("lsn-minage");
    Client shareClient = setup[0];
    string share = setup[1];
    check shareClient->uploadContent("too young", "/incoming/young.dat");

    final Recorder recorder = new;
    Listener lsn = check newListener(share);
    Service svc = @ServiceConfig {minFileAgeSeconds: 3600} service object {
        remote function onFile(byte[] content, FileInfo info, Caller caller) returns error? {
            recorder.hit("dispatched");
        }
    };
    check lsn.attach(svc, "/incoming");
    check lsn.'start();
    // The age gate is categorical here (an hour), so a few polls suffice as the negative window.
    runtime:sleep(4);
    check lsn.gracefulStop();
    check lsn.detach(svc);

    test:assertEquals(recorder.count("dispatched"), 0, "a file younger than minFileAgeSeconds must not dispatch");
    boolean youngPresent = check shareClient->hasFile("/incoming/young.dat");
    test:assertTrue(youngPresent);
}

@test:Config {}
function testNonRecursiveIgnoresSubdirectories() returns error? {
    [Client, string] setup = check setupWatchedShare("lsn-flatwatch");
    Client shareClient = setup[0];
    string share = setup[1];
    check shareClient->createDirectory("/incoming/sub");
    check shareClient->uploadContent("nested", "/incoming/sub/nested.dat");
    check shareClient->uploadContent("top", "/incoming/top.dat");

    final Recorder recorder = new;
    Listener lsn = check newListener(share);
    Service svc = @ServiceConfig {recursive: false} service object {
        remote function onFile(byte[] content, FileInfo info, Caller caller) returns error? {
            recorder.hit(info.name);
            check caller->deleteFile(info.path);
        }
    };
    check lsn.attach(svc, "/incoming");
    check lsn.'start();
    check await(() => recorder.count("top.dat") >= 1);
    runtime:sleep(3);
    check lsn.gracefulStop();
    check lsn.detach(svc);

    test:assertEquals(recorder.count("nested.dat"), 0, "recursive=false must not watch subdirectories");
    boolean nestedPresent = check shareClient->hasFile("/incoming/sub/nested.dat");
    test:assertTrue(nestedPresent);
}

@test:Config {}
function testServiceFileNamePatternFilters() returns error? {
    [Client, string] setup = check setupWatchedShare("lsn-svcpattern");
    Client shareClient = setup[0];
    string share = setup[1];
    check shareClient->uploadContent("wanted", "/incoming/match.dat");
    check shareClient->uploadContent("unwanted", "/incoming/skip.dat");

    final Recorder recorder = new;
    Listener lsn = check newListener(share);
    Service svc = @ServiceConfig {fileNamePattern: "^match\\..*"} service object {
        remote function onFile(byte[] content, FileInfo info, Caller caller) returns error? {
            recorder.hit(info.name);
            check caller->deleteFile(info.path);
        }
    };
    check lsn.attach(svc, "/incoming");
    check lsn.'start();
    check await(() => recorder.count("match.dat") >= 1);
    runtime:sleep(3);
    check lsn.gracefulStop();
    check lsn.detach(svc);

    test:assertEquals(recorder.count("skip.dat"), 0, "a non-matching file name must never dispatch");
    boolean skipPresent = check shareClient->hasFile("/incoming/skip.dat");
    test:assertTrue(skipPresent);
}

@test:Config {}
function testFunctionConfigPatternOverridesExtension() returns error? {
    [Client, string] setup = check setupWatchedShare("lsn-fnpattern");
    Client shareClient = setup[0];
    string share = setup[1];
    // .dat maps to no typed handler, so without the per-handler pattern this file would land in
    // onFile; the pattern must route it to onFileText instead.
    check shareClient->uploadContent("routed-by-pattern", "/incoming/note.dat");

    final Recorder recorder = new;
    Listener lsn = check newListener(share);
    Service svc = service object {
        @FunctionConfig {fileNamePattern: ".*\\.dat$"}
        remote function onFileText(string content, FileInfo info, Caller caller) returns error? {
            recorder.put("text", content);
            check caller->deleteFile(info.path);
        }

        remote function onFile(byte[] content, FileInfo info, Caller caller) returns error? {
            recorder.hit("fallback");
        }
    };
    check lsn.attach(svc, "/incoming");
    check lsn.'start();
    check await(() => recorder.count("text") >= 1);
    check lsn.gracefulStop();
    check lsn.detach(svc);

    test:assertEquals(recorder.payload("text"), "routed-by-pattern");
    test:assertEquals(recorder.count("fallback"), 0, "a pattern-routed file must not reach onFile");
}

@test:Config {}
function testRoutingPatternPrecedenceCanonical() returns error? {
    [Client, string] setup = check setupWatchedShare("lsn-routeorder");
    Client shareClient = setup[0];
    string share = setup[1];
    check shareClient->uploadContent("alpha", "/incoming/report.dat");

    final Recorder recorder = new;
    Listener lsn = check newListener(share);
    // Both routing patterns match report.dat; the canonical order (onFileText before
    // onFileCsv, onFile last) decides the winner, not the declaration order. onFileCsv is
    // deliberately declared first so declaration order cannot mask a broken precedence.
    Service svc = service object {
        @FunctionConfig {fileNamePattern: "report\\..*"}
        remote function onFileCsv(string[][] content) returns error? {
            recorder.hit("csv");
        }

        @FunctionConfig {fileNamePattern: ".*\\.dat$", afterProcess: DELETE}
        remote function onFileText(string content) returns error? {
            recorder.hit("text");
        }
    };
    check lsn.attach(svc, "/incoming");
    check lsn.'start();
    check await(() => recorder.count("text") >= 1);
    runtime:sleep(3);
    check lsn.gracefulStop();
    check lsn.detach(svc);

    test:assertEquals(recorder.count("csv"), 0,
            "when two routing patterns match, onFileText must win over onFileCsv");
}

@test:Config {}
function testInvalidFileNamePatternRejectedAtAttach() returns error? {
    string share = testShare("lsn-badpattern");
    Listener lsn = check newListener(share);
    Service svc = @ServiceConfig {fileNamePattern: "["} service object {
        remote function onFile(byte[] content) returns error? {
        }
    };
    error? attached = lsn.attach(svc, "/incoming");
    test:assertTrue(attached is error, "an invalid fileNamePattern regex must fail at attach");
}


@test:Config {}
function testMoveOntoExistingFileReplaces() returns error? {
    [Client, string] setup = check setupWatchedShare("lsn-moveclash");
    Client shareClient = setup[0];
    string share = setup[1];
    check shareClient->createDirectory("/processed");
    check shareClient->uploadContent("occupied", "/processed/report.dat");
    check shareClient->uploadContent("mover", "/incoming/report.dat");

    final Recorder recorder = new;
    Listener lsn = check newListener(share);
    Service svc = service object {
        @FunctionConfig {afterProcess: {moveTo: "/processed"}}
        remote function onFile(byte[] content, FileInfo info, Caller caller) returns error? {
            recorder.hit("ran");
        }
    };
    check lsn.attach(svc, "/incoming");
    check lsn.'start();
    check await(function() returns boolean|error {
        boolean sourcePresent = check shareClient->hasFile("/incoming/report.dat");
        return recorder.count("ran") >= 1 && !sourcePresent;
    });
    check lsn.gracefulStop();
    check lsn.detach(svc);

    stream<byte[], Error?> chunks = check shareClient->getFileContent("/processed/report.dat");
    byte[] gathered = [];
    check chunks.forEach(function(byte[] chunk) {
        gathered.push(...chunk);
    });
    test:assertEquals(check string:fromBytes(gathered), "mover",
            "a move onto an existing same-named file must replace it");
}

@test:Config {}
function testMovePreserveSubDirsFalseFlattens() returns error? {
    [Client, string] setup = check setupWatchedShare("lsn-moveflat");
    Client shareClient = setup[0];
    string share = setup[1];
    check shareClient->createDirectory("/incoming/sub");
    check shareClient->uploadContent("deep", "/incoming/sub/deep.dat");

    final Recorder recorder = new;
    Listener lsn = check newListener(share);
    Service svc = service object {
        @FunctionConfig {afterProcess: {moveTo: "/flat", preserveSubDirs: false}}
        remote function onFile(byte[] content, FileInfo info, Caller caller) returns error? {
            recorder.hit("moved");
        }
    };
    check lsn.attach(svc, "/incoming");
    check lsn.'start();
    check await(function() returns boolean|error {
        boolean atFlat = check shareClient->hasFile("/flat/deep.dat");
        boolean atSource = check shareClient->hasFile("/incoming/sub/deep.dat");
        return atFlat && !atSource;
    });
    check lsn.gracefulStop();
    check lsn.detach(svc);

    boolean preserved = check shareClient->hasDirectory("/flat/sub");
    test:assertFalse(preserved, "preserveSubDirs=false must not recreate the sub-path under moveTo");
}

@test:Config {}
function testUnmappedFileSkippedWithoutOnFile() returns error? {
    [Client, string] setup = check setupWatchedShare("lsn-skip");
    Client shareClient = setup[0];
    string share = setup[1];
    // .txt maps to onFileText, which is undeclared; with no onFile catch-all either, the file is
    // skipped (and logged) rather than dispatched, and stays in place.
    check shareClient->uploadContent("{}", "/incoming/note.txt");

    final Recorder recorder = new;
    Listener lsn = check newListener(share);
    Service svc = service object {
        remote function onFileJson(map<json> content, FileInfo info, Caller caller) returns error? {
            recorder.hit("json");
        }
    };
    check lsn.attach(svc, "/incoming");
    check lsn.'start();
    runtime:sleep(4);
    check lsn.gracefulStop();
    check lsn.detach(svc);

    test:assertEquals(recorder.count("json"), 0, "a .txt file must not reach onFileJson");
    boolean notePresent = check shareClient->hasFile("/incoming/note.txt");
    test:assertTrue(notePresent);
}

@test:Config {}
function testUnconsumedFileRedelivers() returns error? {
    [Client, string] setup = check setupWatchedShare("lsn-redeliver");
    Client shareClient = setup[0];
    string share = setup[1];
    check shareClient->uploadContent("try again", "/incoming/retry.dat");

    final Recorder recorder = new;
    Listener lsn = check newListener(share);
    Service svc = service object {
        remote function onFile(byte[] content, FileInfo info, Caller caller) returns error? {
            recorder.hit("attempt");
            if recorder.count("attempt") == 1 {
                return error("transient handler failure");
            }
            check caller->deleteFile(info.path);
        }
    };
    check lsn.attach(svc, "/incoming");
    check lsn.'start();
    check await(() => recorder.count("attempt") >= 2);
    check await(function() returns boolean|error {
        boolean present = check shareClient->hasFile("/incoming/retry.dat");
        return !present;
    });
    check lsn.gracefulStop();
    check lsn.detach(svc);

    test:assertTrue(recorder.count("attempt") >= 2,
            "an unconsumed file must be redelivered on a later poll");
}

// ===== Poll-failure surfacing =====
// Pinned to the mock: a failing directory listing cannot be provoked on a real account on
// demand. The mock's listing-fault hook forces every directory listing to fail until it is
// cleared, letting these tests drive the poller's failure path directly through poll().

// Creates (once) a mock-backed share with its watched "/incoming" directory, for the
// mock-pinned poll-failure tests.
function setupMockWatchedShare(string base) returns [Client, string]|error {
    string share = testShare(base);
    AdminClient admin = check newMockAdmin();
    boolean shareExists = check admin->hasShare(share);
    if !shareExists {
        check admin->createShare(share);
    }
    Client shareClient = check newMockShareClient(share);
    boolean dirExists = check shareClient->hasDirectory("/incoming");
    if !dirExists {
        check shareClient->createDirectory("/incoming");
    }
    return [shareClient, share];
}

@test:Config {}
function testPollFailureSurfacesTypedError() returns error? {
    [Client, string] setup = check setupMockWatchedShare("lsn-pollfail");
    string share = setup[1];

    Listener lsn = check newMockListener(share);
    Service svc = service object {
        remote function onFile(byte[] content) returns error? {
        }
    };
    check lsn.attach(svc, "/incoming");

    mockListFaultCode = "AuthenticationFailed";
    error? result = poll(lsn);
    mockListFaultCode = ();

    test:assertTrue(result is AuthorizationError,
            "a 403 AuthenticationFailed listing must surface from poll() as an AuthorizationError");
    check lsn.detach(svc);
}

@test:Config {}
function testPollFailureMapsClientSideError() returns error? {
    // A scan failure that is not an Azure service error (here, the endpoint refuses the
    // connection) surfaces as the module's generic Error, not a ServiceError.
    Listener lsn = check new ("pollfail-conn", auth = {
        accountName: "mockaccount",
        accountKey: MOCK_KEY,
        serviceUrl: "http://localhost:1"
    }, pollingInterval = 1, retryConfig = {maxTries: 1});
    Service svc = service object {
        remote function onFile(byte[] content) returns error? {
        }
    };
    check lsn.attach(svc, "/incoming");

    error? result = poll(lsn);
    test:assertTrue(result is Error && result !is ServiceError,
            "a non-Azure scan failure must surface from poll() as a client-side error");
    check lsn.detach(svc);
}

@test:Config {}
function testListenerRejectsNonPositivePollingInterval() returns error? {
    Listener|Error zero = new ("interval-check", auth = testAuth(), pollingInterval = 0);
    test:assertTrue(zero is Error && zero !is ServiceError,
            "a pollingInterval of zero must fail listener initialization");
    if zero is Error {
        test:assertEquals(zero.message(), "pollingInterval must be greater than zero");
    }
    Listener|Error negative = new ("interval-check", auth = testAuth(), pollingInterval = -1);
    test:assertTrue(negative is Error,
            "a negative pollingInterval must fail listener initialization");
}

@test:Config {}
function testPollFailureRecoversOnNextPoll() returns error? {
    [Client, string] setup = check setupMockWatchedShare("lsn-recover");
    Client shareClient = setup[0];
    string share = setup[1];

    final Recorder recorder = new;
    Listener lsn = check newMockListener(share);
    Service svc = service object {
        remote function onFile(byte[] content, FileInfo info, Caller caller) returns error? {
            recorder.hit("dispatch");
            check caller->deleteFile(info.path);
        }
    };
    check lsn.attach(svc, "/incoming");

    mockListFaultCode = "AuthenticationFailed";
    error? failed = poll(lsn);
    mockListFaultCode = ();
    test:assertTrue(failed is Error, "a failing poll must surface its error");

    // Polling keeps its fixed cadence: the very next poll scans again, and a cleared fault
    // means it succeeds and dispatches immediately, with no cool-down to wait out.
    check shareClient->uploadContent("recovered", "/incoming/recover.dat");
    error? recovered = poll(lsn);
    test:assertTrue(recovered is (), "the poll after the fault clears must succeed");
    check await(() => recorder.count("dispatch") >= 1);
    check lsn.detach(svc);
}

@test:Config {}
function testPollFailureSurfacesEveryPoll() returns error? {
    // Every failing poll returns its error, so the poll service's log line and a declared
    // onError run on each scheduled attempt; there is no suppression between polls.
    [Client, string] setup = check setupMockWatchedShare("lsn-pollrepeat");
    string share = setup[1];

    final Recorder recorder = new;
    Listener lsn = check newMockListener(share);
    Service svc = service object {
        remote function onFile(byte[] content) returns error? {
        }

        remote function onError(Error err) returns error? {
            recorder.hit("onerror");
        }
    };
    check lsn.attach(svc, "/incoming");

    mockListFaultCode = "AuthenticationFailed";
    error? first = poll(lsn);
    error? second = poll(lsn);
    mockListFaultCode = ();

    test:assertTrue(first is AuthorizationError, "the first failing poll must surface its error");
    test:assertTrue(second is AuthorizationError,
            "every failing poll must surface its error, not only the first");
    check await(() => recorder.count("onerror") >= 2);
    test:assertTrue(recorder.count("onerror") >= 2,
            "each failing poll must notify a declared onError");
    check lsn.detach(svc);
}

// ===== onError =====

// Pinned to the mock: uses the listing-fault hook to fail the poll on demand.
@test:Config {}
function testOnErrorFiresOnPollFailure() returns error? {
    [Client, string] setup = check setupMockWatchedShare("lsn-onerr-poll");
    string share = setup[1];

    final Recorder recorder = new;
    Listener lsn = check newMockListener(share);
    Service svc = service object {
        remote function onFile(byte[] content) returns error? {
        }

        remote function onError(Error err) returns error? {
            if err is AuthorizationError {
                recorder.hit("onerror-auth");
            } else {
                recorder.hit("onerror-other");
            }
        }
    };
    check lsn.attach(svc, "/incoming");

    mockListFaultCode = "AuthenticationFailed";
    error? result = poll(lsn);
    mockListFaultCode = ();

    test:assertTrue(result is AuthorizationError, "the failing poll must still surface its error");
    check await(() => recorder.count("onerror-auth") >= 1);
    test:assertEquals(recorder.count("onerror-other"), 0,
            "onError must receive the mapped typed error for a poll failure");
    check lsn.detach(svc);
}

@test:Config {}
function testOnErrorFiresOnBindingFailure() returns error? {
    [Client, string] setup = check setupWatchedShare("lsn-onerr-bind");
    Client shareClient = setup[0];
    string share = setup[1];
    check shareClient->uploadContent("{not-json", "/incoming/broken.json");

    final Recorder recorder = new;
    Listener lsn = check newListener(share);
    Service svc = service object {
        remote function onFileJson(map<json> content) returns error? {
            recorder.hit("json");
        }

        remote function onError(Error err) returns error? {
            if err !is ServiceError {
                recorder.put("onerror", err.message());
            }
        }
    };
    check lsn.attach(svc, "/incoming");
    check lsn.'start();
    check await(() => recorder.count("onerror") >= 1);
    check lsn.gracefulStop();
    check lsn.detach(svc);

    test:assertEquals(recorder.count("json"), 0, "malformed content must not reach the typed handler");
    test:assertTrue(recorder.count("onerror") >= 1,
            "a content-binding failure must notify onError with a client-side error");
}

@test:Config {}
function testOnErrorReceivesCaller() returns error? {
    [Client, string] setup = check setupMockWatchedShare("lsn-onerr-caller");
    Client shareClient = setup[0];
    string share = setup[1];

    final Recorder recorder = new;
    Listener lsn = check newMockListener(share);
    Service svc = service object {
        remote function onFile(byte[] content) returns error? {
        }

        remote function onError(Error err, Caller caller) returns error? {
            check caller->uploadContent("probe", "/onerror-probe.txt");
            recorder.hit("onerror-caller");
        }
    };
    check lsn.attach(svc, "/incoming");

    mockListFaultCode = "AuthenticationFailed";
    error? result = poll(lsn);
    mockListFaultCode = ();
    test:assertTrue(result is Error);

    check await(() => recorder.count("onerror-caller") >= 1);
    boolean probeLanded = check shareClient->hasFile("/onerror-probe.txt");
    test:assertTrue(probeLanded,
            "the two-parameter onError must receive a usable Caller bound to the watched share");
    check lsn.detach(svc);
}

@test:Config {}
function testOnErrorNotFiredOnHandlerError() returns error? {
    [Client, string] setup = check setupWatchedShare("lsn-onerr-handler");
    Client shareClient = setup[0];
    string share = setup[1];
    check shareClient->uploadContent("handler fails", "/incoming/fail.dat");

    final Recorder recorder = new;
    Listener lsn = check newListener(share);
    Service svc = service object {
        remote function onFile(byte[] content, FileInfo info, Caller caller) returns error? {
            recorder.hit("attempt");
            if recorder.count("attempt") == 1 {
                return error("handler failure");
            }
            check caller->deleteFile(info.path);
        }

        remote function onError(Error err) returns error? {
            recorder.hit("onerror");
        }
    };
    check lsn.attach(svc, "/incoming");
    check lsn.'start();
    check await(() => recorder.count("attempt") >= 2);
    check lsn.gracefulStop();
    check lsn.detach(svc);

    test:assertEquals(recorder.count("onerror"), 0,
            "an error returned by a content handler must not notify onError");
}

@test:Config {}
function testBindingFailureAfterErrorInteraction() returns error? {
    [Client, string] setup = check setupWatchedShare("lsn-onerr-after");
    Client shareClient = setup[0];
    string share = setup[1];
    check shareClient->uploadContent("{still-not-json", "/incoming/broken.json");

    final Recorder recorder = new;
    Listener lsn = check newListener(share);
    Service svc = service object {
        @FunctionConfig {afterError: DELETE}
        remote function onFileJson(map<json> content) returns error? {
            recorder.hit("json");
        }

        remote function onError(Error err) returns error? {
            recorder.hit("onerror");
        }
    };
    check lsn.attach(svc, "/incoming");
    check lsn.'start();
    check await(() => recorder.count("onerror") >= 1);
    check await(function() returns boolean|error {
        boolean present = check shareClient->hasFile("/incoming/broken.json");
        return !present;
    });
    check lsn.gracefulStop();
    check lsn.detach(svc);

    test:assertTrue(recorder.count("onerror") >= 1,
            "a binding failure must notify a declared onError");
    boolean stillPresent = check shareClient->hasFile("/incoming/broken.json");
    test:assertFalse(stillPresent,
            "afterError must still consume the file when onError is declared");
}

@test:Config {}
function testOnErrorErrorReturnIsSwallowed() returns error? {
    [Client, string] setup = check setupWatchedShare("lsn-onerr-swallow");
    Client shareClient = setup[0];
    string share = setup[1];
    check shareClient->uploadContent("{bad", "/incoming/bad.json");

    final Recorder recorder = new;
    Listener lsn = check newListener(share);
    Service svc = service object {
        @FunctionConfig {afterError: DELETE}
        remote function onFileJson(map<json> content) returns error? {
            recorder.hit("json");
        }

        remote function onFile(byte[] content, FileInfo info, Caller caller) returns error? {
            recorder.hit("onfile");
            check caller->deleteFile(info.path);
        }

        remote function onError(Error err) returns error? {
            recorder.hit("onerror");
            return error("onError itself failed");
        }
    };
    check lsn.attach(svc, "/incoming");
    check lsn.'start();
    check await(() => recorder.count("onerror") >= 1);
    // A failing onError must not disturb the listener: a later file still dispatches.
    check shareClient->uploadContent("plain payload", "/incoming/next.dat");
    check await(() => recorder.count("onfile") >= 1);
    check lsn.gracefulStop();
    check lsn.detach(svc);
}

// ===== laxDataBinding and record binding =====

// A JSON/CSV binding target with a required nilable field, for the projection tests.
type BindingRow record {|
    int id;
    string? name;
|};

// An XML binding target.
type XmlDoc record {|
    int v;
|};

// A closed XML binding target, for the projection tests: an extra element in the document
// binds only when relaxed projection is on.
type XmlOpen record {|
    int v;
|};

// A CSV binding target whose fields map to a header row.
type CsvPerson record {|
    string name;
    int age;
|};

// A CSV binding target with a required nilable field, for the projection tests.
type CsvSparse record {|
    string name;
    int? age;
|};

@test:Config {}
function testJsonRecordStrictBindingRejectsAbsentField() returns error? {
    [Client, string] setup = check setupWatchedShare("lsn-strict-json");
    Client shareClient = setup[0];
    string share = setup[1];
    check shareClient->uploadContent(string `{"id": 1}`, "/incoming/row.json");

    final Recorder recorder = new;
    Listener lsn = check new (share, auth = testAuth(), pollingInterval = 1);
    Service svc = service object {
        @FunctionConfig {afterError: DELETE}
        remote function onFileJson(BindingRow content) returns error? {
            recorder.hit("json");
        }

        remote function onError(Error err) returns error? {
            recorder.hit("onerror");
        }
    };
    check lsn.attach(svc, "/incoming");
    check lsn.'start();
    check await(() => recorder.count("onerror") >= 1);
    check lsn.gracefulStop();
    check lsn.detach(svc);

    test:assertEquals(recorder.count("json"), 0,
            "with the default strict binding, JSON missing a required field must not bind");
}

@test:Config {}
function testJsonRecordLaxBindingProjects() returns error? {
    [Client, string] setup = check setupWatchedShare("lsn-lax-json");
    Client shareClient = setup[0];
    string share = setup[1];
    check shareClient->uploadContent(string `{"id": 2}`, "/incoming/row.json");

    final Recorder recorder = new;
    Listener lsn = check new (share, auth = testAuth(), pollingInterval = 1, laxDataBinding = true);
    Service svc = service object {
        @FunctionConfig {afterProcess: DELETE}
        remote function onFileJson(BindingRow content) returns error? {
            recorder.put("json", string `${content.id}:${content.name ?: "<nil>"}`);
        }
    };
    check lsn.attach(svc, "/incoming");
    check lsn.'start();
    check await(() => recorder.count("json") >= 1);
    check lsn.gracefulStop();
    check lsn.detach(svc);

    test:assertEquals(recorder.payload("json"), "2:<nil>",
            "lax binding must project an absent JSON member onto the nilable field");
}

@test:Config {}
function testXmlRecordBinding() returns error? {
    [Client, string] setup = check setupWatchedShare("lsn-xml-rec");
    Client shareClient = setup[0];
    string share = setup[1];
    check shareClient->uploadContent("<XmlDoc><v>7</v></XmlDoc>", "/incoming/doc.xml");

    final Recorder recorder = new;
    Listener lsn = check new (share, auth = testAuth(), pollingInterval = 1);
    Service svc = service object {
        @FunctionConfig {afterProcess: DELETE}
        remote function onFileXml(XmlDoc content) returns error? {
            recorder.put("xml", content.v.toString());
        }
    };
    check lsn.attach(svc, "/incoming");
    check lsn.'start();
    check await(() => recorder.count("xml") >= 1);
    check lsn.gracefulStop();
    check lsn.detach(svc);

    test:assertEquals(recorder.payload("xml"), "7",
            "well formed XML must bind to the declared record");
}

@test:Config {}
function testXmlRecordLaxBinding() returns error? {
    [Client, string] setup = check setupWatchedShare("lsn-xml-lax");
    Client shareClient = setup[0];
    string share = setup[1];
    check shareClient->uploadContent("<XmlOpen><v>9</v><extra>x</extra></XmlOpen>", "/incoming/doc.xml");

    final Recorder recorder = new;
    Listener lsn = check new (share, auth = testAuth(), pollingInterval = 1, laxDataBinding = true);
    Service svc = service object {
        @FunctionConfig {afterProcess: DELETE}
        remote function onFileXml(XmlOpen content) returns error? {
            recorder.put("xml", content.v.toString());
        }
    };
    check lsn.attach(svc, "/incoming");
    check lsn.'start();
    check await(() => recorder.count("xml") >= 1);
    check lsn.gracefulStop();
    check lsn.detach(svc);

    test:assertEquals(recorder.payload("xml"), "9",
            "lax binding must project away an XML element the record does not declare");
}

@test:Config {}
function testCsvRecordArrayBindingUsesHeaderRow() returns error? {
    [Client, string] setup = check setupWatchedShare("lsn-csv-rec");
    Client shareClient = setup[0];
    string share = setup[1];
    check shareClient->uploadContent("name,age\nalice,30\nbob,25", "/incoming/people.csv");

    final Recorder recorder = new;
    Listener lsn = check new (share, auth = testAuth(), pollingInterval = 1);
    Service svc = service object {
        @FunctionConfig {afterProcess: DELETE}
        remote function onFileCsv(CsvPerson[] rows) returns error? {
            string[] parts = [];
            foreach CsvPerson row in rows {
                parts.push(string `${row.name}=${row.age}`);
            }
            recorder.put("csv", string:'join(";", ...parts));
        }
    };
    check lsn.attach(svc, "/incoming");
    check lsn.'start();
    check await(() => recorder.count("csv") >= 1);
    check lsn.gracefulStop();
    check lsn.detach(svc);

    test:assertEquals(recorder.payload("csv"), "alice=30;bob=25",
            "CSV record binding must use the first row as the header");
}

@test:Config {}
function testCsvLaxBindingRecordArray() returns error? {
    [Client, string] setup = check setupWatchedShare("lsn-csv-lax");
    Client shareClient = setup[0];
    string share = setup[1];
    check shareClient->uploadContent("name\ncara", "/incoming/people.csv");

    final Recorder recorder = new;
    Listener lsn = check new (share, auth = testAuth(), pollingInterval = 1, laxDataBinding = true);
    Service svc = service object {
        @FunctionConfig {afterProcess: DELETE}
        remote function onFileCsv(CsvSparse[] rows) returns error? {
            string[] parts = [];
            foreach CsvSparse row in rows {
                parts.push(string `${row.name}=${row.age ?: -1}`);
            }
            recorder.put("csv", string:'join(";", ...parts));
        }
    };
    check lsn.attach(svc, "/incoming");
    check lsn.'start();
    check await(() => recorder.count("csv") >= 1);
    check lsn.gracefulStop();
    check lsn.detach(svc);

    test:assertEquals(recorder.payload("csv"), "cara=-1",
            "lax binding must project an absent CSV column onto the nilable field");
}

// ===== CSV binding strictness =====

@test:Config {}
function testCsvMalformedRowFailsBinding() returns error? {
    [Client, string] setup = check setupWatchedShare("lsn-failsafe-off");
    Client shareClient = setup[0];
    string share = setup[1];
    check shareClient->uploadContent("name,age\ndana,notanint", "/incoming/strict.csv");

    final Recorder recorder = new;
    Listener lsn = check new (share, auth = testAuth(), pollingInterval = 1);
    Service svc = service object {
        @FunctionConfig {afterError: DELETE}
        remote function onFileCsv(CsvPerson[] rows) returns error? {
            recorder.hit("csv");
        }

        remote function onError(Error err) returns error? {
            recorder.hit("onerror");
        }
    };
    check lsn.attach(svc, "/incoming");
    check lsn.'start();
    check await(() => recorder.count("onerror") >= 1);
    check lsn.gracefulStop();
    check lsn.detach(svc);

    test:assertEquals(recorder.count("csv"), 0,
            "a malformed CSV row must fail the whole binding");
}

// ===== Streaming content handlers =====

// Drains a byte stream fully, concatenating every chunk.
function drainByteStream(stream<byte[], error?> content) returns byte[]|error {
    byte[] all = [];
    record {|byte[] value;|}|error? entry = content.next();
    while entry is record {|byte[] value;|} {
        foreach byte b in entry.value {
            all.push(b);
        }
        entry = content.next();
    }
    if entry is error {
        return entry;
    }
    return all;
}

@test:Config {}
function testOnFileByteStreamDeliversContent() returns error? {
    [Client, string] setup = check setupWatchedShare("lsn-bytestream");
    Client shareClient = setup[0];
    string share = setup[1];
    check shareClient->uploadContent("stream-payload", "/incoming/data.bin");

    final Recorder recorder = new;
    Listener lsn = check newListener(share);
    Service svc = isolated service object {
        remote function onFile(stream<byte[], error?> content, FileInfo info, Caller caller) returns error? {
            byte[] all = check drainByteStream(content);
            recorder.put("stream", check string:fromBytes(all));
            check caller->deleteFile(info.path);
        }
    };
    check lsn.attach(svc, "/incoming");
    check lsn.'start();
    check await(() => recorder.count("stream") >= 1);
    check lsn.gracefulStop();
    check lsn.detach(svc);

    test:assertEquals(recorder.payload("stream"), "stream-payload",
            "a drained byte stream must deliver the file's full content");
}

@test:Config {}
function testOnFileByteStreamLargeFileChunks() returns error? {
    [Client, string] setup = check setupWatchedShare("lsn-bigstream");
    Client shareClient = setup[0];
    string share = setup[1];
    byte[] big = [];
    foreach int i in 0 ..< 20000 {
        big.push(<byte>(i % 256));
    }
    check shareClient->uploadContent(big, "/incoming/big.bin");

    final Recorder recorder = new;
    Listener lsn = check newListener(share);
    Service svc = isolated service object {
        remote function onFile(stream<byte[], error?> content, FileInfo info, Caller caller) returns error? {
            int chunks = 0;
            int total = 0;
            record {|byte[] value;|}|error? entry = content.next();
            while entry is record {|byte[] value;|} {
                chunks += 1;
                total += entry.value.length();
                entry = content.next();
            }
            if entry is error {
                return entry;
            }
            recorder.put("chunks", string `${chunks}:${total}`);
            check caller->deleteFile(info.path);
        }
    };
    check lsn.attach(svc, "/incoming");
    check lsn.'start();
    check await(() => recorder.count("chunks") >= 1);
    check lsn.gracefulStop();
    check lsn.detach(svc);

    string[] parts = re `:`.split(recorder.payload("chunks"));
    int chunkCount = check int:fromString(parts[0]);
    int totalBytes = check int:fromString(parts[1]);
    test:assertEquals(totalBytes, 20000, "the chunks must add up to the file size");
    test:assertTrue(chunkCount >= 2,
            "a payload larger than one chunk must arrive as multiple stream entries");
}

@test:Config {}
function testStreamHandlerAfterProcessOnReturn() returns error? {
    [Client, string] setup = check setupWatchedShare("lsn-stream-after");
    Client shareClient = setup[0];
    string share = setup[1];
    check shareClient->uploadContent("consume me", "/incoming/done.bin");

    final Recorder recorder = new;
    Listener lsn = check newListener(share);
    Service svc = isolated service object {
        @FunctionConfig {afterProcess: DELETE}
        remote function onFile(stream<byte[], error?> content) returns error? {
            byte[] all = check drainByteStream(content);
            recorder.put("stream", check string:fromBytes(all));
        }
    };
    check lsn.attach(svc, "/incoming");
    check lsn.'start();
    check await(() => recorder.count("stream") >= 1);
    check await(function() returns boolean|error {
        boolean present = check shareClient->hasFile("/incoming/done.bin");
        return !present;
    });
    check lsn.gracefulStop();
    check lsn.detach(svc);

    boolean stillPresent = check shareClient->hasFile("/incoming/done.bin");
    test:assertFalse(stillPresent, "afterProcess must consume the file when the handler returns");
}

@test:Config {}
function testStreamPartialDrainThenClose() returns error? {
    [Client, string] setup = check setupWatchedShare("lsn-stream-close");
    Client shareClient = setup[0];
    string share = setup[1];
    check shareClient->uploadContent("partial read", "/incoming/partial.bin");

    final Recorder recorder = new;
    Listener lsn = check newListener(share);
    Service svc = isolated service object {
        @FunctionConfig {afterProcess: DELETE}
        remote function onFile(stream<byte[], error?> content) returns error? {
            record {|byte[] value;|}|error? first = content.next();
            if first is record {|byte[] value;|} {
                recorder.hit("read");
            }
            check content.close();
            recorder.hit("closed");
            // A next() after close may end the stream or surface a read error, but must
            // never panic and must never deliver another chunk.
            record {|byte[] value;|}|error? afterClose = trap content.next();
            if afterClose is record {|byte[] value;|} {
                recorder.hit("value-after-close");
            } else if afterClose is error && afterClose.message().includes("NullPointerException") {
                recorder.hit("npe-after-close");
            }
        }
    };
    check lsn.attach(svc, "/incoming");
    check lsn.'start();
    check await(() => recorder.count("closed") >= 1);
    check await(function() returns boolean|error {
        boolean present = check shareClient->hasFile("/incoming/partial.bin");
        return !present;
    });
    check lsn.gracefulStop();
    check lsn.detach(svc);

    test:assertTrue(recorder.count("read") >= 1, "the first chunk must be readable");
    test:assertEquals(recorder.count("npe-after-close"), 0,
            "a next() after close must not raise a NullPointerException panic");
    test:assertEquals(recorder.count("value-after-close"), 0,
            "a next() after close must not deliver another chunk");
    boolean stillPresent = check shareClient->hasFile("/incoming/partial.bin");
    test:assertFalse(stillPresent,
            "afterProcess must still run when the handler closes the stream early and returns");
}

@test:Config {}
function testCsvStreamStringArrays() returns error? {
    [Client, string] setup = check setupWatchedShare("lsn-csvstream-str");
    Client shareClient = setup[0];
    string share = setup[1];
    check shareClient->uploadContent("a,b\nc,d", "/incoming/rows.csv");

    final Recorder recorder = new;
    Listener lsn = check newListener(share);
    Service svc = isolated service object {
        @FunctionConfig {afterProcess: DELETE}
        remote function onFileCsv(stream<string[], error?> rows) returns error? {
            string[] collected = [];
            record {|string[] value;|}|error? entry = rows.next();
            while entry is record {|string[] value;|} {
                collected.push(string:'join(",", ...entry.value));
                entry = rows.next();
            }
            if entry is error {
                return entry;
            }
            recorder.put("csv", string:'join(";", ...collected));
        }
    };
    check lsn.attach(svc, "/incoming");
    check lsn.'start();
    check await(() => recorder.count("csv") >= 1);
    check lsn.gracefulStop();
    check lsn.detach(svc);

    test:assertEquals(recorder.payload("csv"), "a,b;c,d",
            "the string array stream must yield every row of the file");
}

@test:Config {}
function testCsvStreamRecords() returns error? {
    [Client, string] setup = check setupWatchedShare("lsn-csvstream-rec");
    Client shareClient = setup[0];
    string share = setup[1];
    check shareClient->uploadContent("name,age\nalice,30\nbob,25", "/incoming/people.csv");

    final Recorder recorder = new;
    Listener lsn = check newListener(share);
    Service svc = isolated service object {
        @FunctionConfig {afterProcess: DELETE}
        remote function onFileCsv(stream<CsvPerson, error?> rows) returns error? {
            string[] collected = [];
            record {|CsvPerson value;|}|error? entry = rows.next();
            while entry is record {|CsvPerson value;|} {
                collected.push(string `${entry.value.name}=${entry.value.age}`);
                entry = rows.next();
            }
            if entry is error {
                return entry;
            }
            recorder.put("csv", string:'join(";", ...collected));
        }
    };
    check lsn.attach(svc, "/incoming");
    check lsn.'start();
    check await(() => recorder.count("csv") >= 1);
    check lsn.gracefulStop();
    check lsn.detach(svc);

    test:assertEquals(recorder.payload("csv"), "alice=30;bob=25",
            "the record stream must map each row through the header row");
}

@test:Config {}
function testCsvStreamLaxBinding() returns error? {
    [Client, string] setup = check setupWatchedShare("lsn-csvstream-lax");
    Client shareClient = setup[0];
    string share = setup[1];
    check shareClient->uploadContent("name\ncara", "/incoming/sparse.csv");

    final Recorder recorder = new;
    Listener lsn = check new (share, auth = testAuth(), pollingInterval = 1, laxDataBinding = true);
    Service svc = isolated service object {
        @FunctionConfig {afterProcess: DELETE}
        remote function onFileCsv(stream<CsvSparse, error?> rows) returns error? {
            string[] collected = [];
            record {|CsvSparse value;|}|error? entry = rows.next();
            while entry is record {|CsvSparse value;|} {
                collected.push(string `${entry.value.name}=${entry.value.age ?: -1}`);
                entry = rows.next();
            }
            if entry is error {
                return entry;
            }
            recorder.put("csv", string:'join(";", ...collected));
        }
    };
    check lsn.attach(svc, "/incoming");
    check lsn.'start();
    check await(() => recorder.count("csv") >= 1);
    check lsn.gracefulStop();
    check lsn.detach(svc);

    test:assertEquals(recorder.payload("csv"), "cara=-1",
            "lax binding must apply to the CSV record stream");
}

@test:Config {}
function testCsvStreamBindingErrorMidStream() returns error? {
    [Client, string] setup = check setupWatchedShare("lsn-csvstream-err");
    Client shareClient = setup[0];
    string share = setup[1];
    check shareClient->uploadContent("name,age\nalice,30\nbob,notanint\ncara,22",
            "/incoming/people.csv");

    final Recorder recorder = new;
    Listener lsn = check newListener(share);
    Service svc = isolated service object {
        @FunctionConfig {afterProcess: DELETE}
        remote function onFileCsv(stream<CsvPerson, error?> rows) returns error? {
            int good = 0;
            record {|CsvPerson value;|}|error? entry = rows.next();
            while entry is record {|CsvPerson value;|} {
                good += 1;
                entry = rows.next();
            }
            if entry is error {
                recorder.put("midstream",
                        string `${good}:${entry is Error && entry !is ServiceError ? "typed" : "untyped"}`);
            }
        }

        remote function onError(Error err) returns error? {
            recorder.hit("onerror");
        }
    };
    check lsn.attach(svc, "/incoming");
    check lsn.'start();
    check await(() => recorder.count("midstream") >= 1);
    check lsn.gracefulStop();
    check lsn.detach(svc);

    test:assertEquals(recorder.payload("midstream"), "1:typed",
            "a malformed row must surface as a typed error from next() after the valid rows");
    test:assertEquals(recorder.count("onerror"), 0,
            "a lazy stream binding failure belongs to the handler, not onError");
}

// A byte source that records whether its close() ran, for asserting stream cleanup.
class RecordingByteSource {
    private boolean closed = false;

    public isolated function next() returns record {|byte[] value;|}|error? {
        return ();
    }

    public isolated function close() returns error? {
        lock {
            self.closed = true;
        }
        return ();
    }

    public isolated function isClosed() returns boolean {
        lock {
            return self.closed;
        }
    }
}

@test:Config {}
function testCsvStreamCreationFailure() returns error? {
    RecordingByteSource src = new;
    stream<byte[], error?> bytes = new (src);
    ContentCsvStream|error created = new (CsvPerson, bytes, {encoding: "no-such-charset"});
    test:assertTrue(created is Error && created !is ServiceError,
            "a CSV row stream that cannot be created must fail as a client-side error");
    if created is error {
        test:assertTrue(created.message().startsWith("CSV stream binding could not be created"),
                "the error must state the CSV stream binding could not be created");
    }
    test:assertTrue(src.isClosed(), "the byte stream must be closed when creation fails");
}

@test:Config {}
function testStreamHandlerErrorTriggersAfterError() returns error? {
    [Client, string] setup = check setupWatchedShare("lsn-stream-herr");
    Client shareClient = setup[0];
    string share = setup[1];
    check shareClient->uploadContent("some bytes", "/incoming/herr.bin");

    final Recorder recorder = new;
    Listener lsn = check newListener(share);
    Service svc = isolated service object {
        @FunctionConfig {afterError: DELETE}
        remote function onFile(stream<byte[], error?> content) returns error? {
            recorder.hit("attempt");
            check content.close();
            return error("stream handler failure");
        }

        remote function onError(Error err) returns error? {
            recorder.hit("onerror");
        }
    };
    check lsn.attach(svc, "/incoming");
    check lsn.'start();
    check await(() => recorder.count("attempt") >= 1);
    check await(function() returns boolean|error {
        boolean present = check shareClient->hasFile("/incoming/herr.bin");
        return !present;
    });
    check lsn.gracefulStop();
    check lsn.detach(svc);

    test:assertEquals(recorder.count("onerror"), 0,
            "an error returned by a stream handler must not notify onError");
    boolean stillPresent = check shareClient->hasFile("/incoming/herr.bin");
    test:assertFalse(stillPresent, "afterError must consume the file the stream handler failed on");
}

// Creates a directory when it does not exist yet, for tests needing a second watched path.
function ensureTestDirectory(Client shareClient, string path) returns error? {
    boolean exists = check shareClient->hasDirectory(path);
    if !exists {
        check shareClient->createDirectory(path);
    }
}

@test:Config {}
function testDetachThenReattachUsesNewServiceConfig() returns error? {
    [Client, string] setup = check setupWatchedShare("lsn-reattach");
    Client shareClient = setup[0];
    string share = setup[1];
    // The conditional lives in the helper: an if statement before the anonymous annotated
    // services would trip the compiler's annotation-dropping defect (see the file header note).
    check ensureTestDirectory(shareClient, "/second");
    check shareClient->uploadContent("first watch", "/incoming/first.dat");
    check shareClient->uploadContent("second watch", "/second/second.dat");

    final Recorder recorder = new;
    Listener lsn = check newListener(share);
    Service first = service object {
        remote function onFile(byte[] content) returns error? {
            recorder.hit("a");
        }
    };
    Service second = service object {
        remote function onFile(byte[] content, FileInfo info, Caller caller) returns error? {
            recorder.hit("b");
            check caller->deleteFile(info.path);
        }
    };
    check lsn.attach(first, "/incoming");
    check lsn.detach(first);
    // A detached listener accepts a new service, and dispatch follows the new service's
    // configuration only.
    check lsn.attach(second, "/second");
    check lsn.'start();
    check await(() => recorder.count("b") >= 1);
    check lsn.gracefulStop();
    check lsn.detach(second);

    test:assertEquals(recorder.count("a"), 0,
            "the detached service's configuration must not linger after a re-attach");
    boolean firstPresent = check shareClient->hasFile("/incoming/first.dat");
    test:assertTrue(firstPresent,
            "a file under the detached service's path must not be dispatched");
}

// ===== Watched path from the service attach point =====

@test:Config {}
function testAttachPointPathWatches() returns error? {
    [Client, string] setup = check setupWatchedShare("lsn-attachpath");
    Client shareClient = setup[0];
    string share = setup[1];
    check shareClient->uploadContent("by attach point", "/incoming/point.dat");

    final Recorder recorder = new;
    Listener lsn = check newListener(share);
    Service svc = service object {
        remote function onFile(byte[] content, FileInfo info, Caller caller) returns error? {
            recorder.put("file", check string:fromBytes(content));
            check caller->deleteFile(info.path);
        }
    };
    check lsn.attach(svc, "/incoming");
    check lsn.'start();
    check await(() => recorder.count("file") >= 1);
    check lsn.gracefulStop();
    check lsn.detach(svc);

    test:assertEquals(recorder.payload("file"), "by attach point",
            "a string attach point must be the watched path, with no annotation involved");
}

@test:Config {}
function testAttachPointResourcePathForm() returns error? {
    [Client, string] setup = check setupWatchedShare("lsn-attachres");
    Client shareClient = setup[0];
    string share = setup[1];
    check shareClient->uploadContent("by resource path", "/incoming/res.dat");

    final Recorder recorder = new;
    Listener lsn = check newListener(share);
    Service svc = service object {
        remote function onFile(byte[] content, FileInfo info, Caller caller) returns error? {
            recorder.hit("file");
            check caller->deleteFile(info.path);
        }
    };
    check lsn.attach(svc, ["incoming"]);
    check lsn.'start();
    check await(() => recorder.count("file") >= 1);
    check lsn.gracefulStop();
    check lsn.detach(svc);

    test:assertTrue(recorder.count("file") >= 1,
            "a resource path attach point must join its segments into the watched path");
}

@test:Config {}
function testAttachPointNormalization() returns error? {
    [Client, string] setup = check setupWatchedShare("lsn-attachnorm");
    Client shareClient = setup[0];
    string share = setup[1];
    check shareClient->uploadContent("normalized", "/incoming/norm.dat");

    final Recorder recorder = new;
    Listener lsn = check newListener(share);
    Service svc = service object {
        remote function onFile(byte[] content, FileInfo info, Caller caller) returns error? {
            recorder.hit("file");
            check caller->deleteFile(info.path);
        }
    };
    // No leading slash, a trailing slash: both normalize away.
    check lsn.attach(svc, "incoming/");
    check lsn.'start();
    check await(() => recorder.count("file") >= 1);
    check lsn.gracefulStop();
    check lsn.detach(svc);

    test:assertTrue(recorder.count("file") >= 1,
            "the attach point must normalize the leading and trailing slashes");
}

@test:Config {}
function testAbsentPathDefaultsToShareRoot() returns error? {
    string share = testShare("lsn-rootdefault");
    AdminClient admin = check newAdmin();
    boolean shareExists = check admin->hasShare(share);
    if !shareExists {
        check admin->createShare(share);
    }
    Client shareClient = check newShareClient(share);
    check shareClient->uploadContent("at the root", "/root.dat");

    final Recorder recorder = new;
    Listener lsn = check newListener(share);
    Service svc = service object {
        remote function onFile(byte[] content, FileInfo info, Caller caller) returns error? {
            recorder.put("file", check string:fromBytes(content));
            check caller->deleteFile(info.path);
        }
    };
    check lsn.attach(svc);
    check lsn.'start();
    check await(() => recorder.count("file") >= 1);
    check lsn.gracefulStop();
    check lsn.detach(svc);

    test:assertEquals(recorder.payload("file"), "at the root",
            "a service without an attach point must watch the share root");
}

@test:Config {}
function testEmptyAttachPointDefaultsToShareRoot() returns error? {
    string share = testShare("lsn-emptyroot");
    AdminClient admin = check newAdmin();
    boolean shareExists = check admin->hasShare(share);
    if !shareExists {
        check admin->createShare(share);
    }
    Client shareClient = check newShareClient(share);
    check shareClient->uploadContent("empty means root", "/empty.dat");

    final Recorder recorder = new;
    Listener lsn = check newListener(share);
    Service svc = service object {
        remote function onFile(byte[] content, FileInfo info, Caller caller) returns error? {
            recorder.hit("file");
            check caller->deleteFile(info.path);
        }
    };
    check lsn.attach(svc, "");
    check lsn.'start();
    check await(() => recorder.count("file") >= 1);
    check lsn.gracefulStop();
    check lsn.detach(svc);

    test:assertTrue(recorder.count("file") >= 1,
            "an empty attach point must watch the share root");
}

// Pinned to the mock: uses the listing-fault hook. A root-defaulted watch under a credential
// that cannot list surfaces the typed error on the first poll; nothing fails silently.
@test:Config {}
function testRootDefaultSurfacesAuthorizationError() returns error? {
    [Client, string] setup = check setupMockWatchedShare("lsn-rootauth");
    string share = setup[1];

    Listener lsn = check newMockListener(share);
    Service svc = service object {
        remote function onFile(byte[] content) returns error? {
        }
    };
    check lsn.attach(svc);

    mockListFaultCode = "AuthenticationFailed";
    error? result = poll(lsn);
    mockListFaultCode = ();

    test:assertTrue(result is AuthorizationError,
            "an unauthorized listing under the root default must surface as an AuthorizationError");
    check lsn.detach(svc);
}

@test:Config {}
function testAnnotationFiltersApplyWithAttachPoint() returns error? {
    [Client, string] setup = check setupWatchedShare("lsn-attachfilter");
    Client shareClient = setup[0];
    string share = setup[1];
    check shareClient->uploadContent("should match", "/incoming/match.one");
    check shareClient->uploadContent("should not", "/incoming/skip.two");

    final Recorder recorder = new;
    Listener lsn = check newListener(share);
    Service svc = @ServiceConfig {fileNamePattern: "^match\\..*"} service object {
        remote function onFile(byte[] content, FileInfo info, Caller caller) returns error? {
            recorder.put("file", info.name);
            check caller->deleteFile(info.path);
        }
    };
    check lsn.attach(svc, "/incoming");
    check lsn.'start();
    check await(() => recorder.count("file") >= 1);
    check lsn.gracefulStop();
    check lsn.detach(svc);

    test:assertEquals(recorder.payload("file"), "match.one",
            "annotation filters must apply to the attach point's watched path");
    boolean skipped = check shareClient->hasFile("/incoming/skip.two");
    test:assertTrue(skipped, "a non-matching file must not be dispatched");
}

// ---------------------------------------------------------------------------
// Dispatch concurrency
// ---------------------------------------------------------------------------

// Tracks how many handlers run at once and the maximum observed, for the concurrency tests.
isolated class Gauge {
    private int current = 0;
    private int maxSeen = 0;

    isolated function enter() {
        lock {
            self.current += 1;
            if self.current > self.maxSeen {
                self.maxSeen = self.current;
            }
        }
    }

    isolated function exit() {
        lock {
            self.current -= 1;
        }
    }

    isolated function max() returns int {
        lock {
            return self.maxSeen;
        }
    }
}

@test:Config {}
function testDispatchRunsHandlersConcurrently() returns error? {
    [Client, string] setup = check setupWatchedShare("lsn-concurrent");
    Client shareClient = setup[0];
    string share = setup[1];
    check shareClient->uploadContent("one", "/incoming/c1.dat");
    check shareClient->uploadContent("two", "/incoming/c2.dat");

    final Recorder recorder = new;
    final Gauge gauge = new;
    Listener lsn = check newListener(share);
    Service svc = isolated service object {
        isolated remote function onFile(byte[] content, FileInfo info) returns error? {
            gauge.enter();
            runtime:sleep(1.5);
            gauge.exit();
            recorder.hit(info.name);
        }
    };
    check lsn.attach(svc, "/incoming");
    check lsn.'start();
    check await(() => recorder.count("c1.dat") >= 1 && recorder.count("c2.dat") >= 1);
    check lsn.immediateStop();
    test:assertTrue(gauge.max() >= 2,
            "two files present in one poll must be dispatched to concurrently running handlers");
}

@test:Config {}
function testOverwriteDuringHandlingSerializesPerPath() returns error? {
    [Client, string] setup = check setupWatchedShare("lsn-pathguard");
    Client shareClient = setup[0];
    string share = setup[1];
    check shareClient->uploadContent("version one", "/incoming/hot.dat");

    final Recorder recorder = new;
    final Gauge gauge = new;
    Listener lsn = check newListener(share);
    Service svc = isolated service object {
        isolated remote function onFile(byte[] content, FileInfo info) returns error? {
            gauge.enter();
            recorder.hit("dispatch");
            if recorder.count("dispatch") == 1 {
                recorder.put("firstETag", info.eTag);
                recorder.put("lastETag", info.eTag);
                runtime:sleep(3);
            } else {
                recorder.put("lastETag", info.eTag);
            }
            gauge.exit();
        }
    };
    check lsn.attach(svc, "/incoming");
    check lsn.'start();
    check await(() => recorder.count("dispatch") >= 1, intervalSeconds = 0.2);
    // Overwrite while the first dispatch is still handling the old version: the new version
    // must wait for that handling to finish, then arrive on a later poll.
    check shareClient->uploadContent("version two", "/incoming/hot.dat");
    check await(() => recorder.payload("lastETag") != ""
            && recorder.payload("lastETag") != recorder.payload("firstETag"));
    check lsn.immediateStop();

    test:assertEquals(gauge.max(), 1,
            "one file must never be dispatched to two handlers at once, even across versions");
}

@test:Config {}
function testOverwriteDuringHandlingNotConsumedUnseen() returns error? {
    [Client, string] setup = check setupWatchedShare("lsn-consumeguard");
    Client shareClient = setup[0];
    string share = setup[1];
    check shareClient->uploadContent("version one", "/incoming/hot.dat");

    final Recorder recorder = new;
    Listener lsn = check newListener(share);
    Service svc = isolated service object {
        @FunctionConfig {afterProcess: DELETE}
        isolated remote function onFile(byte[] content, FileInfo info) returns error? {
            recorder.hit("dispatch");
            recorder.put("last", check string:fromBytes(content));
            if recorder.count("dispatch") == 1 {
                // Hold the first handling open while the file is overwritten underneath it.
                runtime:sleep(3);
            }
        }
    };
    check lsn.attach(svc, "/incoming");
    check lsn.'start();
    check await(() => recorder.count("dispatch") >= 1, intervalSeconds = 0.2);
    // Overwrite while the first dispatch is still handling: the finishing dispatch's
    // afterProcess must not consume the version it never saw.
    check shareClient->uploadContent("version two", "/incoming/hot.dat");
    check await(() => recorder.count("dispatch") >= 2);
    test:assertEquals(recorder.payload("last"), "version two",
            "the overwritten content must be dispatched before any consume");
    // With no further overwrites, the second dispatch's afterProcess consumes the file.
    check await(function() returns boolean|error {
        boolean present = check shareClient->hasFile("/incoming/hot.dat");
        return !present;
    });
    check lsn.gracefulStop();
    check lsn.detach(svc);
}

@test:Config {}
function testImmediateStopDuringScanIsPrompt() returns error? {
    [Client, string] setup = check setupWatchedShare("lsn-stopscan");
    Client shareClient = setup[0];
    string share = setup[1];
    foreach int i in 0 ..< 24 {
        check shareClient->uploadContent(string `payload-${i}`, string `/incoming/s${i}.dat`);
    }

    final Recorder recorder = new;
    Listener lsn = check newListener(share);
    Service svc = isolated service object {
        isolated remote function onFile(byte[] content, FileInfo info) returns error? {
            recorder.hit("dispatched");
            runtime:sleep(5);
        }
    };
    check lsn.attach(svc, "/incoming");
    check lsn.'start();
    check await(() => recorder.count("dispatched") >= 1, intervalSeconds = 0.2);
    time:Utc before = time:utcNow();
    check lsn.immediateStop();
    decimal elapsed = time:utcDiffSeconds(time:utcNow(), before);
    test:assertTrue(elapsed < 4.0d,
            "immediateStop must not wait out in-flight handlers or a full scan");
    // Dispatches already in flight at the stop run to completion; once they drain, no new
    // dispatches may occur because no further poll runs.
    runtime:sleep(7);
    int afterDrain = recorder.count("dispatched");
    runtime:sleep(3);
    test:assertEquals(recorder.count("dispatched"), afterDrain,
            "no new dispatches may occur after immediateStop once in-flight handlers drain");
}

@test:Config {}
function testCallerTypedRead() returns error? {
    [Client, string] setup = check setupWatchedShare("lsn-typedread");
    Client shareClient = setup[0];
    string share = setup[1];
    check shareClient->uploadContent({"kind": "probe", "value": 7}, "/incoming/data.json");

    final Recorder recorder = new;
    Listener lsn = check newListener(share);
    Service svc = service object {
        remote function onFile(byte[] content, FileInfo info, Caller caller) returns error? {
            json bound = check caller->getFileJson(info.path);
            recorder.put("typed", bound.toJsonString());
        }
    };
    check lsn.attach(svc, "/incoming");
    check lsn.'start();
    check await(() => recorder.count("typed") >= 1);
    check lsn.immediateStop();
    json bound = check recorder.payload("typed").fromJsonString();
    test:assertEquals(bound, {kind: "probe", value: 7});
}
