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

# The standard content headers that can be set on a file.
public type ContentHeaders record {|
    # The MIME type of the content (e.g. `application/pdf`), served as `Content-Type` on downloads
    string contentType?;
    # Any encoding applied to the stored content (e.g. `gzip`)
    string contentEncoding?;
    # The natural language of the content (e.g. `en-US`)
    string contentLanguage?;
    # How receivers should present the content (e.g. `attachment` or `inline`)
    string contentDisposition?;
    # Caching directives served with the file (e.g. `max-age=3600, private`)
    string cacheControl?;
    # Base64-encoded MD5 of the content, for integrity verification
    string contentMd5?;
|};

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
|};

# Options for `AdminClient.createShare`.
public type ShareCreateOptions record {|
    # User-defined metadata to set on the new share
    map<string> metadata?;
    # The provisioned capacity of the share, in GiB; when absent, the account kind's default
    # quota applies
    int quotaInGb?;
    # The access tier for the share; when absent, the account kind's default tier applies
    # (`TRANSACTION_OPTIMIZED` on pay-as-you-go accounts, `PREMIUM` on premium accounts)
    ShareAccessTier accessTier?;
    # The protocols to enable on the share (SMB and/or NFS)
    ShareProtocol[] enabledProtocols = [SMB];
    # The NFS root-squash setting (NFS shares only); when absent, NFS shares default to
    # `NO_ROOT_SQUASH`
    NfsRootSquash rootSquash?;
|};

# Options for `AdminClient.deleteShare`.
public type ShareDeleteOptions record {|
    # How the share's snapshots are handled; when absent, only the share itself is deleted
    # (the delete fails if snapshots exist)
    ShareSnapshotsDeleteOption deleteSnapshots?;
    # Delete a specific snapshot rather than the share itself
    string snapshotId?;
    # The active lease id, required when the share is leased
    string leaseId?;
|};

# Options for `Client.createDirectory`.
public type DirectoryCreateOptions record {|
    # User-defined metadata to set on the new directory
    map<string> metadata?;
|};

# Options for `Client.list`.
public type ListOptions record {|
    # Return only entries whose name begins with this prefix
    string prefix?;
    # List entries in subdirectories as well
    boolean recursive = false;
    # The number of entries fetched per service round-trip, up to the service maximum of
    # 5,000. Does not cap the total number of results
    int pageSize = 5000;
    # Include the ETag and timestamps on each entry
    boolean includeExtendedInfo = false;
    # List from the share snapshot with this id instead of the live share
    string snapshotId?;
|};

# Options for `Client.renameFile` and `Client.renameDirectory`.
public type RenameOptions record {|
    # If a file already occupies the destination path, delete it and give its path to the
    # renamed entry. A directory occupying the destination always fails the operation
    # regardless of this flag
    boolean replaceIfExists = false;
    # User-defined metadata to set on the renamed entry (replaces all existing metadata);
    # when absent, the existing metadata is preserved
    map<string> metadata?;
|};

# Options for `Client.createFile` (creating an empty file of a given size).
public type CreateOptions record {|
    # Content headers to set on the file, such as `Content-Type` and `Cache-Control`
    ContentHeaders contentHeaders?;
    # User-defined metadata to set on the file
    map<string> metadata?;
|};

# Options for the upload operations (`uploadFile`, `uploadContent`, `uploadFromStream`).
public type UploadOptions record {|
    # Content headers to set on the file, such as `Content-Type` and `Cache-Control`
    ContentHeaders contentHeaders?;
    # User-defined metadata to set on the file
    map<string> metadata?;
|};

# The content forms accepted by `uploadContent`: raw bytes, text, a JSON or XML value,
# and records or record arrays serialized per the resolved `FileFormat`.
public type UploadContent byte[]|string|json|xml|record {}|record {}[];

# The target forms `getFile` retrieves: raw bytes, text, a JSON or XML value, records
# or record arrays bound per the resolved `FileFormat`, a lazy byte stream, or a lazy
# stream of CSV-bound records.
public type RetrievableType byte[]|string|json|xml|record {}|record {}[]|
    stream<byte[], error?>|stream<record {}, error?>;

# Options for `getFile`, extending the download options with the record binding format.
public type GetFileOptions record {|
    *DownloadOptions;
    # The binding format for `record {}` and `record {}[]` targets; when absent, the
    # format is inferred from the path's extension (`.json`, `.xml`, `.csv`)
    FileFormat fileFormat?;
|};

# The serialization and binding format of record and json content.
public enum FileFormat {
    JSON,
    XML,
    CSV
}

# Options for `uploadContent`, extending the upload options with the content
# serialization format.
public type UploadContentOptions record {|
    *UploadOptions;
    # The serialization format for `json`, `record {}`, and `record {}[]` content; when
    # absent, the format is inferred from the destination path's extension (`.json`,
    # `.xml`, `.csv`)
    FileFormat fileFormat?;
|};

# Options for the download operations (`downloadFile`, `getFileContent`).
public type DownloadOptions record {|
    # Download only this byte range instead of the whole file
    Range range?;
    # Read from the share snapshot with this id instead of the live share
    string snapshotId?;
|};

# Options for `Client.copyFile` and `Client.copyFileFromUrl`.
public type CopyOptions record {|
    # User-defined metadata to set on the destination; when absent, the metadata is copied
    # from the source file
    map<string> metadata?;
|};

# Options for `Client.listRanges` and `Client.listRangesDiff`.
public type RangeListOptions record {|
    # Restrict the listing to this byte range
    Range range?;
|};
