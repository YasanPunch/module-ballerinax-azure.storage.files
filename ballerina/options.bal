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

# Standard HTTP content headers that can be set on a file.
#
# + contentType - The MIME content type
# + contentEncoding - The content encoding
# + contentLanguage - The content language
# + contentDisposition - The content disposition
# + cacheControl - The cache-control header value
# + contentMd5 - The base64-encoded MD5 hash of the content
public type HttpHeaders record {|
    string contentType?;
    string contentEncoding?;
    string contentLanguage?;
    string contentDisposition?;
    string cacheControl?;
    string contentMd5?;
|};

// ---------------------------------------------------------------------------
// Share option records
// ---------------------------------------------------------------------------

# Options for `AdminClient.listShares`.
#
# + prefix - Return only shares whose name begins with this prefix
# + includeMetadata - Include each share's metadata in the results
# + includeSnapshots - Include share snapshots in the results
# + includeDeleted - Include soft-deleted shares in the results
# + maxResults - The maximum number of shares to return per page
public type ShareListOptions record {|
    string prefix?;
    boolean includeMetadata = false;
    boolean includeSnapshots = false;
    boolean includeDeleted = false;
    int maxResults?;
|};

# Options for `AdminClient.createShare`.
#
# + metadata - User-defined metadata to set on the new share
# + quotaInGb - The provisioned capacity of the share, in GiB
# + accessTier - The access tier for the share
# + enabledProtocols - The protocols to enable on the share (SMB and/or NFS)
# + rootSquash - The NFS root-squash setting (NFS shares only)
public type ShareCreateOptions record {|
    map<string> metadata?;
    int quotaInGb?;
    ShareAccessTier accessTier?;
    ShareProtocol[] enabledProtocols?;
    NfsRootSquash rootSquash?;
|};

# Options for `AdminClient.deleteShare`.
#
# + deleteSnapshots - Also delete the share's snapshots
# + snapshot - Delete a specific snapshot rather than the share itself
# + leaseId - The active lease id, required when the share is leased
public type ShareDeleteOptions record {|
    boolean deleteSnapshots = false;
    string snapshot?;
    string leaseId?;
|};

# Options for `Client.setShareProperties`.
#
# + quotaInGb - The new provisioned capacity of the share, in GiB
# + accessTier - The new access tier for the share
# + leaseId - The active lease id, required when the share is leased
public type ShareSetPropertiesOptions record {|
    int quotaInGb?;
    ShareAccessTier accessTier?;
    string leaseId?;
|};

// ---------------------------------------------------------------------------
// Directory option records
// ---------------------------------------------------------------------------

# Options for `Client.createDirectory`.
#
# + metadata - User-defined metadata to set on the new directory
# + filePermission - An SDDL permission string to apply
# + smbProperties - SMB properties to apply
public type DirectoryCreateOptions record {|
    map<string> metadata?;
    string filePermission?;
    SmbProperties smbProperties?;
|};

# Options for `Client.listDirectoriesAndFiles`.
#
# + prefix - Return only entries whose name begins with this prefix
# + recursive - List entries in subdirectories as well
# + maxResults - The maximum number of entries to return per page
# + includeExtendedInfo - Include ETag and timestamps on each entry (needed for change detection)
public type ListOptions record {|
    string prefix?;
    boolean recursive = false;
    int maxResults?;
    boolean includeExtendedInfo = true;
|};

// ---------------------------------------------------------------------------
// File option records
// ---------------------------------------------------------------------------

# Options for `Client.rename` and `Client.renameDirectory`.
#
# + replaceIfExists - Overwrite the destination if it already exists
# + ignoreReadOnly - Rename even if the destination has the read-only attribute set
# + filePermission - An SDDL permission string to apply to the renamed entry
# + metadata - User-defined metadata to set on the renamed entry
public type RenameOptions record {|
    boolean replaceIfExists = false;
    boolean ignoreReadOnly = false;
    string filePermission?;
    map<string> metadata?;
|};

# Options for `Client.create` (creating an empty file of a given size).
#
# + httpHeaders - Content headers to set on the file
# + metadata - User-defined metadata to set on the file
# + filePermission - An SDDL permission string to apply
# + smbProperties - SMB properties to apply
public type CreateOptions record {|
    HttpHeaders httpHeaders?;
    map<string> metadata?;
    string filePermission?;
    SmbProperties smbProperties?;
|};

# Options for the upload operations (`upload`, `uploadFromBytes`, `uploadFromStream`,
# `uploadContent`).
#
# + httpHeaders - Content headers to set on the file
# + metadata - User-defined metadata to set on the file
public type UploadOptions record {|
    HttpHeaders httpHeaders?;
    map<string> metadata?;
|};

# Options for the download operations (`download`, `getBytes`).
#
# + range - Download only this byte range instead of the whole file
# + rangeGetContentMd5 - Request the MD5 of the downloaded range
public type DownloadOptions record {|
    Range range?;
    boolean rangeGetContentMd5 = false;
|};

# Options for `Client.copy` and `Client.copyFromUrl`.
#
# + metadata - User-defined metadata to set on the destination
# + filePermission - An SDDL permission string to apply to the destination
# + smbProperties - SMB properties to apply to the destination
# + permissionCopyMode - How to handle the source permission when copying
# + ignoreReadOnly - Copy even if the destination has the read-only attribute set
public type CopyOptions record {|
    map<string> metadata?;
    string filePermission?;
    SmbProperties smbProperties?;
    PermissionCopyMode permissionCopyMode?;
    boolean ignoreReadOnly?;
|};

# Options for `Client.listRanges` and `Client.listRangesDiff`.
#
# + range - Restrict the listing to this byte range
# + previousSnapshot - The baseline snapshot id for a range diff
public type RangeListOptions record {|
    Range range?;
    string previousSnapshot?;
|};

// ---------------------------------------------------------------------------
// SAS records
// ---------------------------------------------------------------------------

# The values used to generate a share-scoped Shared Access Signature via
# `Client.generateShareSas`.
#
# + expiryTime - The expiry time, ISO-8601; omit when `identifier` refers to a stored policy
# + permissions - The permissions granted by the SAS
# + startTime - The start time, ISO-8601
# + protocol - The transport protocol(s) permitted by the SAS
# + ipRange - An allowed IP address or range, e.g. `"168.1.5.60-168.1.5.70"`
# + identifier - The name of a stored access policy to base the SAS on
public type ShareSasSignatureValues record {|
    string expiryTime;
    ShareSasPermissions permissions;
    string startTime?;
    SasProtocol protocol?;
    string ipRange?;
    string identifier?;
|};

# The permissions that can be granted by a share-scoped SAS.
#
# + read - Read file content and properties
# + create - Create new files or directories
# + write - Write file content and properties
# + delete - Delete files or directories
# + list - List directories and files
public type ShareSasPermissions record {|
    boolean read = false;
    boolean create = false;
    boolean write = false;
    boolean delete = false;
    boolean list = false;
|};
