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

import ballerina/crypto;
import ballerina/time;

// ---------------------------------------------------------------------------
// Data-model records (results returned by operations)
// ---------------------------------------------------------------------------

# One share as returned by `AdminClient.listShares`.
public type ShareInfo record {|
    # The share name
    string name;
    # The share's properties
    ShareProperties properties;
    # User-defined metadata, when requested via `ShareListOptions.includeMetadata`
    map<string> metadata?;
    # The snapshot identifier, present only for snapshot listings
    string snapshotId?;
    # `true` when this entry is a soft-deleted share (requires `includeDeleted`)
    boolean isDeleted?;
    # The share version; pass to `AdminClient.undeleteShare` to restore a deleted share
    string version?;
|};

# Properties of a file share. A point-in-time snapshot; call `getShareProperties` again for
# current state.
public type ShareProperties record {|
    # The provisioned capacity of the share, in GiB
    int quotaInGb;
    # The share's access tier. Shares on premium (FileStorage) accounts always report `PREMIUM`
    ShareAccessTier accessTier;
    # The entity tag for optimistic concurrency
    string eTag;
    # The last-modified time (UTC)
    time:Utc lastModified;
    # User-defined metadata
    map<string> metadata?;
    # The enabled protocols (SMB and/or NFS)
    ShareProtocol[] enabledProtocols?;
    # The NFS root-squash setting (NFS shares only)
    NfsRootSquash rootSquash?;
    # Where the lease stands in its lifecycle; present only while a lease exists
    LeaseState leaseState?;
    # `LOCKED` while a lease is in force, `UNLOCKED` otherwise; present only while a lease exists
    LeaseStatus leaseStatus?;
    # Whether the active lease is infinite or fixed-duration; present only while a lease
    # exists
    LeaseDuration leaseDuration?;
    # Provisioned IOPS (premium shares only)
    int provisionedIops?;
    # Provisioned bandwidth in MiB/s (premium shares only)
    int provisionedBandwidthMibps?;
|};

# Properties of a directory. A point-in-time snapshot; call `getDirectoryProperties` again
# for current state.
public type DirectoryProperties record {|
    # The entity tag for optimistic concurrency
    string eTag;
    # The last-modified time (UTC)
    time:Utc lastModified;
    # User-defined metadata
    map<string> metadata?;
    # Whether the service has encrypted the directory at rest
    boolean isServerEncrypted;
    # SMB-specific properties; populated on SMB shares, absent on NFS shares
    SmbProperties smbProperties?;
    # POSIX/NFS-specific properties (NFS shares only)
    PosixProperties posixProperties?;
|};

# Properties of a file. A point-in-time snapshot; call `getFileProperties` again for
# current state.
public type FileProperties record {|
    # The entity tag for optimistic concurrency
    string eTag;
    # The last-modified time (UTC)
    time:Utc lastModified;
    # The size of the file in bytes
    int contentLength;
    # The MIME type of the content (e.g. `application/pdf`), served as `Content-Type` on
    # downloads. `application/octet-stream` when no content type was ever set
    string contentType = "application/octet-stream";
    # The encoding applied to the stored content (e.g. `gzip`)
    string contentEncoding?;
    # How receivers should present the content (e.g. `attachment` or `inline`)
    string contentDisposition?;
    # Caching directives served with the file (e.g. `max-age=3600, private`)
    string cacheControl?;
    # Base64-encoded MD5 of the content, for integrity verification
    string contentMd5?;
    # User-defined metadata
    map<string> metadata?;
    # Whether the service has encrypted the file at rest (server-side encryption, covering
    # the file data and its metadata)
    boolean isServerEncrypted;
    # Where the lease stands in its lifecycle; present only while a lease exists
    LeaseState leaseState?;
    # `LOCKED` while a lease is in force, `UNLOCKED` otherwise; present only while a lease exists
    LeaseStatus leaseStatus?;
    # Whether the active lease is infinite or fixed-duration; present only while a lease
    # exists
    LeaseDuration leaseDuration?;
    # The status of the most recent copy operation, if any
    CopyStatus copyStatus?;
    # The identifier of the most recent copy operation, if any
    string copyId?;
    # Progress of the most recent copy operation, if any
    CopyProgress copyProgress?;
    # SMB-specific properties
    SmbProperties smbProperties?;
    # POSIX/NFS-specific properties (NFS shares only)
    PosixProperties posixProperties?;
|};

# Progress of an asynchronous copy operation.
public type CopyProgress record {|
    # The number of bytes copied so far
    int copiedBytes;
    # The total number of bytes to be copied
    int totalBytes;
|};

# One entry returned by `Client.list`.
public type Entry record {|
    # The share-relative path of the entry, e.g. `/dir1/dir2/file.ext`
    string path;
    # The entry name (file or directory), without the directory component
    string name;
    # `true` if the entry is a directory, `false` if it is a file
    boolean isDirectory;
    # The file size in bytes; not present for directories
    int sizeBytes?;
    # The entry identifier
    string id;
    # The entity tag; present only when the listing requests extended info
    # (`ListOptions.includeExtendedInfo`)
    string eTag?;
    # The last-modified time (UTC); present only when the listing requests extended info
    # (`ListOptions.includeExtendedInfo`)
    time:Utc lastModified?;
|};

# The listing-derived payload delivered to a listener service's handlers, identifying the file
# an event is about. It carries what a directory listing provides; for full properties
# (content type, metadata, headers), construct a `Client` and call `getFileProperties`.
public type FileInfo record {|
    # The share-relative path of the file, e.g. `/dir1/dir2/file.ext`
    string path;
    # The file name only, without the directory component
    string name;
    # The file size in bytes
    int sizeBytes;
    # The entity tag of the file
    string eTag;
    # The last-modified time (UTC)
    time:Utc lastModified;
|};

# SMB-specific properties of a file or directory. Populated on SMB shares and absent on
# NFS shares.
public type SmbProperties record {|
    # The NTFS attributes of the file or directory. More than one attribute can be set at a
    # time (e.g. read-only and hidden)
    NtfsFileAttribute[] ntfsFileAttributes?;
    # The key of a permission (SDDL string) stored in the share's permission store
    string filePermissionKey?;
    # The creation time (UTC)
    time:Utc fileCreationTime?;
    # The last-write time (UTC): the last time data was written to the file, excluding
    # metadata changes
    time:Utc fileLastWriteTime?;
    # The change time (UTC): the last time the file's content or metadata (permissions,
    # size, attributes) was modified
    time:Utc fileChangeTime?;
    # The file identifier
    string fileId?;
    # The parent directory identifier
    string parentId?;
|};

# POSIX/NFS-specific properties of a file or directory. Present only on NFS shares.
public type PosixProperties record {|
    # The owner user id (UID)
    string owner?;
    # The owning group id (GID)
    string group?;
    # The file mode (permissions), octal or symbolic
    string fileMode?;
    # The NFS file type (regular file, directory, or symbolic link)
    NfsFileType fileType?;
    # The number of hard links to the file (number of references to the file)
    int linkCount?;
|};

# The result of starting a copy operation. Copies are asynchronous.
public type CopyInfo record {|
    # The copy operation identifier; pass to `Client.abortCopy` to cancel a pending copy
    string copyId;
    # The copy status at the moment the copy started, `PENDING` while the copy is still in progress
    CopyStatus copyStatus;
    # The entity tag of the destination after the copy started
    string eTag;
    # The last-modified time of the destination (UTC)
    time:Utc lastModified;
|};

# The state of the most recent copy operation that targeted a file, as returned by
# `Client.checkCopyStatus`. A point-in-time snapshot; call `checkCopyStatus` again to
# observe the progress of a pending copy.
public type CopyStatusInfo record {|
    # The identifier of the copy operation; pass to `Client.abortCopy` to cancel a pending copy
    string copyId;
    # The status of the copy
    CopyStatus copyStatus;
    # Progress of the copy (bytes copied so far out of the total)
    CopyProgress copyProgress?;
|};

# A single byte range within a file. Both bounds are inclusive (a range starting at offset
# `o` with length `l` is `startByte = o`, `endByte = o + l - 1`).
public type Range record {|
    # The zero-based inclusive start offset
    int startByte;
    # The zero-based inclusive end offset
    int endByte;
|};

# The account's file-service configuration: request-metrics collection and cross-origin
# resource sharing rules.
public type ServiceProperties record {|
    # Metrics aggregated per hour
    Metrics hourMetrics?;
    # Metrics aggregated per minute
    Metrics minuteMetrics?;
    # The CORS (Cross-Origin Resource Sharing) rules, evaluated in order; at most five
    CorsRule[] cors?;
    # Protocol-level settings
    ProtocolSettings protocol?;
|};

# A metrics-collection setting of the file service.
public type Metrics record {|
    # Whether metrics are collected
    boolean enabled;
    # The storage-analytics version the setting applies to
    string version?;
    # Whether metrics cover called API operations as well as storage capacity
    boolean includeApis?;
    # How many days collected metrics are retained
    int retentionDays?;
|};

# One CORS (Cross-Origin Resource Sharing) rule of the file service. The string fields are
# comma-separated lists; `*` allows all.
public type CorsRule record {|
    # The origin domains allowed to make requests
    string allowedOrigins;
    # The HTTP methods an allowed origin may use
    string allowedMethods;
    # The request headers an allowed origin may send
    string allowedHeaders;
    # The response headers exposed to the browser
    string exposedHeaders;
    # How long, in seconds, a browser may cache the preflight response
    int maxAgeInSeconds;
|};

# Protocol-level settings of the file service.
public type ProtocolSettings record {|
    # Whether SMB multichannel (multiple parallel network channels per SMB session) is
    # enabled for the account
    boolean smbMultichannelEnabled?;
|};

# A key for signing user-delegation SAS tokens, obtained via
# `AdminClient.getUserDelegationKey`.
public type UserDelegationKey record {|
    # The object id of the Entra ID principal the key was issued to
    string signedObjectId;
    # The Entra ID tenant the key was issued in
    string signedTenantId;
    # The start of the key's validity period (UTC)
    time:Utc signedStart;
    # The end of the key's validity period (UTC)
    time:Utc signedExpiry;
    # The service the key is valid for
    string signedService;
    # The storage service version the key was issued for
    string signedVersion;
    # The key itself, base64-encoded
    string value;
|};

# One share snapshot, as returned by `Client.createShareSnapshot` and
# `Client.listShareSnapshots`.
public type ShareSnapshotInfo record {|
    # The snapshot identifier, an opaque UTC-timestamp-formatted string. Pass it as the
    # `snapshotId` of the download and list options to read from the snapshot
    string snapshotId;
    # The entity tag of the share at the moment of the snapshot
    string eTag;
    # The last-modified time of the share at the moment of the snapshot (UTC)
    time:Utc lastModified;
|};

# A stored access policy with its identifier. Share SAS tokens can reference the policy
# by `id`.
public type SignedIdentifier record {|
    # The policy identifier referenced by SAS tokens (at most 64 characters)
    string id;
    # The policy itself: validity window and permissions
    AccessPolicy accessPolicy;
|};

# A stored access policy's validity window and permissions.
public type AccessPolicy record {|
    # The start of the policy's validity period (UTC); omit for immediately valid
    time:Utc startsOn?;
    # The end of the policy's validity period (UTC); omit for no expiry
    time:Utc expiresOn?;
    # The permission string, in the service's fixed letter order (e.g. `rwdl` for read,
    # write, delete, list)
    string permissions;
|};

# One open SMB handle on a file or directory.
public type HandleInfo record {|
    # The handle identifier; pass to the force-close operations to close just this handle
    string handleId;
    # The share-relative path the handle is open on
    string path;
    # The identifier of the file or directory the handle is open on
    string fileId?;
    # The SMB session identifier the handle belongs to
    string sessionId?;
    # The IP address of the client holding the handle
    string clientIp?;
    # When the handle was opened (UTC)
    time:Utc openTime?;
    # When the client last reconnected the handle (UTC)
    time:Utc lastReconnectTime?;
|};

# The result of force-closing SMB handles.
public type CloseHandlesInfo record {|
    # The number of handles that were closed
    int closedHandles;
    # The number of handles that could not be closed
    int failedHandles;
|};

# The result of `Client.listRangesDiff`: how a file's ranges changed since a share snapshot.
public type RangeDiff record {|
    # The ranges written since the baseline snapshot
    Range[] ranges;
    # The ranges cleared since the baseline snapshot
    Range[] clearRanges;
|};

// ---------------------------------------------------------------------------
// SAS signature values
// ---------------------------------------------------------------------------

# The inputs for generating an account-level SAS via `AdminClient.generateAccountSas`.
public type AccountSasSignatureValues record {|
    # The end of the SAS validity period (UTC)
    time:Utc expiryTime;
    # The permissions the SAS grants
    AccountSasPermissions permissions;
    # The resource types the SAS applies to
    AccountSasResourceTypes resourceTypes;
    # The start of the SAS validity period (UTC); omit for immediately valid
    time:Utc startTime?;
    # The protocols a request presenting the SAS may use; omit to allow HTTPS and HTTP
    SasProtocol protocol?;
    # An IP address or range the requests must come from (e.g. `168.1.5.60-168.1.5.70`)
    string ipRange?;
|};

# The permissions granted by an account-level SAS. Every permission is off unless enabled.
public type AccountSasPermissions record {|
    # Read content, properties, and metadata, and list entries
    boolean read = false;
    # Write content, properties, and metadata
    boolean write = false;
    # Delete resources
    boolean delete = false;
    # List shares and directory contents
    boolean list = false;
    # Add content (append-style operations of other storage services)
    boolean add = false;
    # Create new resources
    boolean create = false;
    # Update stored entities (of other storage services)
    boolean update = false;
    # Process stored messages (of other storage services)
    boolean process = false;
|};

# The resource types an account-level SAS applies to. Every type is off unless enabled.
public type AccountSasResourceTypes record {|
    # Service-level operations (e.g. list shares, service properties)
    boolean 'service = false;
    # Container-level operations (the share level: share properties, metadata)
    boolean container = false;
    # Object-level operations (files and directories)
    boolean 'object = false;
|};

# The inputs for generating a share-scoped SAS via `Client.generateShareSas` or
# `Client.generateShareUserDelegationSas`.
public type ShareSasSignatureValues record {|
    # The end of the SAS validity period (UTC). May be omitted only when `identifier`
    # references a stored access policy that carries an expiry
    time:Utc expiryTime;
    # The permissions the SAS grants
    ShareSasPermissions permissions;
    # The start of the SAS validity period (UTC); omit for immediately valid
    time:Utc startTime?;
    # The protocols a request presenting the SAS may use; omit to allow HTTPS and HTTP
    SasProtocol protocol?;
    # An IP address or range the requests must come from (e.g. `168.1.5.60-168.1.5.70`)
    string ipRange?;
    # The identifier of a stored access policy on the share, as an alternative to spelling
    # out expiry and permissions here
    string identifier?;
|};

# The permissions granted by a share-scoped SAS. Every permission is off unless enabled.
public type ShareSasPermissions record {|
    # Read file content, properties, and metadata
    boolean read = false;
    # Create files and directories
    boolean create = false;
    # Write file content, properties, and metadata
    boolean write = false;
    # Delete files and directories
    boolean delete = false;
    # List files and directories
    boolean list = false;
|};

# The inputs for generating a file-scoped SAS via `Client.generateSas` or
# `Client.generateUserDelegationSas`.
public type FileSasSignatureValues record {|
    # The end of the SAS validity period (UTC). May be omitted only when `identifier`
    # references a stored access policy that carries an expiry
    time:Utc expiryTime;
    # The permissions the SAS grants
    FileSasPermissions permissions;
    # The start of the SAS validity period (UTC); omit for immediately valid
    time:Utc startTime?;
    # The protocols a request presenting the SAS may use; omit to allow HTTPS and HTTP
    SasProtocol protocol?;
    # An IP address or range the requests must come from (e.g. `168.1.5.60-168.1.5.70`)
    string ipRange?;
    # The identifier of a stored access policy on the share, as an alternative to spelling
    # out expiry and permissions here
    string identifier?;
|};

# The permissions granted by a file-scoped SAS. Every permission is off unless enabled.
public type FileSasPermissions record {|
    # Read the file's content, properties, and metadata
    boolean read = false;
    # Create the file
    boolean create = false;
    # Write the file's content, properties, and metadata
    boolean write = false;
    # Delete the file
    boolean delete = false;
|};

// ---------------------------------------------------------------------------
// Enums
// ---------------------------------------------------------------------------

# How a share's snapshots are handled when the share is deleted.
public enum ShareSnapshotsDeleteOption {
    # Also delete the share's snapshots
    INCLUDE = "include",
    # Also delete the share's snapshots, breaking any leases on them
    INCLUDE_LEASED = "include-leased"
}

# The billing and performance tier of a file share.
public enum ShareAccessTier {
    # Optimized for frequently accessed data
    HOT = "Hot",
    # Optimized for infrequently accessed data
    COOL = "Cool",
    # Optimized for high transaction volumes
    TRANSACTION_OPTIMIZED = "TransactionOptimized",
    # The default (and only) tier of provisioned premium file shares
    PREMIUM = "Premium"
}

# The file-access protocol(s) enabled on a share.
public enum ShareProtocol {
    # Server Message Block
    SMB,
    # Network File System
    NFS
}

# The NFS root-squash behaviour applied to a share.
public enum NfsRootSquash {
    # No squashing is applied
    NO_ROOT_SQUASH = "NoRootSquash",
    # The root user is mapped to an anonymous user
    ROOT_SQUASH = "RootSquash",
    # All users are mapped to an anonymous user
    ALL_SQUASH = "AllSquash"
}

# An NTFS attribute of a file or directory. A file or directory can carry several attributes
# at once, as an `NtfsFileAttribute[]`.
public enum NtfsFileAttribute {
    # The file is read-only
    READ_ONLY = "ReadOnly",
    # The file is hidden, and excluded from ordinary directory listings
    HIDDEN = "Hidden",
    # The file is a system file, used by the operating system
    SYSTEM = "System",
    # The file is a standard file with no special attributes; valid only on its own
    NORMAL = "None",
    # The entry is a directory rather than a file
    DIRECTORY = "Directory",
    # The file is marked for backup or removal
    ARCHIVE = "Archive",
    # The file holds temporary data
    TEMPORARY = "Temporary",
    # The file's data is not immediately available
    OFFLINE = "Offline",
    # The file is excluded from the operating system's content indexing
    NOT_CONTENT_INDEXED = "NotContentIndexed",
    # The file is excluded from the data integrity scan
    NO_SCRUB_DATA = "NoScrubData"
}

# The type of an NFS file-system entry: a regular file (`Regular`), a directory
# (`Directory`), or a symbolic link (`SymLink`).
public enum NfsFileType {
    # A regular file
    REGULAR = "Regular",
    // DIRECTORY is a module-level constant shared with NtfsFileAttribute (enum members merge
    // when their values match), so its doc line lives on the NtfsFileAttribute member.
    DIRECTORY = "Directory",
    # A symbolic link
    SYMLINK = "SymLink"
}

# The status of an asynchronous copy operation.
public enum CopyStatus {
    # The copy is in progress
    PENDING = "pending",
    # The copy completed successfully
    SUCCESS = "success",
    # The copy was aborted
    ABORTED = "aborted",
    # The copy failed
    FAILED = "failed"
}

# The lifecycle state of a share's or file's lease.
public enum LeaseState {
    # No lease is held and a new lease can be acquired
    AVAILABLE = "available",
    # A lease is currently held
    LEASED = "leased",
    # A fixed-duration lease has expired
    EXPIRED = "expired",
    # The lease is being broken and will expire after the break period
    BREAKING = "breaking",
    # The lease has been broken
    BROKEN = "broken"
}

# Whether a lease currently locks the share or file: `LOCKED` while a lease is in force,
# `UNLOCKED` otherwise.
public enum LeaseStatus {
    # A lease is held and the resource is locked
    LOCKED = "locked",
    # No lease is held and the resource is unlocked
    UNLOCKED = "unlocked"
}

# The duration category of a lease.
public enum LeaseDuration {
    # The lease never expires until explicitly released
    INFINITE = "infinite",
    # The lease expires after a fixed period
    FIXED = "fixed"
}

# How file permissions are handled when copying a file.
public enum PermissionCopyMode {
    # Copy the permission from the source file
    SOURCE = "source",
    # Override with an explicitly supplied permission
    OVERRIDE = "override"
}

# The protocols a request presenting a SAS token may use.
public enum SasProtocol {
    # HTTPS requests only
    HTTPS = "https",
    # HTTPS and HTTP requests
    HTTPS_HTTP = "https,http"
}

// ---------------------------------------------------------------------------
// Authentication
// ---------------------------------------------------------------------------

# Shared Key authentication using one of the storage account's access keys.
public type SharedKeyConfig record {|
    # The storage account name, used to sign requests and to derive the service URL
    string accountName;
    # A base64-encoded access key of the storage account
    string accountKey;
    # The file service endpoint URL, including the scheme. Omit to use the default
    # `https://{accountName}.file.core.windows.net`
    string serviceUrl?;
|};

# Shared Access Signature (SAS) authentication with a bare SAS token, as issued by
# `az storage share generate-sas` or the SAS-generation operations.
public type SasConfig record {|
    # The name of the storage account the token belongs to (determines the service URL)
    string accountName;
    # A SAS token scoped to the required resources and permissions
    string sasToken;
|};

# Shared Access Signature (SAS) authentication with a full SAS URL, which carries the service
# URL and the SAS token in one string, as issued by the Azure portal.
public type SasUrlConfig record {|
    # A full file-service SAS URL, including the scheme and the SAS query string
    # (e.g. `https://{account}.file.core.windows.net/?sv=...&sig=...`)
    string sasUrl;
|};

# Connection-string authentication. The connection string carries the account name, the
# credential (an account key or a SAS token), and the service endpoints.
public type ConnectionStringConfig record {|
    # An Azure Storage connection string, as issued by the Azure portal, the Azure CLI, or
    # infrastructure tooling
    string connectionString;
|};

// ---------------------------------------------------------------------------
// Entra ID authentication
// ---------------------------------------------------------------------------

# The credential-kind discriminator value selecting `DefaultEntraIdConfig`.
public const DEFAULT_AZURE_CREDENTIAL = "default";

# The credential-kind discriminator value selecting `ManagedIdentityConfig`.
public const MANAGED_IDENTITY = "managed-identity";

# Microsoft Entra ID authentication through the default credential chain. The chain tries the
# environment, a managed identity, and developer sign-ins (Azure CLI, IDE accounts) in turn, so
# one configuration works both locally and when deployed.
public type DefaultEntraIdConfig record {|
    # Selects the default credential chain
    DEFAULT_AZURE_CREDENTIAL kind;
    # The storage account name (determines the service URL unless `serviceUrl` overrides it)
    string accountName;
    # The file service endpoint URL, including the scheme. Omit to use the default
    # `https://{accountName}.file.core.windows.net`
    string serviceUrl?;
|};

# Microsoft Entra ID authentication as an Azure managed identity, for workloads running on
# Azure compute (VMs, App Service, AKS, Functions).
public type ManagedIdentityConfig record {|
    # Selects the managed-identity credential
    MANAGED_IDENTITY kind;
    # The storage account name (determines the service URL unless `serviceUrl` overrides it)
    string accountName;
    # The client id of a user-assigned managed identity; omit to use the system-assigned
    # identity
    string clientId?;
    # The file service endpoint URL, including the scheme. Omit to use the default
    # `https://{accountName}.file.core.windows.net`
    string serviceUrl?;
|};

# Microsoft Entra ID authentication as a service principal with a client secret.
public type ClientSecretConfig record {|
    # The storage account name (determines the service URL unless `serviceUrl` overrides it)
    string accountName;
    # The Entra ID tenant (directory) id
    string tenantId;
    # The application (client) id of the service principal
    string clientId;
    # The client secret of the service principal
    string clientSecret;
    # The file service endpoint URL, including the scheme. Omit to use the default
    # `https://{accountName}.file.core.windows.net`
    string serviceUrl?;
|};

# Microsoft Entra ID authentication as a service principal with a client certificate.
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
    # The file service endpoint URL, including the scheme. Omit to use the default
    # `https://{accountName}.file.core.windows.net`
    string serviceUrl?;
|};

# Microsoft Entra ID workload-identity authentication, for Kubernetes workloads federated
# with Entra ID.
public type WorkloadIdentityConfig record {|
    # The storage account name (determines the service URL unless `serviceUrl` overrides it)
    string accountName;
    # The Entra ID tenant (directory) id
    string tenantId;
    # The application (client) id federated with the workload
    string clientId;
    # The path to the file holding the federated service-account token
    string tokenFilePath;
    # The file service endpoint URL, including the scheme. Omit to use the default
    # `https://{accountName}.file.core.windows.net`
    string serviceUrl?;
|};

# Microsoft Entra ID authentication: one record per credential kind. The identity must hold the
# `Storage File Data Privileged Reader` or `Storage File Data Privileged Contributor` role.
public type EntraIdConfig DefaultEntraIdConfig|ManagedIdentityConfig|ClientSecretConfig|
    ClientCertificateConfig|WorkloadIdentityConfig;

# The authentication configuration: one credential-artifact record (an account key, a bare SAS
# token, a full SAS URL, a connection string, or a Microsoft Entra ID identity).
public type AuthConfig SharedKeyConfig|SasConfig|SasUrlConfig|ConnectionStringConfig|EntraIdConfig;

// ---------------------------------------------------------------------------
// Resilience and transport
// ---------------------------------------------------------------------------

# The retry policy kinds: `EXPONENTIAL` grows the delay between tries exponentially;
# `FIXED` keeps the same delay between every try.
public enum RetryPolicyType {
    # Delays grow exponentially between tries
    EXPONENTIAL = "exponential",
    // FIXED is a module-level constant shared with LeaseDuration (enum members merge when
    // their values match), so its doc line lives on the LeaseDuration member.
    FIXED = "fixed"
}

# Retry behaviour for service requests.
public type RetryConfig record {|
    # How the delay between tries grows
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

# The proxy protocol kinds.
public enum ProxyType {
    # An HTTP proxy
    HTTP,
    # A SOCKS4 proxy
    SOCKS4,
    # A SOCKS5 proxy
    SOCKS5
}

# Routes the connector's traffic through a proxy server.
public type ProxyConfig record {|
    # The proxy protocol
    ProxyType proxyType;
    # The proxy host name or IP address
    string host;
    # The proxy port
    int port;
    # The user name, when the proxy requires authentication
    string username?;
    # The password, when the proxy requires authentication
    string password?;
    # Hosts reached directly, bypassing the proxy
    string[] nonProxyHosts = [];
|};

# Tunes the connector's HTTP connection pool.
public type ConnectionPoolConfig record {|
    # The maximum number of concurrent connections
    int maxConnections = 50;
    # How long an idle connection is kept before being closed, in seconds
    decimal idleTimeoutSeconds = 60;
    # The timeout for establishing a connection, in seconds
    decimal connectTimeoutSeconds = 10;
    # The timeout for reading a response, in seconds
    decimal readTimeoutSeconds = 60;
|};

# HTTP transport settings: proxying, connection pooling, and TLS.
public type TransportConfig record {|
    # Route traffic through this proxy
    ProxyConfig proxy?;
    # Connection-pool tuning
    ConnectionPoolConfig connectionPool = {};
    # Custom TLS settings (trust and key material, verification)
    SecureSocket secureSocket?;
|};

# Custom TLS settings for the connection to the service.
public type SecureSocket record {|
    # The trust material for verifying the server: a PKCS12 or JKS truststore, or the path
    # to a PEM certificate file. Omit to trust the platform's default certificate authorities
    crypto:TrustStore|string cert?;
    # The client's own identity for mutual TLS: a PKCS12 or JKS keystore, or a certificate
    # and private key pair. Omit when the server does not request a client certificate
    crypto:KeyStore|CertKey 'key?;
    # The TLS versions offered during the handshake (e.g. `TLSv1.3`, `TLSv1.2`). Omit to use
    # the platform defaults
    string[] tlsVersions?;
    # The cipher suites offered during the handshake. Omit to use the platform defaults
    string[] ciphers?;
    # Verify that the server certificate matches the host being called. Disabling this
    # removes protection against man-in-the-middle attacks, so it is meant for testing only
    boolean verifyHostName = true;
    # Allow TLS sessions to be reused across connections
    boolean shareSession = true;
    # Check the server certificate against revocation information: a stapled OCSP response
    # when the server sends one, otherwise an OCSP or CRL fetch. Requires `cert` to be set
    boolean validateRevocation = false;
    # The SNI (Server Name Indication) host name presented during the handshake; omit to use
    # the host being called
    string serverName?;
    # The TLS handshake timeout, in seconds
    decimal handshakeTimeoutSeconds?;
    # How long a TLS session stays reusable, in seconds
    decimal sessionTimeoutSeconds?;
|};

# A client certificate and private key pair, as files.
public type CertKey record {|
    # The path to the certificate file
    string certFile;
    # The path to the private key file
    string keyFile;
    # The password protecting the private key, when it has one
    string keyPassword?;
|};

# Configuration for an `azure.storage.files` client (`Client` or `AdminClient`).
public type ClientConfiguration record {|
    # The authentication configuration (see `AuthConfig`)
    AuthConfig auth;
    # Retry behaviour for service requests; omit for the service defaults
    RetryConfig retryConfig?;
    # HTTP transport settings (proxy, connection pool, TLS); omit for the defaults
    TransportConfig transportConfig?;
|};
