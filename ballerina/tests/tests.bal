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

// The connector test suite. Every test treats live Azure as the ground truth: when live
// credentials are configured (see backend.bal), the tests run against the real account;
// otherwise they run against the in-process mock FileREST service, so the whole suite
// works on any machine with no Azure account. A few tests are pinned to the mock because
// the condition they exercise cannot be produced on a real account on demand (forced
// service errors, transport failures, open SMB handles); the Microsoft Entra ID auth
// tests run only live because mocking the identity service would exercise Microsoft's
// SDK rather than this connector.

import ballerina/file;
import ballerina/io;
import ballerina/test;
import ballerina/time;

// ---------------------------------------------------------------------------
// init validation (no service involved)
// ---------------------------------------------------------------------------

@test:Config {}
function testInitRejectsBadBase64Key() {
    Client|Error result = new ("share", auth = {accountName: "acct", accountKey: "not base64!!!"});
    test:assertTrue(result is ProcessingError, "expected a ProcessingError for a non-base64 key");
}

@test:Config {}
function testInitRejectsEmptyAccountName() {
    Client|Error result = new ("share", auth = {accountName: "  ", accountKey: MOCK_KEY});
    test:assertTrue(result is ProcessingError, "expected a ProcessingError for an empty account name");
}

@test:Config {}
function testInitRejectsBadServiceUrl() {
    Client|Error result = new ("share",
            auth = {accountName: "acct", accountKey: MOCK_KEY, serviceUrl: "ftp://example.com"});
    test:assertTrue(result is ProcessingError, "expected a ProcessingError for a non-http serviceUrl");
}

@test:Config {}
function testInitRejectsEmptyShareName() {
    Client|Error result = new ("", auth = {accountName: "acct", accountKey: MOCK_KEY});
    test:assertTrue(result is ProcessingError, "expected a ProcessingError for an empty share name");
}

@test:Config {}
function testInitRejectsSasUrlWithoutSignature() {
    Client|Error result = new ("share", auth = {sasUrl: "https://acct.file.core.windows.net/?sv=2024"});
    test:assertTrue(result is ProcessingError, "expected a ProcessingError for a SAS URL without sig=");
}

@test:Config {}
function testInitRejectsConnectionStringWithoutEndpoint() {
    Client|Error result = new ("share",
            auth = {connectionString: "DefaultEndpointsProtocol=https;AccountKey=" + MOCK_KEY});
    test:assertTrue(result is ProcessingError,
            "expected a ProcessingError for a connection string without FileEndpoint/AccountName");
}

@test:Config {}
function testInitAcceptsConnectionString() {
    Client|Error result = new ("share", auth = {connectionString: testConnectionString()});
    test:assertTrue(result is Client, "expected a connection-string client to initialize");
}

@test:Config {}
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

@test:Config {}
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

// Pinned to the mock: retry and proxy behavior only manifests against an endpoint that
// can be made to fail on demand.
@test:Config {}
function testRetryAndTransportConfig() returns error? {
    AdminClient admin = check newMockAdmin();
    string share = testShare("transport-config");
    check admin->createShare(share);

    // A tuned retry policy still round-trips content.
    Client retryClient = check new (share, auth = {
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
    Client pooledClient = check new (share, auth = {
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
    Client proxied = check new (share, auth = {
        accountName: "mockaccount",
        accountKey: MOCK_KEY,
        serviceUrl: string `http://localhost:${MOCK_PORT}`
    }, transportConfig = {proxy: {proxyType: HTTP, host: "localhost", port: 39999}});
    Error? throughDeadProxy = proxied->uploadContent("x", "/proxied.txt");
    test:assertTrue(throughDeadProxy is ProcessingError,
            "expected a request through an unreachable proxy to fail");
    check proxied.close();
}

@test:Config {}
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

@test:Config {}
function testClosedClientFails() returns error? {
    Client fileClient = check newShareClient("closed-share");
    check fileClient.close();
    boolean|Error result = fileClient->hasFile("/a.txt");
    test:assertTrue(result is ProcessingError, "expected an op on a closed client to fail");
}

// ---------------------------------------------------------------------------
// AdminClient share management
// ---------------------------------------------------------------------------

@test:Config {}
function testShareLifecycle() returns error? {
    AdminClient admin = check newAdmin();
    string share = testShare("lifecycle");
    check admin->createShare(share, {quotaInGb: 100, metadata: {owner: "tests"}});
    boolean actionResult1 = check admin->hasShare(share);
    test:assertTrue(actionResult1);
    // Built directly, not via testShare: a second testShare call inside a test would
    // roll-clean the test's own share.
    boolean actionResult2 = check admin->hasShare(string `${share}-absent`);
    test:assertFalse(actionResult2);

    // Listing can lag share creation.
    check await(function() returns boolean|error {
        ShareInfo[] listed = check admin->listShares({prefix: share, includeMetadata: true});
        return listed.length() == 1;
    });
    ShareInfo[] shares = check admin->listShares({prefix: share, includeMetadata: true});
    test:assertEquals(shares.length(), 1);
    test:assertEquals(shares[0].name, share);
    test:assertEquals(shares[0].properties.quotaInGb, 100);
    test:assertEquals(shares[0].metadata, {owner: "tests"});

    check admin->deleteShare(share);
    boolean actionResult3 = check admin->hasShare(share);
    test:assertFalse(actionResult3);

    if check isPremiumAccount() {
        // The premium test account runs without share soft delete (a soft-deleted premium
        // share keeps holding its provisioned IOPS against the account limit), so the
        // undelete tail is exercised on standard accounts and the mock.
        check admin.close();
        return;
    }

    // A soft-deleted share surfaces in the deleted listing only after the deletion
    // settles, and undelete can conflict while it is still in progress.
    check await(function() returns boolean|error {
        ShareInfo[] deletedNow = check admin->listShares({prefix: share, includeDeleted: true});
        return deletedNow.length() == 1 && deletedNow[0].isDeleted == true
            && deletedNow[0].version is string;
    });
    ShareInfo[] deleted = check admin->listShares({prefix: share, includeDeleted: true});
    test:assertEquals(deleted[0].isDeleted, true);
    string version = deleted[0].version ?: "";
    check await(function() returns boolean|error {
        Error? undeleted = admin->undeleteShare(share, version);
        if undeleted is ConflictError {
            return false;
        }
        if undeleted is Error {
            return undeleted;
        }
        return true;
    });
    check await(function() returns boolean|error {
        boolean|Error present = admin->hasShare(share);
        return present;
    });
    check admin.close();
}

@test:Config {}
function testCreateShareTwiceConflicts() returns error? {
    AdminClient admin = check newAdmin();
    string share = testShare("dup");
    check admin->createShare(share);
    Error? result = admin->createShare(share);
    test:assertTrue(result is ConflictError, "expected a ConflictError for a duplicate share");
}

// ---------------------------------------------------------------------------
// Client share ops
// ---------------------------------------------------------------------------

@test:Config {}
function testSharePropertiesAndUsage() returns error? {
    AdminClient admin = check newAdmin();
    string share = testShare("props");
    check admin->createShare(share, {quotaInGb: 40});
    Client fileClient = check newShareClient(share);

    ShareProperties props = check fileClient->getShareProperties();
    test:assertEquals(props.quotaInGb, 40);
    if check isPremiumAccount() {
        // Premium shares carry provisioned throughput figures. (The tier label is not
        // asserted: classic accounts report Premium, provisioned v2 a legacy label.)
        test:assertTrue(props.provisionedIops is int,
                "expected provisioned IOPS on a premium share");
    } else {
        test:assertEquals(props.accessTier, TRANSACTION_OPTIMIZED);
    }
    test:assertTrue(props.eTag.length() > 0);

    check fileClient->setShareMetadata({env: "mock"});
    props = check fileClient->getShareProperties();
    test:assertEquals(props.metadata, {env: "mock"});

    int actionResult15 = check fileClient->getShareUsage();
    test:assertEquals(actionResult15, 0);
    check fileClient->uploadContent("12345", "/usage.txt");
    // Share statistics can lag recent writes.
    check await(function() returns boolean|error {
        int usage = check fileClient->getShareUsage();
        return usage == 5;
    });
}

// ---------------------------------------------------------------------------
// Directories
// ---------------------------------------------------------------------------

@test:Config {}
function testDirectoryLifecycle() returns error? {
    AdminClient admin = check newAdmin();
    string share = testShare("dir");
    check admin->createShare(share);
    Client fileClient = check newShareClient(share);

    check fileClient->createDirectory("/docs");
    check fileClient->createDirectory("/docs/2026", {metadata: {year: "2026"}});
    boolean actionResult5 = check fileClient->hasDirectory("/docs/2026");
    test:assertTrue(actionResult5);
    boolean actionResult6 = check fileClient->hasDirectory("/docs/2030");
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
    boolean actionResult7 = check fileClient->hasDirectory("/archive");
    test:assertTrue(actionResult7);
    boolean actionResult8 = check fileClient->hasDirectory("/docs/2026");
    test:assertFalse(actionResult8);
    check fileClient->deleteDirectory("/archive");
    check fileClient->deleteDirectory("/docs");
}

@test:Config {}
function testDeleteNonEmptyDirectoryConflicts() returns error? {
    AdminClient admin = check newAdmin();
    string share = testShare("nonempty");
    check admin->createShare(share);
    Client fileClient = check newShareClient(share);
    check fileClient->createDirectory("/keep");
    check fileClient->uploadContent("x", "/keep/file.txt");
    Error? result = fileClient->deleteDirectory("/keep");
    test:assertTrue(result is ConflictError, "expected DirectoryNotEmpty to map to ConflictError");
}

// ---------------------------------------------------------------------------
// Files
// ---------------------------------------------------------------------------

@test:Config {}
function testFileLifecycle() returns error? {
    AdminClient admin = check newAdmin();
    string share = testShare("file");
    check admin->createShare(share);
    Client fileClient = check newShareClient(share);

    check fileClient->createFile("/report.bin", 16, {metadata: {kind: "report"}});
    boolean actionResult9 = check fileClient->hasFile("/report.bin");
    test:assertTrue(actionResult9);
    boolean actionResult10 = check fileClient->hasFile("/missing.bin");
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
    boolean actionResult11 = check fileClient->hasFile("/report.bin");
    test:assertFalse(actionResult11);
    boolean actionResult12 = check fileClient->hasFile("/final.bin");
    test:assertTrue(actionResult12);

    check fileClient->deleteFile("/final.bin");
    boolean actionResult13 = check fileClient->hasFile("/final.bin");
    test:assertFalse(actionResult13);

    FileProperties|Error missing = fileClient->getFileProperties("/final.bin");
    test:assertTrue(missing is NotFoundError, "expected NotFoundError for a deleted file");
}

// ---------------------------------------------------------------------------
// Transfer ops
// ---------------------------------------------------------------------------

@test:Config {}
function testUploadContentVariantsAndDownloadStream() returns error? {
    AdminClient admin = check newAdmin();
    string share = testShare("content");
    check admin->createShare(share);
    Client fileClient = check newShareClient(share);

    check fileClient->uploadContent("hello mock", "/text.txt");
    test:assertEquals(check readAll(fileClient, "/text.txt"), "hello mock".toBytes());

    byte[] binary = [1, 2, 3, 4, 5];
    check fileClient->uploadContent(binary, "/binary.bin");
    test:assertEquals(check readAll(fileClient, "/binary.bin"), binary);

    check fileClient->uploadContent({metric: 42}, "/data.json");
    byte[] jsonBytes = check readAll(fileClient, "/data.json");
    test:assertEquals(jsonBytes, "{\"metric\":42}".toBytes());
    // The downloaded bytes parse back to the value that was uploaded.
    string jsonText = check string:fromBytes(jsonBytes);
    json reparsedJson = check jsonText.fromJsonString();
    test:assertEquals(reparsedJson, <json>{metric: 42});

    xml document = xml `<report><value>1</value></report>`;
    check fileClient->uploadContent(document, "/doc.xml");
    byte[] xmlBytes = check readAll(fileClient, "/doc.xml");
    test:assertEquals(xmlBytes, document.toString().toBytes());
    xml reparsedXml = check xml:fromString(check string:fromBytes(xmlBytes));
    test:assertEquals(reparsedXml, document);
}

@test:Config {}
function testUploadAndDownloadLocalFile() returns error? {
    AdminClient admin = check newAdmin();
    string share = testShare("transfer");
    check admin->createShare(share);
    Client fileClient = check newShareClient(share);

    string localSource = "target/mock-upload-source.txt";
    string localDestination = "target/mock-download-target.txt";
    check io:fileWriteString(localSource, "round trip payload");
    if check file:test(localDestination, file:EXISTS) {
        check file:remove(localDestination);
    }

    check fileClient->uploadFile(localSource, "/roundtrip.txt");
    boolean actionResult14 = check fileClient->hasFile("/roundtrip.txt");
    test:assertTrue(actionResult14);

    check fileClient->downloadFile("/roundtrip.txt", localDestination);
    test:assertEquals(check io:fileReadString(localDestination), "round trip payload");

    // The destination must not already exist (CREATE_NEW contract).
    Error? again = fileClient->downloadFile("/roundtrip.txt", localDestination);
    test:assertTrue(again is ProcessingError, "expected an existing local file to fail the download");

    Error? missingLocal = fileClient->uploadFile("target/does-not-exist.txt", "/x.txt");
    test:assertTrue(missingLocal is ProcessingError, "expected a missing local file to fail the upload");
}

@test:Config {}
function testUploadFromStream() returns error? {
    AdminClient admin = check newAdmin();
    string share = testShare("stream");
    check admin->createShare(share);
    Client fileClient = check newShareClient(share);

    byte[][] chunks = ["abc".toBytes(), "defg".toBytes(), "hi".toBytes()];
    check fileClient->uploadFromStream(chunks.toStream(), 9, "/streamed.txt");
    test:assertEquals(check readAll(fileClient, "/streamed.txt"), "abcdefghi".toBytes());

    // A declared length that does not match the stream fails with a ProcessingError.
    byte[][] shortChunks = ["abc".toBytes()];
    Error? shortResult = fileClient->uploadFromStream(shortChunks.toStream(), 9, "/short.txt");
    test:assertTrue(shortResult is ProcessingError, "expected a short stream to fail");
}

@test:Config {}
function testRangedDownload() returns error? {
    AdminClient admin = check newAdmin();
    string share = testShare("range-read");
    check admin->createShare(share);
    Client fileClient = check newShareClient(share);
    check fileClient->uploadContent("0123456789", "/digits.txt");

    stream<byte[], Error?> content =
        check fileClient->getFileContent("/digits.txt", {range: {startByte: 2, endByte: 5}});
    test:assertEquals(check collectBytes(content), "2345".toBytes());
}

// ---------------------------------------------------------------------------
// Listing
// ---------------------------------------------------------------------------

@test:Config {}
function testListFlatAndRecursive() returns error? {
    AdminClient admin = check newAdmin();
    string share = testShare("list");
    check admin->createShare(share);
    Client fileClient = check newShareClient(share);
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

@test:Config {}
function testCopyWithinShare() returns error? {
    AdminClient admin = check newAdmin();
    string share = testShare("copy");
    check admin->createShare(share);
    Client fileClient = check newShareClient(share);
    check fileClient->uploadContent("copy me", "/source.txt");

    CopyInfo info = check fileClient->copyFile("/source.txt", "/target.txt");
    test:assertTrue(info.copyId.length() > 0);
    // A copy can be briefly pending even within a share.
    check await(function() returns boolean|error {
        CopyStatusInfo? pending = check fileClient->checkCopyStatus("/target.txt");
        return pending is CopyStatusInfo && pending.copyStatus == SUCCESS;
    });
    test:assertEquals(check readAll(fileClient, "/target.txt"), "copy me".toBytes());

    CopyStatusInfo? status = check fileClient->checkCopyStatus("/target.txt");
    if status is CopyStatusInfo {
        test:assertEquals(status.copyStatus, SUCCESS);
        test:assertEquals(status.copyId, info.copyId);
    } else {
        test:assertFail("expected copy status on the destination file");
    }

    // A file that was never a copy destination reports no status.
    CopyStatusInfo? actionResult17 = check fileClient->checkCopyStatus("/source.txt");
    test:assertEquals(actionResult17, ());

    // The copy has already completed, so an abort conflicts.
    Error? abort = fileClient->abortCopy("/target.txt", info.copyId);
    test:assertTrue(abort is Error, "expected abortCopy on a finished copy to fail");
}

@test:Config {}
function testCopyFromUrl() returns error? {
    AdminClient admin = check newAdmin();
    string share = testShare("copy-url");
    check admin->createShare(share);
    Client fileClient = check newShareClient(share);
    check fileClient->uploadContent("via url", "/origin.txt");

    // The service fetches the source URL itself, so it carries a read SAS; the mock
    // ignores the token while live Azure verifies it.
    time:Utc sourceExpiry = time:utcAddSeconds(time:utcNow(), 3600);
    string token = check fileClient->generateSas("/origin.txt",
            {expiryTime: sourceExpiry, permissions: {read: true}});
    string sourceUrl = string `${sasBaseUrl()}/${share}/origin.txt?${token}`;
    CopyInfo info = check fileClient->copyFileFromUrl(sourceUrl, "/copied.txt");
    test:assertTrue(info.copyId.length() > 0);
    check await(function() returns boolean|error {
        CopyStatusInfo? status = check fileClient->checkCopyStatus("/copied.txt");
        return status is CopyStatusInfo && status.copyStatus == SUCCESS;
    });
    test:assertEquals(check readAll(fileClient, "/copied.txt"), "via url".toBytes());
}

// ---------------------------------------------------------------------------
// Range ops
// ---------------------------------------------------------------------------

@test:Config {}
function testRangeWriteClearAndList() returns error? {
    AdminClient admin = check newAdmin();
    string share = testShare("ranges");
    check admin->createShare(share);
    Client fileClient = check newShareClient(share);
    check fileClient->createFile("/ranges.bin", 8);

    Range[] empty = check fileClient->listRanges("/ranges.bin");
    test:assertEquals(empty.length(), 0);

    check fileClient->uploadRange("/ranges.bin", 0, "ABCDEFGH".toBytes());
    Range[] written = check fileClient->listRanges("/ranges.bin");
    test:assertEquals(written, [{startByte: 0, endByte: 7}]);
    test:assertEquals(check readAll(fileClient, "/ranges.bin"), "ABCDEFGH".toBytes());

    check fileClient->clearRange("/ranges.bin", 0, 8);
    // The cleared bytes read back as zeros. Live Azure deallocates ranges in 512-byte
    // pages, so a sub-page clear zeroes the bytes while the range stays listed; the mock
    // tracks exact ranges and drops it.
    test:assertEquals(check readAll(fileClient, "/ranges.bin"), [0, 0, 0, 0, 0, 0, 0, 0]);
    if !liveRun {
        Range[] cleared = check fileClient->listRanges("/ranges.bin");
        test:assertEquals(cleared.length(), 0);
    }

    // Writing past the pre-allocated size is rejected by the service.
    Error? overflow = fileClient->uploadRange("/ranges.bin", 4, "TOO LONG!".toBytes());
    test:assertTrue(overflow is RangeNotSatisfiableError,
            "expected InvalidRange to map to RangeNotSatisfiableError");
}

// ---------------------------------------------------------------------------
// Error mapping
// ---------------------------------------------------------------------------

// Pinned to the mock: these error codes (quota exhaustion, forced 500s) cannot be
// provoked on a real account on demand; the realistic codes are covered live by the
// negative assertions in the ordinary tests.
@test:Config {}
function testErrorCodeMapping() returns error? {
    AdminClient admin = check newMockAdmin();
    string share = testShare("errors");
    check admin->createShare(share);
    Client fileClient = check newMockShareClient(share);

    FileProperties|Error quota = fileClient->getFileProperties("/__err-403-ShareSizeLimitReached");
    test:assertTrue(quota is QuotaExceededError, "403 ShareSizeLimitReached should map to QuotaExceededError");

    FileProperties|Error smbFull = fileClient->getFileProperties("/__err-403-SmbShareFull");
    test:assertTrue(smbFull is QuotaExceededError, "403 SmbShareFull should map to QuotaExceededError");

    FileProperties|Error auth = fileClient->getFileProperties("/__err-403-AuthenticationFailed");
    test:assertTrue(auth is AuthorizationError, "403 AuthenticationFailed should map to AuthorizationError");

    // The code Azure returns for an Entra ID identity lacking the required RBAC role.
    FileProperties|Error rbac = fileClient->getFileProperties("/__err-403-AuthorizationPermissionMismatch");
    test:assertTrue(rbac is AuthorizationError,
            "403 AuthorizationPermissionMismatch should map to AuthorizationError");

    // A SAS used outside its permitted IP range.
    FileProperties|Error sasIp = fileClient->getFileProperties("/__err-403-AuthorizationSourceIPMismatch");
    test:assertTrue(sasIp is AuthorizationError,
            "403 AuthorizationSourceIPMismatch should map to AuthorizationError");

    FileProperties|Error precondition = fileClient->getFileProperties("/__err-412-ConditionNotMet");
    test:assertTrue(precondition is PreconditionFailedError,
            "412 ConditionNotMet should map to PreconditionFailedError");

    // Lease-id requirements on data operations are preconditions, unlike the 409 conflicts
    // the lease operations themselves raise.
    FileProperties|Error leaseMissing = fileClient->getFileProperties("/__err-412-LeaseIdMissing");
    test:assertTrue(leaseMissing is PreconditionFailedError,
            "412 LeaseIdMissing should map to PreconditionFailedError");

    FileProperties|Error leaseMismatch =
            fileClient->getFileProperties("/__err-412-LeaseIdMismatchWithFileOperation");
    test:assertTrue(leaseMismatch is PreconditionFailedError,
            "412 LeaseIdMismatchWithFileOperation should map to PreconditionFailedError");

    FileProperties|Error leaseLost = fileClient->getFileProperties("/__err-412-LeaseLost");
    test:assertTrue(leaseLost is PreconditionFailedError,
            "412 LeaseLost should map to PreconditionFailedError");

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

@test:Config {}
function testShareLeaseLifecycle() returns error? {
    AdminClient admin = check newAdmin();
    string share = testShare("share-lease");
    check admin->createShare(share);
    Client fileClient = check newShareClient(share);

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
    test:assertTrue(props.leaseState is ()|AVAILABLE, "expected no lease after release");

    // Breaking with no lease in place conflicts.
    int|Error nothingToBreak = fileClient->breakShareLease();
    test:assertTrue(nothingToBreak is ConflictError,
            "expected breaking without a lease to conflict");

    // Break reports how long until the lease is gone; the service may round the
    // remaining time down.
    string reacquired = check fileClient->acquireShareLease(15);
    test:assertTrue(reacquired.length() > 0);
    int remaining = check fileClient->breakShareLease(5);
    test:assertTrue(remaining >= 0 && remaining <= 5,
            "expected the break period to be at most the requested 5s");
}

@test:Config {}
function testFileLeaseLifecycle() returns error? {
    AdminClient admin = check newAdmin();
    string share = testShare("file-lease");
    check admin->createShare(share);
    Client fileClient = check newShareClient(share);
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
    test:assertTrue(props.leaseState is ()|AVAILABLE, "expected no lease after release");

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

@test:Config {}
function testShareSnapshotLifecycle() returns error? {
    AdminClient admin = check newAdmin();
    string share = testShare("snap");
    check admin->createShare(share);
    Client fileClient = check newShareClient(share);
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

@test:Config {}
function testListRangesDiff() returns error? {
    AdminClient admin = check newAdmin();
    string share = testShare("diff");
    check admin->createShare(share);
    Client fileClient = check newShareClient(share);
    check fileClient->createFile("/diff.bin", 16);
    check fileClient->uploadRange("/diff.bin", 0, "AAAABBBB".toBytes());
    ShareSnapshotInfo baseline = check fileClient->createShareSnapshot();

    // Overwrite the second half of the written region and clear the first.
    check fileClient->uploadRange("/diff.bin", 4, "CCCC".toBytes());
    check fileClient->clearRange("/diff.bin", 0, 4);

    RangeDiff diff = check fileClient->listRangesDiff("/diff.bin", baseline.snapshotId);
    if liveRun {
        // Live range accounting works in 512-byte pages, so only the presence of the
        // change is stable.
        test:assertTrue(diff.ranges.length() > 0, "expected the overwrite to appear in the diff");
    } else {
        test:assertEquals(diff.ranges, [{startByte: 4, endByte: 7}]);
        test:assertEquals(diff.clearRanges, [{startByte: 0, endByte: 3}]);
    }

    // A well-formed but nonexistent baseline snapshot fails.
    RangeDiff|Error missing = fileClient->listRangesDiff("/diff.bin", "2020-01-01T00:00:00.0000000Z");
    test:assertTrue(missing is NotFoundError, "expected an unknown baseline snapshot to fail");
}

// ---------------------------------------------------------------------------
// Property setters, access policy, permissions
// ---------------------------------------------------------------------------

@test:Config {}
function testSetShareProperties() returns error? {
    AdminClient admin = check newAdmin();
    string share = testShare("set-props");
    check admin->createShare(share, {quotaInGb: 40});
    Client fileClient = check newShareClient(share);

    if check isPremiumAccount() {
        // Premium shares have no working access tier: classic accounts reject the set,
        // provisioned v2 accounts accept and ignore it. The quota is the provisioned
        // size, which only grows safely.
        Error? tierSet = fileClient->setShareProperties({accessTier: HOT});
        if tierSet is () {
            ShareProperties ignored = check fileClient->getShareProperties();
            test:assertTrue(ignored.accessTier != HOT,
                    "expected the tier change to be ignored on a premium share");
        }
        check fileClient->setShareProperties({quotaInGb: 50});
        ShareProperties premiumProps = check fileClient->getShareProperties();
        test:assertEquals(premiumProps.quotaInGb, 50);
        return;
    }

    // A tier change can apply asynchronously, so the read-back is polled.
    check fileClient->setShareProperties({quotaInGb: 50, accessTier: HOT});
    check await(function() returns boolean|error {
        ShareProperties props = check fileClient->getShareProperties();
        return props.quotaInGb == 50 && props.accessTier == HOT;
    }, timeoutSeconds = 120);

    // Changing one property leaves the other in place.
    check fileClient->setShareProperties({quotaInGb: 60});
    check await(function() returns boolean|error {
        ShareProperties props = check fileClient->getShareProperties();
        return props.quotaInGb == 60 && props.accessTier == HOT;
    }, timeoutSeconds = 120);
}

@test:Config {}
function testSetFileProperties() returns error? {
    AdminClient admin = check newAdmin();
    string share = testShare("set-file");
    check admin->createShare(share);
    Client fileClient = check newShareClient(share);
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

@test:Config {}
function testSetDirectoryProperties() returns error? {
    AdminClient admin = check newAdmin();
    string share = testShare("set-dir");
    check admin->createShare(share);
    Client fileClient = check newShareClient(share);
    check fileClient->createDirectory("/tuned");

    // A directory's attribute set must include the Directory flag; other attributes
    // ride along with it.
    check fileClient->setDirectoryProperties("/tuned",
            {smbProperties: {ntfsFileAttributes: [DIRECTORY, READ_ONLY, HIDDEN]}});

    Error? withoutFlag = fileClient->setDirectoryProperties("/tuned",
            {smbProperties: {ntfsFileAttributes: [HIDDEN]}});
    test:assertTrue(withoutFlag is Error,
            "expected an attribute set without Directory to be rejected on a directory");

    Error? missing = fileClient->setDirectoryProperties("/no-such-dir", {});
    test:assertTrue(missing is NotFoundError, "expected a missing directory to fail");
}

@test:Config {}
function testShareAccessPolicyRoundtrip() returns error? {
    AdminClient admin = check newAdmin();
    string share = testShare("acl");
    check admin->createShare(share);
    Client fileClient = check newShareClient(share);

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

@test:Config {}
function testSharePermissionStore() returns error? {
    AdminClient admin = check newAdmin();
    string share = testShare("permission");
    check admin->createShare(share);
    Client fileClient = check newShareClient(share);

    string sddl = "O:S-1-5-21-2127521184-1604012920-1887927527-21560751G:S-1-5-21-2127521184-1604012920-1887927527-513D:AI(A;;FA;;;SY)";
    string key = check fileClient->createSharePermission(sddl);
    test:assertTrue(key.length() > 0);

    string fetched = check fileClient->getSharePermission(key);
    if liveRun {
        // Azure normalizes stored SDDL, so only readability is stable.
        test:assertTrue(fetched.length() > 0, "expected the stored SDDL to be readable");
    } else {
        test:assertEquals(fetched, sddl);
    }

    string|Error missing = fileClient->getSharePermission("no-such-key");
    if liveRun {
        // A fabricated key is rejected, though the error code differs from a plain miss.
        test:assertTrue(missing is Error, "expected an unknown permission key to fail");
    } else {
        test:assertTrue(missing is NotFoundError, "expected an unknown permission key to fail");
    }
}

// ---------------------------------------------------------------------------
// SMB handles
// ---------------------------------------------------------------------------

// Pinned to the mock: an open SMB handle exists only while a real SMB client has the
// share mounted with the file open, which no REST call can produce; the mock fabricates
// one so the handle listing and force-close paths execute. testNoOpenHandles covers the
// zero-handle behavior in both modes.
@test:Config {}
function testSmbHandles() returns error? {
    AdminClient admin = check newMockAdmin();
    string share = testShare("handles");
    check admin->createShare(share);
    Client fileClient = check newMockShareClient(share);
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

@test:Config {}
function testServicePropertiesRoundtrip() returns error? {
    AdminClient admin = check newAdmin();

    if liveRun {
        // Non-destructive live check: write the account's current settings back to it,
        // proving the service accepts this connector's serialization of what it
        // returned. The echo carries only the groups every account accepts (the SMB
        // multichannel protocol settings write back only on premium accounts). The full
        // mutation round-trip below runs on the mock, where changing account-global
        // settings harms nothing.
        ServiceProperties current = check admin->getServiceProperties();
        ServiceProperties echo = {};
        Metrics? currentHour = current.hourMetrics;
        if currentHour is Metrics {
            echo.hourMetrics = currentHour;
        }
        Metrics? currentMinute = current.minuteMetrics;
        if currentMinute is Metrics {
            echo.minuteMetrics = currentMinute;
        }
        CorsRule[]? currentCors = current.cors;
        if currentCors is CorsRule[] {
            echo.cors = currentCors;
        }
        check admin->setServiceProperties(echo);
        ServiceProperties reread = check admin->getServiceProperties();
        test:assertEquals(reread.cors, current.cors);
        check admin.close();
        return;
    }

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

// Azure serves user-delegation keys only to Entra-authenticated callers, so in live
// runs this needs the Entra credentials and skips without them; mock runs always work.
@test:Config {enable: !liveRun || liveEntraEnabled}
function testGetUserDelegationKey() returns error? {
    AdminClient admin = liveRun ? check newEntraAdmin() : check newMockAdmin();
    time:Utc keyStart = [time:utcNow()[0], 0];
    time:Utc keyExpiry = time:utcAddSeconds(keyStart, 3600);

    UserDelegationKey key = check admin->getUserDelegationKey(keyStart, keyExpiry);
    if liveRun {
        test:assertTrue(key.signedObjectId.length() > 0, "expected a signed object id");
        test:assertTrue(key.signedTenantId.length() > 0, "expected a signed tenant id");
        test:assertTrue(key.value.length() > 0, "expected key material");
        test:assertTrue(key.signedVersion.length() > 0, "expected a signed version");
    } else {
        test:assertEquals(key.signedObjectId, "mock-oid");
        test:assertEquals(key.signedTenantId, "mock-tid");
        test:assertEquals(key.signedVersion, "2025-05-05");
        test:assertEquals(key.value, "bW9jay11ZGstdmFsdWU=");
    }
    test:assertEquals(key.signedStart, keyStart);
    test:assertEquals(key.signedExpiry, keyExpiry);
    test:assertEquals(key.signedService, "f");
    check admin.close();
}

// ---------------------------------------------------------------------------
// SAS generation
// ---------------------------------------------------------------------------

@test:Config {}
function testGenerateShareAndFileSas() returns error? {
    AdminClient admin = check newAdmin();
    string share = testShare("sas");
    check admin->createShare(share);
    Client fileClient = check newShareClient(share);
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
    Client sasClient = check new (share, auth = {
        sasUrl: string `${sasBaseUrl()}?sv=2025-05-05&sp=rl&se=2026-08-01T00%3A00%3A00Z&sig=ZmFrZQ%3D%3D`
    });
    string|Error denied = sasClient->generateShareSas(
            {expiryTime: expiry, permissions: {read: true}});
    test:assertTrue(denied is ProcessingError,
            "expected SAS generation without an account key to fail");
}

// Azure serves user-delegation keys only to Entra-authenticated callers, so in live
// runs this needs the Entra credentials and skips without them; mock runs always work.
// Signing with the fetched key needs no credentials, so the regular clients do the rest.
@test:Config {enable: !liveRun || liveEntraEnabled}
function testGenerateUserDelegationSas() returns error? {
    AdminClient keyAdmin = liveRun ? check newEntraAdmin() : check newMockAdmin();
    AdminClient admin = check newAdmin();
    string share = testShare("uds");
    check admin->createShare(share);
    Client fileClient = check newShareClient(share);
    time:Utc keyStart = [time:utcNow()[0], 0];
    UserDelegationKey key = check keyAdmin->getUserDelegationKey(keyStart,
            time:utcAddSeconds(keyStart, 86400));
    time:Utc expiry = time:utcAddSeconds(keyStart, 3600);

    string shareToken = check fileClient->generateShareUserDelegationSas(
            {expiryTime: expiry, permissions: {read: true}}, key);
    map<string> shareParams = sasParams(shareToken);
    test:assertEquals(shareParams["sp"], "r");
    test:assertEquals(shareParams["skoid"], key.signedObjectId);
    test:assertTrue(shareParams.hasKey("sig"), "expected a signature");

    string fileToken = check fileClient->generateUserDelegationSas("/f.txt",
            {expiryTime: expiry, permissions: {read: true, delete: true}}, key);
    map<string> fileParams = sasParams(fileToken);
    test:assertEquals(fileParams["sp"], "rd");
    test:assertEquals(fileParams["sktid"], key.signedTenantId);
    check keyAdmin.close();
    check admin.close();
}

@test:Config {}
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

@test:Config {}
function testNfsLinks() returns error? {
    if liveRun && !(check isPremiumAccount()) {
        // NFS shares exist only on premium (FileStorage) accounts, and a live run never
        // falls back to the mock, so a standard-account live run skips this. Mock runs
        // cover the operations.
        return;
    }
    AdminClient admin = check newAdmin();
    string share = testShare("nfs");
    check admin->createShare(share, {enabledProtocols: [NFS]});
    Client fileClient = check newShareClient(share);
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

    // Targets survive characters the wire percent-encodes, including a literal plus,
    // which naive form-decoding would corrupt into a space.
    check fileClient->createSymbolicLink("/tricky.txt", "../else where/a+b.txt");
    string trickyText = check fileClient->getSymbolicLink("/tricky.txt");
    test:assertEquals(trickyText, "../else where/a+b.txt");

    string|Error notALink = fileClient->getSymbolicLink("/original.txt");
    test:assertTrue(notALink is Error, "expected reading a non-link to fail");
}

// ---------------------------------------------------------------------------
// Core gap-fills
// ---------------------------------------------------------------------------

@test:Config {}
function testRenameReplaceIfExists() returns error? {
    AdminClient admin = check newAdmin();
    string share = testShare("rename");
    check admin->createShare(share);
    Client fileClient = check newShareClient(share);
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

@test:Config {}
function testLargeUploadSplitsIntoRanges() returns error? {
    AdminClient admin = check newAdmin();
    string share = testShare("large");
    check admin->createShare(share);
    Client fileClient = check newShareClient(share);

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

@test:Config {}
function testEarlyStreamClose() returns error? {
    AdminClient admin = check newAdmin();
    string share = testShare("close");
    check admin->createShare(share);
    Client fileClient = check newShareClient(share);
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

@test:Config {}
function testStreamFailurePaths() returns error? {
    AdminClient admin = check newAdmin();
    string share = testShare("stream-fail");
    check admin->createShare(share);
    Client fileClient = check newShareClient(share);

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

@test:Config {}
function testUploadFromStreamOverflow() returns error? {
    AdminClient admin = check newAdmin();
    string share = testShare("overflow");
    check admin->createShare(share);
    Client fileClient = check newShareClient(share);

    byte[][] longChunks = ["abcdef".toBytes(), "ghijkl".toBytes()];
    Error? overflow = fileClient->uploadFromStream(longChunks.toStream(), 5, "/overflow.txt");
    test:assertTrue(overflow is ProcessingError,
            "expected a stream longer than contentLength to fail");
}

@test:Config {}
function testConnectionStringClientOps() returns error? {
    AdminClient admin = check newAdmin();
    string share = testShare("cs");
    check admin->createShare(share);
    Client fileClient = check new (share, auth = {connectionString: testConnectionString()});
    check fileClient->uploadContent("via connection string", "/cs.txt");
    test:assertEquals(check readAll(fileClient, "/cs.txt"), "via connection string".toBytes());
}

@test:Config {}
function testClosedAdminClientFails() returns error? {
    AdminClient admin = check newAdmin();
    check admin.close();
    boolean|Error result = admin->hasShare("any-share");
    test:assertTrue(result is ProcessingError, "expected an op on a closed admin client to fail");
}

// ---------------------------------------------------------------------------
// SAS round-trip and open handles
// ---------------------------------------------------------------------------

@test:Config {}
function testSasRoundtrip() returns error? {
    AdminClient admin = check newAdmin();
    string share = testShare("sas-roundtrip");
    check admin->createShare(share);
    Client keyClient = check newShareClient(share);
    check keyClient->uploadContent("sas readable", "/sas-probe.txt");

    time:Utc expiry = time:utcAddSeconds(time:utcNow(), 3600);
    string token = check keyClient->generateShareSas(
            {expiryTime: expiry, permissions: {read: true, list: true, delete: true}});

    // The minted token authenticates a fresh client through its full SAS URL. The mock
    // ignores signatures, so the signature itself is verified only live; the client
    // wiring runs in both modes.
    Client sasUrlClient = check new (share, auth = {sasUrl: string `${sasBaseUrl()}?${token}`});
    test:assertEquals(check readAll(sasUrlClient, "/sas-probe.txt"), "sas readable".toBytes());
    check sasUrlClient.close();

    if liveRun {
        // SasConfig derives its endpoint from the account name, so it can only target
        // the real service.
        Client sasClient = check new (share,
                auth = {accountName: liveAccountName, sasToken: token});
        check sasClient->deleteFile("/sas-probe.txt");
        check sasClient.close();
    }
    check keyClient.close();
    check admin.close();
}

@test:Config {}
function testNoOpenHandles() returns error? {
    AdminClient admin = check newAdmin();
    string share = testShare("no-handles");
    check admin->createShare(share);
    Client fileClient = check newShareClient(share);
    check fileClient->uploadContent("no handles", "/handle-probe.txt");

    HandleInfo[] handles = check fileClient->listFileHandles("/handle-probe.txt");
    test:assertEquals(handles.length(), 0, "REST clients hold no SMB handles");
    CloseHandlesInfo closed = check fileClient->forceCloseFileHandles("/handle-probe.txt");
    test:assertEquals(closed.closedHandles, 0);
    test:assertEquals(closed.failedHandles, 0);
}

// ---------------------------------------------------------------------------
// Microsoft Entra ID auth (live only: mocking the identity service would test
// Microsoft's SDK, not this connector)
// ---------------------------------------------------------------------------

@test:Config {enable: liveEntraEnabled}
function testLiveEntraAuth() returns error? {
    // A NotFound answer for a nonexistent share proves the token was both authenticated
    // and authorized; a missing role surfaces as an authorization error instead.
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

@test:Config {enable: liveEntraDefaultChainEnabled}
function testLiveEntraDefaultChainAuth() returns error? {
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
