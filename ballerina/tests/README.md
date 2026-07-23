# Running the tests

There is one test suite, and every test is just a test. Each test targets live Azure as the ground truth and also runs against an in-process mock of the Azure Files REST service. The backend for a run is chosen by credential presence:

- **No credentials configured**: the whole suite runs against the mock. No Azure account, no network, works on every machine. This is what CI and fork pull requests run.
- **Credentials configured** (Config.toml or environment): the suite runs against the real storage account instead. One backend per run; a live run never silently falls back to the mock.

```sh
cd ballerina
bal test
```

## Backend selection

`backend.bal` reads `liveAccountName`/`liveAccountKey` (Config.toml entries, or the `LIVE_ACCOUNT_NAME`/`LIVE_ACCOUNT_KEY` environment variables; a Config.toml entry takes precedence). When both are set, the client factories build clients against the real account; otherwise they point at the mock on `localhost:9099`. To force a mock run on a machine that has credentials, move `tests/Config.toml` aside for that run.

A small number of tests deviate from the both-backends rule, each for a stated physical reason:

- **Pinned to the mock** (their bodies use the explicit mock factories): `testErrorCodeMapping` (forces service error codes such as quota exhaustion and internal errors that a real account cannot produce on demand), `testRetryAndTransportConfig` (retry and proxy behavior needs an endpoint that can be made to fail), and `testSmbHandles` (an open SMB handle exists only while a real SMB client has the share mounted, which no REST call can produce; `testNoOpenHandles` covers the zero-handle case in both modes). These still run in every run, including live runs, because the mock listener is always up.
- **Entra-gated**: `testGetUserDelegationKey` and `testGenerateUserDelegationSas` always run on the mock, but live they need the Entra credentials below (Azure rejects user-delegation requests made with shared key) and skip without them. `testLiveEntraAuth` and `testLiveEntraDefaultChainAuth` are live-only: mocking the identity service would exercise Microsoft's SDK rather than this connector.
- **Account-kind-gated**: `testNfsLinks` needs a premium account when live (see below) and skips in a live run on a standard account.

## The mock

`mock_service.bal` starts an in-process HTTP service on `localhost:9099` that speaks enough of the Azure Files REST protocol for the real `azure-storage-file-share` SDK to run against it, statefully (uploaded bytes are stored and served back). The mock ignores authentication, which is why the SAS signature tests only prove real verification in live runs. The mock must keep up with the tests, never the reverse: a test is written to pass against Azure first.

When extending the mock:

- The mock is a non `isolated` service: requests dispatch serially, so its in-memory state needs no locking (the compiler hint about this is expected).
- A path segment of the form `__err-<status>-<AzureErrorCode>` (for example `/__err-403-ShareSizeLimitReached`) makes the mock return that error response; the error-mapping test uses this.
- HEAD responses must carry the file's real content, so the listener computes the correct `Content-Length` (the body is stripped on the wire).

## Live runs

### One-time Azure setup

1. In the [Azure portal](https://portal.azure.com), create a **storage account** for Azure Files with a **classic (SMB) file share** configuration: Standard performance, **Pay-as-you-go** file share billing, LRS redundancy. Keep share **soft delete** enabled (the default); the share-lifecycle test exercises undelete.
2. Keep **Allow storage account key access** enabled (it is by default); the tests authenticate with the account key.
3. After deployment, open **Security + networking → Access keys** and copy the storage account name and the key1 value.

The suite is account-kind adaptive: pointed at a **premium (FileStorage)** account instead, it detects the kind at runtime and adjusts the tier and quota assertions, and `testNfsLinks` runs live against a real NFS share. A standard account remains the primary target (it is what most users run); a premium run is an optional second pass for the premium-specific behaviors.

### Configure and run

Create `ballerina/tests/Config.toml` (gitignored; never commit it) with:

```toml
liveAccountName = "<storage account name>"
liveAccountKey = "<key1>"

# optional: enables the Entra ID auth test and the live user-delegation tests; the app
# registration needs a client secret and the Storage File Data Privileged Contributor
# role on the account
# liveEntraTenantId = "<tenant id>"
# liveEntraClientId = "<application id>"
# liveEntraClientSecret = "<client secret>"
```

Note the location: for `bal test`, configurable values are read from `Config.toml` inside the `tests/` directory, not the package root. Role assignments can take a few minutes to propagate; if a freshly configured Entra test fails with an authorization error, wait and rerun.

The credential values can also be supplied as environment variables: `LIVE_ACCOUNT_NAME`, `LIVE_ACCOUNT_KEY`, `LIVE_ENTRA_TENANT_ID`, `LIVE_ENTRA_CLIENT_ID`, `LIVE_ENTRA_CLIENT_SECRET`. This is how the repository's CI receives them from repository secrets of the same names; runs without those secrets (for example fork pull requests) run the suite against the mock and stay green.

A second Entra test covers the default credential chain. It enables itself when the standard Azure environment variables `AZURE_TENANT_ID`, `AZURE_CLIENT_ID`, and `AZURE_CLIENT_SECRET` are set (environment only, no Config.toml entries: the default chain authenticates from the environment by design), and the identity they name needs the same Storage File Data Privileged Contributor role.

### Share naming, cost, and cleanup

Each test creates its own share under a per-run prefix, `azft-<run id>-` on GitHub Actions or `azft-<epoch seconds>-` locally, so reruns never collide with leftovers from an interrupted run. An `AfterSuite` cleanup deletes every share carrying the run's prefix (snapshots included), breaking stray leases where needed. A live run churns roughly fifty small shares; with soft delete enabled the deleted shares sit in the 7-day retention window at negligible cost for test-sized data. Shares abandoned by a crashed run keep their run's prefix and can be swept manually (`az storage share list --include-deleted` filtered on `azft-`).

Treat the account key as a development-only secret: it can be regenerated at any time under **Access keys**, which immediately invalidates the old value.

## Gradle and Docker

`./gradlew build` runs `bal test` inside the `ballerina/ballerina` Docker container (standard behavior of the Ballerina Gradle plugin for connectors), mounting the repository. The same credential rule applies: with `ballerina/tests/Config.toml` present the containerized suite runs live, and without it the run is mock-backed.
