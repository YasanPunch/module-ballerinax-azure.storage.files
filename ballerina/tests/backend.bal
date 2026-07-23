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

// Test backend selection. The suite runs against live Azure when account credentials are
// configured (Config.toml, or the environment variables CI supplies from repository
// secrets) and against the in-process mock FileREST service otherwise. One backend per
// run: credentials present means live only.

import ballerina/lang.runtime;
import ballerina/os;
import ballerina/test;
import ballerina/time;

// Credentials come from Config.toml, or from environment variables when no Config.toml
// entry is present (how CI supplies them from repository secrets).
configurable string liveAccountName = os:getEnv("LIVE_ACCOUNT_NAME");
configurable string liveAccountKey = os:getEnv("LIVE_ACCOUNT_KEY");

// Microsoft Entra ID credentials. Needed by the Entra auth tests and, in live runs, by
// the user-delegation tests (Azure rejects user-delegation requests made with shared
// key). The identity must hold the Storage File Data Privileged Contributor role on the
// account. The default-chain test enables itself when the standard Azure environment
// variables are present, which the default credential chain consumes identically
// wherever the tests run (host shell, container, CI).
configurable string liveEntraTenantId = os:getEnv("LIVE_ENTRA_TENANT_ID");
configurable string liveEntraClientId = os:getEnv("LIVE_ENTRA_CLIENT_ID");
configurable string liveEntraClientSecret = os:getEnv("LIVE_ENTRA_CLIENT_SECRET");

// One backend per run, chosen by credential presence.
final boolean liveRun = liveAccountName != "" && liveAccountKey != "";

final boolean liveEntraEnabled = liveRun && liveEntraTenantId != ""
    && liveEntraClientId != "" && liveEntraClientSecret != "";
final boolean liveEntraDefaultChainEnabled = liveRun
    && os:getEnv("AZURE_TENANT_ID") != ""
    && os:getEnv("AZURE_CLIENT_ID") != ""
    && os:getEnv("AZURE_CLIENT_SECRET") != "";

// A syntactically valid (base64) but fake account key; the mock ignores authentication.
const string MOCK_KEY = "bW9jay1hY2NvdW50LWtleS1mb3ItdGVzdHM=";

// Every share name carries a per-run prefix, so a live rerun never collides with
// leftovers from an earlier failed run and the end-of-suite cleanup can find everything
// this run created by prefix alone.
final string sharePrefix = buildSharePrefix();

isolated function buildSharePrefix() returns string {
    string runId = os:getEnv("GITHUB_RUN_ID");
    string tag = runId != "" ? runId : time:utcNow()[0].toString();
    return string `azft-${tag}`;
}

isolated function testShare(string base) returns string => string `${sharePrefix}-${base}`;

// Backend-switching factories: tests obtain their clients here and stay unaware of
// which backend the run uses.
isolated function newAdmin() returns AdminClient|Error => liveRun
    ? new (auth = {accountName: liveAccountName, accountKey: liveAccountKey})
    : newMockAdmin();

isolated function newShareClient(string share) returns Client|Error => liveRun
    ? new (share, auth = {accountName: liveAccountName, accountKey: liveAccountKey})
    : newMockShareClient(share);

// Explicit mock factories, for the tests that are pinned to the mock because the
// condition they exercise cannot be produced on a real account.
isolated function newMockAdmin() returns AdminClient|Error => new (auth = {
    accountName: "mockaccount",
    accountKey: MOCK_KEY,
    serviceUrl: string `http://localhost:${MOCK_PORT}`
});

isolated function newMockShareClient(string share) returns Client|Error => new (share, auth = {
    accountName: "mockaccount",
    accountKey: MOCK_KEY,
    serviceUrl: string `http://localhost:${MOCK_PORT}`
});

// Entra-authenticated admin client, for the user-delegation tests in live runs.
isolated function newEntraAdmin() returns AdminClient|Error => new (auth = {
    accountName: liveAccountName,
    tenantId: liveEntraTenantId,
    clientId: liveEntraClientId,
    clientSecret: liveEntraClientSecret
});

// The connection string for the current backend.
isolated function testConnectionString() returns string => liveRun
    ? string `DefaultEndpointsProtocol=https;AccountName=${liveAccountName};AccountKey=${liveAccountKey};EndpointSuffix=core.windows.net`
    : string `DefaultEndpointsProtocol=http;AccountName=mockaccount;AccountKey=${MOCK_KEY};FileEndpoint=http://localhost:${MOCK_PORT}`;

// The account base URL for the current backend, for building SAS and copy-source URLs.
isolated function sasBaseUrl() returns string => liveRun
    ? string `https://${liveAccountName}.file.core.windows.net`
    : string `http://localhost:${MOCK_PORT}`;

// Whether the live account is a premium (FileStorage) account. Premium and standard
// accounts speak the same wire contract but differ in a few observable behaviors
// (access tiers, quota-as-provisioned-size, NFS availability), so the affected
// assertions branch on this. Probed once per run from a created share's access tier.
boolean? premiumAccountCache = ();

function isPremiumAccount() returns boolean|error {
    boolean? cached = premiumAccountCache;
    if cached is boolean {
        return cached;
    }
    boolean premium = false;
    if liveRun {
        AdminClient admin = check newAdmin();
        string probe = testShare("kind-probe");
        check admin->createShare(probe, {quotaInGb: 40});
        Client probeClient = check newShareClient(probe);
        ShareProperties props = check probeClient->getShareProperties();
        premium = props.accessTier == PREMIUM;
        check probeClient.close();
        check admin->deleteShare(probe);
        check admin.close();
    }
    premiumAccountCache = premium;
    return premium;
}

// Polls until the probe reports true. The mock serves every effect synchronously, so
// the first probe already holds there and no delay occurs; live Azure serves a few
// effects asynchronously (copy completion, share statistics, soft-delete visibility).
function await(function () returns boolean|error probe, decimal timeoutSeconds = 60,
        decimal intervalSeconds = 2) returns error? {
    decimal waited = 0;
    while true {
        boolean|error met = probe();
        if met is boolean && met {
            return;
        }
        if waited >= timeoutSeconds {
            if met is error {
                return met;
            }
            return error(string `condition not met within ${timeoutSeconds}s`);
        }
        runtime:sleep(intervalSeconds);
        waited += intervalSeconds;
    }
}

// Live runs create one share per test; delete everything this run's prefix owns so a
// green run leaves the account clean. Best effort on purpose: a share that resists
// deletion (for example a lease left by a failed test) must not flip the suite red.
@test:AfterSuite {alwaysRun: true}
function cleanupTestShares() returns error? {
    if !liveRun {
        return;
    }
    AdminClient admin = check newAdmin();
    ShareInfo[] leftovers = check admin->listShares({prefix: sharePrefix});
    foreach ShareInfo shareInfo in leftovers {
        Error? deleted = admin->deleteShare(shareInfo.name, {deleteSnapshots: INCLUDE});
        if deleted is Error {
            Client shareClient = check newShareClient(shareInfo.name);
            int|Error broken = shareClient->breakShareLease();
            check shareClient.close();
            Error? retried = admin->deleteShare(shareInfo.name, {deleteSnapshots: INCLUDE});
            if broken is Error || retried is Error {
                // Left behind; the next run's fresh prefix keeps it out of the way.
            }
        }
    }
    check admin.close();
}
