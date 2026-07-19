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

// The credential-free "mock" test group: every test runs against the in-process mock FileREST
// service through the SharedKeyConfig.serviceUrl override, so the whole group runs on any
// machine with no Azure account.

import ballerina/file;
import ballerina/io;
import ballerina/test;

// A syntactically valid (base64) but fake account key; the mock ignores authentication.
const string MOCK_KEY = "bW9jay1hY2NvdW50LWtleS1mb3ItdGVzdHM=";

isolated function newAdmin() returns AdminClient|Error => new (auth = {
    accountName: "mockaccount",
    accountKey: MOCK_KEY,
    serviceUrl: string `http://localhost:${MOCK_PORT}`
});

isolated function newShareClient(string share) returns Client|Error => new (share, auth = {
    accountName: "mockaccount",
    accountKey: MOCK_KEY,
    serviceUrl: string `http://localhost:${MOCK_PORT}`
});

// ---------------------------------------------------------------------------
// init validation (no service involved)
// ---------------------------------------------------------------------------

@test:Config {groups: ["mock"]}
function testInitRejectsBadBase64Key() {
    Client|Error result = new ("share", auth = {accountName: "acct", accountKey: "not base64!!!"});
    test:assertTrue(result is ProcessingError, "expected a ProcessingError for a non-base64 key");
}

@test:Config {groups: ["mock"]}
function testInitRejectsEmptyAccountName() {
    Client|Error result = new ("share", auth = {accountName: "  ", accountKey: MOCK_KEY});
    test:assertTrue(result is ProcessingError, "expected a ProcessingError for an empty account name");
}

@test:Config {groups: ["mock"]}
function testInitRejectsBadServiceUrl() {
    Client|Error result = new ("share",
            auth = {accountName: "acct", accountKey: MOCK_KEY, serviceUrl: "ftp://example.com"});
    test:assertTrue(result is ProcessingError, "expected a ProcessingError for a non-http serviceUrl");
}

@test:Config {groups: ["mock"]}
function testInitRejectsEmptyShareName() {
    Client|Error result = new ("", auth = {accountName: "acct", accountKey: MOCK_KEY});
    test:assertTrue(result is ProcessingError, "expected a ProcessingError for an empty share name");
}

@test:Config {groups: ["mock"]}
function testInitRejectsSasUrlWithoutSignature() {
    Client|Error result = new ("share", auth = {sasUrl: "https://acct.file.core.windows.net/?sv=2024"});
    test:assertTrue(result is ProcessingError, "expected a ProcessingError for a SAS URL without sig=");
}

@test:Config {groups: ["mock"]}
function testInitRejectsConnectionStringWithoutEndpoint() {
    Client|Error result = new ("share",
            auth = {connectionString: "DefaultEndpointsProtocol=https;AccountKey=" + MOCK_KEY});
    test:assertTrue(result is ProcessingError,
            "expected a ProcessingError for a connection string without FileEndpoint/AccountName");
}

@test:Config {groups: ["mock"]}
function testInitAcceptsConnectionString() {
    Client|Error result = new ("share", auth = {
        connectionString: string `DefaultEndpointsProtocol=http;AccountName=mockaccount;AccountKey=${MOCK_KEY};FileEndpoint=http://localhost:${MOCK_PORT}/mockaccount`
    });
    test:assertTrue(result is Client, "expected a connection-string client to initialize");
}

@test:Config {groups: ["mock"]}
function testInitEntraIdNotImplemented() {
    Client|Error result = new ("share", auth = {kind: "default", accountName: "acct"});
    if result is Error {
        test:assertEquals(result.detail().errorCode, "NotImplemented");
    } else {
        test:assertFail("expected Entra ID auth to fail as NotImplemented");
    }
}

@test:Config {groups: ["mock"]}
function testInitRetryConfigNotImplemented() {
    Client|Error result = new ("share",
            auth = {accountName: "acct", accountKey: MOCK_KEY}, retryConfig = {});
    if result is Error {
        test:assertEquals(result.detail().errorCode, "NotImplemented");
    } else {
        test:assertFail("expected retryConfig to fail as NotImplemented");
    }
}

@test:Config {groups: ["mock"]}
function testClosedClientFails() returns error? {
    Client fileClient = check newShareClient("closed-share");
    check fileClient.close();
    boolean|Error result = fileClient->hasFile("/a.txt");
    test:assertTrue(result is ProcessingError, "expected an op on a closed client to fail");
}

// ---------------------------------------------------------------------------
// AdminClient share management
// ---------------------------------------------------------------------------

@test:Config {groups: ["mock"]}
function testShareLifecycle() returns error? {
    AdminClient admin = check newAdmin();
    check admin->createShare("lifecycle", {quotaInGb: 100, metadata: {owner: "tests"}});
    var actionResult1 = check admin->hasShare("lifecycle");
    test:assertTrue(actionResult1);
    var actionResult2 = check admin->hasShare("no-such-share");
    test:assertFalse(actionResult2);

    ShareInfo[] shares = check admin->listShares({prefix: "lifecycle", includeMetadata: true});
    test:assertEquals(shares.length(), 1);
    test:assertEquals(shares[0].name, "lifecycle");
    test:assertEquals(shares[0].properties.quotaInGb, 100);
    test:assertEquals(shares[0].metadata, {owner: "tests"});

    check admin->deleteShare("lifecycle");
    var actionResult3 = check admin->hasShare("lifecycle");
    test:assertFalse(actionResult3);

    ShareInfo[] deleted = check admin->listShares({prefix: "lifecycle", includeDeleted: true});
    test:assertEquals(deleted.length(), 1);
    test:assertEquals(deleted[0].isDeleted, true);
    string version = deleted[0].version ?: "";
    check admin->undeleteShare("lifecycle", version);
    var actionResult4 = check admin->hasShare("lifecycle");
    test:assertTrue(actionResult4);
    check admin.close();
}

@test:Config {groups: ["mock"]}
function testCreateShareTwiceConflicts() returns error? {
    AdminClient admin = check newAdmin();
    check admin->createShare("dup-share");
    Error? result = admin->createShare("dup-share");
    test:assertTrue(result is ConflictError, "expected a ConflictError for a duplicate share");
}

// ---------------------------------------------------------------------------
// Client share ops
// ---------------------------------------------------------------------------

@test:Config {groups: ["mock"]}
function testSharePropertiesAndUsage() returns error? {
    AdminClient admin = check newAdmin();
    check admin->createShare("props-share", {quotaInGb: 7});
    Client fileClient = check newShareClient("props-share");

    ShareProperties props = check fileClient->getShareProperties();
    test:assertEquals(props.quotaInGb, 7);
    test:assertEquals(props.accessTier, TRANSACTION_OPTIMIZED);
    test:assertTrue(props.eTag.length() > 0);

    check fileClient->setShareMetadata({env: "mock"});
    props = check fileClient->getShareProperties();
    test:assertEquals(props.metadata, {env: "mock"});

    var actionResult15 = check fileClient->getShareUsage();
    test:assertEquals(actionResult15, 0);
    check fileClient->uploadContent("12345", "/usage.txt");
    var actionResult16 = check fileClient->getShareUsage();
    test:assertEquals(actionResult16, 5);
}

// ---------------------------------------------------------------------------
// Directories
// ---------------------------------------------------------------------------

@test:Config {groups: ["mock"]}
function testDirectoryLifecycle() returns error? {
    AdminClient admin = check newAdmin();
    check admin->createShare("dir-share");
    Client fileClient = check newShareClient("dir-share");

    check fileClient->createDirectory("/docs");
    check fileClient->createDirectory("/docs/2026", {metadata: {year: "2026"}});
    var actionResult5 = check fileClient->hasDirectory("/docs/2026");
    test:assertTrue(actionResult5);
    var actionResult6 = check fileClient->hasDirectory("/docs/2030");
    test:assertFalse(actionResult6);

    DirectoryProperties props = check fileClient->getDirectoryProperties("/docs/2026");
    test:assertEquals(props.metadata, {year: "2026"});
    test:assertTrue(props.isServerEncrypted);

    check fileClient->setDirectoryMetadata("/docs/2026", {year: "updated"});
    props = check fileClient->getDirectoryProperties("/docs/2026");
    test:assertEquals(props.metadata, {year: "updated"});

    // A missing parent fails.
    Error? orphan = fileClient->createDirectory("/no-parent/child");
    test:assertTrue(orphan is NotFoundError, "expected ParentNotFound to map to NotFoundError");

    // Deleting a non-empty directory conflicts; after moving out, it deletes.
    check fileClient->renameDirectory("/docs/2026", "/archive");
    var actionResult7 = check fileClient->hasDirectory("/archive");
    test:assertTrue(actionResult7);
    var actionResult8 = check fileClient->hasDirectory("/docs/2026");
    test:assertFalse(actionResult8);
    check fileClient->deleteDirectory("/archive");
    check fileClient->deleteDirectory("/docs");
}

@test:Config {groups: ["mock"]}
function testDeleteNonEmptyDirectoryConflicts() returns error? {
    AdminClient admin = check newAdmin();
    check admin->createShare("nonempty-share");
    Client fileClient = check newShareClient("nonempty-share");
    check fileClient->createDirectory("/keep");
    check fileClient->uploadContent("x", "/keep/file.txt");
    Error? result = fileClient->deleteDirectory("/keep");
    test:assertTrue(result is ConflictError, "expected DirectoryNotEmpty to map to ConflictError");
}

// ---------------------------------------------------------------------------
// Files
// ---------------------------------------------------------------------------

@test:Config {groups: ["mock"]}
function testFileLifecycle() returns error? {
    AdminClient admin = check newAdmin();
    check admin->createShare("file-share");
    Client fileClient = check newShareClient("file-share");

    check fileClient->createFile("/report.bin", 16, {metadata: {kind: "report"}});
    var actionResult9 = check fileClient->hasFile("/report.bin");
    test:assertTrue(actionResult9);
    var actionResult10 = check fileClient->hasFile("/missing.bin");
    test:assertFalse(actionResult10);

    FileProperties props = check fileClient->getFileProperties("/report.bin");
    test:assertEquals(props.contentLength, 16);
    test:assertEquals(props.contentType, "application/octet-stream");
    test:assertEquals(props.metadata, {kind: "report"});
    test:assertTrue(props.isServerEncrypted);

    check fileClient->setFileMetadata("/report.bin", {kind: "updated"});
    props = check fileClient->getFileProperties("/report.bin");
    test:assertEquals(props.metadata, {kind: "updated"});

    check fileClient->setContentHeaders("/report.bin",
            {contentType: "application/pdf", cacheControl: "max-age=60"});
    props = check fileClient->getFileProperties("/report.bin");
    test:assertEquals(props.contentType, "application/pdf");
    test:assertEquals(props.cacheControl, "max-age=60");

    check fileClient->renameFile("/report.bin", "/final.bin");
    var actionResult11 = check fileClient->hasFile("/report.bin");
    test:assertFalse(actionResult11);
    var actionResult12 = check fileClient->hasFile("/final.bin");
    test:assertTrue(actionResult12);

    check fileClient->deleteFile("/final.bin");
    var actionResult13 = check fileClient->hasFile("/final.bin");
    test:assertFalse(actionResult13);

    FileProperties|Error missing = fileClient->getFileProperties("/final.bin");
    test:assertTrue(missing is NotFoundError, "expected NotFoundError for a deleted file");
}

// ---------------------------------------------------------------------------
// Transfer ops
// ---------------------------------------------------------------------------

@test:Config {groups: ["mock"]}
function testUploadContentVariantsAndDownloadStream() returns error? {
    AdminClient admin = check newAdmin();
    check admin->createShare("content-share");
    Client fileClient = check newShareClient("content-share");

    check fileClient->uploadContent("hello mock", "/text.txt");
    test:assertEquals(check readAll(fileClient, "/text.txt"), "hello mock".toBytes());

    byte[] binary = [1, 2, 3, 4, 5];
    check fileClient->uploadContent(binary, "/binary.bin");
    test:assertEquals(check readAll(fileClient, "/binary.bin"), binary);

    check fileClient->uploadContent({metric: 42}, "/data.json");
    test:assertEquals(check readAll(fileClient, "/data.json"), "{\"metric\":42}".toBytes());

    xml document = xml `<report><value>1</value></report>`;
    check fileClient->uploadContent(document, "/doc.xml");
    test:assertEquals(check readAll(fileClient, "/doc.xml"), document.toString().toBytes());
}

@test:Config {groups: ["mock"]}
function testUploadAndDownloadLocalFile() returns error? {
    AdminClient admin = check newAdmin();
    check admin->createShare("transfer-share");
    Client fileClient = check newShareClient("transfer-share");

    string localSource = "target/mock-upload-source.txt";
    string localDestination = "target/mock-download-target.txt";
    check io:fileWriteString(localSource, "round trip payload");
    if check file:test(localDestination, file:EXISTS) {
        check file:remove(localDestination);
    }

    check fileClient->uploadFile(localSource, "/roundtrip.txt");
    var actionResult14 = check fileClient->hasFile("/roundtrip.txt");
    test:assertTrue(actionResult14);

    check fileClient->downloadFile("/roundtrip.txt", localDestination);
    test:assertEquals(check io:fileReadString(localDestination), "round trip payload");

    // The destination must not already exist (CREATE_NEW contract).
    Error? again = fileClient->downloadFile("/roundtrip.txt", localDestination);
    test:assertTrue(again is ProcessingError, "expected an existing local file to fail the download");

    Error? missingLocal = fileClient->uploadFile("target/does-not-exist.txt", "/x.txt");
    test:assertTrue(missingLocal is ProcessingError, "expected a missing local file to fail the upload");
}

@test:Config {groups: ["mock"]}
function testUploadFromStream() returns error? {
    AdminClient admin = check newAdmin();
    check admin->createShare("stream-share");
    Client fileClient = check newShareClient("stream-share");

    byte[][] chunks = ["abc".toBytes(), "defg".toBytes(), "hi".toBytes()];
    check fileClient->uploadFromStream(chunks.toStream(), 9, "/streamed.txt");
    test:assertEquals(check readAll(fileClient, "/streamed.txt"), "abcdefghi".toBytes());

    // A declared length that does not match the stream fails with a ProcessingError.
    byte[][] shortChunks = ["abc".toBytes()];
    Error? shortResult = fileClient->uploadFromStream(shortChunks.toStream(), 9, "/short.txt");
    test:assertTrue(shortResult is ProcessingError, "expected a short stream to fail");
}

@test:Config {groups: ["mock"]}
function testRangedDownload() returns error? {
    AdminClient admin = check newAdmin();
    check admin->createShare("range-read-share");
    Client fileClient = check newShareClient("range-read-share");
    check fileClient->uploadContent("0123456789", "/digits.txt");

    stream<byte[], Error?> content =
        check fileClient->getFileContent("/digits.txt", {range: {startByte: 2, endByte: 5}});
    test:assertEquals(check collectBytes(content), "2345".toBytes());
}

// ---------------------------------------------------------------------------
// Listing
// ---------------------------------------------------------------------------

@test:Config {groups: ["mock"]}
function testListFlatAndRecursive() returns error? {
    AdminClient admin = check newAdmin();
    check admin->createShare("list-share");
    Client fileClient = check newShareClient("list-share");
    check fileClient->createDirectory("/a");
    check fileClient->createDirectory("/a/b");
    check fileClient->uploadContent("1", "/root.txt");
    check fileClient->uploadContent("2", "/a/one.txt");
    check fileClient->uploadContent("3", "/a/b/two.txt");

    stream<Entry, Error?> entryStream18 = check fileClient->list("/");
    Entry[] flat = check collectEntries(entryStream18);
    test:assertEquals(entryPaths(flat).sort(), ["/a", "/root.txt"]);

    stream<Entry, Error?> entryStream19 = check fileClient->list("/", {recursive: true});
    Entry[] deep = check collectEntries(entryStream19);
    test:assertEquals(entryPaths(deep).sort(),
            ["/a", "/a/b", "/a/b/two.txt", "/a/one.txt", "/root.txt"]);

    stream<Entry, Error?> entryStream20 = check fileClient->list("/a");
    Entry[] scoped = check collectEntries(entryStream20);
    test:assertEquals(entryPaths(scoped).sort(), ["/a/b", "/a/one.txt"]);

    // Extended info brings the eTag along.
    stream<Entry, Error?> entryStream21 = check fileClient->list("/", {includeExtendedInfo: true});
    Entry[] extended = check collectEntries(entryStream21);
    foreach Entry entry in extended {
        test:assertTrue(entry.eTag is string, "expected an eTag with includeExtendedInfo");
    }
}

// ---------------------------------------------------------------------------
// Copy ops
// ---------------------------------------------------------------------------

@test:Config {groups: ["mock"]}
function testCopyWithinShare() returns error? {
    AdminClient admin = check newAdmin();
    check admin->createShare("copy-share");
    Client fileClient = check newShareClient("copy-share");
    check fileClient->uploadContent("copy me", "/source.txt");

    CopyInfo info = check fileClient->copyFile("/source.txt", "/target.txt");
    test:assertTrue(info.copyId.length() > 0);
    test:assertEquals(check readAll(fileClient, "/target.txt"), "copy me".toBytes());

    CopyStatusInfo? status = check fileClient->checkCopyStatus("/target.txt");
    if status is CopyStatusInfo {
        test:assertEquals(status.copyStatus, SUCCESS);
        test:assertEquals(status.copyId, info.copyId);
    } else {
        test:assertFail("expected copy status on the destination file");
    }

    // A file that was never a copy destination reports no status.
    var actionResult17 = check fileClient->checkCopyStatus("/source.txt");
    test:assertEquals(actionResult17, ());

    // The mock completes copies synchronously, so an abort always conflicts.
    Error? abort = fileClient->abortCopy("/target.txt", info.copyId);
    test:assertTrue(abort is Error, "expected abortCopy on a finished copy to fail");
}

@test:Config {groups: ["mock"]}
function testCopyFromUrl() returns error? {
    AdminClient admin = check newAdmin();
    check admin->createShare("copy-url-share");
    Client fileClient = check newShareClient("copy-url-share");
    check fileClient->uploadContent("via url", "/origin.txt");

    string sourceUrl = string `http://localhost:${MOCK_PORT}/copy-url-share/origin.txt`;
    CopyInfo info = check fileClient->copyFileFromUrl(sourceUrl, "/copied.txt");
    test:assertTrue(info.copyId.length() > 0);
    test:assertEquals(check readAll(fileClient, "/copied.txt"), "via url".toBytes());
}

// ---------------------------------------------------------------------------
// Range ops
// ---------------------------------------------------------------------------

@test:Config {groups: ["mock"]}
function testRangeWriteClearAndList() returns error? {
    AdminClient admin = check newAdmin();
    check admin->createShare("ranges-share");
    Client fileClient = check newShareClient("ranges-share");
    check fileClient->createFile("/ranges.bin", 8);

    Range[] empty = check fileClient->listRanges("/ranges.bin");
    test:assertEquals(empty.length(), 0);

    check fileClient->uploadRange("/ranges.bin", 0, "ABCDEFGH".toBytes());
    Range[] written = check fileClient->listRanges("/ranges.bin");
    test:assertEquals(written, [{startByte: 0, endByte: 7}]);
    test:assertEquals(check readAll(fileClient, "/ranges.bin"), "ABCDEFGH".toBytes());

    check fileClient->clearRange("/ranges.bin", 0, 8);
    Range[] cleared = check fileClient->listRanges("/ranges.bin");
    test:assertEquals(cleared.length(), 0);

    // Writing past the pre-allocated size is rejected by the service.
    Error? overflow = fileClient->uploadRange("/ranges.bin", 4, "TOO LONG!".toBytes());
    test:assertTrue(overflow is RangeNotSatisfiableError,
            "expected InvalidRange to map to RangeNotSatisfiableError");
}

// ---------------------------------------------------------------------------
// Error mapping
// ---------------------------------------------------------------------------

@test:Config {groups: ["mock"]}
function testErrorCodeMapping() returns error? {
    AdminClient admin = check newAdmin();
    check admin->createShare("errors-share");
    Client fileClient = check newShareClient("errors-share");

    FileProperties|Error quota = fileClient->getFileProperties("/__err-403-ShareSizeLimitReached");
    test:assertTrue(quota is QuotaExceededError, "403 ShareSizeLimitReached should map to QuotaExceededError");

    FileProperties|Error smbFull = fileClient->getFileProperties("/__err-403-SmbShareFull");
    test:assertTrue(smbFull is QuotaExceededError, "403 SmbShareFull should map to QuotaExceededError");

    FileProperties|Error auth = fileClient->getFileProperties("/__err-403-AuthenticationFailed");
    test:assertTrue(auth is AuthorizationError, "403 AuthenticationFailed should map to AuthorizationError");

    FileProperties|Error precondition = fileClient->getFileProperties("/__err-412-ConditionNotMet");
    test:assertTrue(precondition is PreconditionFailedError,
            "412 ConditionNotMet should map to PreconditionFailedError");

    FileProperties|Error sharing = fileClient->getFileProperties("/__err-409-SharingViolation");
    test:assertTrue(sharing is ConflictError, "409 SharingViolation should map to ConflictError");

    FileProperties|Error unknown = fileClient->getFileProperties("/__err-500-InternalError");
    if unknown is Error {
        test:assertFalse(unknown is NotFoundError|ConflictError|AuthorizationError
                |PreconditionFailedError|RangeNotSatisfiableError|QuotaExceededError|ProcessingError,
                "an unmapped code should stay the generic Error type");
        test:assertEquals(unknown.detail().httpStatus, 500);
        test:assertEquals(unknown.detail().errorCode, "InternalError");
    } else {
        test:assertFail("expected an error for the forced 500");
    }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

isolated function readAll(Client fileClient, string path) returns byte[]|error {
    stream<byte[], Error?> content = check fileClient->getFileContent(path);
    return collectBytes(content);
}

isolated function collectBytes(stream<byte[], Error?> content) returns byte[]|error {
    byte[] collected = [];
    record {|byte[] value;|}|Error? chunk = content.next();
    while chunk is record {|byte[] value;|} {
        foreach byte b in chunk.value {
            collected.push(b);
        }
        chunk = content.next();
    }
    if chunk is Error {
        return chunk;
    }
    return collected;
}

isolated function collectEntries(stream<Entry, Error?> entries) returns Entry[]|error {
    Entry[] collected = [];
    record {|Entry value;|}|Error? entry = entries.next();
    while entry is record {|Entry value;|} {
        collected.push(entry.value);
        entry = entries.next();
    }
    if entry is Error {
        return entry;
    }
    return collected;
}

isolated function entryPaths(Entry[] entries) returns string[] {
    return entries.map(entry => entry.path);
}
