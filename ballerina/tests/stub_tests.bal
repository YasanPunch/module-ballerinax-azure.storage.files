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

// Contract tests for the parts of the surface that are declared but not yet implemented:
// every stub must fail with the NotImplemented error code, and the implemented local
// methods around them (construction, lifecycle, getShareName) must behave.

import ballerina/test;

isolated function expectNotImplemented(Error? result, string operation) {
    if result is Error {
        test:assertEquals(result.detail().errorCode, "NotImplemented",
                operation + " should fail as NotImplemented");
    } else {
        test:assertFail(operation + " is a stub and should fail as NotImplemented");
    }
}

@test:Config {groups: ["mock"]}
function testCallerFileStubs() {
    Caller caller = new ("stub-share");
    test:assertEquals(caller.getShareName(), "stub-share");

    Error? downloadResult = caller->downloadFile("/a.txt", "target/stub-download.txt");
    expectNotImplemented(downloadResult, "downloadFile");
    Error? uploadResult = caller->uploadFile("target/stub-upload.txt", "/a.txt");
    expectNotImplemented(uploadResult, "uploadFile");
    Error? uploadContentResult = caller->uploadContent("payload", "/a.txt");
    expectNotImplemented(uploadContentResult, "uploadContent");
    Error? deleteResult = caller->deleteFile("/a.txt");
    expectNotImplemented(deleteResult, "deleteFile");
    Error? abortResult = caller->abortCopy("/a.txt", "copy-id");
    expectNotImplemented(abortResult, "abortCopy");
    Error? renameResult = caller->renameFile("/a.txt", "/b.txt");
    expectNotImplemented(renameResult, "renameFile");

    stream<byte[], Error?>|Error content = caller->getFileContent("/a.txt");
    if content is Error {
        test:assertEquals(content.detail().errorCode, "NotImplemented");
    } else {
        test:assertFail("getFileContent is a stub and should fail as NotImplemented");
    }

    CopyInfo|Error copy = caller->copyFile("/a.txt", "/b.txt");
    if copy is Error {
        test:assertEquals(copy.detail().errorCode, "NotImplemented");
    } else {
        test:assertFail("copyFile is a stub and should fail as NotImplemented");
    }
}

@test:Config {groups: ["mock"]}
function testCallerDirectoryStubs() {
    Caller caller = new ("stub-share");

    Error? createResult = caller->createDirectory("/incoming");
    expectNotImplemented(createResult, "createDirectory");
    Error? deleteResult = caller->deleteDirectory("/incoming");
    expectNotImplemented(deleteResult, "deleteDirectory");

    stream<Entry, Error?>|Error entries = caller->list("/incoming");
    if entries is Error {
        test:assertEquals(entries.detail().errorCode, "NotImplemented");
    } else {
        test:assertFail("list is a stub and should fail as NotImplemented");
    }
}

@test:Config {groups: ["mock"]}
function testListenerLifecycleStubs() returns error? {
    Listener shareListener = check new ("stub-share",
            auth = {accountName: "acct", accountKey: MOCK_KEY});
    Service handler = service object {
        remote function onFile(FileInfo file, Caller caller) returns error? {
            return;
        }
    };
    check shareListener.attach(handler, "/incoming");
    check shareListener.'start();
    check shareListener.gracefulStop();
    check shareListener.immediateStop();
    check shareListener.detach(handler);
}
