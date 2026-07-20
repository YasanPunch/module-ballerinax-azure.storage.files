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

import ballerina/os;
import ballerina/test;
import ballerina/time;

// Credentials come from Config.toml, or from environment variables when no Config.toml
// entry is present (how CI supplies them from repository secrets).
configurable string liveAccountName = os:getEnv("LIVE_ACCOUNT_NAME");
configurable string liveAccountKey = os:getEnv("LIVE_ACCOUNT_KEY");
configurable string liveShareName = defaultLiveShareName();

// Microsoft Entra ID smoke tests. Both need an identity holding the Storage File Data
// Privileged Contributor role on the account. The service-principal variant reads its
// credentials from configuration; the default-chain variant enables itself when the
// standard Azure environment variables are present, which the default credential chain
// consumes identically wherever the tests run (host shell, container, CI).
configurable string liveEntraTenantId = os:getEnv("LIVE_ENTRA_TENANT_ID");
configurable string liveEntraClientId = os:getEnv("LIVE_ENTRA_CLIENT_ID");
configurable string liveEntraClientSecret = os:getEnv("LIVE_ENTRA_CLIENT_SECRET");

// Concurrent CI runs must not share a test share, so the default name is scoped to the
// GitHub Actions run when one is present. Local runs keep the fixed name.
isolated function defaultLiveShareName() returns string {
    string runId = os:getEnv("GITHUB_RUN_ID");
    return runId == "" ? "bal-azfiles-live-tests" : string `bal-azfiles-live-tests-${runId}`;
}

final boolean liveEnabled = liveAccountName != "" && liveAccountKey != "";
final boolean liveEntraEnabled = liveEnabled && liveEntraTenantId != ""
    && liveEntraClientId != "" && liveEntraClientSecret != "";
final boolean liveEntraDefaultChainEnabled = liveEnabled
    && os:getEnv("AZURE_TENANT_ID") != ""
    && os:getEnv("AZURE_CLIENT_ID") != ""
    && os:getEnv("AZURE_CLIENT_SECRET") != "";

isolated function newLiveAdmin() returns AdminClient|Error =>
    new (auth = {accountName: liveAccountName, accountKey: liveAccountKey});

isolated function newLiveClient() returns Client|Error =>
    new (liveShareName, auth = {accountName: liveAccountName, accountKey: liveAccountKey});

@test:Config {groups: ["live"], enable: liveEnabled}
function testLiveShareLifecycle() returns error? {
    AdminClient admin = check newLiveAdmin();
    // Idempotent setup: a leftover share from an interrupted run is reused.
    boolean existsAlready = check admin->hasShare(liveShareName);
    if !existsAlready {
        check admin->createShare(liveShareName);
    }
    boolean exists = check admin->hasShare(liveShareName);
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
function testLiveLeases() returns error? {
    Client fileClient = check newLiveClient();

    string shareLeaseId = check fileClient->acquireShareLease(-1);
    ShareProperties props = check fileClient->getShareProperties();
    test:assertEquals(props.leaseState, LEASED);
    test:assertEquals(props.leaseDuration, INFINITE);
    string changedShareLease = check fileClient->changeShareLease(shareLeaseId,
            "20000000-0000-0000-0000-000000000001");
    check fileClient->releaseShareLease(changedShareLease);

    check fileClient->uploadContent("leased", "/lease-probe.txt");
    string fileLeaseId = check fileClient->acquireLease("/lease-probe.txt");
    string|Error second = fileClient->acquireLease("/lease-probe.txt");
    test:assertTrue(second is ConflictError, "expected LeaseAlreadyPresent to conflict");
    check fileClient->releaseLease("/lease-probe.txt", fileLeaseId);
    check fileClient->deleteFile("/lease-probe.txt");
}

@test:Config {groups: ["live"], enable: liveEnabled, dependsOn: [testLiveLeases]}
function testLiveSnapshots() returns error? {
    Client fileClient = check newLiveClient();
    check fileClient->uploadContent("before snapshot", "/snap-probe.txt");
    ShareSnapshotInfo snapshot = check fileClient->createShareSnapshot();

    check fileClient->uploadContent("after snapshot!", "/snap-probe.txt");
    stream<byte[], Error?> frozen = check fileClient->getFileContent("/snap-probe.txt",
            {snapshotId: snapshot.snapshotId});
    test:assertEquals(check collectBytes(frozen), "before snapshot".toBytes());

    RangeDiff diff = check fileClient->listRangesDiff("/snap-probe.txt", snapshot.snapshotId);
    test:assertTrue(diff.ranges.length() > 0, "expected the overwrite to appear in the diff");

    ShareSnapshotInfo[] snapshots = check fileClient->listShareSnapshots();
    test:assertTrue(snapshots.some(s => s.snapshotId == snapshot.snapshotId));
    check fileClient->deleteShareSnapshot(snapshot.snapshotId);
    check fileClient->deleteFile("/snap-probe.txt");
}

@test:Config {groups: ["live"], enable: liveEnabled, dependsOn: [testLiveSnapshots]}
function testLiveSetters() returns error? {
    Client fileClient = check newLiveClient();
    check fileClient->setShareProperties({quotaInGb: 6});
    ShareProperties shareProps = check fileClient->getShareProperties();
    test:assertEquals(shareProps.quotaInGb, 6);

    check fileClient->uploadContent("0123456789", "/setter-probe.txt");
    check fileClient->setContentHeaders("/setter-probe.txt", {contentType: "text/plain"});
    check fileClient->setFileProperties("/setter-probe.txt", {newFileSizeBytes: 4});
    FileProperties props = check fileClient->getFileProperties("/setter-probe.txt");
    test:assertEquals(props.contentLength, 4);
    test:assertEquals(props.contentType, "text/plain");
    check fileClient->deleteFile("/setter-probe.txt");
}

@test:Config {groups: ["live"], enable: liveEnabled, dependsOn: [testLiveSetters]}
function testLiveAccessPolicyAndPermissions() returns error? {
    Client fileClient = check newLiveClient();
    time:Utc startsOn = time:utcNow();
    time:Utc expiresOn = time:utcAddSeconds(startsOn, 3600);
    check fileClient->setShareAccessPolicy([
        {id: "live-read-policy", accessPolicy: {startsOn, expiresOn, permissions: "rl"}}
    ]);
    SignedIdentifier[] stored = check fileClient->getShareAccessPolicy();
    test:assertEquals(stored.length(), 1);
    test:assertEquals(stored[0].id, "live-read-policy");
    test:assertEquals(stored[0].accessPolicy.permissions, "rl");
    check fileClient->setShareAccessPolicy([]);

    string sddl = "O:SYG:SYD:(A;;FA;;;SY)";
    string permissionKey = check fileClient->createSharePermission(sddl);
    test:assertTrue(permissionKey.length() > 0);
    string fetched = check fileClient->getSharePermission(permissionKey);
    test:assertTrue(fetched.length() > 0, "expected the stored SDDL to be readable");
}

@test:Config {groups: ["live"], enable: liveEnabled, dependsOn: [testLiveAccessPolicyAndPermissions]}
function testLiveSasRoundtrip() returns error? {
    Client keyClient = check newLiveClient();
    check keyClient->uploadContent("sas readable", "/sas-probe.txt");

    time:Utc expiry = time:utcAddSeconds(time:utcNow(), 3600);
    string shareSas = check keyClient->generateShareSas(
            {expiryTime: expiry, permissions: {read: true, list: true, delete: true}});

    // The minted token authenticates a fresh client end to end.
    Client sasClient = check new (liveShareName,
            auth = {accountName: liveAccountName, sasToken: shareSas});
    byte[] content = check readAll(sasClient, "/sas-probe.txt");
    test:assertEquals(content, "sas readable".toBytes());
    check sasClient->deleteFile("/sas-probe.txt");
    check sasClient.close();
}

@test:Config {groups: ["live"], enable: liveEnabled, dependsOn: [testLiveSasRoundtrip]}
function testLiveHandles() returns error? {
    Client fileClient = check newLiveClient();
    check fileClient->uploadContent("no handles", "/handle-probe.txt");
    HandleInfo[] handles = check fileClient->listFileHandles("/handle-probe.txt");
    test:assertEquals(handles.length(), 0, "REST clients hold no SMB handles");
    CloseHandlesInfo closed = check fileClient->forceCloseFileHandles("/handle-probe.txt");
    test:assertEquals(closed.closedHandles, 0);
    check fileClient->deleteFile("/handle-probe.txt");
}

@test:Config {groups: ["live"], enable: liveEnabled, dependsOn: [testLiveHandles]}
function testLiveCopyRangesAndRename() returns error? {
    Client fileClient = check newLiveClient();
    check fileClient->uploadContent("copy me", "/copy-source.txt");
    CopyInfo info = check fileClient->copyFile("/copy-source.txt", "/copy-target.txt");
    test:assertTrue(info.copyId.length() > 0);
    test:assertEquals(check readAll(fileClient, "/copy-target.txt"), "copy me".toBytes());

    check fileClient->createFile("/live-ranges.bin", 8);
    check fileClient->uploadRange("/live-ranges.bin", 0, "ABCDEFGH".toBytes());
    Range[] written = check fileClient->listRanges("/live-ranges.bin");
    test:assertEquals(written, [{startByte: 0, endByte: 7}]);
    // Ranges deallocate in 512-byte pages, so a sub-page clear zeroes the bytes while the
    // range stays listed.
    check fileClient->clearRange("/live-ranges.bin", 0, 8);
    byte[] zeroed = check readAll(fileClient, "/live-ranges.bin");
    test:assertEquals(zeroed, [0, 0, 0, 0, 0, 0, 0, 0]);

    // The copy target already exists, so the rename needs replaceIfExists.
    Error? clash = fileClient->renameFile("/copy-source.txt", "/copy-target.txt");
    test:assertTrue(clash is ConflictError, "expected an existing destination to conflict");
    check fileClient->renameFile("/copy-source.txt", "/copy-target.txt", {replaceIfExists: true});

    check fileClient->deleteFile("/copy-target.txt");
    check fileClient->deleteFile("/live-ranges.bin");
}

@test:Config {groups: ["live"], enable: liveEnabled, dependsOn: [testLiveCopyRangesAndRename]}
function testLiveConnectionStringAuth() returns error? {
    Client csClient = check new (liveShareName, auth = {
        connectionString: string `DefaultEndpointsProtocol=https;AccountName=${liveAccountName};AccountKey=${liveAccountKey};EndpointSuffix=core.windows.net`
    });
    check csClient->uploadContent("via connection string", "/cs-probe.txt");
    test:assertEquals(check readAll(csClient, "/cs-probe.txt"), "via connection string".toBytes());
    check csClient->deleteFile("/cs-probe.txt");
    check csClient.close();
}

@test:Config {groups: ["live"], enable: liveEnabled, dependsOn: [testLiveConnectionStringAuth]}
function testLiveSasUrlAuth() returns error? {
    Client keyClient = check newLiveClient();
    check keyClient->uploadContent("via sas url", "/sasurl-probe.txt");
    time:Utc expiry = time:utcAddSeconds(time:utcNow(), 3600);
    string token = check keyClient->generateShareSas(
            {expiryTime: expiry, permissions: {read: true, delete: true}});

    // The minted token authenticates a fresh client through its full SAS URL.
    Client sasUrlClient = check new (liveShareName, auth = {
        sasUrl: string `https://${liveAccountName}.file.core.windows.net?${token}`
    });
    test:assertEquals(check readAll(sasUrlClient, "/sasurl-probe.txt"), "via sas url".toBytes());
    check sasUrlClient->deleteFile("/sasurl-probe.txt");
    check sasUrlClient.close();
}

@test:Config {groups: ["live"], enable: liveEntraDefaultChainEnabled}
function testLiveEntraDefaultChainAuth() returns error? {
    // Standalone (not in the cleanup chain) so a missing sign-in never skips cleanup.
    // A NotFound answer for a nonexistent share proves the token was both authenticated
    // and authorized; a missing role surfaces as an authorization error instead.
    Client entraClient = check new ("entra-probe-share",
            auth = {kind: "default", accountName: liveAccountName});
    FileProperties|Error result = entraClient->getFileProperties("/probe.txt");
    if result is FileProperties {
        test:assertFail("expected NotFound for a nonexistent share, but got file properties");
    } else if result !is NotFoundError {
        test:assertFail("Entra call failed before an authorized NotFound: " + result.message());
    }
    check entraClient.close();
}

@test:Config {groups: ["live"], enable: liveEntraEnabled}
function testLiveEntraAuth() returns error? {
    // Standalone (not in the cleanup chain) so missing Entra credentials never skip cleanup.
    Client entraClient = check new ("entra-probe-share", auth = {
        accountName: liveAccountName,
        tenantId: liveEntraTenantId,
        clientId: liveEntraClientId,
        clientSecret: liveEntraClientSecret
    });
    FileProperties|Error result = entraClient->getFileProperties("/probe.txt");
    if result is FileProperties {
        test:assertFail("expected NotFound for a nonexistent share, but got file properties");
    } else if result !is NotFoundError {
        test:assertFail("Entra call failed before an authorized NotFound: " + result.message());
    }
    check entraClient.close();
}

@test:Config {groups: ["live"], enable: liveEnabled, dependsOn: [testLiveSasUrlAuth]}
function testLiveCleanup() returns error? {
    AdminClient admin = check newLiveAdmin();
    check admin->deleteShare(liveShareName, {deleteSnapshots: INCLUDE});
}
