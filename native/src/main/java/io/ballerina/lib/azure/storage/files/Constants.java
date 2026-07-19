/*
 * Copyright (c) 2026, WSO2 LLC. (https://www.wso2.com).
 *
 * WSO2 LLC. licenses this file to you under the Apache License,
 * Version 2.0 (the "License"); you may not use this file except
 * in compliance with the License.
 * You may obtain a copy of the License at
 *
 *    http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing,
 * software distributed under the License is distributed on an
 * "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
 * KIND, either express or implied. See the License for the
 * specific language governing permissions and limitations
 * under the License.
 */

package io.ballerina.lib.azure.storage.files;

import io.ballerina.runtime.api.utils.StringUtils;
import io.ballerina.runtime.api.values.BString;

/**
 * Constants shared across the native adaptor classes: native-data keys and the field names of
 * the Ballerina records the adaptor reads and writes.
 */
public final class Constants {

    private Constants() {
    }

    /** Key under which the SDK {@code ShareServiceClient} is stored on the client object. */
    public static final String NATIVE_SERVICE_CLIENT = "azure.storage.files.native.serviceClient";
    /** Key under which the SDK {@code ShareClient} is stored on the share-bound client object. */
    public static final String NATIVE_SHARE_CLIENT = "azure.storage.files.native.shareClient";
    /** Key under which the closed flag is stored on a client object. */
    public static final String NATIVE_CLOSED = "azure.storage.files.native.closed";
    /** Key under which a native iterator state is stored on a stream generator object. */
    public static final String NATIVE_ITERATOR = "azure.storage.files.native.iterator";
    /** Key under which an open content input stream is stored on a stream generator object. */
    public static final String NATIVE_INPUT_STREAM = "azure.storage.files.native.inputStream";

    // Auth record fields
    public static final BString ACCOUNT_NAME = StringUtils.fromString("accountName");
    public static final BString ACCOUNT_KEY = StringUtils.fromString("accountKey");
    public static final BString SAS_TOKEN = StringUtils.fromString("sasToken");
    public static final BString SAS_URL = StringUtils.fromString("sasUrl");
    public static final BString CONNECTION_STRING = StringUtils.fromString("connectionString");
    public static final BString SERVICE_URL = StringUtils.fromString("serviceUrl");
    public static final BString AUTH = StringUtils.fromString("auth");
    public static final BString RETRY_CONFIG = StringUtils.fromString("retryConfig");
    public static final BString TRANSPORT_CONFIG = StringUtils.fromString("transportConfig");

    // Option record fields
    public static final BString PREFIX = StringUtils.fromString("prefix");
    public static final BString INCLUDE_METADATA = StringUtils.fromString("includeMetadata");
    public static final BString INCLUDE_SNAPSHOTS = StringUtils.fromString("includeSnapshots");
    public static final BString INCLUDE_DELETED = StringUtils.fromString("includeDeleted");
    public static final BString METADATA = StringUtils.fromString("metadata");
    public static final BString QUOTA_IN_GB = StringUtils.fromString("quotaInGb");
    public static final BString ACCESS_TIER = StringUtils.fromString("accessTier");
    public static final BString ENABLED_PROTOCOLS = StringUtils.fromString("enabledProtocols");
    public static final BString ROOT_SQUASH = StringUtils.fromString("rootSquash");
    public static final BString DELETE_SNAPSHOTS = StringUtils.fromString("deleteSnapshots");
    public static final BString SNAPSHOT_ID = StringUtils.fromString("snapshotId");
    public static final BString LEASE_ID = StringUtils.fromString("leaseId");
    public static final BString FILE_PERMISSION = StringUtils.fromString("filePermission");
    public static final BString SMB_PROPERTIES = StringUtils.fromString("smbProperties");
    public static final BString POSIX_PROPERTIES = StringUtils.fromString("posixProperties");
    public static final BString RECURSIVE = StringUtils.fromString("recursive");
    public static final BString PAGE_SIZE = StringUtils.fromString("pageSize");
    public static final BString INCLUDE_EXTENDED_INFO = StringUtils.fromString("includeExtendedInfo");
    public static final BString REPLACE_IF_EXISTS = StringUtils.fromString("replaceIfExists");
    public static final BString IGNORE_READ_ONLY = StringUtils.fromString("ignoreReadOnly");
    public static final BString CONTENT_HEADERS = StringUtils.fromString("contentHeaders");
    public static final BString RANGE = StringUtils.fromString("range");
    public static final BString PERMISSION_COPY_MODE = StringUtils.fromString("permissionCopyMode");

    // ContentHeaders fields
    public static final BString CONTENT_TYPE = StringUtils.fromString("contentType");
    public static final BString CONTENT_ENCODING = StringUtils.fromString("contentEncoding");
    public static final BString CONTENT_LANGUAGE = StringUtils.fromString("contentLanguage");
    public static final BString CONTENT_DISPOSITION = StringUtils.fromString("contentDisposition");
    public static final BString CACHE_CONTROL = StringUtils.fromString("cacheControl");
    public static final BString CONTENT_MD5 = StringUtils.fromString("contentMd5");

    // SmbProperties fields
    public static final BString NTFS_FILE_ATTRIBUTES = StringUtils.fromString("ntfsFileAttributes");
    public static final BString FILE_PERMISSION_KEY = StringUtils.fromString("filePermissionKey");
    public static final BString FILE_CREATION_TIME = StringUtils.fromString("fileCreationTime");
    public static final BString FILE_LAST_WRITE_TIME = StringUtils.fromString("fileLastWriteTime");
    public static final BString FILE_CHANGE_TIME = StringUtils.fromString("fileChangeTime");
    public static final BString FILE_ID = StringUtils.fromString("fileId");
    public static final BString PARENT_ID = StringUtils.fromString("parentId");

    // PosixProperties fields
    public static final BString OWNER = StringUtils.fromString("owner");
    public static final BString GROUP = StringUtils.fromString("group");
    public static final BString FILE_MODE = StringUtils.fromString("fileMode");
    public static final BString FILE_TYPE = StringUtils.fromString("fileType");
    public static final BString LINK_COUNT = StringUtils.fromString("linkCount");

    // Result record fields
    public static final BString NAME = StringUtils.fromString("name");
    public static final BString PROPERTIES = StringUtils.fromString("properties");
    public static final BString IS_DELETED = StringUtils.fromString("isDeleted");
    public static final BString VERSION = StringUtils.fromString("version");
    public static final BString E_TAG = StringUtils.fromString("eTag");
    public static final BString LAST_MODIFIED = StringUtils.fromString("lastModified");
    public static final BString LEASE_STATE = StringUtils.fromString("leaseState");
    public static final BString LEASE_STATUS = StringUtils.fromString("leaseStatus");
    public static final BString LEASE_DURATION = StringUtils.fromString("leaseDuration");
    public static final BString PROVISIONED_IOPS = StringUtils.fromString("provisionedIops");
    public static final BString PROVISIONED_BANDWIDTH = StringUtils.fromString("provisionedBandwidthMibps");
    public static final BString IS_SERVER_ENCRYPTED = StringUtils.fromString("isServerEncrypted");
    public static final BString CONTENT_LENGTH = StringUtils.fromString("contentLength");
    public static final BString COPY_STATUS = StringUtils.fromString("copyStatus");
    public static final BString COPY_ID = StringUtils.fromString("copyId");
    public static final BString COPY_PROGRESS = StringUtils.fromString("copyProgress");
    public static final BString COPIED_BYTES = StringUtils.fromString("copiedBytes");
    public static final BString TOTAL_BYTES = StringUtils.fromString("totalBytes");
    public static final BString PATH = StringUtils.fromString("path");
    public static final BString IS_DIRECTORY = StringUtils.fromString("isDirectory");
    public static final BString SIZE_BYTES = StringUtils.fromString("sizeBytes");
    public static final BString ID = StringUtils.fromString("id");
    public static final BString START_BYTE = StringUtils.fromString("startByte");
    public static final BString END_BYTE = StringUtils.fromString("endByte");

    // Record type names
    public static final String RECORD_SHARE_INFO = "ShareInfo";
    public static final String RECORD_SHARE_PROPERTIES = "ShareProperties";
    public static final String RECORD_DIRECTORY_PROPERTIES = "DirectoryProperties";
    public static final String RECORD_FILE_PROPERTIES = "FileProperties";
    public static final String RECORD_COPY_PROGRESS = "CopyProgress";
    public static final String RECORD_COPY_INFO = "CopyInfo";
    public static final String RECORD_COPY_STATUS_INFO = "CopyStatusInfo";
    public static final String RECORD_ENTRY = "Entry";
    public static final String RECORD_RANGE = "Range";
    public static final String RECORD_SMB_PROPERTIES = "SmbProperties";
    public static final String RECORD_POSIX_PROPERTIES = "PosixProperties";
}
