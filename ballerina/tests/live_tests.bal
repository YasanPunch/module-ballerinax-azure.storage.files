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

// The "live" test group: smoke tests against a real Azure storage account. The group is
// gated on configuration and skips entirely when no credentials are supplied. Provide them
// via Config.toml or environment-backed configurable values:
//
//   liveAccountName = "<storage account>"
//   liveAccountKey  = "<account key>"

import ballerina/test;

configurable string liveAccountName = "";
configurable string liveAccountKey = "";
configurable string liveShareName = "bal-azfiles-live-tests";

final boolean liveEnabled = liveAccountName != "" && liveAccountKey != "";

isolated function newLiveAdmin() returns AdminClient|Error =>
    new (auth = {accountName: liveAccountName, accountKey: liveAccountKey});

isolated function newLiveClient() returns Client|Error =>
    new (liveShareName, auth = {accountName: liveAccountName, accountKey: liveAccountKey});

@test:Config {groups: ["live"], enable: liveEnabled}
function testLiveShareLifecycle() returns error? {
    AdminClient admin = check newLiveAdmin();
    check admin->createShare(liveShareName);
    var exists = check admin->hasShare(liveShareName);
    test:assertTrue(exists);
}

@test:Config {groups: ["live"], enable: liveEnabled, dependsOn: [testLiveShareLifecycle]}
function testLiveContentRoundtrip() returns error? {
    Client fileClient = check newLiveClient();
    check fileClient->createDirectory("/live-tests");
    check fileClient->uploadContent("live payload", "/live-tests/roundtrip.txt");

    FileProperties props = check fileClient->getFileProperties("/live-tests/roundtrip.txt");
    test:assertEquals(props.contentLength, 12);

    byte[] content = check readAll(fileClient, "/live-tests/roundtrip.txt");
    test:assertEquals(content, "live payload".toBytes());

    stream<Entry, Error?> listed = check fileClient->list("/live-tests");
    Entry[] entries = check collectEntries(listed);
    test:assertEquals(entries.length(), 1);
    test:assertEquals(entries[0].path, "/live-tests/roundtrip.txt");

    check fileClient->deleteFile("/live-tests/roundtrip.txt");
    check fileClient->deleteDirectory("/live-tests");
}

@test:Config {groups: ["live"], enable: liveEnabled, dependsOn: [testLiveContentRoundtrip]}
function testLiveCleanup() returns error? {
    AdminClient admin = check newLiveAdmin();
    check admin->deleteShare(liveShareName);
}
