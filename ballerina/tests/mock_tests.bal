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
import ballerina/time;

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
function testInitEntraIdModes() returns error? {
    // Every Entra credential kind builds locally; tokens are requested only on first use.
    Client defaultChain = check new ("share", auth = {kind: "default", accountName: "acct"});
    check defaultChain.close();

    Client managed = check new ("share",
            auth = {kind: "managed-identity", accountName: "acct", clientId: "mi-client"});
    check managed.close();

    Client secret = check new ("share",
            auth = {accountName: "acct", tenantId: "tenant", clientId: "client", clientSecret: "s3cret"});
    check secret.close();

    string tokenFile = "target/mock-workload-token.txt";
    check io:fileWriteString(tokenFile, "federated-token");
    Client workload = check new ("share",
            auth = {accountName: "acct", tenantId: "tenant", clientId: "client", tokenFilePath: tokenFile});
    check workload.close();

    string certificateFile = "target/mock-entra-cert.pem";
    check io:fileWriteString(certificateFile,
            "-----BEGIN CERTIFICATE-----\nTUlJQg==\n-----END CERTIFICATE-----\n");
    Client certificate = check new ("share", auth = {
        accountName: "acct",
        tenantId: "tenant",
        clientId: "client",
        certificatePath: certificateFile
    });
    check certificate.close();
}

@test:Config {groups: ["mock"]}
function testInitEntraIdValidation() {
    Client|Error emptyTenant = new ("share",
            auth = {accountName: "acct", tenantId: " ", clientId: "client", clientSecret: "s3cret"});
    test:assertTrue(emptyTenant is ProcessingError, "expected a blank tenantId to fail");

    Client|Error missingCertificate = new ("share", auth = {
        accountName: "acct",
        tenantId: "tenant",
        clientId: "client",
        certificatePath: "target/no-such-cert.pem"
    });
    test:assertTrue(missingCertificate is ProcessingError,
            "expected a missing certificate file to fail");

    Client|Error emptyAccount = new ("share", auth = {kind: "default", accountName: "  "});
    test:assertTrue(emptyAccount is ProcessingError, "expected a blank account name to fail");
}

@test:Config {groups: ["mock"]}
function testRetryAndTransportConfig() returns error? {
    AdminClient admin = check newAdmin();
    check admin->createShare("transport-config-share");

    // A tuned retry policy still round-trips content.
    Client retryClient = check new ("transport-config-share", auth = {
        accountName: "mockaccount",
        accountKey: MOCK_KEY,
        serviceUrl: string `http://localhost:${MOCK_PORT}`
    }, retryConfig = {
        retryPolicyType: FIXED,
        maxTries: 2,
        tryTimeoutSeconds: 10,
        retryDelaySeconds: 1,
        maxRetryDelaySeconds: 2
    });
    check retryClient->uploadContent("with retry", "/retry.txt");
    test:assertEquals(check readAll(retryClient, "/retry.txt"), "with retry".toBytes());
    check retryClient.close();

    // A custom transport (connection pool + timeouts) still round-trips content.
    Client pooledClient = check new ("transport-config-share", auth = {
        accountName: "mockaccount",
        accountKey: MOCK_KEY,
        serviceUrl: string `http://localhost:${MOCK_PORT}`
    }, transportConfig = {
        connectionPool: {
            maxConnections: 5,
            idleTimeoutSeconds: 30,
            connectTimeoutSeconds: 5,
            readTimeoutSeconds: 30
        }
    });
    check pooledClient->uploadContent("pooled", "/pooled.txt");
    test:assertEquals(check readAll(pooledClient, "/pooled.txt"), "pooled".toBytes());
    check pooledClient.close();

    // A proxy is honored: pointing at a dead port fails the request, not the init.
    Client proxied = check new ("transport-config-share", auth = {
        accountName: "mockaccount",
        accountKey: MOCK_KEY,
        serviceUrl: string `http://localhost:${MOCK_PORT}`
    }, transportConfig = {proxy: {proxyType: HTTP, host: "localhost", port: 39999}});
    Error? throughDeadProxy = proxied->uploadContent("x", "/proxied.txt");
    test:assertTrue(throughDeadProxy is ProcessingError,
            "expected a request through an unreachable proxy to fail");
    check proxied.close();
}

@test:Config {groups: ["mock"]}
function testTransportTlsConfig() returns error? {
    // Trust material as a PEM file.
    Client pemTrust = check new ("share", auth = {accountName: "acct", accountKey: MOCK_KEY},
            transportConfig = {secureSocket: {cert: "tests/resources/cert.pem"}});
    check pemTrust.close();

    // Trust material as a PKCS12 store.
    Client storeTrust = check new ("share", auth = {accountName: "acct", accountKey: MOCK_KEY},
            transportConfig = {
                secureSocket: {cert: {path: "tests/resources/trust.p12", password: "ballerina"}}
            });
    check storeTrust.close();

    // Client identity from a certificate and key pair, plus version and cipher pinning,
    // hostname-verification and session flags, and timeouts.
    Client mutualTls = check new ("share", auth = {accountName: "acct", accountKey: MOCK_KEY},
            transportConfig = {
                secureSocket: {
                    cert: "tests/resources/cert.pem",
                    'key: {certFile: "tests/resources/cert.pem", keyFile: "tests/resources/key.pem"},
                    tlsVersions: ["TLSv1.3", "TLSv1.2"],
                    ciphers: ["TLS_AES_128_GCM_SHA256"],
                    verifyHostName: false,
                    shareSession: false,
                    serverName: "localhost",
                    handshakeTimeoutSeconds: 10,
                    sessionTimeoutSeconds: 600
                }
            });
    check mutualTls.close();

    // Revocation checking builds against PEM trust material.
    Client revocation = check new ("share", auth = {accountName: "acct", accountKey: MOCK_KEY},
            transportConfig = {
                secureSocket: {cert: "tests/resources/cert.pem", validateRevocation: true}
            });
    check revocation.close();

    // Broken TLS input fails at init with a clear error.
    Client|Error missingCert = new ("share", auth = {accountName: "acct", accountKey: MOCK_KEY},
            transportConfig = {secureSocket: {cert: "tests/resources/absent.pem"}});
    test:assertTrue(missingCert is ProcessingError, "expected a missing cert file to fail");

    Client|Error wrongPassword = new ("share", auth = {accountName: "acct", accountKey: MOCK_KEY},
            transportConfig = {
                secureSocket: {cert: {path: "tests/resources/trust.p12", password: "wrong"}}
            });
    test:assertTrue(wrongPassword is ProcessingError, "expected a wrong store password to fail");

    Client|Error validationWithoutTrust = new ("share",
            auth = {accountName: "acct", accountKey: MOCK_KEY},
            transportConfig = {secureSocket: {validateRevocation: true}});
    test:assertTrue(validationWithoutTrust is ProcessingError,
            "expected validateRevocation without trust material to fail");
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
// Leases
// ---------------------------------------------------------------------------

@test:Config {groups: ["mock"]}
function testShareLeaseLifecycle() returns error? {
    AdminClient admin = check newAdmin();
    check admin->createShare("share-lease-share");
    Client fileClient = check newShareClient("share-lease-share");

    // An out-of-range duration is rejected before any request is made.
    string|Error invalid = fileClient->acquireShareLease(10);
    test:assertTrue(invalid is ProcessingError, "expected an invalid duration to fail locally");
    string|Error invalidHigh = fileClient->acquireShareLease(61);
    test:assertTrue(invalidHigh is ProcessingError, "expected an invalid duration to fail locally");

    string leaseId = check fileClient->acquireShareLease(-1,
            "11111111-1111-1111-1111-111111111111");
    test:assertEquals(leaseId, "11111111-1111-1111-1111-111111111111");

    ShareProperties props = check fileClient->getShareProperties();
    test:assertEquals(props.leaseState, LEASED);
    test:assertEquals(props.leaseStatus, LOCKED);
    test:assertEquals(props.leaseDuration, INFINITE);

    // Acquiring while a lease is held conflicts.
    string|Error second = fileClient->acquireShareLease(-1);
    test:assertTrue(second is ConflictError, "expected LeaseAlreadyPresent to map to ConflictError");

    check fileClient->renewShareLease(leaseId);

    string changed = check fileClient->changeShareLease(leaseId,
            "22222222-2222-2222-2222-222222222222");
    test:assertEquals(changed, "22222222-2222-2222-2222-222222222222");

    // The old id no longer works after the change.
    Error? stale = fileClient->renewShareLease(leaseId);
    test:assertTrue(stale is ConflictError, "expected a stale lease id to conflict");

    check fileClient->releaseShareLease(changed);
    props = check fileClient->getShareProperties();
    test:assertTrue(props.leaseState is (), "expected no lease fields after release");

    // Break reports how long until the lease is gone.
    string reacquired = check fileClient->acquireShareLease(15);
    test:assertTrue(reacquired.length() > 0);
    int remaining = check fileClient->breakShareLease(5);
    test:assertEquals(remaining, 5);

    // Breaking with no lease in place conflicts.
    int|Error nothingToBreak = fileClient->breakShareLease();
    test:assertTrue(nothingToBreak is ConflictError,
            "expected breaking without a lease to conflict");
}

@test:Config {groups: ["mock"]}
function testFileLeaseLifecycle() returns error? {
    AdminClient admin = check newAdmin();
    check admin->createShare("file-lease-share");
    Client fileClient = check newShareClient("file-lease-share");
    check fileClient->uploadContent("locked", "/locked.txt");

    string leaseId = check fileClient->acquireLease("/locked.txt");
    test:assertTrue(leaseId.length() > 0);

    FileProperties props = check fileClient->getFileProperties("/locked.txt");
    test:assertEquals(props.leaseState, LEASED);
    test:assertEquals(props.leaseStatus, LOCKED);
    test:assertEquals(props.leaseDuration, INFINITE);

    string|Error second = fileClient->acquireLease("/locked.txt");
    test:assertTrue(second is ConflictError, "expected LeaseAlreadyPresent to map to ConflictError");

    string changed = check fileClient->changeLease("/locked.txt", leaseId,
            "33333333-3333-3333-3333-333333333333");
    test:assertEquals(changed, "33333333-3333-3333-3333-333333333333");

    // Releasing with the superseded id conflicts; the changed id releases.
    Error? wrongId = fileClient->releaseLease("/locked.txt", leaseId);
    test:assertTrue(wrongId is ConflictError, "expected a stale lease id to conflict");
    check fileClient->releaseLease("/locked.txt", changed);

    props = check fileClient->getFileProperties("/locked.txt");
    test:assertTrue(props.leaseState is (), "expected no lease fields after release");

    // Break needs no id; the file is immediately leasable again.
    string beforeBreak = check fileClient->acquireLease("/locked.txt",
            "44444444-4444-4444-4444-444444444444");
    test:assertEquals(beforeBreak, "44444444-4444-4444-4444-444444444444");
    check fileClient->breakLease("/locked.txt");
    string afterBreak = check fileClient->acquireLease("/locked.txt");
    test:assertTrue(afterBreak.length() > 0);
    check fileClient->releaseLease("/locked.txt", afterBreak);
}

// ---------------------------------------------------------------------------
// Share snapshots
// ---------------------------------------------------------------------------

@test:Config {groups: ["mock"]}
function testShareSnapshotLifecycle() returns error? {
    AdminClient admin = check newAdmin();
    check admin->createShare("snap-share");
    Client fileClient = check newShareClient("snap-share");
    check fileClient->uploadContent("version one", "/versioned.txt");
    check fileClient->createDirectory("/snapdir");
    check fileClient->uploadContent("stay", "/snapdir/keep.txt");

    ShareSnapshotInfo snapshot = check fileClient->createShareSnapshot({label: "baseline"});
    test:assertTrue(snapshot.snapshotId.length() > 0);
    test:assertTrue(snapshot.eTag.length() > 0);

    // Mutate the live share after the snapshot.
    check fileClient->uploadContent("version two!", "/versioned.txt");
    check fileClient->deleteFile("/snapdir/keep.txt");

    // Snapshot reads serve the frozen content; the live share serves the new content.
    stream<byte[], Error?> old = check fileClient->getFileContent("/versioned.txt",
            {snapshotId: snapshot.snapshotId});
    test:assertEquals(check collectBytes(old), "version one".toBytes());
    test:assertEquals(check readAll(fileClient, "/versioned.txt"), "version two!".toBytes());

    string localTarget = "target/mock-snapshot-download.txt";
    if check file:test(localTarget, file:EXISTS) {
        check file:remove(localTarget);
    }
    check fileClient->downloadFile("/versioned.txt", localTarget,
            {snapshotId: snapshot.snapshotId});
    test:assertEquals(check io:fileReadString(localTarget), "version one");

    // Snapshot listing still sees the file deleted from the live share.
    stream<Entry, Error?> snapEntries = check fileClient->list("/snapdir",
            {snapshotId: snapshot.snapshotId});
    Entry[] frozen = check collectEntries(snapEntries);
    test:assertEquals(entryPaths(frozen), ["/snapdir/keep.txt"]);
    stream<Entry, Error?> liveEntries = check fileClient->list("/snapdir");
    Entry[] current = check collectEntries(liveEntries);
    test:assertEquals(current.length(), 0);

    ShareSnapshotInfo[] snapshots = check fileClient->listShareSnapshots();
    test:assertEquals(snapshots.length(), 1);
    test:assertEquals(snapshots[0].snapshotId, snapshot.snapshotId);

    check fileClient->deleteShareSnapshot(snapshot.snapshotId);
    ShareSnapshotInfo[] afterDelete = check fileClient->listShareSnapshots();
    test:assertEquals(afterDelete.length(), 0);

    // Reading from the deleted snapshot fails. The failed download still creates the local
    // file, so clear any leftover from a previous run first.
    string missTarget = "target/mock-snapshot-miss.txt";
    if check file:test(missTarget, file:EXISTS) {
        check file:remove(missTarget);
    }
    Error? gone = fileClient->downloadFile("/versioned.txt", missTarget,
            {snapshotId: snapshot.snapshotId});
    test:assertTrue(gone is NotFoundError, "expected a deleted snapshot to read as NotFound");
}

@test:Config {groups: ["mock"]}
function testListRangesDiff() returns error? {
    AdminClient admin = check newAdmin();
    check admin->createShare("diff-share");
    Client fileClient = check newShareClient("diff-share");
    check fileClient->createFile("/diff.bin", 16);
    check fileClient->uploadRange("/diff.bin", 0, "AAAABBBB".toBytes());
    ShareSnapshotInfo baseline = check fileClient->createShareSnapshot();

    // Overwrite the second half of the written region and clear the first.
    check fileClient->uploadRange("/diff.bin", 4, "CCCC".toBytes());
    check fileClient->clearRange("/diff.bin", 0, 4);

    RangeDiff diff = check fileClient->listRangesDiff("/diff.bin", baseline.snapshotId);
    test:assertEquals(diff.ranges, [{startByte: 4, endByte: 7}]);
    test:assertEquals(diff.clearRanges, [{startByte: 0, endByte: 3}]);

    RangeDiff|Error missing = fileClient->listRangesDiff("/diff.bin", "no-such-snapshot");
    test:assertTrue(missing is NotFoundError, "expected an unknown baseline snapshot to fail");
}

// ---------------------------------------------------------------------------
// Property setters, access policy, permissions
// ---------------------------------------------------------------------------

@test:Config {groups: ["mock"]}
function testSetShareProperties() returns error? {
    AdminClient admin = check newAdmin();
    check admin->createShare("set-props-share", {quotaInGb: 5});
    Client fileClient = check newShareClient("set-props-share");

    check fileClient->setShareProperties({quotaInGb: 10, accessTier: HOT});
    ShareProperties props = check fileClient->getShareProperties();
    test:assertEquals(props.quotaInGb, 10);
    test:assertEquals(props.accessTier, HOT);

    // Changing one property leaves the other in place.
    check fileClient->setShareProperties({quotaInGb: 20});
    props = check fileClient->getShareProperties();
    test:assertEquals(props.quotaInGb, 20);
    test:assertEquals(props.accessTier, HOT);
}

@test:Config {groups: ["mock"]}
function testSetFileProperties() returns error? {
    AdminClient admin = check newAdmin();
    check admin->createShare("set-file-share");
    Client fileClient = check newShareClient("set-file-share");
    check fileClient->uploadContent("0123456789", "/resize.bin");
    check fileClient->setContentHeaders("/resize.bin", {contentType: "text/plain"});

    // Shrinking truncates the content; content headers survive because only what is set
    // changes.
    check fileClient->setFileProperties("/resize.bin", {newFileSizeBytes: 4});
    FileProperties props = check fileClient->getFileProperties("/resize.bin");
    test:assertEquals(props.contentLength, 4);
    test:assertEquals(props.contentType, "text/plain");
    test:assertEquals(check readAll(fileClient, "/resize.bin"), "0123".toBytes());

    // Growing pre-allocates zeros past the old end.
    check fileClient->setFileProperties("/resize.bin", {newFileSizeBytes: 6});
    props = check fileClient->getFileProperties("/resize.bin");
    test:assertEquals(props.contentLength, 6);
    test:assertEquals(check readAll(fileClient, "/resize.bin"), [48, 49, 50, 51, 0, 0]);

    // Setting content headers alone keeps the size.
    check fileClient->setFileProperties("/resize.bin",
            {contentHeaders: {contentType: "application/pdf", cacheControl: "no-store"}});
    props = check fileClient->getFileProperties("/resize.bin");
    test:assertEquals(props.contentLength, 6);
    test:assertEquals(props.contentType, "application/pdf");
    test:assertEquals(props.cacheControl, "no-store");
}

@test:Config {groups: ["mock"]}
function testSetDirectoryProperties() returns error? {
    AdminClient admin = check newAdmin();
    check admin->createShare("set-dir-share");
    Client fileClient = check newShareClient("set-dir-share");
    check fileClient->createDirectory("/tuned");

    check fileClient->setDirectoryProperties("/tuned",
            {smbProperties: {ntfsFileAttributes: [READ_ONLY, HIDDEN]}});

    Error? missing = fileClient->setDirectoryProperties("/no-such-dir", {});
    test:assertTrue(missing is NotFoundError, "expected a missing directory to fail");
}

@test:Config {groups: ["mock"]}
function testShareAccessPolicyRoundtrip() returns error? {
    AdminClient admin = check newAdmin();
    check admin->createShare("acl-share");
    Client fileClient = check newShareClient("acl-share");

    SignedIdentifier[] initial = check fileClient->getShareAccessPolicy();
    test:assertEquals(initial.length(), 0);

    time:Utc startsOn = check time:utcFromString("2026-07-01T00:00:00Z");
    time:Utc expiresOn = check time:utcFromString("2026-08-01T00:00:00Z");
    check fileClient->setShareAccessPolicy([
        {id: "read-only-policy", accessPolicy: {startsOn, expiresOn, permissions: "rl"}},
        {id: "write-policy", accessPolicy: {permissions: "w"}}
    ]);

    SignedIdentifier[] stored = check fileClient->getShareAccessPolicy();
    test:assertEquals(stored.length(), 2);
    test:assertEquals(stored[0].id, "read-only-policy");
    test:assertEquals(stored[0].accessPolicy.permissions, "rl");
    test:assertEquals(stored[0].accessPolicy.startsOn, startsOn);
    test:assertEquals(stored[0].accessPolicy.expiresOn, expiresOn);
    test:assertEquals(stored[1].id, "write-policy");
    test:assertEquals(stored[1].accessPolicy.permissions, "w");
    test:assertTrue(stored[1].accessPolicy.startsOn is (), "expected no start time");

    // Setting an empty list clears the policies.
    check fileClient->setShareAccessPolicy([]);
    SignedIdentifier[] cleared = check fileClient->getShareAccessPolicy();
    test:assertEquals(cleared.length(), 0);
}

@test:Config {groups: ["mock"]}
function testSharePermissionStore() returns error? {
    AdminClient admin = check newAdmin();
    check admin->createShare("permission-share");
    Client fileClient = check newShareClient("permission-share");

    string sddl = "O:S-1-5-21-2127521184-1604012920-1887927527-21560751G:S-1-5-21-2127521184-1604012920-1887927527-513D:AI(A;;FA;;;SY)";
    string key = check fileClient->createSharePermission(sddl);
    test:assertTrue(key.length() > 0);

    string fetched = check fileClient->getSharePermission(key);
    test:assertEquals(fetched, sddl);

    string|Error missing = fileClient->getSharePermission("no-such-key");
    test:assertTrue(missing is NotFoundError, "expected an unknown permission key to fail");
}

// ---------------------------------------------------------------------------
// SMB handles
// ---------------------------------------------------------------------------

@test:Config {groups: ["mock"]}
function testSmbHandles() returns error? {
    AdminClient admin = check newAdmin();
    check admin->createShare("handles-share");
    Client fileClient = check newShareClient("handles-share");
    check fileClient->uploadContent("held", "/held.txt");
    check fileClient->uploadContent("free", "/free.txt");
    check fileClient->createDirectory("/hdir");
    check fileClient->uploadContent("held", "/hdir/held.txt");

    HandleInfo[] fileHandles = check fileClient->listFileHandles("/held.txt");
    test:assertEquals(fileHandles.length(), 1);
    test:assertEquals(fileHandles[0].path, "/held.txt");
    test:assertTrue(fileHandles[0].handleId.length() > 0);
    test:assertTrue(fileHandles[0].clientIp is string, "expected the client IP to map");
    test:assertTrue(fileHandles[0].openTime !is (), "expected the open time to map");

    HandleInfo[] none = check fileClient->listFileHandles("/free.txt");
    test:assertEquals(none.length(), 0);

    HandleInfo[] dirHandles = check fileClient->listDirectoryHandles("/hdir");
    test:assertEquals(dirHandles.length(), 1);
    test:assertEquals(dirHandles[0].path, "/hdir/held.txt");

    CloseHandlesInfo closedOne = check fileClient->forceCloseFileHandles("/held.txt", "1");
    test:assertEquals(closedOne.closedHandles, 1);
    test:assertEquals(closedOne.failedHandles, 0);

    CloseHandlesInfo closedAll = check fileClient->forceCloseDirectoryHandles("/hdir",
            recursive = true);
    test:assertEquals(closedAll.closedHandles, 1);
}

// ---------------------------------------------------------------------------
// Service properties and user delegation
// ---------------------------------------------------------------------------

@test:Config {groups: ["mock"]}
function testServicePropertiesRoundtrip() returns error? {
    AdminClient admin = check newAdmin();

    ServiceProperties desired = {
        hourMetrics: {enabled: true, includeApis: true, retentionDays: 7},
        minuteMetrics: {enabled: false},
        cors: [
            {
                allowedOrigins: "https://example.com",
                allowedMethods: "GET,PUT",
                allowedHeaders: "x-ms-meta-target*",
                exposedHeaders: "x-ms-meta-source*",
                maxAgeInSeconds: 300
            }
        ],
        protocol: {smbMultichannelEnabled: true}
    };
    check admin->setServiceProperties(desired);

    ServiceProperties stored = check admin->getServiceProperties();
    Metrics? hour = stored.hourMetrics;
    if hour is Metrics {
        test:assertEquals(hour.enabled, true);
        test:assertEquals(hour.includeApis, true);
        test:assertEquals(hour.retentionDays, 7);
        test:assertEquals(hour.version, "1.0");
    } else {
        test:assertFail("expected hour metrics to round-trip");
    }
    Metrics? minute = stored.minuteMetrics;
    if minute is Metrics {
        test:assertEquals(minute.enabled, false);
        test:assertTrue(minute.retentionDays is (), "expected no retention when unset");
    } else {
        test:assertFail("expected minute metrics to round-trip");
    }
    test:assertEquals(stored.cors, desired.cors);
    ProtocolSettings? protocol = stored.protocol;
    test:assertEquals(protocol?.smbMultichannelEnabled, true);
}

@test:Config {groups: ["mock"]}
function testGetUserDelegationKey() returns error? {
    AdminClient admin = check newAdmin();
    time:Utc keyStart = check time:utcFromString("2026-07-19T00:00:00.000Z");
    time:Utc keyExpiry = check time:utcFromString("2026-07-20T00:00:00.000Z");

    UserDelegationKey key = check admin->getUserDelegationKey(keyStart, keyExpiry);
    test:assertEquals(key.signedObjectId, "mock-oid");
    test:assertEquals(key.signedTenantId, "mock-tid");
    test:assertEquals(key.signedStart, keyStart);
    test:assertEquals(key.signedExpiry, keyExpiry);
    test:assertEquals(key.signedService, "f");
    test:assertEquals(key.signedVersion, "2025-05-05");
    test:assertEquals(key.value, "bW9jay11ZGstdmFsdWU=");
}

// ---------------------------------------------------------------------------
// SAS generation
// ---------------------------------------------------------------------------

@test:Config {groups: ["mock"]}
function testGenerateShareAndFileSas() returns error? {
    AdminClient admin = check newAdmin();
    check admin->createShare("sas-share");
    Client fileClient = check newShareClient("sas-share");
    time:Utc expiry = check time:utcFromString("2026-08-01T00:00:00Z");

    string shareSas = check fileClient->generateShareSas(
            {expiryTime: expiry, permissions: {read: true, list: true}});
    map<string> shareParams = sasParams(shareSas);
    test:assertEquals(shareParams["sp"], "rl");
    test:assertTrue(shareParams.hasKey("sig"), "expected a signature");
    test:assertTrue(shareParams.hasKey("se"), "expected an expiry");
    test:assertTrue(shareParams.hasKey("sv"), "expected a service version");
    test:assertFalse(shareParams.hasKey("st"), "expected no start time when unset");

    string fileSas = check fileClient->generateSas("/data.txt", {
        expiryTime: expiry,
        permissions: {read: true, write: true},
        protocol: HTTPS,
        ipRange: "168.1.5.60-168.1.5.70",
        startTime: check time:utcFromString("2026-07-01T00:00:00Z")
    });
    map<string> fileParams = sasParams(fileSas);
    test:assertEquals(fileParams["sp"], "rw");
    test:assertEquals(fileParams["spr"], "https");
    test:assertEquals(fileParams["sip"], "168.1.5.60-168.1.5.70");
    test:assertTrue(fileParams.hasKey("st"), "expected the start time to be included");

    // Signing needs the account key: a SAS-authenticated client cannot mint tokens.
    Client sasClient = check new ("sas-share", auth = {
        sasUrl: string `http://localhost:${MOCK_PORT}?sv=2025-05-05&sp=rl&se=2026-08-01T00%3A00%3A00Z&sig=ZmFrZQ%3D%3D`
    });
    string|Error denied = sasClient->generateShareSas(
            {expiryTime: expiry, permissions: {read: true}});
    test:assertTrue(denied is ProcessingError,
            "expected SAS generation without an account key to fail");
}

@test:Config {groups: ["mock"]}
function testGenerateUserDelegationSas() returns error? {
    AdminClient admin = check newAdmin();
    check admin->createShare("uds-share");
    Client fileClient = check newShareClient("uds-share");
    UserDelegationKey key = check admin->getUserDelegationKey(
            check time:utcFromString("2026-07-19T00:00:00.000Z"),
            check time:utcFromString("2026-07-26T00:00:00.000Z"));
    time:Utc expiry = check time:utcFromString("2026-07-25T00:00:00Z");

    string shareToken = check fileClient->generateShareUserDelegationSas(
            {expiryTime: expiry, permissions: {read: true}}, key);
    map<string> shareParams = sasParams(shareToken);
    test:assertEquals(shareParams["sp"], "r");
    test:assertEquals(shareParams["skoid"], "mock-oid");
    test:assertTrue(shareParams.hasKey("sig"), "expected a signature");

    string fileToken = check fileClient->generateUserDelegationSas("/f.txt",
            {expiryTime: expiry, permissions: {read: true, delete: true}}, key);
    map<string> fileParams = sasParams(fileToken);
    test:assertEquals(fileParams["sp"], "rd");
    test:assertEquals(fileParams["sktid"], "mock-tid");
}

@test:Config {groups: ["mock"]}
function testGenerateAccountSas() returns error? {
    AdminClient admin = check newAdmin();
    time:Utc expiry = check time:utcFromString("2026-08-01T00:00:00Z");

    string accountSas = check admin->generateAccountSas({
        expiryTime: expiry,
        permissions: {read: true, write: true, list: true},
        resourceTypes: {'service: true, container: true, 'object: true}
    });
    map<string> params = sasParams(accountSas);
    test:assertEquals(params["ss"], "f");
    test:assertEquals(params["srt"], "sco");
    test:assertEquals(params["sp"], "rwl");
    test:assertTrue(params.hasKey("sig"), "expected a signature");
}

// ---------------------------------------------------------------------------
// NFS links
// ---------------------------------------------------------------------------

@test:Config {groups: ["mock"]}
function testNfsLinks() returns error? {
    AdminClient admin = check newAdmin();
    check admin->createShare("nfs-share");
    Client fileClient = check newShareClient("nfs-share");
    check fileClient->uploadContent("original", "/original.txt");

    // A hard link reads the same content as its target.
    check fileClient->createHardLink("/link.txt", "/original.txt");
    test:assertEquals(check readAll(fileClient, "/link.txt"), "original".toBytes());

    // A hard link to a missing target fails.
    Error? missing = fileClient->createHardLink("/dangling.txt", "/no-such.txt");
    test:assertTrue(missing is NotFoundError, "expected a missing hard-link target to fail");

    // A symbolic link stores its target text verbatim, resolved only by NFS clients.
    check fileClient->createSymbolicLink("/pointer.txt", "../elsewhere/target.txt");
    string linkText = check fileClient->getSymbolicLink("/pointer.txt");
    test:assertEquals(linkText, "../elsewhere/target.txt");

    string|Error notALink = fileClient->getSymbolicLink("/original.txt");
    test:assertTrue(notALink is Error, "expected reading a non-link to fail");
}

// ---------------------------------------------------------------------------
// Core gap-fills
// ---------------------------------------------------------------------------

@test:Config {groups: ["mock"]}
function testRenameReplaceIfExists() returns error? {
    AdminClient admin = check newAdmin();
    check admin->createShare("rename-share");
    Client fileClient = check newShareClient("rename-share");
    check fileClient->uploadContent("new", "/incoming.txt");
    check fileClient->uploadContent("old", "/settled.txt");

    // An existing destination conflicts unless replaceIfExists is set.
    Error? clash = fileClient->renameFile("/incoming.txt", "/settled.txt");
    test:assertTrue(clash is ConflictError, "expected an existing destination to conflict");

    check fileClient->renameFile("/incoming.txt", "/settled.txt", {replaceIfExists: true});
    test:assertEquals(check readAll(fileClient, "/settled.txt"), "new".toBytes());
    boolean sourceStillThere = check fileClient->hasFile("/incoming.txt");
    test:assertFalse(sourceStillThere);
}

@test:Config {groups: ["mock"]}
function testLargeUploadSplitsIntoRanges() returns error? {
    AdminClient admin = check newAdmin();
    check admin->createShare("large-share");
    Client fileClient = check newShareClient("large-share");

    // 4 MiB is the service's maximum single-range size, so this upload must split.
    final int rangeCap = 4 * 1024 * 1024;
    string big = "".padStart(rangeCap, "A") + "TAIL";
    check fileClient->uploadContent(big, "/large.bin");

    FileProperties props = check fileClient->getFileProperties("/large.bin");
    test:assertEquals(props.contentLength, rangeCap + 4);

    // Read across the split boundary: the last bytes of range one, the first of range two.
    stream<byte[], Error?> boundary = check fileClient->getFileContent("/large.bin",
            {range: {startByte: rangeCap - 2, endByte: rangeCap + 1}});
    test:assertEquals(check collectBytes(boundary), "AATA".toBytes());
}

@test:Config {groups: ["mock"]}
function testEarlyStreamClose() returns error? {
    AdminClient admin = check newAdmin();
    check admin->createShare("close-share");
    Client fileClient = check newShareClient("close-share");
    check fileClient->uploadContent("0123456789", "/close.txt");
    check fileClient->createDirectory("/somedir");

    stream<byte[], Error?> content = check fileClient->getFileContent("/close.txt");
    record {|byte[] value;|}|Error? first = content.next();
    test:assertTrue(first is record {|byte[] value;|}, "expected a first chunk before closing");
    check content.close();

    stream<Entry, Error?> entries = check fileClient->list("/");
    check entries.close();
}

// A byte source that fails after its first chunk, driving the source-error path of
// uploadFromStream.
class FailingByteSource {
    private boolean first = true;

    public isolated function next() returns record {|byte[] value;|}|error? {
        lock {
            if self.first {
                self.first = false;
                return {value: "abc".toBytes()};
            }
        }
        return error("the source broke");
    }
}

@test:Config {groups: ["mock"]}
function testStreamFailurePaths() returns error? {
    AdminClient admin = check newAdmin();
    check admin->createShare("stream-fail-share");
    Client fileClient = check newShareClient("stream-fail-share");

    stream<Entry, Error?>|Error missingDirectory = fileClient->list("/no-such-dir");
    test:assertTrue(missingDirectory is NotFoundError,
            "expected listing a missing directory to fail");

    stream<byte[], Error?>|Error missingContent = fileClient->getFileContent("/absent.txt");
    if missingContent is Error {
        test:assertTrue(missingContent is NotFoundError,
                "expected opening a missing file to fail as NotFound");
    } else {
        byte[]|error collected = collectBytes(missingContent);
        test:assertTrue(collected is error, "expected reading a missing file to fail");
    }

    stream<byte[], error?> failingSource = new (new FailingByteSource());
    Error? aborted = fileClient->uploadFromStream(failingSource, 10, "/failed.txt");
    test:assertTrue(aborted is ProcessingError, "expected a failing source stream to abort");
}

@test:Config {groups: ["mock"]}
function testUploadFromStreamOverflow() returns error? {
    AdminClient admin = check newAdmin();
    check admin->createShare("overflow-share");
    Client fileClient = check newShareClient("overflow-share");

    byte[][] longChunks = ["abcdef".toBytes(), "ghijkl".toBytes()];
    Error? overflow = fileClient->uploadFromStream(longChunks.toStream(), 5, "/overflow.txt");
    test:assertTrue(overflow is ProcessingError,
            "expected a stream longer than contentLength to fail");
}

@test:Config {groups: ["mock"]}
function testConnectionStringClientOps() returns error? {
    AdminClient admin = check newAdmin();
    check admin->createShare("cs-share");
    Client fileClient = check new ("cs-share", auth = {
        connectionString: string `DefaultEndpointsProtocol=http;AccountName=mockaccount;AccountKey=${MOCK_KEY};FileEndpoint=http://localhost:${MOCK_PORT}`
    });
    check fileClient->uploadContent("via connection string", "/cs.txt");
    test:assertEquals(check readAll(fileClient, "/cs.txt"), "via connection string".toBytes());
}

@test:Config {groups: ["mock"]}
function testClosedAdminClientFails() returns error? {
    AdminClient admin = check newAdmin();
    check admin.close();
    boolean|Error result = admin->hasShare("any-share");
    test:assertTrue(result is ProcessingError, "expected an op on a closed admin client to fail");
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

isolated function sasParams(string token) returns map<string> {
    map<string> params = {};
    string query = token.startsWith("?") ? token.substring(1) : token;
    foreach string pair in re `&`.split(query) {
        string[] parts = re `=`.split(pair);
        if parts.length() >= 2 {
            params[parts[0]] = parts[1];
        }
    }
    return params;
}
