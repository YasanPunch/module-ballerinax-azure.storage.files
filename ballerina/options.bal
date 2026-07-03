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
// Content headers
// ---------------------------------------------------------------------------

# The standard content headers that can be set on a file.
public type ContentHeaders record {|
    # The MIME content type
    string contentType?;
    # The content encoding
    string contentEncoding?;
    # The content language
    string contentLanguage?;
    # The content disposition
    string contentDisposition?;
    # The cache-control header value
    string cacheControl?;
    # The base64-encoded MD5 hash of the content
    string contentMd5?;
|};

// ---------------------------------------------------------------------------
// Share option records
// ---------------------------------------------------------------------------

# Options for `AdminClient.listShares`.
public type ShareListOptions record {|
    # Return only shares whose name begins with this prefix
    string prefix?;
    # Include each share's metadata in the results
    boolean includeMetadata = false;
    # Include share snapshots in the results
    boolean includeSnapshots = false;
    # Include soft-deleted shares in the results
    boolean includeDeleted = false;
    # The number of shares fetched per service round-trip (page). Tunes latency/memory of the
    # lazy stream; it does NOT cap the total number of results. Service default and maximum: 5,000.
    int pageSize?;
|};

# Options for `AdminClient.createShare`.
public type ShareCreateOptions record {|
    # User-defined metadata to set on the new share
    map<string> metadata?;
    # The provisioned capacity of the share, in GiB
    int quotaInGb?;
    # The access tier for the share
    ShareAccessTier accessTier?;
    # The protocols to enable on the share (SMB and/or NFS)
    ShareProtocol[] enabledProtocols?;
    # The NFS root-squash setting (NFS shares only)
    NfsRootSquash rootSquash?;
|};

# Options for `AdminClient.deleteShare`.
public type ShareDeleteOptions record {|
    # Also delete the share's snapshots
    boolean deleteSnapshots = false;
    # Delete a specific snapshot rather than the share itself
    string snapshotId?;
    # The active lease id, required when the share is leased
    string leaseId?;
|};

// ---------------------------------------------------------------------------
// Directory option records
// ---------------------------------------------------------------------------

# Options for `Client.createDirectory`.
public type DirectoryCreateOptions record {|
    # User-defined metadata to set on the new directory
    map<string> metadata?;
    # An SDDL permission string to apply
    string filePermission?;
    # SMB properties to apply
    SmbProperties smbProperties?;
|};

# Options for `Client.list`.
public type ListOptions record {|
    # Return only entries whose name begins with this prefix
    string prefix?;
    # List entries in subdirectories as well
    boolean recursive = false;
    # The number of entries fetched per service round-trip (page). Tunes latency/memory of the
    # lazy stream; it does NOT cap the total number of results. Service default and maximum: 5,000.
    int pageSize?;
    # Include ETag and timestamps on each entry (needed for change detection)
    boolean includeExtendedInfo = true;
|};

// ---------------------------------------------------------------------------
// File option records
// ---------------------------------------------------------------------------

# Options for `Client.rename` and `Client.renameDirectory`.
public type RenameOptions record {|
    # Overwrite an existing **file** at the destination. The service never allows overwriting
    # an existing directory: for both `rename` and `renameDirectory`, a directory at the
    # destination path fails the operation regardless of this flag.
    boolean replaceIfExists = false;
    # Rename even if the destination has the read-only attribute set (requires `replaceIfExists`)
    boolean ignoreReadOnly = false;
    # An SDDL permission string to apply to the renamed entry
    string filePermission?;
    # User-defined metadata to set on the renamed entry
    map<string> metadata?;
|};

# Options for `Client.create` (creating an empty file of a given size).
public type CreateOptions record {|
    # Content headers to set on the file
    ContentHeaders contentHeaders?;
    # User-defined metadata to set on the file
    map<string> metadata?;
    # An SDDL permission string to apply
    string filePermission?;
    # SMB properties to apply
    SmbProperties smbProperties?;
|};

# Options for the upload operations (`upload`, `uploadContent`, `uploadFromStream`).
# Upload creates the destination file, so the create-time attributes are available here too.
public type UploadOptions record {|
    # Content headers to set on the file
    ContentHeaders contentHeaders?;
    # User-defined metadata to set on the file
    map<string> metadata?;
    # An SDDL permission string to apply
    string filePermission?;
    # SMB properties to apply
    SmbProperties smbProperties?;
|};

# Options for the download operations (`download`, `getBytes`, `getStream`).
public type DownloadOptions record {|
    # Download only this byte range instead of the whole file
    Range range?;
|};

# Options for `Client.copy` and `Client.copyFromUrl`.
public type CopyOptions record {|
    # User-defined metadata to set on the destination
    map<string> metadata?;
    # An SDDL permission string to apply to the destination
    string filePermission?;
    # SMB properties to apply to the destination
    SmbProperties smbProperties?;
    # How to handle the source permission when copying
    PermissionCopyMode permissionCopyMode?;
    # Copy even if the destination has the read-only attribute set
    boolean ignoreReadOnly?;
|};

# Options for `Client.listRanges`.
public type RangeListOptions record {|
    # Restrict the listing to this byte range
    Range range?;
|};
