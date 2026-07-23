# Specification: Ballerina Azure Files connector

_Authors_: @YasanPunch \
_Created_: 2026/07/13 \
_Updated_: 2026/07/23 \
_Edition_: Swan Lake

## Summary

Ballerina's current support for Azure Files lives inside `ballerinax/azure_storage_service`, a combined package that re-implements the Azure Storage REST protocol (Shared Key signing, chunked transfer, error handling) by hand and is pinned to the 2019-12-12 API version. This specification introduces **ballerinax/azure.storage.files**, a standalone connector for [Azure Files](https://learn.microsoft.com/en-us/azure/storage/files/storage-files-introduction) built on Microsoft's official `com.azure:azure-storage-file-share` Java SDK. It provides a two-tier client (`AdminClient` for account-level operations, `Client` bound to one share), a union-typed authentication model, and a consistent error hierarchy. A polling `Listener` for event-driven services follows in a later release. It is the sibling of `ballerinax/azure.storage.blob` and shares its design conventions.

## Motivation

The existing `azure_storage_service.files` module has accumulated several problems:

1. **Hand-written protocol layer:** Shared Key signing, chunked upload, and response parsing are implemented in Ballerina and pinned to the 2019-12-12 REST API version. Every protocol fix and every new service capability must be re-implemented by hand.
2. **Fully in-memory transfers:** `getFile` buffers the entire file before writing to disk, and the hand-rolled chunked upload both swallows failures in a logging side effect and carries a chunk-size discrepancy between its two size constants.
3. **Ambiguous configuration:** the auth record makes every field optional (`accessKeyOrSAS?`, `accountName?`), so misconfiguration surfaces as a runtime failure instead of a compile error.
4. **Inconsistent error handling:** error subtypes are defined but applied inconsistently, and an empty directory listing is raised as an error even though it is a valid state.
5. **No event-driven support:** there is no listener, so applications that react to files arriving in a share must hand-roll polling.
6. **No tests in CI:** the legacy tests are live-only and CI skips them entirely.
7. **Combined packaging:** file support is a submodule of a package that also covers Blob, so users pull one large artifact for one service, against the prevailing one-package-per-service pattern of the Azure ecosystem.

Microsoft's own SDKs solve the protocol problems once, centrally: `azure-storage-file-share` encapsulates signing, SAS construction, retry policies, parallel chunked transfer, connection-string parsing, and parity with new REST API versions. Wrapping the SDK instead of the REST API means the connector inherits all of this and Microsoft remains responsible for maintaining it.

## Goals

* Provide an idiomatic Ballerina API for Azure Files with a focused core surface: share lifecycle, directory and file CRUD, upload/download (disk, in-memory, stream), listing, properties and metadata, rename/move, copy, and byte ranges.
* Match Microsoft's two-tier mental model: `AdminClient` for account-level operations and `Client(shareName)` for everything inside one share.
* Provide a union-typed authentication model where each member is exactly one real-world credential artifact and misconfiguration is a compile error.
* Provide a consistent, pattern-matchable error hierarchy keyed on the Azure error code.
* Be a strict superset of the file surface of the existing `azure_storage_service` connector, so existing users can migrate with no loss of functionality.
* Provide, in a later release, a polling `Listener` (there is no Event Grid source for Azure Files) with a `Caller` so handlers can act on the event's file without constructing a separate client.

## Non-Goals

- **No Blob, Queue, or Table support.** Blob is the sibling package `azure.storage.blob`; Queue and Table would be their own future packages.
- **No re-implementation of the wire protocol.** Authentication, signing, retry, and chunked transfer are delegated to the official SDK.

## Design

### 1. Module overview

The module is `ballerinax/azure.storage.files`. The hierarchical name groups it with its sibling `azure.storage.blob`, following the pattern of `azure.openai.chat` and `azure.openai.responses`. The package has two parts: a `ballerina/` module holding the public API and a `native/` Java subproject that adapts it onto `com.azure:azure-storage-file-share`.

Microsoft's SDK is structured as a chain of four clients (`ShareServiceClient` account scope, `ShareClient` share scope, `ShareDirectoryClient`, `ShareFileClient`). The connector exposes the two scopes users actually think in:

- **`AdminClient`**: account level. List, create, delete, and restore shares. Used by admin tooling and applications that work with multiple shares.
- **`Client`**: bound to one share at `init`. All directory, file, transfer, copy, and range operations, plus share-level properties and metadata. This is the client most applications instantiate.

The lower SDK levels are not surfaced as classes. Directory and file operations are methods on `Client` taking a single slash-delimited, share-relative `path` (for example `"/reports/2026/q4.pdf"`); the Java adaptor splits the path into the segments the SDK requires. Where two paths co-occur they are named `sourcePath` and `destinationPath` in logical source-first order.

Because `azure-storage-blob` and `azure-storage-file-share` depend on the same `azure-storage-common` artifact, splitting Blob and Files into two Ballerina packages duplicates nothing at the JVM level: the auth, signing, and retry layer is shared by Microsoft's own packaging.

### 2. Authentication

#### 2.1 The `AuthConfig` union

Each union member is exactly one real-world credential artifact, the thing the portal, CLI, or IaC tooling actually hands the user:

```ballerina
# The authentication configuration: exactly one credential-artifact record.
public type AuthConfig SharedKeyConfig|SasConfig|SasUrlConfig|ConnectionStringConfig|EntraIdConfig;
```

`EntraIdConfig` covers Microsoft Entra ID authentication (DefaultAzureCredential, managed identity, client secret, client certificate, workload identity).

#### 2.2 Credential records

```ballerina
# Authenticates with the storage account name and key (Shared Key).
public type SharedKeyConfig record {|
    # Storage account name, the signing identity
    string accountName;
    # Storage account access key (base64)
    string accountKey;
    # Overrides where requests are sent; defaults to `https://{accountName}.file.core.windows.net`
    string serviceUrl?;
|};

# Authenticates with a bare shared access signature (SAS) token.
public type SasConfig record {|
    # Storage account name, used to derive the service URL
    string accountName;
    # The SAS token, e.g. `sv=...&sig=...`
    string sasToken;
|};

# Authenticates with the portal's fused SAS URL (endpoint and token in one string).
public type SasUrlConfig record {|
    # The full File service SAS URL
    string sasUrl;
|};

# Authenticates with a storage account connection string, which carries the endpoint.
public type ConnectionStringConfig record {|
    # The connection string as shown in the portal
    string connectionString;
|};

public type ClientConfiguration record {|
    # The authentication configuration
    AuthConfig auth;
    # Retry behaviour for service requests; omit for the service defaults (section 6)
    RetryConfig retryConfig?;
    # HTTP transport settings (proxy, connection pool, TLS); omit for the defaults (section 6)
    TransportConfig transportConfig?;
|};
```

Each of the four credential-artifact records has a unique required field, so both the compiler and `Config.toml` select the right member by structural matching, with no discriminator field. (The two Entra ID chain records, which are structurally identical, are the exception: they carry a `kind` discriminator.)

```toml
# The fields present select the union member:
[myapp.filesConfig]
auth = {accountName = "myacct", accountKey = "..."}               # SharedKeyConfig
# auth = {accountName = "myacct", sasToken = "sv=..."}            # SasConfig
# auth = {sasUrl = "https://myacct.file.core.windows.net/?sv=..."}# SasUrlConfig
# auth = {connectionString = "..."}                               # ConnectionStringConfig
```

Every auth mode is validated at `init` with local computation and no call to Azure: connection strings run the SDK's own strict parser plus a file-endpoint check, and the explicit records get non-empty, base64, and URL-scheme checks. A malformed credential surfaces a specific error at `init` rather than an opaque failure at first use.

### 3. The `AdminClient`

The core `AdminClient` surface is the share lifecycle plus an existence check:

```ballerina
public isolated function init(*ClientConfiguration config) returns Error?;

public function close() returns Error?;

remote function hasShare(string shareName) returns boolean|Error;

remote function listShares(ShareListOptions? options = ()) returns ShareInfo[]|Error;

remote function createShare(string shareName, ShareCreateOptions? options = ()) returns Error?;

remote function deleteShare(string shareName, ShareDeleteOptions? options = ()) returns Error?;

remote function undeleteShare(string shareName, string version) returns Error?;
```

`config` is an included record parameter; callers pass its fields as named arguments, e.g. `new (auth = {accountName, accountKey})`. `hasShare` returns `false` only when Azure confirms absence (404); an `Error` means the check itself could not complete, so an auth problem is never misreported as a missing share. `deleteShare` is soft under the account's soft-delete retention policy and restorable via `undeleteShare`.

### 4. The `Client`

```ballerina
public isolated function init(string shareName, *ClientConfiguration config) returns Error?;

public function close() returns Error?;
```

Binding is lazy: `init` makes no call to Azure, so the first operation against a nonexistent share fails with `NotFoundError`; the up-front check is `AdminClient.hasShare`. Every operation on both public classes is an `isolated remote function` on an `isolated` class holding only immutable configuration, so concurrent invocation from parallel strands is safe (the qualifier is omitted below for brevity). `close` is an ordinary method rather than a remote one, because it makes no call to Azure.

A method name carries the `File` token either to disambiguate a verb that also exists for directories (`createFile` next to `createDirectory`) or to keep a bare verb from implying it handles directories when it is file-only (`uploadFile`, `downloadFile`, `copyFile`). Verbs whose object is already explicit stay bare (`uploadContent`, `uploadRange`, `setContentHeaders`), and `list` is deliberately tier-neutral because it returns files and directories in one stream.

#### 4.1 Share-level operations

```ballerina
remote function getShareProperties() returns ShareProperties|Error;

remote function setShareMetadata(map<string> metadata) returns Error?;

# Returns the approximate stored bytes.
remote function getShareUsage() returns int|Error;
```

#### 4.2 Directory operations

```ballerina
remote function createDirectory(string directoryPath, DirectoryCreateOptions? options = ()) returns Error?;

remote function deleteDirectory(string directoryPath) returns Error?;

remote function hasDirectory(string directoryPath) returns boolean|Error;

remote function getDirectoryProperties(string directoryPath) returns DirectoryProperties|Error;

remote function setDirectoryMetadata(string directoryPath, map<string> metadata) returns Error?;

# Lists both files and subdirectories, as one stream.
remote function list(string directoryPath, ListOptions? options = ()) returns stream<Entry, Error?>|Error;

# Rename doubles as move.
remote function renameDirectory(string sourcePath, string destinationPath, RenameOptions? options = ()) returns Error?;
```

Every `Entry` from `list` carries its full share-relative path, so entries feed directly into the path-taking operations. Rename doubles as move: the destination is a full share-relative path, so `"/X/A"` to `"/Y/A"` re-parents within the same share.

#### 4.3 File operations

```ballerina
remote function createFile(string path, int sizeInBytes, CreateOptions? options = ()) returns Error?;

remote function deleteFile(string path) returns Error?;

remote function hasFile(string path) returns boolean|Error;

remote function getFileProperties(string path) returns FileProperties|Error;

remote function setFileMetadata(string path, map<string> metadata) returns Error?;

# Replaces the complete content-header set; omitted headers are cleared.
remote function setContentHeaders(string path, ContentHeaders headers) returns Error?;

remote function renameFile(string sourcePath, string destinationPath, RenameOptions? options = ()) returns Error?;
```

Metadata is read via `getFileProperties().metadata`; only a setter is exposed.

#### 4.4 Transfer operations

```ballerina
# Both paths are full paths including the file name, in source-first order.
remote function uploadFile(string sourcePath, string destinationPath, UploadOptions? options = ()) returns Error?;

remote function uploadContent(byte[]|string|xml|map<json> content, string destinationPath, UploadOptions? options = ()) returns Error?;

remote function uploadFromStream(stream<byte[], error?> content, int contentLength, string destinationPath, UploadOptions? options = ()) returns Error?;

remote function downloadFile(string sourcePath, string destinationPath, DownloadOptions? options = ()) returns Error?;

# Opens the file's content as one lazy byte stream.
remote function getFileContent(string path, DownloadOptions? options = ()) returns stream<byte[], Error?>|Error;
```

`uploadFile` and `downloadFile` move a local file on disk. `uploadContent` takes in-memory content (`byte[]` and `string` written as-is, `xml` serialized, `map<json>` serialized as JSON). `uploadFromStream` requires `contentLength` because Azure Files pre-allocates a file at a fixed size before content is written into its ranges. The transfer methods chunk internally, and downloads stream rather than buffer.

#### 4.5 Copy operations

```ballerina
remote function copyFile(string sourcePath, string destinationPath, CopyOptions? options = ()) returns CopyInfo|Error;

remote function copyFileFromUrl(string sourceUrl, string destinationPath, CopyOptions? options = ()) returns CopyInfo|Error;

# Returns () when the file has never been a copy destination.
remote function checkCopyStatus(string path) returns CopyStatusInfo?|Error;

remote function abortCopy(string path, string copyId) returns Error?;
```

Copies are asynchronous; observe an in-flight copy with `checkCopyStatus`.

#### 4.6 Range operations

```ballerina
# A single Put Range (at most 4 MiB); the transfer methods above chunk internally.
remote function uploadRange(string path, int offset, byte[] content) returns Error?;

remote function clearRange(string path, int offset, int length) returns Error?;

remote function listRanges(string path, RangeListOptions? options = ()) returns Range[]|Error;
```

### 5. Errors

A distinct error hierarchy allows pattern-matching on specific failures:

```ballerina
public type ErrorDetail record {|
    # HTTP status; absent on client-side failures with no server exchange
    int httpStatus?;
    # The Azure error code, or a connector-defined identifier for client-side failures
    string errorCode;
|};

public type Error                    distinct error<ErrorDetail>;
public type NotFoundError            distinct Error;
public type ConflictError            distinct Error;
public type AuthorizationError       distinct Error;
public type PreconditionFailedError  distinct Error;
public type RangeNotSatisfiableError distinct Error;
public type QuotaExceededError       distinct Error;
public type ProcessingError          distinct Error;
```

Mapping keys on the Azure error code string, not the HTTP status alone: `ShareSizeLimitReached` (403) maps to `QuotaExceededError`, distinct from auth failures (also 403) mapping to `AuthorizationError`. The human-readable message becomes the Ballerina error's `message()` rather than being duplicated into the detail record.

### 6. Advanced surface

Beyond the core surface above, the same classes carry the full Azure Files capability set as additive methods and configuration, kept out of the core so the common path stays small:

* **Authentication:** the `EntraIdConfig` union members (DefaultAzureCredential, managed identity, client secret, client certificate, workload identity). The connector sets the required `ShareTokenIntent.BACKUP` request intent implicitly.
* **Resilience and transport configuration:** a retry record mirroring the SDK's `RequestRetryOptions` (with the SDK's own defaults) plus proxy, TLS, and connection-pool settings.
* **`AdminClient`:** `getServiceProperties`, `setServiceProperties`, `getUserDelegationKey`, `generateAccountSas`.
* **`Client`:** share snapshots (`createShareSnapshot`, `listShareSnapshots`, `deleteShareSnapshot`, `listRangesDiff`, and snapshot-scoped reads via a `snapshotId` option on the download and list operations); share and file leases (share: acquire, renew, release, break, change; file: acquire, release, break, change, since file leases are always infinite); SMB handle enumeration and force-close; post-create property updates (`setShareProperties` quota/tier, `setFileProperties` including resize, `setDirectoryProperties`); SAS generation (`generateShareSas`, `generateSas`) and user-delegation SAS; stored access policies; SDDL permission get/create; NFS hard and symbolic links plus POSIX owner, group, and mode writes via a `posixProperties` option on the create, upload, and property-setter operations.

### 7. Usage

Working with files in a share:

```ballerina
import ballerinax/azure.storage.files;

configurable files:ClientConfiguration filesConfig = ?;

public function main() returns error? {
    files:Client fileShare = check new ("invoices", filesConfig);

    check fileShare->uploadFile("./invoice-2026-07.pdf", "/2026/07/invoice.pdf");

    stream<files:Entry, files:Error?> entries = check fileShare->list("/2026/07");
    check entries.forEach(function(files:Entry entry) {
        // ...
    });

    check fileShare.close();
}
```

Share administration:

```ballerina
files:AdminClient admin = check new (auth = {accountName: "myacct", accountKey: "..."});
if !(check admin->hasShare("invoices")) {
    check admin->createShare("invoices", {quotaInGb: 100});
}
```

## Alternatives

* **Revamp `azure_storage_service` in place.** Rejected: the hand-written protocol layer remains the maintenance burden, and the combined Blob-plus-Files packaging contradicts the one-package-per-service pattern of the rest of the Azure ecosystem.
* **Generate a client from the REST/OpenAPI definition.** Rejected: the generated client would still leave Shared Key signing, SAS construction, retry, and chunked transfer to be implemented and maintained by hand; the official SDK already encapsulates all of it and tracks new API versions.
* **Surface the SDK's four-client chain directly** (`ShareServiceClient`, `ShareClient`, `ShareDirectoryClient`, `ShareFileClient`). Rejected: navigating a client chain to reach a file is SDK ergonomics, not Ballerina ergonomics. Two clients plus a combined `path` parameter keeps the common case to a single object and small signatures.
* **One combined package for Blob and Files.** Rejected: users pull one artifact per service everywhere else in the ecosystem, and Microsoft's own packaging already shares the common auth/retry layer between the two SDK artifacts, so separate Ballerina packages duplicate nothing.

## Testing

Azure Files has no local emulator (Azurite covers Blob, Queue, and Table only), so the connector carries an in-process mock of the File REST service that the real SDK runs against. There is one test suite: without credentials it runs against the mock (every build, including fork pull requests, credential-free), and when storage-account credentials are configured the same tests run against a live storage account instead, which also verifies the mock's fidelity. A few tests are single-backend where the condition they exercise physically requires it (forced service errors and transport failures stay on the mock; Microsoft Entra ID token flows run only live).

## Dependencies

* Azure SDK for Java: `com.azure:azure-storage-file-share` (and `com.azure:azure-identity` for Entra ID support)

## References

* [Azure Files documentation](https://learn.microsoft.com/en-us/azure/storage/files/storage-files-introduction)
* [Azure Files REST API](https://learn.microsoft.com/en-us/rest/api/storageservices/file-service-rest-api)
* [Azure SDK for Java, File Share client library](https://learn.microsoft.com/en-us/java/api/overview/azure/storage-file-share-readme)
* [Existing connector: `ballerinax/azure_storage_service`](https://central.ballerina.io/ballerinax/azure_storage_service/latest)
