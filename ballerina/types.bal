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

// ---------------------------------------------------------------------------
// Data-model records (results returned by operations)
// ---------------------------------------------------------------------------

# One share as returned by `AdminClient.listShares` (maps to the SDK `ShareItem`).
#
# + name - The share name
# + properties - The share's properties
# + metadata - User-defined metadata, when requested via `ShareListOptions.includeMetadata`
# + snapshot - The snapshot identifier, present only for snapshot listings
# + deleted - `true` when this entry is a soft-deleted share (requires `includeDeleted`)
# + version - The share version; pass to `AdminClient.undeleteShare` to restore a deleted share
public type ShareInfo record {|
    string name;
    ShareProperties properties;
    map<string> metadata?;
    string snapshot?;
    boolean deleted?;
    string version?;
|};

# Properties of a file share (maps to the SDK `ShareProperties`).
#
# + quotaInGb - The provisioned capacity of the share, in GiB
# + accessTier - The share's access tier
# + eTag - The entity tag for optimistic concurrency
# + lastModified - Last-modified time, ISO-8601
# + metadata - User-defined metadata
# + enabledProtocols - The enabled protocols (SMB and/or NFS)
# + rootSquash - The NFS root-squash setting (NFS shares only)
# + leaseState - The current lease state (read-only)
# + leaseStatus - The current lease status (read-only)
# + leaseDuration - The current lease duration (read-only)
# + provisionedIops - Provisioned IOPS (premium shares only)
# + provisionedBandwidthMbps - Provisioned bandwidth in MiB/s (premium shares only)
public type ShareProperties record {|
    int quotaInGb;
    ShareAccessTier accessTier?;
    string eTag?;
    string lastModified?;
    map<string> metadata?;
    ShareProtocol[] enabledProtocols?;
    NfsRootSquash rootSquash?;
    LeaseState leaseState?;
    LeaseStatus leaseStatus?;
    LeaseDuration leaseDuration?;
    int provisionedIops?;
    int provisionedBandwidthMbps?;
|};

# Usage statistics for a file share (maps to the SDK `ShareStatistics`).
#
# + shareUsageInBytes - The approximate size of the data stored on the share, in bytes
public type ShareStatistics record {|
    int shareUsageInBytes;
|};

# Properties of a directory (maps to the SDK `ShareDirectoryProperties`).
#
# + eTag - The entity tag for optimistic concurrency
# + lastModified - Last-modified time, ISO-8601
# + metadata - User-defined metadata
# + isServerEncrypted - Whether the directory metadata is encrypted at rest
# + smbProperties - SMB-specific properties
# + posixProperties - POSIX/NFS-specific properties (NFS shares only)
public type DirectoryProperties record {|
    string eTag;
    string lastModified;
    map<string> metadata?;
    boolean isServerEncrypted?;
    SmbProperties smbProperties?;
    PosixProperties posixProperties?;
|};

# Properties of a file (curated from the SDK `ShareFileProperties`).
#
# + eTag - The entity tag for optimistic concurrency
# + lastModified - Last-modified time, ISO-8601
# + contentLength - The size of the file in bytes
# + contentType - The MIME content type
# + contentEncoding - The content encoding
# + contentDisposition - The content disposition
# + cacheControl - The cache-control header value
# + contentMd5 - The base64-encoded MD5 hash of the content
# + metadata - User-defined metadata
# + isServerEncrypted - Whether the file data is encrypted at rest
# + leaseState - The current lease state (read-only)
# + leaseStatus - The current lease status (read-only)
# + leaseDuration - The current lease duration (read-only)
# + copyStatus - The status of the most recent copy operation, if any
# + copyId - The identifier of the most recent copy operation, if any
# + smbProperties - SMB-specific properties
# + posixProperties - POSIX/NFS-specific properties (NFS shares only)
public type Properties record {|
    string eTag;
    string lastModified;
    int contentLength;
    string contentType?;
    string contentEncoding?;
    string contentDisposition?;
    string cacheControl?;
    string contentMd5?;
    map<string> metadata?;
    boolean isServerEncrypted?;
    LeaseState leaseState?;
    LeaseStatus leaseStatus?;
    LeaseDuration leaseDuration?;
    CopyStatus copyStatus?;
    string copyId?;
    SmbProperties smbProperties?;
    PosixProperties posixProperties?;
|};

# One entry returned by `Client.listDirectoriesAndFiles` (maps to the SDK `ShareFileItem`).
#
# + name - The entry name (file or directory)
# + isDirectory - `true` if the entry is a directory, `false` if it is a file
# + sizeBytes - The file size in bytes; not present for directories
# + id - The entry identifier
# + eTag - The entity tag; drives the polling `Listener`'s change detection
# + lastModified - Last-modified time, ISO-8601
public type FileSystemEntry record {|
    string name;
    boolean isDirectory;
    int sizeBytes?;
    string id?;
    string eTag?;
    string lastModified?;
|};

# SMB-specific properties of a file or directory (maps to the SDK `FileSmbProperties`).
#
# + ntfsFileAttributes - The NTFS attributes, e.g. `"ReadOnly|Hidden"`
# + filePermissionKey - The key of a permission stored in the share's permission store
# + fileCreationTime - Creation time, ISO-8601
# + fileLastWriteTime - Last-write time, ISO-8601
# + fileChangeTime - Change time, ISO-8601
# + fileId - The file identifier
# + parentId - The parent directory identifier
public type SmbProperties record {|
    string ntfsFileAttributes?;
    string filePermissionKey?;
    string fileCreationTime?;
    string fileLastWriteTime?;
    string fileChangeTime?;
    string fileId?;
    string parentId?;
|};

# POSIX/NFS-specific properties of a file or directory (maps to the SDK `FilePosixProperties`).
# Present only on NFS shares.
#
# + owner - The owner user id (UID)
# + group - The owning group id (GID)
# + fileMode - The file mode, octal or symbolic
# + fileType - The NFS file type
# + linkCount - The number of hard links to the file
public type PosixProperties record {|
    string owner?;
    string group?;
    string fileMode?;
    NfsFileType fileType?;
    int linkCount?;
|};

# The result of a copy operation (maps to the SDK `ShareFileCopyInfo`). Copies are asynchronous;
# `copyStatus` is `PENDING` until the server-side copy completes.
#
# + copyId - The copy operation identifier; pass to `Client.abortCopy` to cancel a pending copy
# + copyStatus - The current status of the copy
# + eTag - The entity tag of the destination after the copy started
# + lastModified - Last-modified time of the destination, ISO-8601
public type CopyInfo record {|
    string copyId;
    CopyStatus copyStatus;
    string eTag?;
    string lastModified?;
|};

# A single byte range within a file (maps to the SDK `ShareFileRange`). Both bounds are inclusive.
#
# + startByte - The zero-based inclusive start offset
# + endByte - The zero-based inclusive end offset
public type Range record {|
    int startByte;
    int endByte;
|};

# The difference in file ranges between two snapshots (maps to the SDK `ShareFileRangeList`).
#
# + ranges - Ranges that were written (contain data) since the previous snapshot
# + clearRanges - Ranges that were cleared since the previous snapshot
public type RangeDiff record {|
    Range[] ranges;
    Range[] clearRanges;
|};

# A file as surfaced to the polling `Listener`'s event handlers and the `Caller`'s snapshot.
# Carries only listing-derived fields (what a directory listing can provide).
#
# + path - The share-relative path, e.g. `/dir1/dir2/file.ext`
# + name - The file name only (no directory component)
# + sizeBytes - The file size in bytes
# + eTag - The entity tag; a change in this value is what marks a file as modified
# + lastModified - Last-modified time, ISO-8601
public type FileInfo record {|
    string path;
    string name;
    int sizeBytes;
    string eTag;
    string lastModified;
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
    TRANSACTION_OPTIMIZED = "TransactionOptimized"
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

# The transport protocol(s) permitted by a SAS token.
public enum SasProtocol {
    # HTTPS only
    HTTPS = "https",
    # HTTPS and HTTP
    HTTPS_HTTP = "https,http"
}
