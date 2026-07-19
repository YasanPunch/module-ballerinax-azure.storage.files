# Running the tests

The suite has two groups: `mock` (credential-free, runs everywhere) and `live` (real Azure, opt-in).

## The mock group

```sh
cd ballerina
bal test --groups mock
```

`mock_service.bal` starts an in-process HTTP service on `localhost:9099` that speaks enough of the Azure Files REST protocol for the real `azure-storage-file-share` SDK to run against it. The tests reach it through the `serviceUrl` field of `SharedKeyConfig`, with a syntactically valid but fake account key (the mock ignores authentication). No Azure account, credentials, or network access is needed, so this group runs on every build, including CI and fork pull requests.

When extending the mock:

- The mock is a non `isolated` service: requests dispatch serially, so its in-memory state needs no locking (the compiler hint about this is expected).
- A path segment of the form `__err-<status>-<AzureErrorCode>` (for example `/__err-403-ShareSizeLimitReached`) makes the mock return that error response; the error-mapping tests use this.
- HEAD responses must carry the file's real content, so the listener computes the correct `Content-Length` (the body is stripped on the wire).

## The live group

Smoke tests against a real storage account: they create a share (`bal-azfiles-live-tests` by default), round-trip a file through it, and delete everything again.

### One-time Azure setup

1. In the [Azure portal](https://portal.azure.com), create a **storage account** for Azure Files with a **classic (SMB) file share** configuration: Standard performance, **Pay-as-you-go** file share billing, LRS redundancy. The tests use the REST API, so the SMB/NFS mount choice does not matter beyond this; premium/provisioned options only add cost.
2. Keep **Allow storage account key access** enabled (it is by default); the tests authenticate with the account key.
3. After deployment, open **Security + networking → Access keys** and copy the storage account name and the key1 value.

### Configure and run

Create `ballerina/tests/Config.toml` (gitignored; never commit it) with:

```toml
liveAccountName = "<storage account name>"
liveAccountKey = "<key1>"
# optional, defaults to "bal-azfiles-live-tests"
# liveShareName = "my-test-share"

# optional: enables the Microsoft Entra ID smoke test. Needs an app registration
# holding the Storage File Data Privileged Contributor role on the account.
# liveEntraTenantId = "<tenant id>"
# liveEntraClientId = "<application id>"
# liveEntraClientSecret = "<client secret>"
```

Note the location: for `bal test`, configurable values are read from `Config.toml` inside the `tests/` directory, not the package root.

```sh
cd ballerina
bal test --groups live    # only the live smoke tests
bal test                  # mock + live together
```

When the two values are absent or empty, the live tests disable themselves (`bal test --groups live` then reports "No tests found"), which is what keeps CI and forks green without secrets.

### Cost and cleanup

The tests delete the share they create. With soft delete enabled (the account default), the deleted share is retained for 7 days at negligible cost for test-sized data. Treat the account key as a development-only secret: it can be regenerated at any time under **Access keys**, which immediately invalidates the old value.

## Gradle and Docker

`./gradlew build` runs `bal test` inside the `ballerina/ballerina` Docker container (standard behavior of the Ballerina Gradle plugin for connectors), mounting the repository. That means it runs both groups: the mock group always, and the live group too whenever `ballerina/tests/Config.toml` holds credentials, since the container reads the mounted file and has outbound network access. Without the config file, the Gradle build stays mock-only.
