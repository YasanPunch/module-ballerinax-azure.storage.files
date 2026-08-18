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
    test:assertTrue(result is Error && result !is ServiceError, "expected a client-side error for a non-base64 key");
}

@test:Config {}
function testInitRejectsEmptyAccountName() {
    Client|Error result = new ("share", auth = {accountName: "  ", accountKey: MOCK_KEY});
    test:assertTrue(result is Error && result !is ServiceError,
            "expected a client-side error for an empty account name");
}

@test:Config {}
function testInitRejectsBadServiceUrl() {
    Client|Error result = new ("share",
            auth = {accountName: "acct", accountKey: MOCK_KEY, serviceUrl: "ftp://example.com"});
    test:assertTrue(result is Error && result !is ServiceError,
            "expected a client-side error for a non-http serviceUrl");
}

@test:Config {}
function testInitRejectsEmptyShareName() {
    Client|Error result = new ("", auth = {accountName: "acct", accountKey: MOCK_KEY});
    test:assertTrue(result is Error && result !is ServiceError, "expected a client-side error for an empty share name");
}

@test:Config {}
function testInitRejectsSasUrlWithoutSignature() {
    Client|Error result = new ("share", auth = {sasUrl: "https://acct.file.core.windows.net/?sv=2024"});
    test:assertTrue(result is Error && result !is ServiceError,
            "expected a client-side error for a SAS URL without sig=");
}

@test:Config {}
function testInitRejectsConnectionStringWithoutEndpoint() {
    Client|Error result = new ("share",
            auth = {connectionString: "DefaultEndpointsProtocol=https;AccountKey=" + MOCK_KEY});
    test:assertTrue(result is Error && result !is ServiceError,
            "expected a client-side error for a connection string without FileEndpoint/AccountName");
}

@test:Config {}
function testInitAcceptsConnectionString() {
    Client|Error result = new ("share", auth = {connectionString: testConnectionString()});
    test:assertTrue(result is Client, "expected a connection-string client to initialize");
}

@test:Config {}
function testInitEntraIdModes() returns error? {
    // Every Entra credential kind builds locally; tokens are requested only on first use.
    _ = check new Client("share", auth = {kind: "default", accountName: "acct"});

    _ = check new Client("share", auth = {kind: "managed-identity", accountName: "acct", clientId: "mi-client"});

    _ = check new Client("share",
            auth = {accountName: "acct", tenantId: "tenant", clientId: "client", clientSecret: "s3cret"});

    string tokenFile = "target/mock-workload-token.txt";
    check io:fileWriteString(tokenFile, "federated-token");
    _ = check new Client("share",
            auth = {accountName: "acct", tenantId: "tenant", clientId: "client", tokenFilePath: tokenFile});

    string certificateFile = "target/mock-entra-cert.pem";
    check io:fileWriteString(certificateFile, "-----BEGIN CERTIFICATE-----\nTUlJQg==\n-----END CERTIFICATE-----\n");
    _ = check new Client("share", auth = {
        accountName: "acct",
        tenantId: "tenant",
        clientId: "client",
        certificatePath: certificateFile
    });
}

@test:Config {}
function testInitEntraIdValidation() {
    Client|Error emptyTenant = new ("share",
            auth = {accountName: "acct", tenantId: " ", clientId: "client", clientSecret: "s3cret"});
    test:assertTrue(emptyTenant is Error && emptyTenant !is ServiceError, "expected a blank tenantId to fail");

    Client|Error missingCertificate = new ("share", auth = {
        accountName: "acct",
        tenantId: "tenant",
        clientId: "client",
        certificatePath: "target/no-such-cert.pem"
    });
    test:assertTrue(missingCertificate is Error && missingCertificate !is ServiceError,
            "expected a missing certificate file to fail");

    Client|Error emptyAccount = new ("share", auth = {kind: "default", accountName: "  "});
    test:assertTrue(emptyAccount is Error && emptyAccount !is ServiceError, "expected a blank account name to fail");
}

// Pinned to the mock: retry and proxy behavior only manifests against an endpoint that
// can be made to fail on demand.
@test:Config {}
function testRetryAndTransportConfig() returns error? {
    AdminClient admin = check newMockAdmin();
    string share = testShare("transport-config");
    check createTestShare(admin, share);

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
    check retryClient->upload("with retry", "/retry.txt");
    test:assertEquals(check readAll(retryClient, "/retry.txt"), "with retry".toBytes());

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
    check pooledClient->upload("pooled", "/pooled.txt");
    test:assertEquals(check readAll(pooledClient, "/pooled.txt"), "pooled".toBytes());

    // A proxy is honored: pointing at a dead port fails the request, not the init.
    Client proxied = check new (share, auth = {
        accountName: "mockaccount",
        accountKey: MOCK_KEY,
        serviceUrl: string `http://localhost:${MOCK_PORT}`
    }, transportConfig = {proxy: {proxyType: HTTP, host: "localhost", port: 39999}});
    Error? throughDeadProxy = proxied->upload("x", "/proxied.txt");
    test:assertTrue(throughDeadProxy is Error && throughDeadProxy !is ServiceError,
            "expected a request through an unreachable proxy to fail");
}

// Pinned to the mock: a geo-secondary retry only manifests against an endpoint that can
// fail on demand. Primary and secondary are the same mock reached through two host names,
// and the request log's Host header shows which one served the retry.
@test:Config {}
function testSecondaryHostRetryReachesSecondaryHost() returns error? {
    AdminClient admin = check newMockAdmin();
    string share = testShare("secondary-host");
    check createTestShare(admin, share);
    Client fileClient = check new (share, auth = {
        accountName: "mockaccount",
        accountKey: MOCK_KEY,
        serviceUrl: string `http://localhost:${MOCK_PORT}`
    }, retryConfig = {
        maxTries: 2,
        secondaryHostUrl: string `http://127.0.0.1:${MOCK_PORT}`
    });
    check fileClient->upload("payload", "/read.txt");

    mockRequestLog = [];
    mockFaultRemaining = 1;
    FileProperties|Error props = fileClient->getFileProperties("/read.txt");
    mockFaultRemaining = 0;
    test:assertEquals((check props).contentLength, 7, "the read must succeed through the secondary retry");

    string[] reads = [];
    foreach string entry in mockRequestLog {
        if entry.includes(string `/${share}/read.txt`) {
            reads.push(entry);
        }
    }
    test:assertEquals(reads.length(), 2, "expected the failed primary read and one retry");
    test:assertTrue(reads[0].includes(string `host=localhost:${MOCK_PORT}`),
            "the first attempt must target the primary host");
    test:assertTrue(reads[1].includes(string `host=127.0.0.1:${MOCK_PORT}`),
            "the retry must reach the configured secondary host");
}

@test:Config {}
function testTransportTlsConfig() returns error? {
    // Trust material as a PEM file.
    _ = check new Client("share", auth = {accountName: "acct", accountKey: MOCK_KEY},
            transportConfig = {secureSocket: {cert: "tests/resources/cert.pem"}});

    // Trust material as a PKCS12 store.
    _ = check new Client("share", auth = {accountName: "acct", accountKey: MOCK_KEY},
            transportConfig = {secureSocket: {cert: {path: "tests/resources/trust.p12", password: "ballerina"}}});

    // Client identity from a certificate and key pair, plus version and cipher pinning,
    // hostname-verification and session flags, and timeouts.
    _ = check new Client("share", auth = {accountName: "acct", accountKey: MOCK_KEY},
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

    // Revocation checking builds against PEM trust material.
    _ = check new Client("share", auth = {accountName: "acct", accountKey: MOCK_KEY},
            transportConfig = {secureSocket: {cert: "tests/resources/cert.pem", validateRevocation: true}});

    // Broken TLS input fails at init with a clear error.
    Client|Error missingCert = new ("share", auth = {accountName: "acct", accountKey: MOCK_KEY},
            transportConfig = {secureSocket: {cert: "tests/resources/absent.pem"}});
    test:assertTrue(missingCert is Error && missingCert !is ServiceError, "expected a missing cert file to fail");

    Client|Error wrongPassword = new ("share", auth = {accountName: "acct", accountKey: MOCK_KEY},
            transportConfig = {secureSocket: {cert: {path: "tests/resources/trust.p12", password: "wrong"}}});
    test:assertTrue(wrongPassword is Error && wrongPassword !is ServiceError,
            "expected a wrong store password to fail");

    Client|Error validationWithoutTrust = new ("share",
            auth = {accountName: "acct", accountKey: MOCK_KEY},
            transportConfig = {secureSocket: {validateRevocation: true}});
    test:assertTrue(validationWithoutTrust is Error && validationWithoutTrust !is ServiceError,
            "expected validateRevocation without trust material to fail");
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
}

@test:Config {}
function testCreateShareTwiceConflicts() returns error? {
    AdminClient admin = check newAdmin();
    string share = testShare("dup");
    check createTestShare(admin, share);
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
        test:assertTrue(props.provisionedIops is int, "expected provisioned IOPS on a premium share");
    } else {
        test:assertEquals(props.accessTier, TRANSACTION_OPTIMIZED);
    }
    test:assertTrue(props.eTag.length() > 0);

    check fileClient->setShareMetadata({env: "mock"});
    props = check fileClient->getShareProperties();
    test:assertEquals(props.metadata, {env: "mock"});

    int actionResult15 = check fileClient->getShareUsage();
    test:assertEquals(actionResult15, 0);
    check fileClient->upload("12345", "/usage.txt");
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
    check createTestShare(admin, share);
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
    check createTestShare(admin, share);
    Client fileClient = check newShareClient(share);
    check fileClient->createDirectory("/keep");
    check fileClient->upload("x", "/keep/file.txt");
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
    check createTestShare(admin, share);
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

    check fileClient->setContentHeaders("/report.bin", {contentType: "application/pdf", cacheControl: "max-age=60"});
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
    check createTestShare(admin, share);
    Client fileClient = check newShareClient(share);

    check fileClient->upload("hello mock", "/text.txt");
    test:assertEquals(check readAll(fileClient, "/text.txt"), "hello mock".toBytes());

    byte[] binary = [1, 2, 3, 4, 5];
    check fileClient->upload(binary, "/binary.bin");
    test:assertEquals(check readAll(fileClient, "/binary.bin"), binary);

    check fileClient->upload(<map<json>>{"metric": 42}, "/data.json");
    byte[] jsonBytes = check readAll(fileClient, "/data.json");
    test:assertEquals(jsonBytes, "{\"metric\":42}".toBytes());
    // The downloaded bytes parse back to the value that was uploaded.
    string jsonText = check string:fromBytes(jsonBytes);
    json reparsedJson = check jsonText.fromJsonString();
    test:assertEquals(reparsedJson, <json>{metric: 42});

    xml document = xml `<report><value>1</value></report>`;
    check fileClient->upload(document, "/doc.xml");
    byte[] xmlBytes = check readAll(fileClient, "/doc.xml");
    test:assertEquals(xmlBytes, document.toString().toBytes());
    xml reparsedXml = check xml:fromString(check string:fromBytes(xmlBytes));
    test:assertEquals(reparsedXml, document);
}

// An open record (the language default); the get and put APIs must accept open records.
type UploadMetric record {
    string quarter;
    int revenue;
};

type UploadPlayer record {|
    string name;
    int score;
|};

type UploadRanked record {|
    string name;
    int? rank;
|};

type UploadBonus record {|
    string name;
    int score;
    int bonus?;
|};

@test:Config {}
function testUploadContentRecordAsJson() returns error? {
    AdminClient admin = check newAdmin();
    string share = testShare("rec-json");
    check createTestShare(admin, share);
    Client fileClient = check newShareClient(share);

    UploadMetric metric = {quarter: "q1", revenue: 1250000};
    check fileClient->upload(metric, "/metrics.json");
    test:assertEquals(check readAll(fileClient, "/metrics.json"), metric.toJsonString().toBytes());

    // The uploaded document binds back to the same open record.
    UploadMetric bound = check fileClient->getFile("/metrics.json");
    test:assertEquals(bound, metric);
}

@test:Config {}
function testUploadContentRecordAsXml() returns error? {
    AdminClient admin = check newAdmin();
    string share = testShare("rec-xml");
    check createTestShare(admin, share);
    Client fileClient = check newShareClient(share);

    UploadMetric metric = {quarter: "q2", revenue: 7};
    check fileClient->upload(metric, "/metrics.xml");
    UploadMetric bound = check fileClient->getFile("/metrics.xml");
    test:assertEquals(bound, metric);
}

@test:Config {}
function testUploadContentRecordArrayAsCsv() returns error? {
    AdminClient admin = check newAdmin();
    string share = testShare("rec-csv");
    check createTestShare(admin, share);
    Client fileClient = check newShareClient(share);

    // A field containing a comma exercises the quoting-aware CSV writer.
    UploadPlayer[] players = [{name: "alice", score: 12}, {name: "bob, jr", score: 7}];
    check fileClient->upload(players, "/players.csv");
    UploadPlayer[] bound = check fileClient->getFile("/players.csv");
    test:assertEquals(bound, players);
    // The header row derives from the records' field names.
    string playersText = check string:fromBytes(check readAll(fileClient, "/players.csv"));
    test:assertEquals(playersText, "name,score\nalice,12\n\"bob, jr\",7");

    // Nil members become empty cells.
    UploadRanked[] ranked = [{name: "a", rank: 1}, {name: "b", rank: ()}];
    check fileClient->upload(ranked, "/ranked.csv");
    string csvText = check string:fromBytes(check readAll(fileClient, "/ranked.csv"));
    test:assertEquals(csvText, "name,rank\na,1\nb,");
}

@test:Config {}
function testUploadContentRecordArrayHeaderUnion() returns error? {
    AdminClient admin = check newAdmin();
    string share = testShare("csv-headers");
    check createTestShare(admin, share);
    Client fileClient = check newShareClient(share);

    // The header row is the union of every record's field names in first-seen order,
    // so an optional field absent from the first record still gets its column.
    UploadBonus[] squad = [{name: "a", score: 1}, {name: "b", score: 2, bonus: 5}];
    check fileClient->upload(squad, "/squad.csv");
    string csvText = check string:fromBytes(check readAll(fileClient, "/squad.csv"));
    test:assertEquals(csvText, "name,score,bonus\na,1,\nb,2,5");
}

@test:Config {}
function testUploadContentRecordFormatRefusals() returns error? {
    AdminClient admin = check newAdmin();
    string share = testShare("rec-refuse");
    check createTestShare(admin, share);
    Client fileClient = check newShareClient(share);

    UploadMetric metric = {quarter: "q3", revenue: 1};
    UploadPlayer[] players = [{name: "a", score: 1}];

    // A single record is never CSV.
    Error? recordAsCsv = fileClient->upload(metric, "/m.csv");
    test:assertTrue(recordAsCsv is Error && recordAsCsv !is ServiceError,
            "record content to a .csv destination must fail client-side");
    if recordAsCsv is Error {
        test:assertTrue(recordAsCsv.message().includes("cannot be serialized as CSV"),
                "the error must state a record cannot be CSV");
    }

    // A record array is only CSV.
    Error? arrayAsJson = fileClient->upload(players, "/p.json");
    test:assertTrue(arrayAsJson is Error && arrayAsJson !is ServiceError,
            "record array content to a .json destination must fail client-side");
    if arrayAsJson is Error {
        test:assertTrue(arrayAsJson.message().includes("requires CSV format"),
                "the error must state record arrays require CSV");
    }

    // No override and no format-bearing extension: the format is unresolvable.
    Error? unresolved = fileClient->upload(metric, "/m.txt");
    test:assertTrue(unresolved is Error && unresolved !is ServiceError,
            "record content to an extension-less format must fail client-side");
    if unresolved is Error {
        test:assertTrue(unresolved.message().includes("fileFormat"), "the error must point at the fileFormat override");
    }
}

@test:Config {}
function testUploadContentFileFormatOverride() returns error? {
    AdminClient admin = check newAdmin();
    string share = testShare("rec-override");
    check createTestShare(admin, share);
    Client fileClient = check newShareClient(share);

    // The explicit format beats the destination extension, on the write and the read.
    UploadPlayer[] players = [{name: "cara", score: 3}];
    check fileClient->upload(players, "/data.json", {fileFormat: CSV});
    test:assertEquals(check string:fromBytes(check readAll(fileClient, "/data.json")), "name,score\ncara,3");
    UploadPlayer[] rows = check fileClient->getFile("/data.json", {fileFormat: CSV});
    test:assertEquals(rows, players);

    UploadMetric metric = {quarter: "q4", revenue: 9};
    check fileClient->upload(metric, "/notes.txt", {fileFormat: JSON});
    test:assertEquals(check readAll(fileClient, "/notes.txt"), metric.toJsonString().toBytes());
}

@test:Config {}
function testUploadContentStringRowsRefused() returns error? {
    AdminClient admin = check newAdmin();
    string share = testShare("string-rows");
    check createTestShare(admin, share);
    Client fileClient = check newShareClient(share);

    // String matrices and tuple rows are json subtypes, so the calls still compile, but
    // CSV serialization takes record arrays only.
    string[][] rows = [["k1", "v1"], ["k2", "v2"]];
    Error? matrixRefused = fileClient->upload(rows, "/rows.csv");
    test:assertTrue(matrixRefused is Error && matrixRefused !is ServiceError,
            "string[][] content to a .csv destination must fail client-side");
    if matrixRefused is Error {
        test:assertTrue(matrixRefused.message().includes("cannot be serialized as CSV"),
                "the error must state json content cannot be CSV");
    }

    [string, string][] pairs = [["k1", "v1"]];
    Error? tupleRefused = fileClient->upload(pairs, "/pairs.csv");
    test:assertTrue(tupleRefused is Error && tupleRefused !is ServiceError,
            "tuple rows to a .csv destination must fail client-side");
}

@test:Config {}
function testUploadContentBareJson() returns error? {
    AdminClient admin = check newAdmin();
    string share = testShare("bare-json");
    check createTestShare(admin, share);
    Client fileClient = check newShareClient(share);

    // A json array serializes as a JSON document and reads back as json.
    json values = [1, "two", true, ()];
    check fileClient->upload(values, "/values.json");
    test:assertEquals(check readAll(fileClient, "/values.json"), values.toJsonString().toBytes());
    json bound = check fileClient->getFile("/values.json");
    test:assertEquals(bound, values);

    // Scalars and nil are json values too.
    json answer = 42;
    check fileClient->upload(answer, "/answer.json");
    test:assertEquals(check string:fromBytes(check readAll(fileClient, "/answer.json")), "42");
    json nil = ();
    check fileClient->upload(nil, "/null.json");
    test:assertEquals(check string:fromBytes(check readAll(fileClient, "/null.json")), "null");

    // A json string is text and passes through unquoted.
    json text = "plain";
    check fileClient->upload(text, "/text.json");
    test:assertEquals(check string:fromBytes(check readAll(fileClient, "/text.json")), "plain");

    // The explicit override serializes json to a destination without a format extension.
    check fileClient->upload(values, "/values.dat", {fileFormat: JSON});
    test:assertEquals(check readAll(fileClient, "/values.dat"), values.toJsonString().toBytes());
}

@test:Config {}
function testUploadContentJsonFormatRefusals() returns error? {
    AdminClient admin = check newAdmin();
    string share = testShare("json-refuse");
    check createTestShare(admin, share);
    Client fileClient = check newShareClient(share);

    json values = [1, 2, 3];

    // json is never CSV.
    Error? asCsv = fileClient->upload(values, "/v.csv");
    test:assertTrue(asCsv is Error && asCsv !is ServiceError,
            "json content to a .csv destination must fail client-side");
    if asCsv is Error {
        test:assertTrue(asCsv.message().includes("cannot be serialized as CSV"),
                "the error must state json cannot be CSV");
    }

    // A json array or scalar has no XML form.
    Error? asXml = fileClient->upload(values, "/v.xml");
    test:assertTrue(asXml is Error && asXml !is ServiceError,
            "json content to an .xml destination must fail client-side");
    if asXml is Error {
        test:assertTrue(asXml.message().includes("cannot be serialized as XML"),
                "the error must state json cannot be XML");
    }

    // No override and no format-bearing extension: the format is unresolvable.
    Error? unresolved = fileClient->upload(values, "/v.txt");
    test:assertTrue(unresolved is Error && unresolved !is ServiceError,
            "json content to an extension-less format must fail client-side");
    if unresolved is Error {
        test:assertTrue(unresolved.message().includes("fileFormat"), "the error must point at the fileFormat override");
    }

    json scalar = 42;
    Error? scalarAsCsv = fileClient->upload(scalar, "/n.csv");
    test:assertTrue(scalarAsCsv is Error && scalarAsCsv !is ServiceError,
            "a json scalar to a .csv destination must fail client-side");
}

@test:Config {}
function testUploadAndDownloadLocalFile() returns error? {
    AdminClient admin = check newAdmin();
    string share = testShare("transfer");
    check createTestShare(admin, share);
    Client fileClient = check newShareClient(share);

    string localSource = "target/mock-upload-source.txt";
    string localDestination = "target/mock-download-target.txt";
    check io:fileWriteString(localSource, "round trip payload");
    if check file:test(localDestination, file:EXISTS) {
        check file:remove(localDestination);
    }

    check fileClient->uploadFromFile(localSource, "/roundtrip.txt");
    boolean actionResult14 = check fileClient->hasFile("/roundtrip.txt");
    test:assertTrue(actionResult14);

    check fileClient->download("/roundtrip.txt", localDestination);
    test:assertEquals(check io:fileReadString(localDestination), "round trip payload");

    // The destination must not already exist (CREATE_NEW contract).
    Error? again = fileClient->download("/roundtrip.txt", localDestination);
    test:assertTrue(again is Error && again !is ServiceError, "expected an existing local file to fail the download");

    Error? missingLocal = fileClient->uploadFromFile("target/does-not-exist.txt", "/x.txt");
    test:assertTrue(missingLocal is Error && missingLocal !is ServiceError, "expected a missing local file to fail the upload");
}

@test:Config {}
function testUploadFromStream() returns error? {
    AdminClient admin = check newAdmin();
    string share = testShare("stream");
    check createTestShare(admin, share);
    Client fileClient = check newShareClient(share);

    byte[][] chunks = ["abc".toBytes(), "defg".toBytes(), "hi".toBytes()];
    check fileClient->uploadFromStream(chunks.toStream(), 9, "/streamed.txt");
    test:assertEquals(check readAll(fileClient, "/streamed.txt"), "abcdefghi".toBytes());

    // A declared length that does not match the stream fails with a client-side error.
    byte[][] shortChunks = ["abc".toBytes()];
    Error? shortResult = fileClient->uploadFromStream(shortChunks.toStream(), 9, "/short.txt");
    test:assertTrue(shortResult is Error && shortResult !is ServiceError, "expected a short stream to fail");
}

// Pinned to the mock: the range-write count is only observable through the mock's request
// log. Small source chunks must coalesce into 4 MiB range writes, so the request count
// tracks the content size rather than the source's chunking.
@test:Config {}
function testUploadFromStreamCoalescesSmallChunks() returns error? {
    AdminClient admin = check newMockAdmin();
    string share = testShare("stream-coalesce");
    check createTestShare(admin, share);
    Client fileClient = check newMockShareClient(share);

    final int chunkSize = 4096;
    final int chunkCount = 1280;
    final int total = chunkSize * chunkCount;
    byte[][] chunks = [];
    foreach int i in 0 ..< chunkCount {
        byte[] chunk = [];
        chunk.setLength(chunkSize);
        chunk[0] = <byte>(i % 251 + 1);
        chunks.push(chunk);
    }

    mockRequestLog = [];
    check fileClient->uploadFromStream(chunks.toStream(), total, "/coalesced.bin");

    FileProperties props = check fileClient->getFileProperties("/coalesced.bin");
    test:assertEquals(props.contentLength, total);

    // Read across the 4 MiB flush boundary: the marker byte of the chunk that starts the
    // second range write must be in place.
    final int rangeCap = 4 * 1024 * 1024;
    stream<byte[], Error?> boundary = check fileClient->getFile("/coalesced.bin",
            {range: {startByte: rangeCap - 2, endByte: rangeCap + 1}});
    byte boundaryMarker = <byte>((rangeCap / chunkSize) % 251 + 1);
    test:assertEquals(check collectBytes(boundary), <byte[]>[0, 0, boundaryMarker, 0]);

    int rangeWrites = 0;
    foreach string entry in mockRequestLog {
        if entry.startsWith("PUT") && entry.includes(string `/${share}/coalesced.bin`) && entry.includes("comp=range") {
            rangeWrites += 1;
        }
    }
    test:assertEquals(rangeWrites, 2, "a 5 MiB stream of 4 KiB chunks must coalesce into exactly two range writes");
}

// Pinned to the mock: the range-write count is only observable through the request log.
// A source chunk larger than 4 MiB is split by the native layer into service-compliant
// range writes, so no single range write ever exceeds the service cap.
@test:Config {}
function testUploadFromStreamSplitsOversizedChunk() returns error? {
    AdminClient admin = check newMockAdmin();
    string share = testShare("stream-split");
    check createTestShare(admin, share);
    Client fileClient = check newMockShareClient(share);

    final int rangeCap = 4 * 1024 * 1024;
    final int total = rangeCap + 512;
    byte[] big = [];
    big.setLength(total);
    big[rangeCap - 1] = 7;
    big[rangeCap] = 9;
    byte[][] chunks = [big];

    mockRequestLog = [];
    check fileClient->uploadFromStream(chunks.toStream(), total, "/oversized.bin");

    FileProperties props = check fileClient->getFileProperties("/oversized.bin");
    test:assertEquals(props.contentLength, total);
    stream<byte[], Error?> boundary = check fileClient->getFile("/oversized.bin",
            {range: {startByte: rangeCap - 1, endByte: rangeCap}});
    test:assertEquals(check collectBytes(boundary), <byte[]>[7, 9]);

    int rangeWrites = 0;
    foreach string entry in mockRequestLog {
        if entry.startsWith("PUT") && entry.includes(string `/${share}/oversized.bin`) && entry.includes("comp=range") {
            rangeWrites += 1;
        }
    }
    test:assertEquals(rangeWrites, 2, "an oversized chunk must split into two service-compliant range writes");
}

// A byte stream whose close() calls are observable, for the error-path cleanup claims.
class CloseTrackingChunks {
    private final byte[][] chunks;
    private final boolean failAfterChunks;
    private int index = 0;
    boolean closed = false;

    function init(byte[][] chunks, boolean failAfterChunks = false) {
        self.chunks = chunks;
        self.failAfterChunks = failAfterChunks;
    }

    public isolated function next() returns record {|byte[] value;|}|error? {
        if self.index >= self.chunks.length() {
            return self.failAfterChunks ? error("source stream broke") : ();
        }
        byte[] chunk = self.chunks[self.index];
        self.index += 1;
        return {value: chunk};
    }

    public isolated function close() returns error? {
        self.closed = true;
        return;
    }
}

@test:Config {}
function testUploadFromStreamClosesSourceOnError() returns error? {
    AdminClient admin = check newAdmin();
    string share = testShare("stream-close");
    check createTestShare(admin, share);
    Client fileClient = check newShareClient(share);

    // A failing source stream: the upload fails client-side and the source is closed.
    CloseTrackingChunks failing = new (["ab".toBytes()], failAfterChunks = true);
    stream<byte[], error?> failingStream = new (failing);
    Error? failed = fileClient->uploadFromStream(failingStream, 100, "/failing.bin");
    test:assertTrue(failed is Error && failed !is ServiceError,
            "a source-stream failure must fail the upload client-side");
    test:assertTrue(failing.closed, "a source-stream failure must close the source stream");

    // A source that overshoots the declared length: the upload fails and the source is closed.
    CloseTrackingChunks overshooting = new (["abcdef".toBytes()]);
    stream<byte[], error?> overshootStream = new (overshooting);
    Error? overshot = fileClient->uploadFromStream(overshootStream, 3, "/overshoot.bin");
    test:assertTrue(overshot is Error && overshot !is ServiceError,
            "a stream exceeding contentLength must fail the upload client-side");
    test:assertTrue(overshooting.closed, "an overshooting source must be closed");
}

@test:Config {}
function testUploadFromStreamRejectsNegativeLength() returns error? {
    AdminClient admin = check newAdmin();
    string share = testShare("stream-negative");
    check createTestShare(admin, share);
    Client fileClient = check newShareClient(share);

    byte[][] chunks = ["abc".toBytes()];
    Error? negative = fileClient->uploadFromStream(chunks.toStream(), -1, "/negative.bin");
    test:assertTrue(negative is Error && negative !is ServiceError,
            "a negative contentLength must fail client-side before any service call");
    if negative is Error {
        test:assertTrue(negative.message().includes("contentLength"), "the error must name contentLength");
    }
}

@test:Config {}
function testRangedDownload() returns error? {
    AdminClient admin = check newAdmin();
    string share = testShare("range-read");
    check createTestShare(admin, share);
    Client fileClient = check newShareClient(share);
    check fileClient->upload("0123456789", "/digits.txt");

    stream<byte[], Error?> content = check fileClient->getFile("/digits.txt", {range: {startByte: 2, endByte: 5}});
    test:assertEquals(check collectBytes(content), "2345".toBytes());
}

// ---------------------------------------------------------------------------
// Listing
// ---------------------------------------------------------------------------

@test:Config {}
function testListFlatAndRecursive() returns error? {
    AdminClient admin = check newAdmin();
    string share = testShare("list");
    check createTestShare(admin, share);
    Client fileClient = check newShareClient(share);
    check fileClient->createDirectory("/a");
    check fileClient->createDirectory("/a/b");
    check fileClient->upload("1", "/root.txt");
    check fileClient->upload("2", "/a/one.txt");
    check fileClient->upload("3", "/a/b/two.txt");

    stream<Entry, Error?> entryStream18 = check fileClient->list("/");
    Entry[] flat = check collectEntries(entryStream18);
    test:assertEquals(entryPaths(flat).sort(), ["/a", "/root.txt"]);

    stream<Entry, Error?> entryStream19 = check fileClient->list("/", {recursive: true});
    Entry[] deep = check collectEntries(entryStream19);
    test:assertEquals(entryPaths(deep).sort(), ["/a", "/a/b", "/a/b/two.txt", "/a/one.txt", "/root.txt"]);

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
    check createTestShare(admin, share);
    Client fileClient = check newShareClient(share);
    check fileClient->upload("copy me", "/source.txt");

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
    check createTestShare(admin, share);
    Client fileClient = check newShareClient(share);
    check fileClient->upload("via url", "/origin.txt");

    // The service fetches the source URL itself, so it carries a read SAS; the mock
    // ignores the token while live Azure verifies it.
    time:Utc sourceExpiry = time:utcAddSeconds(time:utcNow(), 3600);
    string token = check fileClient.generateSas("/origin.txt", {expiryTime: sourceExpiry, permissions: {read: true}});
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
    check createTestShare(admin, share);
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
    test:assertTrue(overflow is RangeNotSatisfiableError, "expected InvalidRange to map to RangeNotSatisfiableError");
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
    check createTestShare(admin, share);
    Client fileClient = check newMockShareClient(share);

    FileProperties|Error quota = fileClient->getFileProperties("/__err-403-ShareSizeLimitReached");
    test:assertTrue(quota is QuotaExceededError, "403 ShareSizeLimitReached should map to QuotaExceededError");
    if quota is ServiceError {
        test:assertEquals(quota.detail().httpStatus, 403);
        test:assertEquals(quota.detail().errorCode, "ShareSizeLimitReached");
    } else {
        test:assertFail("expected a mapped Azure error to be a ServiceError");
    }

    FileProperties|Error smbFull = fileClient->getFileProperties("/__err-403-SmbShareFull");
    test:assertTrue(smbFull is QuotaExceededError, "403 SmbShareFull should map to QuotaExceededError");

    FileProperties|Error auth = fileClient->getFileProperties("/__err-403-AuthenticationFailed");
    test:assertTrue(auth is AuthorizationError, "403 AuthenticationFailed should map to AuthorizationError");

    // The code Azure returns for an Entra ID identity lacking the required RBAC role.
    FileProperties|Error rbac = fileClient->getFileProperties("/__err-403-AuthorizationPermissionMismatch");
    test:assertTrue(rbac is AuthorizationError, "403 AuthorizationPermissionMismatch should map to AuthorizationError");

    // A SAS used outside its permitted IP range.
    FileProperties|Error sasIp = fileClient->getFileProperties("/__err-403-AuthorizationSourceIPMismatch");
    test:assertTrue(sasIp is AuthorizationError, "403 AuthorizationSourceIPMismatch should map to AuthorizationError");

    FileProperties|Error precondition = fileClient->getFileProperties("/__err-412-ConditionNotMet");
    test:assertTrue(precondition is PreconditionFailedError,
            "412 ConditionNotMet should map to PreconditionFailedError");

    // Lease-id requirements on data operations are preconditions, unlike the 409 conflicts
    // the lease operations themselves raise.
    FileProperties|Error leaseMissing = fileClient->getFileProperties("/__err-412-LeaseIdMissing");
    test:assertTrue(leaseMissing is PreconditionFailedError,
            "412 LeaseIdMissing should map to PreconditionFailedError");

    FileProperties|Error leaseMismatch = fileClient->getFileProperties("/__err-412-LeaseIdMismatchWithFileOperation");
    test:assertTrue(leaseMismatch is PreconditionFailedError,
            "412 LeaseIdMismatchWithFileOperation should map to PreconditionFailedError");

    FileProperties|Error leaseLost = fileClient->getFileProperties("/__err-412-LeaseLost");
    test:assertTrue(leaseLost is PreconditionFailedError, "412 LeaseLost should map to PreconditionFailedError");

    FileProperties|Error sharing = fileClient->getFileProperties("/__err-409-SharingViolation");
    test:assertTrue(sharing is ConflictError, "409 SharingViolation should map to ConflictError");

    FileProperties|Error unknown = fileClient->getFileProperties("/__err-500-InternalError");
    if unknown is ServiceError {
        test:assertFalse(unknown is NotFoundError|ConflictError|AuthorizationError
                |PreconditionFailedError|RangeNotSatisfiableError|QuotaExceededError,
                "an unmapped code should stay the generic ServiceError type");
        test:assertEquals(unknown.detail().httpStatus, 500);
        test:assertEquals(unknown.detail().errorCode, "InternalError");
    } else {
        test:assertFail("expected a ServiceError for the forced 500");
    }
}

// Client-side failures carry no detail: an errorCode is never fabricated, and an HTTP
// status exists only when Azure answered.
@test:Config {}
function testClientSideErrorsCarryNoDetail() returns error? {
    Client|Error bad = new ("share", auth = {accountName: "acct", accountKey: "not base64!!!"});
    if bad is Error {
        test:assertTrue(bad !is ServiceError, "a client-side init failure must not be a ServiceError");
        test:assertFalse(bad.detail().hasKey("errorCode"), "a client-side error must not carry a fabricated errorCode");
        test:assertFalse(bad.detail().hasKey("httpStatus"), "a client-side error must not carry an httpStatus");
    } else {
        test:assertFail("expected a client-side error for a non-base64 key");
    }

    AdminClient admin = check newAdmin();
    string share = testShare("nodetail");
    check createTestShare(admin, share);
    Client fileClient = check newShareClient(share);
    byte[][] longChunks = ["abcdef".toBytes(), "ghijkl".toBytes()];
    Error? overflow = fileClient->uploadFromStream(longChunks.toStream(), 5, "/overflow.txt");
    if overflow is Error {
        test:assertTrue(overflow !is ServiceError, "a connector-raised error must not be a ServiceError");
        test:assertFalse(overflow.detail().hasKey("errorCode"),
                "a connector-raised error must not carry a fabricated errorCode");
        test:assertFalse(overflow.detail().hasKey("httpStatus"),
                "a connector-raised error must not carry an httpStatus");
    } else {
        test:assertFail("expected a stream longer than contentLength to fail");
    }
}

// ---------------------------------------------------------------------------
// Leases
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// Share snapshots
// ---------------------------------------------------------------------------

@test:Config {}
function testShareSnapshotLifecycle() returns error? {
    AdminClient admin = check newAdmin();
    string share = testShare("snap");
    check createTestShare(admin, share);
    Client fileClient = check newShareClient(share);
    check fileClient->upload("version one", "/versioned.txt");
    check fileClient->createDirectory("/snapdir");
    check fileClient->upload("stay", "/snapdir/keep.txt");

    ShareSnapshotInfo snapshot = check fileClient->createShareSnapshot({label: "baseline"});
    test:assertTrue(snapshot.snapshotId.length() > 0);
    test:assertTrue(snapshot.eTag.length() > 0);

    // Mutate the live share after the snapshot.
    check fileClient->upload("version two!", "/versioned.txt");
    check fileClient->deleteFile("/snapdir/keep.txt");

    // Snapshot reads serve the frozen content; the live share serves the new content.
    stream<byte[], Error?> old = check fileClient->getFile("/versioned.txt", {snapshotId: snapshot.snapshotId});
    test:assertEquals(check collectBytes(old), "version one".toBytes());
    test:assertEquals(check readAll(fileClient, "/versioned.txt"), "version two!".toBytes());

    string localTarget = "target/mock-snapshot-download.txt";
    if check file:test(localTarget, file:EXISTS) {
        check file:remove(localTarget);
    }
    check fileClient->download("/versioned.txt", localTarget, {snapshotId: snapshot.snapshotId});
    test:assertEquals(check io:fileReadString(localTarget), "version one");

    // Snapshot listing still sees the file deleted from the live share.
    stream<Entry, Error?> snapEntries = check fileClient->list("/snapdir", {snapshotId: snapshot.snapshotId});
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
    Error? gone = fileClient->download("/versioned.txt", missTarget, {snapshotId: snapshot.snapshotId});
    test:assertTrue(gone is NotFoundError, "expected a deleted snapshot to read as NotFound");
}

@test:Config {}
function testListRangesDiff() returns error? {
    AdminClient admin = check newAdmin();
    string share = testShare("diff");
    check createTestShare(admin, share);
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

// ---------------------------------------------------------------------------
// SMB handles
// ---------------------------------------------------------------------------

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
}

// ---------------------------------------------------------------------------
// SAS generation
// ---------------------------------------------------------------------------

@test:Config {}
function testGenerateShareAndFileSas() returns error? {
    AdminClient admin = check newAdmin();
    string share = testShare("sas");
    check createTestShare(admin, share);
    Client fileClient = check newShareClient(share);
    time:Utc expiry = check time:utcFromString("2026-08-01T00:00:00Z");

    string shareSas = check fileClient.generateShareSas( {expiryTime: expiry, permissions: {read: true, list: true}});
    map<string> shareParams = sasParams(shareSas);
    test:assertEquals(shareParams["sp"], "rl");
    test:assertTrue(shareParams.hasKey("sig"), "expected a signature");
    test:assertTrue(shareParams.hasKey("se"), "expected an expiry");
    test:assertTrue(shareParams.hasKey("sv"), "expected a service version");
    test:assertFalse(shareParams.hasKey("st"), "expected no start time when unset");

    string fileSas = check fileClient.generateSas("/data.txt", {
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
    string|Error denied = sasClient.generateShareSas( {expiryTime: expiry, permissions: {read: true}});
    test:assertTrue(denied is Error && denied !is ServiceError,
            "expected SAS generation without an account key to fail");
}

// Signing is local, so a stored-access-policy token needs no share to exist: the policy
// identifier rides the token and the policy supplies expiry and permissions at use time.
@test:Config {}
function testSasGenerationWithStoredPolicyIdentifier() returns error? {
    Client fileClient = check newShareClient(testShare("saspol"));

    string shareSas = check fileClient.generateShareSas({identifier: "backup-policy"});
    map<string> shareParams = sasParams(shareSas);
    test:assertEquals(shareParams["si"], "backup-policy");
    test:assertTrue(shareParams.hasKey("sig"), "expected a signature");
    test:assertFalse(shareParams.hasKey("se"), "expected no expiry when the policy carries it");
    test:assertFalse(shareParams.hasKey("sp"), "expected no permissions when the policy carries them");

    string fileSas = check fileClient.generateSas("/data.txt", {identifier: "backup-policy"});
    test:assertEquals(sasParams(fileSas)["si"], "backup-policy");
}

@test:Config {}
function testSasGenerationRequiresIdentifierOrExpiryAndPermissions() returns error? {
    Client fileClient = check newShareClient(testShare("sasval"));
    time:Utc expiry = check time:utcFromString("2026-08-01T00:00:00Z");

    string|Error neither = fileClient.generateShareSas({});
    test:assertTrue(neither is Error && neither !is ServiceError,
            "expected SAS generation with no identifier, expiry, or permissions to fail client-side");
    if neither is Error {
        test:assertEquals(neither.message(), "either identifier, or expiryTime and permissions, must be set");
    }

    string|Error expiryOnly = fileClient.generateSas("/data.txt", {expiryTime: expiry});
    test:assertTrue(expiryOnly is Error && expiryOnly !is ServiceError,
            "expected SAS generation without permissions or identifier to fail client-side");

    string|Error permissionsOnly = fileClient.generateShareSas({permissions: {read: true}});
    test:assertTrue(permissionsOnly is Error && permissionsOnly !is ServiceError,
            "expected SAS generation without expiry or identifier to fail client-side");
}

// Azure serves user-delegation keys only to Entra-authenticated callers, so in live
// runs this needs the Entra credentials and skips without them; mock runs always work.
// Signing with the fetched key needs no credentials, so the regular clients do the rest.
@test:Config {enable: !liveRun || liveEntraEnabled}
function testGenerateUserDelegationSas() returns error? {
    AdminClient keyAdmin = liveRun ? check newEntraAdmin() : check newMockAdmin();
    AdminClient admin = check newAdmin();
    string share = testShare("uds");
    check createTestShare(admin, share);
    Client fileClient = check newShareClient(share);
    time:Utc keyStart = [time:utcNow()[0], 0];
    UserDelegationKey key = check keyAdmin->getUserDelegationKey(keyStart, time:utcAddSeconds(keyStart, 86400));
    time:Utc expiry = time:utcAddSeconds(keyStart, 3600);

    string shareToken = check fileClient.generateShareUserDelegationSas(
            {expiryTime: expiry, permissions: {read: true}}, key);
    map<string> shareParams = sasParams(shareToken);
    test:assertEquals(shareParams["sp"], "r");
    test:assertEquals(shareParams["skoid"], key.signedObjectId);
    test:assertTrue(shareParams.hasKey("sig"), "expected a signature");

    string fileToken = check fileClient.generateUserDelegationSas("/f.txt",
            {expiryTime: expiry, permissions: {read: true, delete: true}}, key);
    map<string> fileParams = sasParams(fileToken);
    test:assertEquals(fileParams["sp"], "rd");
    test:assertEquals(fileParams["sktid"], key.signedTenantId);
}

// Stored access policies do not apply to user delegation SAS, so the generators reject an
// identifier and require the explicit values. Validation runs before signing, so no key
// fetch or service call is involved and a placeholder key suffices.
@test:Config {}
function testUserDelegationSasRejectsIdentifierAndRequiresExplicitValues() returns error? {
    Client fileClient = check newShareClient(testShare("udsval"));
    time:Utc keyStart = [time:utcNow()[0], 0];
    UserDelegationKey key = {
        signedObjectId: "00000000-0000-0000-0000-000000000000",
        signedTenantId: "00000000-0000-0000-0000-000000000000",
        signedStart: keyStart,
        signedExpiry: time:utcAddSeconds(keyStart, 3600),
        signedService: "f",
        signedVersion: "2025-05-05",
        value: "ZmFrZQ=="
    };
    time:Utc expiry = time:utcAddSeconds(keyStart, 3600);

    string|Error identifierOnly = fileClient.generateShareUserDelegationSas( {identifier: "backup-policy"}, key);
    test:assertTrue(identifierOnly is Error && identifierOnly !is ServiceError,
            "expected a user delegation SAS with an identifier to fail client-side");
    if identifierOnly is Error {
        test:assertEquals(identifierOnly.message(),
                "a user delegation SAS cannot use a stored access policy identifier");
    }

    string|Error identifierAlongside = fileClient.generateUserDelegationSas("/f.txt",
            {expiryTime: expiry, permissions: {read: true}, identifier: "backup-policy"}, key);
    test:assertTrue(identifierAlongside is Error && identifierAlongside !is ServiceError,
            "expected an identifier alongside explicit values to fail client-side");

    string|Error expiryOnly = fileClient.generateShareUserDelegationSas( {expiryTime: expiry}, key);
    test:assertTrue(expiryOnly is Error && expiryOnly !is ServiceError,
            "expected a user delegation SAS without permissions to fail client-side");
    if expiryOnly is Error {
        test:assertEquals(expiryOnly.message(), "expiryTime and permissions must be set for a user delegation SAS");
    }
}

@test:Config {}
function testGenerateAccountSas() returns error? {
    AdminClient admin = check newAdmin();
    time:Utc expiry = check time:utcFromString("2026-08-01T00:00:00Z");

    string accountSas = check admin.generateAccountSas({
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

// ---------------------------------------------------------------------------
// Core gap-fills
// ---------------------------------------------------------------------------

@test:Config {}
function testRenameReplaceIfExists() returns error? {
    AdminClient admin = check newAdmin();
    string share = testShare("rename");
    check createTestShare(admin, share);
    Client fileClient = check newShareClient(share);
    check fileClient->upload("new", "/incoming.txt");
    check fileClient->upload("old", "/settled.txt");

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
    check createTestShare(admin, share);
    Client fileClient = check newShareClient(share);

    // 4 MiB is the service's maximum single-range size, so this upload must split.
    final int rangeCap = 4 * 1024 * 1024;
    string big = "".padStart(rangeCap, "A") + "TAIL";
    check fileClient->upload(big, "/large.bin");

    FileProperties props = check fileClient->getFileProperties("/large.bin");
    test:assertEquals(props.contentLength, rangeCap + 4);

    // Read across the split boundary: the last bytes of range one, the first of range two.
    stream<byte[], Error?> boundary = check fileClient->getFile("/large.bin",
            {range: {startByte: rangeCap - 2, endByte: rangeCap + 1}});
    test:assertEquals(check collectBytes(boundary), "AATA".toBytes());
}

@test:Config {}
function testEarlyStreamClose() returns error? {
    AdminClient admin = check newAdmin();
    string share = testShare("close");
    check createTestShare(admin, share);
    Client fileClient = check newShareClient(share);
    check fileClient->upload("0123456789", "/close.txt");
    check fileClient->createDirectory("/somedir");

    stream<byte[], Error?> content = check fileClient->getFile("/close.txt");
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
    check createTestShare(admin, share);
    Client fileClient = check newShareClient(share);

    stream<Entry, Error?>|Error missingDirectory = fileClient->list("/no-such-dir");
    test:assertTrue(missingDirectory is NotFoundError, "expected listing a missing directory to fail");

    stream<byte[], Error?>|Error missingContent = fileClient->getFile("/absent.txt");
    if missingContent is Error {
        test:assertTrue(missingContent is NotFoundError, "expected opening a missing file to fail as NotFound");
    } else {
        byte[]|error collected = collectBytes(missingContent);
        test:assertTrue(collected is error, "expected reading a missing file to fail");
    }

    stream<byte[], error?> failingSource = new (new FailingByteSource());
    Error? aborted = fileClient->uploadFromStream(failingSource, 10, "/failed.txt");
    test:assertTrue(aborted is Error && aborted !is ServiceError, "expected a failing source stream to abort");
}

@test:Config {}
function testUploadFromStreamOverflow() returns error? {
    AdminClient admin = check newAdmin();
    string share = testShare("overflow");
    check createTestShare(admin, share);
    Client fileClient = check newShareClient(share);

    byte[][] longChunks = ["abcdef".toBytes(), "ghijkl".toBytes()];
    Error? overflow = fileClient->uploadFromStream(longChunks.toStream(), 5, "/overflow.txt");
    test:assertTrue(overflow is Error && overflow !is ServiceError,
            "expected a stream longer than contentLength to fail");
}

@test:Config {}
function testConnectionStringClientOps() returns error? {
    AdminClient admin = check newAdmin();
    string share = testShare("cs");
    check createTestShare(admin, share);
    Client fileClient = check new (share, auth = {connectionString: testConnectionString()});
    check fileClient->upload("via connection string", "/cs.txt");
    test:assertEquals(check readAll(fileClient, "/cs.txt"), "via connection string".toBytes());
}

// ---------------------------------------------------------------------------
// SAS round-trip and open handles
// ---------------------------------------------------------------------------

@test:Config {}
function testSasRoundtrip() returns error? {
    AdminClient admin = check newAdmin();
    string share = testShare("sas-roundtrip");
    check createTestShare(admin, share);
    Client keyClient = check newShareClient(share);
    check keyClient->upload("sas readable", "/sas-probe.txt");

    time:Utc expiry = time:utcAddSeconds(time:utcNow(), 3600);
    string token = check keyClient.generateShareSas(
            {expiryTime: expiry, permissions: {read: true, list: true, delete: true}});

    // The minted token authenticates a fresh client through its full SAS URL. The mock
    // ignores signatures, so the signature itself is verified only live; the client
    // wiring runs in both modes.
    Client sasUrlClient = check new (share, auth = {sasUrl: string `${sasBaseUrl()}?${token}`});
    test:assertEquals(check readAll(sasUrlClient, "/sas-probe.txt"), "sas readable".toBytes());

    if liveRun {
        // SasConfig derives its endpoint from the account name, so it can only target
        // the real service.
        Client sasClient = check new (share, auth = {accountName: liveAccountName, sasToken: token});
        check sasClient->deleteFile("/sas-probe.txt");
    }
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
}

@test:Config {enable: liveEntraDefaultChainEnabled}
function testLiveEntraDefaultChainAuth() returns error? {
    // A NotFound answer for a nonexistent share proves the token was both authenticated
    // and authorized; a missing role surfaces as an authorization error instead.
    Client entraClient = check new ("entra-probe-share", auth = {kind: "default", accountName: liveAccountName});
    FileProperties|Error result = entraClient->getFileProperties("/probe.txt");
    if result is FileProperties {
        test:assertFail("expected NotFound for a nonexistent share, but got file properties");
    } else if result !is NotFoundError {
        test:assertFail("Entra call failed before an authorized NotFound: " + result.message());
    }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

isolated function readAll(Client fileClient, string path) returns byte[]|error {
    byte[] content = check fileClient->getFile(path);
    return content;
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

// ---------------------------------------------------------------------------
// Typed content reads and CSV upload
// ---------------------------------------------------------------------------

type TypedReadMetric record {|
    string quarter;
    int revenue;
|};

type TypedReadRow record {|
    string name;
    int qty;
|};

type TypedReadNote record {|
    string to;
    string body;
|};

type CsvTricky record {|
    string name;
    string note;
|};

@test:Config {}
function testGetFileStringTarget() returns error? {
    AdminClient admin = check newAdmin();
    string share = testShare("typed-text");
    check createTestShare(admin, share);
    Client fileClient = check newShareClient(share);
    check fileClient->upload("hello typed text", "/hello.txt");
    string full = check fileClient->getFile("/hello.txt");
    test:assertEquals(full, "hello typed text");

    check fileClient->upload("0123456789", "/digits.txt");
    string ranged = check fileClient->getFile("/digits.txt", {range: {startByte: 2, endByte: 5}});
    test:assertEquals(ranged, "2345");
}

@test:Config {}
function testGetFileRejectsInvalidUtf8() returns error? {
    AdminClient admin = check newAdmin();
    string share = testShare("typed-text-utf8");
    check createTestShare(admin, share);
    Client fileClient = check newShareClient(share);
    byte[] invalid = [0xC3, 0x28, 0xFF, 0xFE, 0x80];
    check fileClient->upload(invalid, "/binary.bin");
    string|Error text = fileClient->getFile("/binary.bin");
    test:assertTrue(text is Error && text !is ServiceError,
            "content that is not UTF-8 must fail the text read client-side");
    if text is Error {
        test:assertTrue(text.message().startsWith("the file content is not valid UTF-8 text"),
                "the error must state the content is not valid UTF-8 text");
    }
}

@test:Config {}
function testGetFileJsonTargets() returns error? {
    AdminClient admin = check newAdmin();
    string share = testShare("typed-json");
    check createTestShare(admin, share);
    Client fileClient = check newShareClient(share);

    check fileClient->upload(<map<json>>{"quarter": "q1", "revenue": 1250000}, "/metrics.json");
    json asJson = check fileClient->getFile("/metrics.json");
    test:assertEquals(asJson, {quarter: "q1", revenue: 1250000});
    TypedReadMetric asRecord = check fileClient->getFile("/metrics.json");
    test:assertEquals(asRecord, {quarter: "q1", revenue: 1250000});

    check fileClient->upload("[{\"name\":\"a\",\"qty\":1},{\"name\":\"b\",\"qty\":2}]", "/rows.json");
    TypedReadRow[] asArray = check fileClient->getFile("/rows.json");
    test:assertEquals(asArray, [{name: "a", qty: 1}, {name: "b", qty: 2}]);

    // An OPEN record array (the language default) binds too; it is not a json subtype,
    // so the target typedesc must admit record {}[] directly.
    check fileClient->upload(
            "[{\"quarter\":\"q1\",\"revenue\":1},{\"quarter\":\"q2\",\"revenue\":2}]", "/qs.json");
    UploadMetric[] asOpenArray = check fileClient->getFile("/qs.json");
    test:assertEquals(asOpenArray, [{quarter: "q1", revenue: 1}, {quarter: "q2", revenue: 2}]);

    check fileClient->upload("{not json", "/broken.json");
    json|Error broken = fileClient->getFile("/broken.json");
    test:assertTrue(broken is Error && broken !is ServiceError, "malformed JSON must fail the typed read client-side");
    if broken is Error {
        test:assertTrue(broken.message().startsWith("the file content does not bind"),
                "the binding error must state the content does not bind");
    }
}

@test:Config {}
function testGetFileXmlTargets() returns error? {
    AdminClient admin = check newAdmin();
    string share = testShare("typed-xml");
    check createTestShare(admin, share);
    Client fileClient = check newShareClient(share);

    xml note = xml `<note><to>ops</to><body>rotate the key</body></note>`;
    check fileClient->upload(note, "/note.xml");
    xml asXml = check fileClient->getFile("/note.xml");
    test:assertEquals(asXml.toString(), note.toString());
    TypedReadNote asRecord = check fileClient->getFile("/note.xml");
    test:assertEquals(asRecord, {to: "ops", body: "rotate the key"});

    check fileClient->upload("<open", "/broken.xml");
    xml|Error broken = fileClient->getFile("/broken.xml");
    test:assertTrue(broken is Error && broken !is ServiceError, "malformed XML must fail the typed read");
}

@test:Config {}
function testGetFileCsvTargets() returns error? {
    AdminClient admin = check newAdmin();
    string share = testShare("typed-csv");
    check createTestShare(admin, share);
    Client fileClient = check newShareClient(share);

    check fileClient->upload("name,qty\na,1\nb,2", "/items.csv");
    // A string matrix target compiles (it is a json subtype) but CSV binds record arrays only.
    string[][]|Error asRows = fileClient->getFile("/items.csv");
    test:assertTrue(asRows is Error && asRows !is ServiceError,
            "a string[][] target on CSV content must fail client-side");
    if asRows is Error {
        test:assertTrue(asRows.message().includes("record array"),
                "the refusal must point at record array targets");
    }
    TypedReadRow[] asRecords = check fileClient->getFile("/items.csv");
    test:assertEquals(asRecords, [{name: "a", qty: 1}, {name: "b", qty: 2}]);

    check fileClient->upload("name,qty\na,notanint", "/broken.csv");
    TypedReadRow[]|Error broken = fileClient->getFile("/broken.csv");
    test:assertTrue(broken is Error && broken !is ServiceError, "a CSV row that cannot bind must fail the typed read");
}

@test:Config {}
function testGetFileByteTarget() returns error? {
    AdminClient admin = check newAdmin();
    string share = testShare("get-bytes");
    check createTestShare(admin, share);
    Client fileClient = check newShareClient(share);

    byte[] payload = [0, 1, 2, 251, 252, 253];
    check fileClient->upload(payload, "/blob.bin");
    // A byte[] target materializes the raw content in one call, no format involved.
    byte[] raw = check fileClient->getFile("/blob.bin");
    test:assertEquals(raw, payload);

    byte[] ranged = check fileClient->getFile("/blob.bin", {range: {startByte: 2, endByte: 4}});
    test:assertEquals(ranged, <byte[]>[2, 251, 252]);
}

@test:Config {}
function testGetFileRecordFormatByExtension() returns error? {
    AdminClient admin = check newAdmin();
    string share = testShare("get-ext");
    check createTestShare(admin, share);
    Client fileClient = check newShareClient(share);

    // The same record binds from all three formats; the extension selects the parser.
    UploadMetric metric = {quarter: "q1", revenue: 7};
    check fileClient->upload(metric, "/m.json");
    check fileClient->upload(metric, "/m.xml");
    UploadMetric fromJson = check fileClient->getFile("/m.json");
    test:assertEquals(fromJson, metric);
    UploadMetric fromXml = check fileClient->getFile("/m.xml");
    test:assertEquals(fromXml, metric);

    UploadMetric[] metrics = [{quarter: "q1", revenue: 1}, {quarter: "q2", revenue: 2}];
    check fileClient->upload(metrics, "/m.csv");
    UploadMetric[] fromCsv = check fileClient->getFile("/m.csv");
    test:assertEquals(fromCsv, metrics);
}

@test:Config {}
function testGetFileFormatOverrideAndRefusal() returns error? {
    AdminClient admin = check newAdmin();
    string share = testShare("get-override");
    check createTestShare(admin, share);
    Client fileClient = check newShareClient(share);

    UploadMetric metric = {quarter: "q9", revenue: 3};
    check fileClient->upload(metric.toJsonString(), "/metric.dat");

    // A record target with no format-bearing extension and no override is refused.
    UploadMetric|Error unresolved = fileClient->getFile("/metric.dat");
    test:assertTrue(unresolved is Error && unresolved !is ServiceError,
            "a record target with an unresolvable format must fail client-side");
    if unresolved is Error {
        test:assertTrue(unresolved.message().includes("fileFormat"), "the error must point at the fileFormat override");
    }

    // The explicit override resolves it.
    UploadMetric resolved = check fileClient->getFile("/metric.dat", {fileFormat: JSON});
    test:assertEquals(resolved, metric);
}

@test:Config {}
function testGetFileCsvRowStream() returns error? {
    AdminClient admin = check newAdmin();
    string share = testShare("get-rowstream");
    check createTestShare(admin, share);
    Client fileClient = check newShareClient(share);

    check fileClient->upload("name,qty\na,1\nb,2\nc,3", "/rows.csv");
    stream<TypedReadRow, error?> rows = check fileClient->getFile("/rows.csv");
    TypedReadRow[] collected = [];
    record {|TypedReadRow value;|}|error? entry = rows.next();
    while entry is record {|TypedReadRow value;|} {
        collected.push(entry.value);
        entry = rows.next();
    }
    test:assertTrue(entry is (), "the row stream must end cleanly");
    test:assertEquals(collected, [{name: "a", qty: 1}, {name: "b", qty: 2}, {name: "c", qty: 3}]);

    // A malformed row surfaces as the error entry of that next() call.
    check fileClient->upload("name,qty\nok,1\nbad,notanint", "/badrows.csv");
    stream<TypedReadRow, error?> badRows = check fileClient->getFile("/badrows.csv");
    record {|TypedReadRow value;|}|error? first = badRows.next();
    test:assertTrue(first is record {|TypedReadRow value;|}, "the valid first row must bind");
    record {|TypedReadRow value;|}|error? second = badRows.next();
    test:assertTrue(second is error, "the malformed row must surface as the next() error");
}

@test:Config {}
function testUploadContentCsvRoundTrip() returns error? {
    AdminClient admin = check newAdmin();
    string share = testShare("csv-write");
    check createTestShare(admin, share);
    Client fileClient = check newShareClient(share);

    CsvTricky[] rows = [
        {name: "alpha", note: "a,b"},
        {name: "beta", note: "say \"hi\""},
        {name: "gamma", note: "line1\nline2"},
        {name: "delta", note: "back\\slash"}
    ];
    check fileClient->upload(rows, "/tricky.csv");
    CsvTricky[] roundTripped = check fileClient->getFile("/tricky.csv");
    test:assertEquals(roundTripped, rows);

    // The exact bytes pin the writer dialect: quote on comma, quote, backslash, or line
    // break, with backslash escaping (the dialect data.csv reads by default).
    string csvText = check string:fromBytes(check readAll(fileClient, "/tricky.csv"));
    test:assertEquals(csvText,
            "name,note\nalpha,\"a,b\"\nbeta,\"say \\\"hi\\\"\"\ngamma,\"line1\nline2\"\ndelta,\"back\\\\slash\"");

    CsvTricky[] empty = [];
    check fileClient->upload(empty, "/empty.csv");
    test:assertEquals(check readAll(fileClient, "/empty.csv"), <byte[]>[]);
}
