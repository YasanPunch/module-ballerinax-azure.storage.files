# Specification: Ballerina Azure Files Library

_Owners_: @YasanPunch \
_Reviewers_: @niveathika \
_Created_: 2026/07/13 \
_Updated_: 2026/07/30 \
_Edition_: Swan Lake

## Introduction

This specification describes the Azure Files connector library for the Ballerina programming language, enabling applications to manage Microsoft Azure file shares and the directories and files within them. The library definition has progressed over time and may undergo further refinement. Previous versions are accessible via their corresponding GitHub tags.

For feedback or suggestions regarding this library, please open a discussion through a "GitHub issue" or participate in the "Discord server". Community input drives potential updates to both specification and implementation. Accepted proposals that impact the specification are documented in `/docs/proposals`, with ongoing discussions tagged as `type/proposal` on GitHub.

The official implementation aligns with this specification. Any deviation qualifies as a defect.

## Contents

1. [Overview](#1-overview)
2. [Configuration](#2-configuration)
   * 2.1 [Authentication](#21-authentication)
      * 2.1.1 [Shared Key](#211-shared-key)
      * 2.1.2 [SAS Token](#212-sas-token)
      * 2.1.3 [SAS URL](#213-sas-url)
      * 2.1.4 [Connection String](#214-connection-string)
      * 2.1.5 [Microsoft Entra ID](#215-microsoft-entra-id)
   * 2.2 [Client Configuration](#22-client-configuration)
   * 2.3 [Retry Configuration](#23-retry-configuration)
   * 2.4 [Transport Configuration](#24-transport-configuration)
3. [AdminClient](#3-adminclient)
   * 3.1 [Initializing the AdminClient](#31-initializing-the-adminclient)
   * 3.2 [Share Management Operations](#32-share-management-operations)
   * 3.3 [Service Configuration Operations](#33-service-configuration-operations)
   * 3.4 [User Delegation Key and Account SAS](#34-user-delegation-key-and-account-sas)
4. [Client](#4-client)
   * 4.1 [Initializing the Client](#41-initializing-the-client)
   * 4.2 [Share Operations](#42-share-operations)
   * 4.3 [Directory Operations](#43-directory-operations)
   * 4.4 [File Operations](#44-file-operations)
   * 4.5 [Transfer Operations](#45-transfer-operations)
   * 4.6 [Copy Operations](#46-copy-operations)
   * 4.7 [Range Operations](#47-range-operations)
   * 4.8 [Share Snapshot Operations](#48-share-snapshot-operations)
   * 4.9 [Lease Operations](#49-lease-operations)
   * 4.10 [SMB Handle Operations](#410-smb-handle-operations)
   * 4.11 [Property Update Operations](#411-property-update-operations)
   * 4.12 [Access Policy Operations](#412-access-policy-operations)
   * 4.13 [Permission Operations](#413-permission-operations)
   * 4.14 [SAS Generation](#414-sas-generation)
   * 4.15 [NFS Link Operations](#415-nfs-link-operations)
5. [The Listener and Caller](#5-the-listener-and-caller)
6. [Error Types](#6-error-types)
7. [Samples](#7-samples)

## 1. Overview

[Azure Files](https://learn.microsoft.com/en-us/azure/storage/files/storage-files-introduction) is the fully managed file-share service of Azure Storage, offering shares accessible over SMB, NFS, and REST. The `ballerinax/azure.storage.files` module provides an idiomatic Ballerina API for the service. It is built on the official Azure SDK for Java (`com.azure:azure-storage-file-share`), which supplies request signing, retry, and chunked transfer underneath the Ballerina surface.

The public surface is four types:

* `AdminClient` operates at the storage-account level. It creates, lists, deletes, and restores shares, manages the account's file-service configuration, and mints account-level SAS tokens.
* `Client` is bound to a single share at initialization and carries every operation inside that share: directories, files, transfers, copies, byte ranges, snapshots, leases, SMB handles, access policies, stored permissions, SAS generation, and NFS links.
* `Listener` polls one watched path on a share and dispatches each present file to the matching content handler of its attached service.
* `Caller` is passed to each listener handler. It forwards a curated share-scoped subset of `Client`, so a handler can act on the event's file without constructing a separate client.

Directory and file operations take a single slash-delimited, share-relative path (for example `/reports/2026/q4.pdf`). Where two paths co-occur, they are named `sourcePath` and `destinationPath`, in source-first order. Every entry returned by a listing carries its full share-relative path, so listing results feed directly into the path-taking operations.

`AdminClient`, `Client`, and `Caller` are isolated client classes holding only immutable configuration, and the `Listener` is an isolated class, so a single instance of any of them can be used safely from concurrent strands. Every operation that calls the service is a remote method, invoked with `->`. Methods that make no service call are ordinary methods, invoked with `.`: the `Listener`'s lifecycle methods and the SAS generation methods, which sign tokens locally with the credential the client already holds. The clients hold no releasable resources, so there is no close method; a client that is no longer needed is simply discarded.

For brevity, the `isolated` qualifier is omitted from the signatures in this specification.

## 2. Configuration

### 2.1 Authentication

The authentication configuration is a union in which each member represents exactly one real-world credential artifact, the thing the Azure portal, CLI, or infrastructure tooling actually hands the user:

```ballerina
public type AuthConfig SharedKeyConfig|SasConfig|SasUrlConfig|ConnectionStringConfig|EntraIdConfig;
```

Every member has a unique required field or field combination, so both the compiler and `Config.toml` select the right member by structural matching, with no discriminator field. The two Microsoft Entra ID chain records (`DefaultEntraIdConfig` and `ManagedIdentityConfig`), which would otherwise share the same field shape, are the exception: they carry a `kind` discriminator.

```toml
# The fields present select the union member:
[myapp.filesConfig]
auth = {accountName = "myacct", accountKey = "..."}               # SharedKeyConfig
# auth = {accountName = "myacct", sasToken = "sv=..."}            # SasConfig
# auth = {sasUrl = "https://myacct.file.core.windows.net/?sv=..."}# SasUrlConfig
# auth = {connectionString = "..."}                               # ConnectionStringConfig
# auth = {kind = "default", accountName = "myacct"}               # DefaultEntraIdConfig
# auth = {kind = "managed-identity", accountName = "myacct"}      # ManagedIdentityConfig
# auth = {accountName = "myacct", tenantId = "...", clientId = "...", clientSecret = "..."}                # ClientSecretConfig
# auth = {accountName = "myacct", tenantId = "...", clientId = "...", certificatePath = "/path/cert.pem"}  # ClientCertificateConfig
# auth = {accountName = "myacct", tenantId = "...", clientId = "...", tokenFilePath = "/path/token"}       # WorkloadIdentityConfig
```

Every auth mode is validated at `init` with local computation and no call to Azure: connection strings are parsed strictly and checked for a file endpoint, and the explicit records get non-empty, base64, and URL-scheme checks. A malformed credential surfaces a specific error at `init` rather than an opaque failure at first use.

#### 2.1.1 Shared Key

Authenticates with the storage account name and one of its access keys.

```ballerina
public type SharedKeyConfig record {|
    # The storage account name, used to sign requests and to derive the service URL
    string accountName;
    # A base64-encoded access key of the storage account
    string accountKey;
    # The file service endpoint URL, including the scheme. Omit to use the default
    # `https://{accountName}.file.core.windows.net`
    string serviceUrl?;
|};
```

#### 2.1.2 SAS Token

Authenticates with a bare shared access signature (SAS) token, as issued by `az storage share generate-sas` or the SAS generation methods of this module.

```ballerina
public type SasConfig record {|
    # The name of the storage account the token belongs to (determines the service URL)
    string accountName;
    # A SAS token scoped to the required resources and permissions
    string sasToken;
|};
```

#### 2.1.3 SAS URL

Authenticates with a full SAS URL, which carries the service URL and the SAS token in one string, as issued by the Azure portal ("File service SAS URL").

```ballerina
public type SasUrlConfig record {|
    # A full file-service SAS URL, including the scheme and the SAS query string
    # (e.g. `https://{account}.file.core.windows.net/?sv=...&sig=...`)
    string sasUrl;
|};
```

#### 2.1.4 Connection String

Authenticates with a storage account connection string, which carries the account name, the credential (an account key or a SAS token), and the service endpoints.

```ballerina
public type ConnectionStringConfig record {|
    # An Azure Storage connection string, as issued by the Azure portal, the Azure CLI, or
    # infrastructure tooling
    string connectionString;
|};
```

#### 2.1.5 Microsoft Entra ID

`EntraIdConfig` is itself a union of five records, one per Entra ID credential kind:

```ballerina
public type EntraIdConfig DefaultEntraIdConfig|ManagedIdentityConfig|ClientSecretConfig|
    ClientCertificateConfig|WorkloadIdentityConfig;
```

Azure Files honors OAuth tokens only on requests carrying the backup intent, which the connector sets automatically. The intent bypasses file and directory ACLs and requires the identity to hold the `Storage File Data Privileged Reader` or `Storage File Data Privileged Contributor` role.

```ballerina
# The credential-kind discriminator value selecting `DefaultEntraIdConfig`.
public const DEFAULT_AZURE_CREDENTIAL = "default";

# The credential-kind discriminator value selecting `ManagedIdentityConfig`.
public const MANAGED_IDENTITY = "managed-identity";

# Authentication through the default credential chain, which tries the environment,
# a managed identity, and developer sign-ins in turn.
public type DefaultEntraIdConfig record {|
    # Selects the default credential chain
    DEFAULT_AZURE_CREDENTIAL kind;
    # The storage account name (determines the service URL unless `serviceUrl` overrides it)
    string accountName;
    # The file service endpoint URL; omit for `https://{accountName}.file.core.windows.net`
    string serviceUrl?;
|};

# Authentication as an Azure managed identity, for workloads running on Azure compute.
public type ManagedIdentityConfig record {|
    # Selects the managed-identity credential
    MANAGED_IDENTITY kind;
    # The storage account name (determines the service URL unless `serviceUrl` overrides it)
    string accountName;
    # The client id of a user-assigned managed identity; omit for the system-assigned identity
    string clientId?;
    # The file service endpoint URL; omit for `https://{accountName}.file.core.windows.net`
    string serviceUrl?;
|};

# Authentication as a service principal with a client secret.
public type ClientSecretConfig record {|
    # The storage account name (determines the service URL unless `serviceUrl` overrides it)
    string accountName;
    # The Entra ID tenant (directory) id
    string tenantId;
    # The application (client) id of the service principal
    string clientId;
    # The client secret of the service principal
    string clientSecret;
    # The file service endpoint URL; omit for `https://{accountName}.file.core.windows.net`
    string serviceUrl?;
|};

# Authentication as a service principal with a client certificate.
public type ClientCertificateConfig record {|
    # The storage account name (determines the service URL unless `serviceUrl` overrides it)
    string accountName;
    # The Entra ID tenant (directory) id
    string tenantId;
    # The application (client) id of the service principal
    string clientId;
    # The path to the certificate file (PEM, or PFX when `certificatePassword` is set)
    string certificatePath;
    # The password protecting the certificate file, when it has one
    string certificatePassword?;
    # The file service endpoint URL; omit for `https://{accountName}.file.core.windows.net`
    string serviceUrl?;
|};

# Workload-identity authentication, for Kubernetes workloads federated with Entra ID.
public type WorkloadIdentityConfig record {|
    # The storage account name (determines the service URL unless `serviceUrl` overrides it)
    string accountName;
    # The Entra ID tenant (directory) id
    string tenantId;
    # The application (client) id federated with the workload
    string clientId;
    # The path to the file holding the federated service-account token
    string tokenFilePath;
    # The file service endpoint URL; omit for `https://{accountName}.file.core.windows.net`
    string serviceUrl?;
|};
```

### 2.2 Client Configuration

Both clients take the same configuration record:

```ballerina
public type ClientConfiguration record {|
    # The authentication configuration (see `AuthConfig`)
    AuthConfig auth;
    # Retry behaviour for service requests; omit for the service defaults
    RetryConfig retryConfig?;
    # HTTP transport settings (proxy, connection pool, TLS); omit for the defaults
    TransportConfig transportConfig?;
|};
```

`config` is an included record parameter on both `init` methods, so callers pass its fields as named arguments, for example `new (auth = {accountName, accountKey})`.

### 2.3 Retry Configuration

Retry behaviour for service requests. Omitting the record leaves the default retry behaviour in place.

```ballerina
public type RetryConfig record {|
    # How the delay between tries grows (`EXPONENTIAL` or `FIXED`)
    RetryPolicyType retryPolicyType = EXPONENTIAL;
    # The maximum number of tries (the first attempt plus retries)
    int maxTries = 4;
    # The timeout applied to each individual try, in seconds
    decimal tryTimeoutSeconds = 60;
    # The base delay between tries, in seconds
    decimal retryDelaySeconds = 4;
    # The upper bound on the delay between tries, in seconds
    decimal maxRetryDelaySeconds = 120;
    # A secondary endpoint to retry reads against (geo-redundant accounts)
    string secondaryHostUrl?;
|};
```

### 2.4 Transport Configuration

HTTP transport settings: proxying, connection pooling, and TLS.

```ballerina
public type TransportConfig record {|
    # Route traffic through this proxy
    ProxyConfig proxy?;
    # Connection-pool tuning
    ConnectionPoolConfig connectionPool = {};
    # Custom TLS settings (trust and key material, verification)
    SecureSocket secureSocket?;
|};
```

`ProxyConfig` routes the connector's traffic through an HTTP, SOCKS4, or SOCKS5 proxy, with optional credentials and a bypass list. `ConnectionPoolConfig` tunes the maximum number of concurrent connections and the idle, connect, and read timeouts. `SecureSocket` configures custom trust material (a truststore or a PEM certificate path), a client identity for mutual TLS (a keystore or a `CertKey` certificate and key pair), the offered TLS versions and cipher suites, host-name verification, session reuse, revocation checking, an SNI host name, and handshake and session timeouts.

## 3. AdminClient

The `AdminClient` manages the shares within a storage account. Use it for share lifecycle management, the account's file-service configuration, and account-level SAS tokens. For operations scoped to a single share, use `Client`.

### 3.1 Initializing the AdminClient

```ballerina
public function init(*ClientConfiguration config) returns Error?;
```

```ballerina
files:AdminClient admin = check new (auth = {accountName: "myacct", accountKey: "..."});
```

### 3.2 Share Management Operations

```ballerina
remote function hasShare(string shareName) returns boolean|Error;

remote function listShares(ShareListOptions? options = ()) returns ShareInfo[]|Error;

remote function createShare(string shareName, ShareCreateOptions? options = ()) returns Error?;

remote function deleteShare(string shareName, ShareDeleteOptions? options = ()) returns Error?;

remote function undeleteShare(string shareName, string version) returns Error?;
```

`hasShare` returns `false` only when Azure confirms absence (HTTP 404); an `Error` means the check itself could not complete, so an auth problem is never misreported as a missing share. `createShare` accepts a quota, an access tier, the protocols to enable (SMB and/or NFS), the NFS root-squash setting, and metadata through `ShareCreateOptions`. When the account's soft-delete retention policy is enabled, `deleteShare` retains the share for the configured period; find restorable shares and their versions with `listShares({includeDeleted: true})` and restore them with `undeleteShare`.

### 3.3 Service Configuration Operations

```ballerina
remote function getServiceProperties() returns ServiceProperties|Error;

remote function setServiceProperties(ServiceProperties properties) returns Error?;
```

`ServiceProperties` covers the account's request-metrics collection, CORS rules, and protocol settings. The service applies the record as a whole, so read the current configuration, modify it, and pass the result back.

### 3.4 User Delegation Key and Account SAS

```ballerina
remote function getUserDelegationKey(time:Utc startTime, time:Utc expiryTime) returns UserDelegationKey|Error;

function generateAccountSas(AccountSasSignatureValues values) returns string|Error;
```

`getUserDelegationKey` requires a client authenticated with Microsoft Entra ID whose identity holds the `Storage File Delegator` role; the key is valid at most 7 days and signs user-delegation SAS tokens (section 4.14). `generateAccountSas` is an ordinary method, invoked with `.`: it signs the token locally with the account key and makes no service call. It requires a client authenticated with `SharedKeyConfig` (or a connection string carrying an account key). Rotating the account key revokes every SAS minted from it.

## 4. Client

The `Client` is bound to a single share at initialization and operates on that share and the directories and files within it.

### 4.1 Initializing the Client

```ballerina
public function init(string shareName, *ClientConfiguration config) returns Error?;
```

```ballerina
files:Client fileShare = check new ("invoices", auth = {accountName: "myacct", accountKey: "..."});
```

Binding is lazy: `init` makes no call to Azure, so initializing against a share that does not exist succeeds and the first operation on it fails with a `NotFoundError`. The up-front existence check is `AdminClient.hasShare`.

A method name carries the `File` token either to disambiguate a verb that also exists for directories (`createFile` next to `createDirectory`) or to keep a bare verb from implying it handles directories when it is file-only (`uploadFile`, `downloadFile`, `copyFile`). Verbs whose object is already explicit stay bare (`uploadContent`, `uploadRange`, `setContentHeaders`), and `list` is deliberately neutral because it returns files and directories in one stream.

### 4.2 Share Operations

```ballerina
remote function getShareProperties() returns ShareProperties|Error;

remote function setShareMetadata(map<string> metadata) returns Error?;

remote function getShareUsage() returns int|Error;
```

Metadata is free-form, user-defined annotation; Azure stores and returns it verbatim. `setShareMetadata` replaces the complete metadata set, and metadata is read back through `getShareProperties`. `getShareUsage` returns the approximate stored bytes.

### 4.3 Directory Operations

```ballerina
remote function createDirectory(string directoryPath, DirectoryCreateOptions? options = ()) returns Error?;

remote function deleteDirectory(string directoryPath) returns Error?;

remote function hasDirectory(string directoryPath) returns boolean|Error;

remote function getDirectoryProperties(string directoryPath) returns DirectoryProperties|Error;

remote function setDirectoryMetadata(string directoryPath, map<string> metadata) returns Error?;

remote function list(string directoryPath, ListOptions? options = ()) returns stream<Entry, Error?>|Error;

remote function renameDirectory(string sourcePath, string destinationPath, RenameOptions? options = ()) returns Error?;
```

`deleteDirectory` requires the directory to be empty. `hasDirectory` follows the same semantics as `hasShare`: `false` only on a confirmed 404, an `Error` when the check itself fails. `list` returns files and subdirectories as one lazy stream, so memory stays bounded on large directories; every `Entry` carries its full share-relative `path` and an `isDirectory` flag, and `ListOptions` offers a name prefix, recursion, page sizing, extended info (ETag and timestamps), and a `snapshotId` to list from a share snapshot. Rename doubles as move: the destination is a full share-relative path, so `/X/A` to `/Y/A` re-parents within the same share. A directory can never overwrite an existing directory; with `RenameOptions.replaceIfExists` it may overwrite an existing file at the destination. Moving across shares is not possible.

### 4.4 File Operations

```ballerina
remote function createFile(string path, int sizeInBytes, CreateOptions? options = ()) returns Error?;

remote function deleteFile(string path) returns Error?;

remote function hasFile(string path) returns boolean|Error;

remote function getFileProperties(string path) returns FileProperties|Error;

remote function setFileMetadata(string path, map<string> metadata) returns Error?;

remote function setContentHeaders(string path, ContentHeaders headers) returns Error?;

remote function renameFile(string sourcePath, string destinationPath, RenameOptions? options = ()) returns Error?;
```

`createFile` provisions an empty file of a fixed size; content is written separately via the transfer or range operations. `setContentHeaders` replaces the complete content-header set (`Content-Type`, `Cache-Control`, and the other standard headers): any header omitted from `headers` is cleared on the file. Metadata is read via `getFileProperties().metadata`; only a setter is exposed. `renameFile` overwrites an existing destination file only when `RenameOptions.replaceIfExists` is set, and an existing destination directory always fails the operation.

### 4.5 Transfer Operations

```ballerina
remote function uploadFile(string sourcePath, string destinationPath, UploadOptions? options = ()) returns Error?;

remote function uploadContent(byte[]|string|xml|map<json>|string[][] content, string destinationPath, UploadOptions? options = ()) returns Error?;

remote function uploadFromStream(stream<byte[], error?> content, int contentLength, string destinationPath, UploadOptions? options = ()) returns Error?;

remote function downloadFile(string sourcePath, string destinationPath, DownloadOptions? options = ()) returns Error?;

remote function getFileContent(string path, DownloadOptions? options = ()) returns stream<byte[], Error?>|Error;

remote function getFileText(string path, DownloadOptions? options = ()) returns string|Error;

remote function getFileJson(string path, DownloadOptions? options = (), typedesc<json|record {}> targetType = <>) returns targetType|Error;

remote function getFileXml(string path, DownloadOptions? options = (), typedesc<xml|record {}> targetType = <>) returns targetType|Error;

remote function getFileCsv(string path, DownloadOptions? options = (), typedesc<string[][]|record {}[]> targetType = <>) returns targetType|Error;
```

`uploadFile` and `downloadFile` move a local file on disk; both parameters are full paths including the file name, in source-first order. `uploadContent` takes in-memory content: `byte[]` and `string` are written as-is, `xml` in its textual form, `map<json>` as a JSON document, and `string[][]` as CSV rows (fields containing a comma, quote, backslash, or line break are quoted, matching the dialect `getFileCsv` reads back). `uploadFromStream` requires `contentLength` because Azure Files pre-allocates the file at a fixed size before content is written into its ranges; a source-stream failure, or a stream whose length does not match `contentLength`, surfaces as a client-side `Error`. A failed stream upload leaves the pre-allocated file, holding whatever ranges were written before the failure, at the destination; the connector does not delete it, so the caller can inspect it, overwrite it by uploading again, or delete it. The transfer methods chunk internally (small source chunks coalesce into range writes of the service's maximum range size), and `getFileContent` reads lazily, so memory stays bounded for any file size. `downloadFile` fails with a client-side `Error` when a local file already exists at `destinationPath`. `DownloadOptions` offers a byte `range` and a `snapshotId` to read from a share snapshot.

The typed reads materialize the file's full content and bind it to the caller-directed target type: `getFileText` decodes UTF-8 text, `getFileJson` binds a JSON document to a `json` form or a record, `getFileXml` binds to an `xml` value or a record projected from the document, and `getFileCsv` binds to `string[][]` rows or to a record array whose field names are taken from the file's header row (the string-matrix form keeps every row, including the first). Binding is strict: content that does not match the target type fails with a client-side `Error`. The listener's `laxDataBinding` setting applies only to listener handlers, not to these reads.

### 4.6 Copy Operations

```ballerina
remote function copyFile(string sourcePath, string destinationPath, CopyOptions? options = ()) returns CopyInfo|Error;

remote function copyFileFromUrl(string sourceUrl, string destinationPath, CopyOptions? options = ()) returns CopyInfo|Error;

remote function checkCopyStatus(string path) returns CopyStatusInfo?|Error;

remote function abortCopy(string path, string copyId) returns Error?;
```

Copies are asynchronous: inspect the returned `CopyInfo.copyStatus` and, if pending, observe progress with `checkCopyStatus` (which returns `()` when the file has never been a copy destination) or cancel with `abortCopy`. `copyFile` copies within the bound share under this client's credentials. `copyFileFromUrl` copies from an external URL: a source in a different storage account, or any blob source, must carry its own authorization in the URL (typically a SAS token).

### 4.7 Range Operations

```ballerina
remote function uploadRange(string path, int offset, byte[] content) returns Error?;

remote function clearRange(string path, int offset, int length) returns Error?;

remote function listRanges(string path, RangeListOptions? options = ()) returns Range[]|Error;
```

`uploadRange` writes a single range of at most 4 MiB and performs no chunking; for content of arbitrary size, use the transfer operations. `clearRange` frees the underlying storage; storage deallocates in 512-byte units, so a smaller cleared span is zeroed but may still appear in `listRanges` until the whole unit is cleared. `listRanges` returns the valid (written) byte ranges of a file, each with inclusive start and end offsets.

### 4.8 Share Snapshot Operations

```ballerina
remote function createShareSnapshot(map<string>? metadata = ()) returns ShareSnapshotInfo|Error;

remote function listShareSnapshots() returns ShareSnapshotInfo[]|Error;

remote function deleteShareSnapshot(string snapshotId) returns Error?;

remote function listRangesDiff(string path, string previousSnapshotId, RangeListOptions? options = ()) returns RangeDiff|Error;
```

A share snapshot is a point-in-time, read-only copy of the whole share. Snapshot contents are read through the regular read operations: pass the returned `snapshotId` in `DownloadOptions` (`downloadFile`, `getFileContent`) or `ListOptions` (`list`) to resolve the same paths inside the snapshot instead of the live share. `listShareSnapshots` and `deleteShareSnapshot` run service-level operations, so they need account-level credentials (an account key, a connection string carrying one, or an account SAS; a share-scoped SAS is not sufficient). `listRangesDiff` reports which of a file's ranges were written and which were cleared since a baseline snapshot, for incremental backup on top of snapshots.

### 4.9 Lease Operations

Share leases:

```ballerina
remote function acquireShareLease(int leaseDurationSeconds, string? proposedLeaseId = ()) returns string|Error;

remote function renewShareLease(string leaseId) returns Error?;

remote function releaseShareLease(string leaseId) returns Error?;

remote function breakShareLease(int? breakPeriodSeconds = ()) returns int|Error;

remote function changeShareLease(string leaseId, string proposedLeaseId) returns string|Error;
```

File leases:

```ballerina
remote function acquireLease(string path, string? proposedLeaseId = ()) returns string|Error;

remote function releaseLease(string path, string leaseId) returns Error?;

remote function breakLease(string path) returns Error?;

remote function changeLease(string path, string leaseId, string proposedLeaseId) returns string|Error;
```

A share lease locks the share against deletion by anyone not holding the lease id; it is fixed-duration (15 to 60 seconds) or infinite (-1) and is kept alive with `renewShareLease`. A file lease locks the file against writes and deletion; it is always infinite, so it takes no duration and has no renew. The break operations reclaim a lease without needing its id, for when the holder is gone: a share lease keeps running for `breakPeriodSeconds` (or its own remaining time) before breaking, while a file lease breaks immediately.

### 4.10 SMB Handle Operations

```ballerina
remote function listFileHandles(string path) returns HandleInfo[]|Error;

remote function forceCloseFileHandles(string path, string? handleId = ()) returns CloseHandlesInfo|Error;

remote function listDirectoryHandles(string directoryPath) returns HandleInfo[]|Error;

remote function forceCloseDirectoryHandles(string directoryPath, string? handleId = (), boolean recursive = false) returns CloseHandlesInfo|Error;
```

Handles are opened by SMB clients (mounted drives); REST operations through this connector do not hold handles. The force-close operations release locks whose holders are gone or unresponsive, closing one handle by id or, when `handleId` is absent, all handles on the target; the affected SMB clients receive an error on their next operation. `forceCloseDirectoryHandles` can also close handles throughout the directory's subtree with `recursive`.

### 4.11 Property Update Operations

```ballerina
remote function setShareProperties(ShareSetPropertiesOptions options) returns Error?;

remote function setFileProperties(string path, FileSetPropertiesOptions options) returns Error?;

remote function setDirectoryProperties(string directoryPath, DirectorySetPropertiesOptions options) returns Error?;
```

These update properties after creation; only what is set is changed, and every omitted field keeps the current value. `setShareProperties` changes the share's quota or access tier; it is administrative, needs account-level credentials, and fails with an `AuthorizationError` on a share-scoped SAS. `setFileProperties` covers content headers, SMB properties, an SDDL permission, a new file size (growing pre-allocates, shrinking truncates), and POSIX attributes. `setDirectoryProperties` covers SMB properties, an SDDL permission, and POSIX attributes.

### 4.12 Access Policy Operations

```ballerina
remote function getShareAccessPolicy() returns SignedIdentifier[]|Error;

remote function setShareAccessPolicy(SignedIdentifier[] identifiers) returns Error?;
```

A stored access policy carries a validity window and a permission string under an identifier. Share SAS tokens minted against a policy (via the `identifier` field of the signature values) inherit its window and permissions, so removing or editing a policy immediately revokes or changes every SAS minted against it. `setShareAccessPolicy` replaces the complete set, at most five per share.

### 4.13 Permission Operations

```ballerina
remote function getSharePermission(string permissionKey) returns string|Error;

remote function createSharePermission(string sddlPermission) returns string|Error;
```

The share carries a permission store of security descriptors (SDDL strings). `createSharePermission` stores a descriptor and returns its key, so the same permission can be applied to many files via `SmbProperties.filePermissionKey` without repeating the descriptor; `getSharePermission` reads a stored descriptor back by key.

### 4.14 SAS Generation

The SAS generation methods are ordinary methods, invoked with `.`: signing happens locally with the credential the client holds, and no call is made to Azure.

```ballerina
function generateShareSas(ShareSasSignatureValues values) returns string|Error;

function generateSas(string path, FileSasSignatureValues values) returns string|Error;

function generateShareUserDelegationSas(ShareSasSignatureValues values, UserDelegationKey key) returns string|Error;

function generateUserDelegationSas(string path, FileSasSignatureValues values, UserDelegationKey key) returns string|Error;
```

`generateShareSas` and `generateSas` sign with the account key, so the client must be authenticated with `SharedKeyConfig` (or a connection string carrying an account key); rotating the account key revokes every SAS minted from it. The signature values carry the validity window, the permissions, and optionally a protocol restriction, an IP range, or a stored access policy `identifier` in place of an explicit expiry and permissions; generation fails with an `Error` when neither the identifier nor both `expiryTime` and `permissions` are supplied. The user-delegation variants sign with a `UserDelegationKey` (from `AdminClient.getUserDelegationKey`) instead of the account key, so no storage key is ever handled; they are valid at most 7 days (the key's lifetime), and stored access policies do not apply to them: the user delegation variants reject an `identifier` and require an explicit `expiryTime` and `permissions`.

### 4.15 NFS Link Operations

```ballerina
remote function createHardLink(string path, string targetPath) returns Error?;

remote function createSymbolicLink(string path, string linkTarget) returns Error?;

remote function getSymbolicLink(string path) returns string|Error;
```

These operate on NFS shares only. A hard link makes both paths refer to the same underlying file, and the file's `PosixProperties.linkCount` grows by one. A symbolic link stores its target as a path, resolved by the NFS client at access time; the target need not exist.

## 5. The Listener and Caller

Azure Files is not exposed as an Event Grid source, so the listener polls. It uses **stateless dispatch**: each polling tick lists the watched path and reads each present file, invoking the content handler that matches it. No per-file state is kept, so the contract is that handlers consume files by processing them and then deleting or moving them out of the watched path; an unprocessed file fires again on a later poll. This mode is trivially restart-safe. Delivery is at-least-once. Polling runs on the platform task scheduler at a fixed `pollingInterval`, whose waiting policy makes a tick that fires during a still-running scan wait for it; each matching file is dispatched to its handler on its own thread, so handlers run concurrently beyond the scan. An in-progress guard keyed on the file's path ensures one file is never dispatched to two invocations at once, so a file re-fires only after its previous handling has finished and it is still present; a file overwritten while its previous version is still being handled is dispatched with its new content on a later poll, once that handling completes. A file overwritten in the short window between a poll's listing and its content read is delivered with the new content while the accompanying `FileInfo` still describes the listed version; Azure Files offers no conditional reads to close that window, and at-least-once delivery makes it harmless for handlers that treat `FileInfo` as advisory. Handlers should be idempotent, or claim a file by renaming it out of the watched path before processing.

One listener watches exactly one service and one path. The listener configuration carries the share-level concerns (credentials, polling cadence, transport). What to watch is the service's attach point: `service /invoices on lsn` (a resource path, whose segments join with `/`) or `service "/dir one/reports" on lsn` (a string, for names a resource path cannot express). The path normalizes by trimming whitespace, collapsing repeated slashes, ensuring a leading slash, and stripping a trailing one. A service with no attach point watches the share root. The optional `@ServiceConfig` annotation configures recursion and file-name filtering; no annotation is needed for a service to work.

```ballerina
public type ListenerConfiguration record {|
    # The authentication configuration
    AuthConfig auth;
    # Polling interval in seconds; must be greater than zero
    decimal pollingInterval = 60;
    # Retry configuration for the underlying client
    RetryConfig retryConfig?;
    # HTTP transport configuration for the underlying client
    TransportConfig transportConfig?;
    # Relaxed data binding for the typed content handlers
    boolean laxDataBinding = false;
    # Fail safe CSV processing; skipped records go to an error log file
    FailSafeOptions csvFailSafe?;
|};

public type FailSafeOptions record {|
    # What each skipped CSV record's error log entry carries
    ErrorLogContentType contentType = METADATA;
|};

public enum ErrorLogContentType {
    METADATA,
    RAW,
    RAW_AND_METADATA
}

public type ServiceConfiguration record {|
    # Whether the service watches subdirectories under the watched path
    boolean recursive = true;
    # Regex on the file name; non-matching files are never dispatched to this service
    string fileNamePattern?;
    # Skip files younger than this many seconds, guarding against partial writes
    decimal minFileAgeSeconds?;
|};

public annotation ServiceConfiguration ServiceConfig on service;
```

A listener already bound to a service rejects a second `attach` at runtime, so to watch several paths, run several independent listeners. Overlap can still arise across separate listeners (a file under a path watched by two of them reaches each), so handling races there are the user's responsibility (idempotent handlers, or claim a file by renaming it out of the watched path). The `attach` `name` argument carries the service's attach point, which is the watched path. Attaching a service with an invalid `fileNamePattern` fails. A credential that cannot list the watched path does not fail `attach`; the first poll surfaces the authorization error instead. Calling `start` on a listener that is already running fails, and `detach` of a service that is not attached fails. `gracefulStop` stops the polling schedule and returns without waiting; `immediateStop` stops it immediately. In both cases handler invocations already running complete on their own threads. `init` performs a one-time XML parser setup for the XML content handlers; if that setup fails, `init` returns an error and the initialization can simply be retried.

```ballerina
public isolated class Listener {
    public isolated function init(string shareName, *ListenerConfiguration config) returns Error?;

    public isolated function attach(Service serviceRef, string[]|string? name = ()) returns error?;

    public isolated function 'start() returns error?;

    public isolated function gracefulStop() returns error?;

    public isolated function immediateStop() returns error?;

    public isolated function detach(Service serviceRef) returns error?;
}

# A bare distinct service object; the handler set is validated at compile time.
public type Service distinct service object {
};

# Carries what a directory listing provides, the Listener's data source.
public type FileInfo record {|
    # The name of the share the file lives on
    string shareName;
    # Share-relative path, e.g. "/dir1/dir2/file.ext"
    string path;
    # File name only
    string name;
    # Size in bytes
    int sizeBytes;
    # Entity tag of the file
    string eTag;
    # Last-modified time
    time:Utc lastModified;
|};
```

A service declares at least one content handler. `onFile` is the raw-bytes catch-all, taking its content as `byte[]` or as `stream<byte[], error?>`, and the typed variants receive a matching file's content already deserialised: `onFileText` takes a `string`, `onFileJson` takes a `map<json>`, a record, a `map<json>[]`, or a record array, `onFileXml` takes an `xml` document or a record, and `onFileCsv` takes a `string[][]`, a record array, a `stream<string[], error?>`, or a `stream<record{}, error?>`. An object root binds the `onFileJson` map and record forms (a record binds by projection), and an array root binds the array forms element by element. The `string[][]` and `stream<string[]>` CSV forms yield every row of the file; the CSV record forms map each row's fields through the file's first row, the header. An XML record target binds the document's elements to the record's fields. A root that does not match the declared form is a content-binding error. The `FileInfo` and `Caller` parameters are optional trailing parameters: a handler declares its content parameter first, then either, both, or neither of `FileInfo` and `Caller` (with `FileInfo` before `Caller` when both are present), so the accepted shapes are `(content)`, `(content, FileInfo)`, `(content, Caller)`, and `(content, FileInfo, Caller)`, and the listener passes only what the handler declares. Routing is by file extension (`txt` to `onFileText`, `json` to `onFileJson`, `xml` to `onFileXml`, `csv` to `onFileCsv`), and a per-handler `@FunctionConfig` pattern overrides it. When more than one routing pattern matches a file name, the winner is fixed: patterns are checked in the order `onFileText`, `onFileJson`, `onFileXml`, `onFileCsv`, then `onFile`, so a typed handler's pattern always beats the catch-all's. A file routed to a typed variant whose content is malformed raises a content-binding error rather than falling through to `onFile`. Binding is strict by default; setting `laxDataBinding` on the listener relaxes it, so JSON and CSV record binding treat a null value as an optional field and an absent member as a nilable field, and XML record binding tolerates elements the record does not declare. With `csvFailSafe` set, a malformed record in a materialized CSV binding is skipped instead of failing the whole binding, and is appended to an error log file named `<sourceBaseName>_error.log` in the process working directory; the `contentType` field selects what each entry carries. Fail safe mode applies to the materialized CSV forms only, not the stream forms.

The stream content forms read the file from the service in chunks as the handler drains the stream, instead of downloading it up front. A stream closes its underlying source at the end of the file, and a handler that abandons a stream early should call its `close()`. A CSV stream row that fails to bind surfaces as the error entry of that `next()` call, after which the stream is closed. The consume actions run on the handler's return exactly as for materialized content, so a handler that deletes or moves the file (or declares `afterProcess`) while its stream is not fully drained loses access to the remaining content.

A service may also declare an `onError` handler, `remote function onError(Error err, Caller caller?) returns error?`, which is notified when a poll fails (with the mapped typed error, for example an `AuthorizationError` when the credential lacks access) and when a typed handler's content binding fails (with a client-side `Error`). It is not a content handler: it does not satisfy the at-least-one-handler requirement, takes no annotation, and does not change what happens to the file, so a declared `afterError` still applies to a binding failure. An error returned by `onError` itself is swallowed. Errors returned by content handlers do not notify `onError`, and neither does a CSV stream row that fails to bind lazily (that error belongs to the handler draining the stream).

A compiler plugin validates the service at compile time: at least one content handler, each handler's parameter types and `error?` return (including the accepted parameter shapes and the `onError` signature), and no resource functions or unknown remote methods.

A handler can consume a file by declaring `@FunctionConfig`, which moves or deletes the file after the handler runs:

```ballerina
public const DELETE = "DELETE";

public type Move record {|
    # Target directory; the file keeps its name and the directory is created if absent
    string moveTo;
    # Recreate the file's sub-path under the watched root on recursive watches
    boolean preserveSubDirs = true;
|};

public type MOVE Move;

public type FunctionConfiguration record {|
    # Per-handler routing override (regex on the file name)
    string fileNamePattern?;
    # Auto-consume after the handler succeeds
    DELETE|MOVE afterProcess?;
    # Auto-consume after the handler errors or content-binding fails
    DELETE|MOVE afterError?;
|};

public annotation FunctionConfiguration FunctionConfig on object function;
```

`afterProcess` runs when the handler returns normally, and `afterError` when it errors or content-binding fails; when neither is set the file stays and re-fires. A `Move` onto an existing same-named file replaces it, so a recurring file name moves cleanly every time; with `preserveSubDirs: false`, same-named files from different subdirectories land on one destination name and the last move wins, so flattened moves should only be used where names are unique.

A `Caller` is passed to each handler so it can act on the event's file without constructing a separate client. The listener's own polling uses the same share-scoped client that backs the `Caller`, so one listener holds exactly one connection stack. The `Caller` forwards a curated share-scoped subset of `Client` (`downloadFile`, `getFileContent`, `getFileText`, `getFileJson`, `getFileXml`, `getFileCsv`, `uploadFile`, `uploadContent`, `deleteFile`, `copyFile`, `checkCopyStatus`, `abortCopy`, `renameFile`, `createDirectory`, `deleteDirectory`, `list`). Handlers pass the event's path explicitly, e.g. `caller->deleteFile(file.path)`, and read the share's name from `FileInfo.shareName`.

A failed poll surfaces its error: the listener logs it on every poll, and a declared `onError` receives it. Polling keeps its configured interval, so the next scheduled poll scans again.

## 6. Error Types

Every error raised by an operation of this module is a subtype of the distinct `Error` type. The hierarchy splits by origin: an error the Azure service raised is a `ServiceError` and carries a `ServiceErrorDetail` with the HTTP status and the Azure error code of the failed request, while a client-side failure is the generic `Error` and carries no detail (no server exchange produced a status or a code, and the connector never fabricates them). Callers can pattern-match on specific failures:

```ballerina
public type ServiceErrorDetail record {|
    # The HTTP status code returned by Azure
    int httpStatus;
    # The Azure error code (e.g. `ShareNotFound`)
    string errorCode;
|};

public type Error distinct error;

public type ServiceError distinct (Error & error<ServiceErrorDetail>);

public type NotFoundError distinct ServiceError;

public type ConflictError distinct ServiceError;

public type AuthorizationError distinct ServiceError;

public type PreconditionFailedError distinct ServiceError;

public type RangeNotSatisfiableError distinct ServiceError;

public type QuotaExceededError distinct ServiceError;

```

* `ServiceError`: any error raised by the Azure service; a service failure whose Azure error code maps to none of the specific subtypes below stays this generic type.
* `NotFoundError`: the requested share, directory, or file was not found (HTTP 404).
* `ConflictError`: the operation conflicts with the current state of the resource, for example creating a share that already exists (HTTP 409).
* `AuthorizationError`: authentication or authorization failed, for example an invalid key or insufficient SAS permissions (HTTP 403).
* `PreconditionFailedError`: a precondition such as an ETag condition or a lease-id requirement was not met (HTTP 412).
* `RangeNotSatisfiableError`: the requested byte range cannot be satisfied for the target file (HTTP 416).
* `QuotaExceededError`: a write was rejected because the share's provisioned capacity is exhausted (HTTP 403).

Mapping keys on the Azure error code string, not the HTTP status alone: `ShareSizeLimitReached` (HTTP 403) maps to `QuotaExceededError`, distinct from auth failures (also HTTP 403) mapping to `AuthorizationError`. The human-readable description becomes the Ballerina error's `message()` rather than being duplicated into the detail record.

## 7. Samples

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

    check fileShare->downloadFile("/2026/07/invoice.pdf", "./copies/invoice.pdf");
}
```

Share administration:

```ballerina
files:AdminClient admin = check new (auth = {accountName: "myacct", accountKey: "..."});

if !(check admin->hasShare("invoices")) {
    check admin->createShare("invoices", {quotaInGb: 100});
}
```

Minting a read-only, one-hour SAS token for a single file (a local signing operation, invoked with `.`):

```ballerina
import ballerina/time;

files:Client fileShare = check new ("invoices", auth = {accountName: "myacct", accountKey: "..."});

string sasToken = check fileShare.generateSas("/2026/07/invoice.pdf", {
    expiryTime: time:utcAddSeconds(time:utcNow(), 3600),
    permissions: {read: true}
});
```

Handling a specific failure:

```ballerina
files:FileProperties|files:Error properties = fileShare->getFileProperties("/2026/07/invoice.pdf");
if properties is files:NotFoundError {
    // the file is absent; create it, or skip
} else if properties is files:Error {
    return properties;
}
```

Reacting to files arriving in a share:

```ballerina
import ballerinax/azure.storage.files;

listener files:Listener invoiceListener = check new ("invoices",
    auth = {accountName: "myacct", accountKey: "..."},
    pollingInterval = 30
);

service /incoming on invoiceListener {
    remote function onFile(byte[] content, files:FileInfo file, files:Caller caller) returns error? {
        check caller->downloadFile(file.path, "./processed/" + file.name);
        // Consume the file so it does not fire again on the next poll.
        check caller->deleteFile(file.path);
    }
}
```
