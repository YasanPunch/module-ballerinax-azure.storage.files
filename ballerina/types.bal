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

import ballerina/time;

// ---------------------------------------------------------------------------
// Data-model records (results returned by operations)
// ---------------------------------------------------------------------------

# One share as returned by `AdminClient.listShares` (maps to the SDK `ShareItem`).
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

# Properties of a file share (maps to the SDK `ShareProperties`). A point-in-time snapshot of
# one service response — never updated after it is returned; call `getShareProperties` again for
# current state (the lease fields in particular can change server-side at any moment).
public type ShareProperties record {|
    # The provisioned capacity of the share, in GiB
    int quotaInGb;
    # The share's access tier. On pay-as-you-go (GPv2) accounts this is `TRANSACTION_OPTIMIZED`
    # unless set otherwise at creation; shares on premium (FileStorage) accounts always report
    # `PREMIUM`
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
    # Where the lease stands in its lifecycle (available/leased/expired/breaking/broken) —
    # the detailed view; present only while a lease exists
    LeaseState leaseState?;
    # The binary summary of the lease: `LOCKED` while a lease is in force (writes need the
    # lease id), `UNLOCKED` otherwise; present only while a lease exists
    LeaseStatus leaseStatus?;
    # Whether the active lease is infinite or fixed-duration; present only while a lease
    # exists
    LeaseDuration leaseDuration?;
    # Provisioned IOPS (premium shares only)
    int provisionedIops?;
    # Provisioned bandwidth in MiB/s (premium shares only)
    int provisionedBandwidthMibps?;
|};

# Properties of a directory (maps to the SDK `ShareDirectoryProperties`). A point-in-time
# snapshot of one service response — re-fetch via `getDirectoryProperties` for current state.
public type DirectoryProperties record {|
    # The entity tag for optimistic concurrency
    string eTag;
    # The last-modified time (UTC)
    time:Utc lastModified;
    # User-defined metadata
    map<string> metadata?;
    # Whether the service has encrypted the directory (basically metadata) at rest (server-side encryption)
    boolean isServerEncrypted;
    # SMB-specific properties; populated on SMB shares, absent on NFS shares
    SmbProperties smbProperties?;
    # POSIX/NFS-specific properties (NFS shares only)
    PosixProperties posixProperties?;
|};

# Properties of a file (curated from the SDK `ShareFileProperties`). A point-in-time snapshot
# of one service response — never updated after it is returned; call `getFileProperties` again for
# current state (the lease and copy fields in particular change server-side as leases transition
# and pending copies progress). Stale values cannot corrupt writes: Azure re-checks leases and
# eTag preconditions on every request (a mismatch fails with `PreconditionFailedError`).
public type FileProperties record {|
    # The entity tag for optimistic concurrency
    string eTag;
    # The last-modified time (UTC)
    time:Utc lastModified;
    # The size of the file in bytes
    int contentLength;
    # The MIME type of the content (e.g. `application/pdf`), served as `Content-Type` on
    # downloads so clients know how to handle the bytes; `application/octet-stream` (the
    # service default) when no content type was ever set
    string contentType = "application/octet-stream";
    # The encoding applied to the stored content (e.g. `gzip`), served as `Content-Encoding`
    # so consumers know to decode before use
    string contentEncoding?;
    # How receivers should present the content of the file (e.g. `attachment` to
    # force a save dialog, `inline` to display in the browser, etc.)
    string contentDisposition?;
    # Caching directives served with the file (e.g. `max-age=3600, private`), telling
    # browsers/proxies whether and how long they may cache it
    string cacheControl?;
    # Base64-encoded MD5 of the content, for integrity verification of stored/transferred data
    string contentMd5?;
    # User-defined metadata
    map<string> metadata?;
    # Whether the service has encrypted the file at rest (server-side encryption, covering
    # the file data and its metadata)
    boolean isServerEncrypted;
    # Where the lease stands in its lifecycle (available/leased/expired/breaking/broken) —
    # the detailed view; present only while a lease exists
    LeaseState leaseState?;
    # The binary summary of the lease: `LOCKED` while a lease is in force (writes need the
    # lease id), `UNLOCKED` otherwise; present only while a lease exists
    LeaseStatus leaseStatus?;
    # Whether the active lease is infinite or fixed-duration; present only while a lease
    # exists
    LeaseDuration leaseDuration?;
    # The status of the most recent copy operation, if any. Use `Client.checkCopyStatus` to
    # observe a pending copy's progress.
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

# Progress of an asynchronous copy operation. Parsed by the connector from the service's
# raw `"bytesCopied/totalBytes"` form (the `x-ms-copy-progress` header).
public type CopyProgress record {|
    # The number of bytes copied so far
    int copiedBytes;
    # The total number of bytes to be copied
    int totalBytes;
|};

# One entry returned by `Client.list` (maps to the SDK `ShareFileItem`). The service returns
# only the entry's leaf name; the connector synthesizes the full share-relative `path` while
# it walks the listing, so every entry can be passed directly to the path-taking operations
# (`getFileProperties`, `deleteFile`, `getFileContent`, ...).
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

# SMB-specific properties of a file or directory (maps to the SDK `FileSmbProperties`).
# On SMB shares, property reads populate every field; on NFS shares the record is absent.
# The same record supplies SMB properties on the create/upload/copy options, where every
# field is optional.
public type SmbProperties record {|
    # The NTFS attributes of the file or directory. More than one attribute can be set at a
    # time (e.g. read-only and hidden)
    NtfsFileAttribute[] ntfsFileAttributes?;
    # The key of a permission (SDDL string) stored in the share's permission store
    string filePermissionKey?;
    # The creation time (UTC)
    time:Utc fileCreationTime?;
    # The last-write time (UTC)
    time:Utc fileLastWriteTime?; // last time data was written to the file (excludes metadata changes)
    # The change time (UTC)
    time:Utc fileChangeTime?; // last time the file content or metadata (permissions, size, attributes etc.) was modified
    # The file identifier
    string fileId?;
    # The parent directory identifier
    string parentId?;
|};

# POSIX/NFS-specific properties of a file or directory (maps to the SDK `FilePosixProperties`).
# Present only on NFS shares.
public type PosixProperties record {|
    # The owner user id (UID)
    string owner?;
    # The owning group id (GID) 
    string group?;
    # The file mode (permissions), octal or symbolic.
    string fileMode?;
    # The NFS file type (regular file, directory, or symbolic link)
    NfsFileType fileType?;
    # The number of hard links to the file (number of references to the file)
    int linkCount?;
|};

# The result of starting a copy operation (maps to the SDK `ShareFileCopyInfo`). Copies are
# asynchronous, and this record is a point-in-time snapshot taken when the copy started — it is
# never updated afterwards. To observe progress, call `Client.checkCopyStatus` on the
# destination path; cancel via `Client.abortCopy`.
public type CopyInfo record {|
    # The copy operation identifier; pass to `Client.abortCopy` to cancel a pending copy
    string copyId;
    # The copy status at the moment the copy started — the `CopyStatus` enum value `PENDING`
    # while the server-side copy is still in progress
    CopyStatus copyStatus;
    # The entity tag of the destination after the copy started
    string eTag;
    # The last-modified time of the destination (UTC)
    time:Utc lastModified;
|};

# The state of the most recent copy operation that targeted a file, as returned by
# `Client.checkCopyStatus`. A point-in-time snapshot fetched from the file's properties —
# call `checkCopyStatus` again to observe the progress of a pending copy.
public type CopyStatusInfo record {|
    # The identifier of the copy operation; pass to `Client.abortCopy` to cancel a pending copy
    string copyId;
    # The status of the copy
    CopyStatus copyStatus;
    # Progress of the copy (bytes copied so far out of the total)
    CopyProgress copyProgress?;
|};

# A single byte range within a file (maps to the SDK `ShareFileRange`). Both bounds are
# inclusive, mirroring the service's List Ranges response (a range starting at offset `o`
# with length `l` is `startByte = o`, `endByte = o + l - 1`).
public type Range record {|
    # The zero-based inclusive start offset
    int startByte;
    # The zero-based inclusive end offset
    int endByte;
|};

# The account's file-service configuration (maps to the SDK `ShareServiceProperties`):
# request-metrics collection and cross-origin resource sharing rules.
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
    # The maximum number of channels an SMB multichannel session may open
    int smbMultichannelMaxChannels?;
|};

# A key for signing user-delegation SAS tokens, obtained with Microsoft Entra ID credentials
# via `AdminClient.getUserDelegationKey` (maps to the SDK `UserDelegationKey`). Pass it whole
# to the user-delegation SAS generation operations.
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
# `Client.listShareSnapshots` (maps to the SDK `ShareSnapshotInfo`).
public type ShareSnapshotInfo record {|
    # The snapshot identifier, an opaque UTC-timestamp-formatted string. Pass it as the
    # `snapshotId` of the download and list options to read from the snapshot
    string snapshotId;
    # The entity tag of the share at the moment of the snapshot
    string eTag;
    # The last-modified time of the share at the moment of the snapshot (UTC)
    time:Utc lastModified;
|};

# A stored access policy with its identifier (maps to the SDK `ShareSignedIdentifier`).
# Share SAS tokens can reference the policy by `id`, so revoking or editing the policy
# retroactively controls every SAS minted against it.
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
    # The permission string, in the service's fixed letter order (e.g. `rwdl` (i.e. read, write, delete, list))
    string permissions;
|};

# One open SMB handle on a file or directory (maps to the SDK `HandleItem`).
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

# The result of force-closing SMB handles (maps to the SDK `CloseHandlesInfo`).
public type CloseHandlesInfo record {|
    # The number of handles that were closed
    int closedHandles;
    # The number of handles that could not be closed
    int failedHandles;
|};

# The result of `Client.listRangesDiff`: how a file's ranges changed since a share snapshot
# (maps to the SDK `ShareFileRangeList`).
public type RangeDiff record {|
    # The ranges written since the baseline snapshot
    Range[] ranges;
    # The ranges cleared since the baseline snapshot
    Range[] clearRanges;
|};

// ---------------------------------------------------------------------------
// SAS signature values
// ---------------------------------------------------------------------------

# The inputs for minting an account-level SAS via `AdminClient.generateAccountSas`
# (maps to the SDK `AccountSasSignatureValues`).
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

# The inputs for minting a share-scoped SAS via `Client.generateShareSas` or
# `Client.generateShareUserDelegationSas` (maps to the SDK `ShareServiceSasSignatureValues`).
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

# The inputs for minting a file-scoped SAS via `Client.generateSas` or
# `Client.generateUserDelegationSas` (maps to the SDK `ShareServiceSasSignatureValues`).
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
# There is no list permission at file scope, because a single file cannot be listed.
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

# A file as surfaced to the polling `Listener`'s event handlers.
# Carries only listing-derived fields (what a directory listing can provide), and no event kind:
# `onFile` fires for every file present in the watched path on each poll, so there is no
# added/deleted/modified distinction to convey.
public type FileInfo record {|
    # The share-relative path, e.g. `/dir1/dir2/file.ext`
    string path;
    # The file name only (no directory component)
    string name;
    # The file size in bytes
    int sizeBytes;
    # The entity tag; a change in this value is what marks a file as modified
    string eTag;
    # The last-modified time (UTC)
    time:Utc lastModified;
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
# at once, so the attributes are handled as an array (`NtfsFileAttribute[]`).
public enum NtfsFileAttribute {
    # The file is read-only
    READ_ONLY = "ReadOnly",
    # The file is hidden, and excluded from ordinary directory listings
    HIDDEN = "Hidden",
    # The file is a system file, used by the operating system
    SYSTEM = "System",
    # The file is a standard file with no special attributes; valid only on its own
    NORMAL = "None",
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

# The type of an NFS file-system entry.
public enum NfsFileType {
    # A regular file
    REGULAR = "Regular",
    # A directory
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

# The lifecycle state of a share's or file's lease — the detailed view of where the lease
# stands. For the binary locked-or-not answer, read `LeaseStatus` instead.
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

# Whether a lease currently locks the share or file — the two-valued summary of `LeaseState`
# (`LOCKED` while a lease is in force, including while it is breaking; `UNLOCKED` once it is
# available, expired, or broken).
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
