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

# Properties of a file share (maps to the SDK `ShareProperties`).
public type ShareProperties record {|
    # The provisioned capacity of the share, in GiB
    int quotaInGb;
    # The share's access tier
    ShareAccessTier accessTier?;
    # The entity tag for optimistic concurrency
    string eTag?;
    # The last-modified time (UTC)
    time:Utc lastModified?;
    # User-defined metadata
    map<string> metadata?;
    # The enabled protocols (SMB and/or NFS)
    ShareProtocol[] enabledProtocols?;
    # The NFS root-squash setting (NFS shares only)
    NfsRootSquash rootSquash?;
    # The current lease state (read-only)
    LeaseState leaseState?;
    # The current lease status (read-only)
    LeaseStatus leaseStatus?;
    # The current lease duration (read-only)
    LeaseDuration leaseDuration?;
    # Provisioned IOPS (premium shares only)
    int provisionedIops?;
    # Provisioned bandwidth in MiB/s (premium shares only)
    int provisionedBandwidthMibps?;
|};

# Properties of a directory (maps to the SDK `ShareDirectoryProperties`).
public type DirectoryProperties record {|
    # The entity tag for optimistic concurrency
    string eTag;
    # The last-modified time (UTC)
    time:Utc lastModified;
    # User-defined metadata
    map<string> metadata?;
    # Whether the directory metadata is encrypted at rest
    boolean isServerEncrypted?;
    # SMB-specific properties
    SmbProperties smbProperties?;
    # POSIX/NFS-specific properties (NFS shares only)
    PosixProperties posixProperties?;
|};

# Properties of a file (curated from the SDK `ShareFileProperties`).
public type Properties record {|
    # The entity tag for optimistic concurrency
    string eTag;
    # The last-modified time (UTC)
    time:Utc lastModified;
    # The size of the file in bytes
    int contentLength;
    # The MIME content type
    string contentType?;
    # The content encoding
    string contentEncoding?;
    # The content disposition
    string contentDisposition?;
    # The cache-control header value
    string cacheControl?;
    # The base64-encoded MD5 hash of the content
    string contentMd5?;
    # User-defined metadata
    map<string> metadata?;
    # Whether the file data is encrypted at rest
    boolean isServerEncrypted?;
    # The current lease state (read-only)
    LeaseState leaseState?;
    # The current lease status (read-only)
    LeaseStatus leaseStatus?;
    # The current lease duration (read-only)
    LeaseDuration leaseDuration?;
    # The status of the most recent copy operation, if any. Re-fetch the properties to observe
    # a pending copy's progress.
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
# (`getProperties`, `delete`, `download`, ...).
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
    string id?;
    # The entity tag; drives the polling `Listener`'s change detection
    string eTag?;
    # The last-modified time (UTC)
    time:Utc lastModified?;
|};

# SMB-specific properties of a file or directory (maps to the SDK `FileSmbProperties`).
public type SmbProperties record {|
    # The NTFS attributes, e.g. `"ReadOnly|Hidden"`
    string ntfsFileAttributes?;
    # The key of a permission stored in the share's permission store
    string filePermissionKey?;
    # The creation time (UTC)
    time:Utc fileCreationTime?;
    # The last-write time (UTC)
    time:Utc fileLastWriteTime?;
    # The change time (UTC)
    time:Utc fileChangeTime?;
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
    # The file mode, octal or symbolic
    string fileMode?;
    # The NFS file type
    NfsFileType fileType?;
    # The number of hard links to the file
    int linkCount?;
|};

# The result of starting a copy operation (maps to the SDK `ShareFileCopyInfo`). Copies are
# asynchronous, and this record is a point-in-time snapshot taken when the copy started — it is
# never updated afterwards. To observe progress, poll `Client.getProperties` on the destination
# path and read `copyStatus`/`copyProgress`; cancel via `Client.abortCopy`.
public type CopyInfo record {|
    # The copy operation identifier; pass to `Client.abortCopy` to cancel a pending copy
    string copyId;
    # The copy status at the moment the copy started — the `CopyStatus` enum value `PENDING`
    # while the server-side copy is still in progress
    CopyStatus copyStatus;
    # The entity tag of the destination after the copy started
    string eTag?;
    # The last-modified time of the destination (UTC)
    time:Utc lastModified?;
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

# A file as surfaced to the polling `Listener`'s event handlers.
# Carries only listing-derived fields (what a directory listing can provide).
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

# The lease state of a share or file.
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

# The lock status conferred by a lease.
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
