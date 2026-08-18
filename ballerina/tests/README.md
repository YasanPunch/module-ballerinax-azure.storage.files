# Running the tests

There is one suite and two interchangeable backends, and a run uses exactly one. When both `liveAccountName` and `liveAccountKey` are configured, the whole suite runs against that real storage account; otherwise it runs against an in-process mock of the Azure Files REST service (no Azure account, no network, works on every machine). CI without secrets, including fork pull requests, is a mock run.

```sh
cd ballerina
bal test
```

## Backend selection

`backend.bal` reads `liveAccountName`/`liveAccountKey` from Config.toml, or from the `LIVE_ACCOUNT_NAME`/`LIVE_ACCOUNT_KEY` environment variables (a Config.toml entry takes precedence). A live run never silently falls back to the mock. To force a mock run on a machine that has credentials, move `tests/Config.toml` aside for that run.

A few tests deviate from the one-backend rule for physical reasons and self-select, so no action is needed: `testErrorCodeMapping` and `testRetryAndTransportConfig` always use the mock; the user-delegation and Entra tests need the Entra credentials below when live. The comment on each of these tests states its reason.

## The mock

`mock_service.bal` starts a stateful in-process HTTP service on `localhost:9099` that speaks enough of the Azure Files REST protocol for the real `azure-storage-file-share` SDK to run against it. When extending it:

- The mock is a non `isolated` service: requests dispatch serially, so its in-memory state needs no locking (the compiler hint about this is expected).
- A path segment of the form `__err-<status>-<AzureErrorCode>` (for example `/__err-403-ShareSizeLimitReached`) makes the mock return that error response; the error-mapping test uses this.
- `mockRequestLog` records every request as `METHOD /segments comp=<comp> host=<host header>`; a test clears it by assignment and filters by its own share name (the retry and range-count tests use this).
- Setting `mockFaultRemaining` to N makes the next N requests, of any operation, fail with `mockFaultStatus`/`mockFaultCode` (default 500 `InternalError`); unlike the listing-only `mockListFaultCode` hook it counts down on its own, but reset it after asserting so a test failure cannot leak faults into the next test.
- HEAD responses must carry the file's real content, so the mock's HTTP layer computes the correct `Content-Length` (the body is stripped on the wire).

## Live runs

### One-time Azure setup

1. In the [Azure portal](https://portal.azure.com), create a **storage account** for Azure Files with a **classic (SMB) file share** configuration: Standard performance, **Pay-as-you-go** file share billing, LRS redundancy. Keep share **soft delete** enabled (the default); the share-lifecycle test exercises undelete.
2. Keep **Allow storage account key access** enabled (it is by default); the tests authenticate with the account key.
3. After deployment, open **Security + networking** > **Access keys** and copy the storage account name and the key1 value.

Pointed at a **premium (FileStorage)** account instead, the suite adapts its tier and quota assertions, as an optional second pass for the premium-specific behaviors. Two premium account settings matter: create it with the **provisioned v2** billing model (v1's 100 GiB minimum share size is above what the suite provisions), and **disable share soft delete** on it, because a soft-deleted premium share keeps holding its provisioned IOPS against the account-wide limit, so retained shares from earlier runs would starve later ones. Because soft delete is off there, the share-lifecycle test exercises its undelete tail only on standard accounts and the mock.

### Configure and run

Create `ballerina/tests/Config.toml` (gitignored; never commit it) with the following values:

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

The credential values can also be supplied as environment variables: `LIVE_ACCOUNT_NAME`, `LIVE_ACCOUNT_KEY`, `LIVE_ENTRA_TENANT_ID`, `LIVE_ENTRA_CLIENT_ID`, `LIVE_ENTRA_CLIENT_SECRET`. This is how the repository's CI receives them from repository secrets of the same names.

A second Entra test covers the default credential chain. It enables itself when the standard Azure environment variables `AZURE_TENANT_ID`, `AZURE_CLIENT_ID`, and `AZURE_CLIENT_SECRET` are set (environment only, no Config.toml entries: the default chain authenticates from the environment by design), and the identity they name needs the same Storage File Data Privileged Contributor role.

### Share naming, cost, and cleanup

Each test creates its own share under a per-run prefix, `azft-<run id>-` on GitHub Actions or `azft-<epoch seconds>-` locally, so reruns never collide with leftovers from an interrupted run. Shares are deleted automatically as the run proceeds and swept again at suite end. A live run churns roughly fifty small shares; with soft delete enabled the deleted shares sit in the 7-day retention window at negligible cost for test-sized data. Shares abandoned by a crashed run keep their run's prefix and can be listed for manual sweeping:

```sh
az storage share-rm list --storage-account <account-name> --include-deleted --query "[?starts_with(name, 'azft-')]"
```

Treat the account key as a development-only secret: it can be regenerated at any time under **Access keys**, which immediately invalidates the old value.

## Gradle

`./gradlew build` (or `./gradlew test`) runs the same `bal test` natively, using the Ballerina distribution the build downloads and manages. The same credential rule applies: without credentials the run is mock-backed.
