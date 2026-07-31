/*
 * Copyright (c) 2026, WSO2 LLC. (http://www.wso2.com).
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

package io.ballerina.lib.azure.storage.files.util;

import com.azure.storage.file.share.FileSmbProperties;
import com.azure.storage.file.share.models.ClearRange;
import com.azure.storage.file.share.models.CloseHandlesInfo;
import com.azure.storage.file.share.models.FilePosixProperties;
import com.azure.storage.file.share.models.FileRange;
import com.azure.storage.file.share.models.HandleItem;
import com.azure.storage.file.share.models.LeaseDurationType;
import com.azure.storage.file.share.models.LeaseStateType;
import com.azure.storage.file.share.models.LeaseStatusType;
import com.azure.storage.file.share.models.NtfsFileAttributes;
import com.azure.storage.file.share.models.ShareAccessPolicy;
import com.azure.storage.file.share.models.ShareCorsRule;
import com.azure.storage.file.share.models.ShareDirectoryProperties;
import com.azure.storage.file.share.models.ShareFileItem;
import com.azure.storage.file.share.models.ShareFileProperties;
import com.azure.storage.file.share.models.ShareFileRange;
import com.azure.storage.file.share.models.ShareFileRangeList;
import com.azure.storage.file.share.models.ShareItem;
import com.azure.storage.file.share.models.ShareMetrics;
import com.azure.storage.file.share.models.ShareProperties;
import com.azure.storage.file.share.models.ShareProtocols;
import com.azure.storage.file.share.models.ShareRetentionPolicy;
import com.azure.storage.file.share.models.ShareServiceProperties;
import com.azure.storage.file.share.models.ShareSignedIdentifier;
import com.azure.storage.file.share.models.UserDelegationKey;
import io.ballerina.runtime.api.creators.TypeCreator;
import io.ballerina.runtime.api.creators.ValueCreator;
import io.ballerina.runtime.api.types.PredefinedTypes;
import io.ballerina.runtime.api.utils.StringUtils;
import io.ballerina.runtime.api.utils.TypeUtils;
import io.ballerina.runtime.api.values.BArray;
import io.ballerina.runtime.api.values.BMap;
import io.ballerina.runtime.api.values.BString;

import java.time.OffsetDateTime;
import java.util.Base64;
import java.util.EnumSet;

/**
 * Maps the SDK model classes to the Ballerina result records declared in {@code types.bal}.
 * Optional record fields are set only when the service supplied a value.
 */
public final class RecordMapper {

    // The Ballerina record type names and result-record field names the mapper materializes.
    // Other classes reference these; the option-record vocabulary lives on OptionsReader.
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
    public static final String RECORD_SHARE_SNAPSHOT_INFO = "ShareSnapshotInfo";
    public static final String RECORD_RANGE_DIFF = "RangeDiff";
    public static final String RECORD_SIGNED_IDENTIFIER = "SignedIdentifier";
    public static final String RECORD_ACCESS_POLICY = "AccessPolicy";
    public static final String RECORD_HANDLE_INFO = "HandleInfo";
    public static final String RECORD_CLOSE_HANDLES_INFO = "CloseHandlesInfo";
    public static final String RECORD_SERVICE_PROPERTIES = "ServiceProperties";
    public static final String RECORD_METRICS = "Metrics";
    public static final String RECORD_CORS_RULE = "CorsRule";
    public static final String RECORD_PROTOCOL_SETTINGS = "ProtocolSettings";
    public static final String RECORD_USER_DELEGATION_KEY = "UserDelegationKey";
    // The `FileInfo` listener payload record and its own field vocabulary. FileInfo is a
    // distinct record schema, so it keeps its own field constants even where a spelling
    // coincides with another record's field.
    public static final String RECORD_FILE_INFO = "FileInfo";
    public static final BString FILE_INFO_PATH = StringUtils.fromString("path");
    public static final BString FILE_INFO_NAME = StringUtils.fromString("name");
    public static final BString FILE_INFO_SIZE_BYTES = StringUtils.fromString("sizeBytes");
    public static final BString FILE_INFO_E_TAG = StringUtils.fromString("eTag");
    public static final BString FILE_INFO_LAST_MODIFIED = StringUtils.fromString("lastModified");
    // The Ballerina CopyStatus enum value reported while a copy is still pending.
    public static final String COPY_STATUS_PENDING = "pending";
    // The Ballerina Protocol enum values.
    public static final String PROTOCOL_SMB = "SMB";
    public static final String PROTOCOL_NFS = "NFS";
    // The AccessTier value reported when the service omits the tier.
    private static final String ACCESS_TIER_TRANSACTION_OPTIMIZED = "TransactionOptimized";
    // The content type reported when the service omits one.
    private static final String DEFAULT_CONTENT_TYPE = "application/octet-stream";
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
    public static final BString RANGES = StringUtils.fromString("ranges");
    public static final BString CLEAR_RANGES = StringUtils.fromString("clearRanges");
    public static final BString HANDLE_ID = StringUtils.fromString("handleId");
    public static final BString SESSION_ID = StringUtils.fromString("sessionId");
    public static final BString CLIENT_IP = StringUtils.fromString("clientIp");
    public static final BString OPEN_TIME = StringUtils.fromString("openTime");
    public static final BString LAST_RECONNECT_TIME = StringUtils.fromString("lastReconnectTime");
    public static final BString CLOSED_HANDLES = StringUtils.fromString("closedHandles");
    public static final BString FAILED_HANDLES = StringUtils.fromString("failedHandles");
    public static final BString HOUR_METRICS = StringUtils.fromString("hourMetrics");
    public static final BString MINUTE_METRICS = StringUtils.fromString("minuteMetrics");
    public static final BString CORS = StringUtils.fromString("cors");
    public static final BString PROTOCOL = StringUtils.fromString("protocol");
    public static final BString ENABLED = StringUtils.fromString("enabled");
    public static final BString INCLUDE_APIS = StringUtils.fromString("includeApis");
    public static final BString RETENTION_DAYS = StringUtils.fromString("retentionDays");
    public static final BString ALLOWED_ORIGINS = StringUtils.fromString("allowedOrigins");
    public static final BString ALLOWED_METHODS = StringUtils.fromString("allowedMethods");
    public static final BString ALLOWED_HEADERS = StringUtils.fromString("allowedHeaders");
    public static final BString EXPOSED_HEADERS = StringUtils.fromString("exposedHeaders");
    public static final BString MAX_AGE_IN_SECONDS = StringUtils.fromString("maxAgeInSeconds");
    public static final BString SMB_MULTICHANNEL_ENABLED = StringUtils.fromString("smbMultichannelEnabled");
    public static final BString SIGNED_OBJECT_ID = StringUtils.fromString("signedObjectId");
    public static final BString SIGNED_TENANT_ID = StringUtils.fromString("signedTenantId");
    public static final BString SIGNED_START = StringUtils.fromString("signedStart");
    public static final BString SIGNED_EXPIRY = StringUtils.fromString("signedExpiry");
    public static final BString SIGNED_SERVICE = StringUtils.fromString("signedService");
    public static final BString SIGNED_VERSION = StringUtils.fromString("signedVersion");
    public static final BString VALUE = StringUtils.fromString("value");
    public static final BString ACCESS_POLICY = StringUtils.fromString("accessPolicy");
    public static final BString STARTS_ON = StringUtils.fromString("startsOn");
    public static final BString EXPIRES_ON = StringUtils.fromString("expiresOn");
    public static final BString PERMISSIONS = StringUtils.fromString("permissions");

    private RecordMapper() {
    }

    /** Maps one listed share to a {@code ShareInfo} record. */
    public static BMap<BString, Object> shareInfo(ShareItem item) {
        BMap<BString, Object> record = newRecord(RECORD_SHARE_INFO);
        record.put(NAME, StringUtils.fromString(item.getName()));
        record.put(PROPERTIES, shareProperties(item.getProperties()));
        if (item.getMetadata() != null && !item.getMetadata().isEmpty()) {
            record.put(OptionsReader.METADATA, ValueUtils.toBStringMap(item.getMetadata()));
        }
        if (item.getSnapshot() != null) {
            record.put(OptionsReader.SNAPSHOT_ID, StringUtils.fromString(item.getSnapshot()));
        }
        if (item.isDeleted() != null) {
            record.put(IS_DELETED, item.isDeleted());
        }
        if (item.getVersion() != null) {
            record.put(VERSION, StringUtils.fromString(item.getVersion()));
        }
        return record;
    }

    /** Maps SDK share properties to a {@code ShareProperties} record. */
    public static BMap<BString, Object> shareProperties(ShareProperties p) {
        BMap<BString, Object> record = newRecord(RECORD_SHARE_PROPERTIES);
        record.put(OptionsReader.QUOTA_IN_GB, (long) p.getQuota());
        record.put(OptionsReader.ACCESS_TIER, StringUtils.fromString(
                p.getAccessTier() == null ? ACCESS_TIER_TRANSACTION_OPTIMIZED : p.getAccessTier()));
        record.put(E_TAG, StringUtils.fromString(p.getETag()));
        record.put(LAST_MODIFIED, ValueUtils.toUtc(p.getLastModified()));
        if (p.getMetadata() != null && !p.getMetadata().isEmpty()) {
            record.put(OptionsReader.METADATA, ValueUtils.toBStringMap(p.getMetadata()));
        }
        ShareProtocols protocols = p.getProtocols();
        if (protocols != null) {
            BArray array = ValueCreator.createArrayValue(
                    TypeCreator.createArrayType(PredefinedTypes.TYPE_STRING));
            if (protocols.isSmbEnabled()) {
                array.append(StringUtils.fromString(PROTOCOL_SMB));
            }
            if (protocols.isNfsEnabled()) {
                array.append(StringUtils.fromString(PROTOCOL_NFS));
            }
            if (array.size() > 0) {
                record.put(OptionsReader.ENABLED_PROTOCOLS, array);
            }
        }
        if (p.getRootSquash() != null) {
            record.put(OptionsReader.ROOT_SQUASH, StringUtils.fromString(p.getRootSquash().toString()));
        }
        putLeaseFields(record, p.getLeaseState(), p.getLeaseStatus(), p.getLeaseDuration());
        if (p.getProvisionedIops() != null) {
            record.put(PROVISIONED_IOPS, p.getProvisionedIops().longValue());
        }
        if (p.getProvisionedBandwidthMiBps() != null) {
            record.put(PROVISIONED_BANDWIDTH, p.getProvisionedBandwidthMiBps().longValue());
        }
        return record;
    }

    /** Maps SDK directory properties to a {@code DirectoryProperties} record. */
    public static BMap<BString, Object> directoryProperties(ShareDirectoryProperties p) {
        BMap<BString, Object> record = newRecord(RECORD_DIRECTORY_PROPERTIES);
        record.put(E_TAG, StringUtils.fromString(p.getETag()));
        record.put(LAST_MODIFIED, ValueUtils.toUtc(p.getLastModified()));
        if (p.getMetadata() != null && !p.getMetadata().isEmpty()) {
            record.put(OptionsReader.METADATA, ValueUtils.toBStringMap(p.getMetadata()));
        }
        record.put(IS_SERVER_ENCRYPTED, p.isServerEncrypted());
        putSmbProperties(record, p.getSmbProperties());
        putPosixProperties(record, p.getPosixProperties());
        return record;
    }

    /** Maps SDK file properties to a {@code FileProperties} record. */
    public static BMap<BString, Object> fileProperties(ShareFileProperties p) {
        BMap<BString, Object> record = newRecord(RECORD_FILE_PROPERTIES);
        record.put(E_TAG, StringUtils.fromString(p.getETag()));
        record.put(LAST_MODIFIED, ValueUtils.toUtc(p.getLastModified()));
        record.put(CONTENT_LENGTH, p.getContentLength());
        record.put(OptionsReader.CONTENT_TYPE, StringUtils.fromString(
                p.getContentType() == null ? DEFAULT_CONTENT_TYPE : p.getContentType()));
        if (p.getContentEncoding() != null) {
            record.put(OptionsReader.CONTENT_ENCODING, StringUtils.fromString(p.getContentEncoding()));
        }
        if (p.getContentDisposition() != null) {
            record.put(OptionsReader.CONTENT_DISPOSITION, StringUtils.fromString(p.getContentDisposition()));
        }
        if (p.getCacheControl() != null) {
            record.put(OptionsReader.CACHE_CONTROL, StringUtils.fromString(p.getCacheControl()));
        }
        if (p.getContentMd5() != null) {
            record.put(OptionsReader.CONTENT_MD5,
                    StringUtils.fromString(Base64.getEncoder().encodeToString(p.getContentMd5())));
        }
        if (p.getMetadata() != null && !p.getMetadata().isEmpty()) {
            record.put(OptionsReader.METADATA, ValueUtils.toBStringMap(p.getMetadata()));
        }
        record.put(IS_SERVER_ENCRYPTED, Boolean.TRUE.equals(p.isServerEncrypted()));
        putLeaseFields(record, p.getLeaseState(), p.getLeaseStatus(), p.getLeaseDuration());
        if (p.getCopyStatus() != null) {
            record.put(COPY_STATUS, StringUtils.fromString(p.getCopyStatus().toString()));
        }
        if (p.getCopyId() != null) {
            record.put(COPY_ID, StringUtils.fromString(p.getCopyId()));
        }
        BMap<BString, Object> progress = copyProgress(p.getCopyProgress());
        if (progress != null) {
            record.put(COPY_PROGRESS, progress);
        }
        putSmbProperties(record, p.getSmbProperties());
        putPosixProperties(record, p.getPosixProperties());
        return record;
    }

    /**
     * Parses the service's {@code bytesCopied/totalBytes} copy-progress form into a
     * {@code CopyProgress} record; {@code null} when absent or unparseable.
     */
    public static BMap<BString, Object> copyProgress(String raw) {
        if (raw == null) {
            return null;
        }
        int slash = raw.indexOf('/');
        if (slash < 1) {
            return null;
        }
        try {
            long copied = Long.parseLong(raw.substring(0, slash).trim());
            long total = Long.parseLong(raw.substring(slash + 1).trim());
            BMap<BString, Object> record = newRecord(RECORD_COPY_PROGRESS);
            record.put(COPIED_BYTES, copied);
            record.put(TOTAL_BYTES, total);
            return record;
        } catch (NumberFormatException e) {
            return null;
        }
    }

    /** Builds a {@code CopyInfo} record from the copy-start snapshot values. */
    public static BMap<BString, Object> copyInfo(String copyId, String copyStatus, String eTag,
                                          OffsetDateTime lastModified) {
        BMap<BString, Object> record = newRecord(RECORD_COPY_INFO);
        record.put(COPY_ID, StringUtils.fromString(copyId));
        record.put(COPY_STATUS, StringUtils.fromString(copyStatus));
        record.put(E_TAG, StringUtils.fromString(eTag));
        record.put(LAST_MODIFIED, ValueUtils.toUtc(lastModified));
        return record;
    }

    /**
     * Builds a {@code CopyStatusInfo} record from fetched file properties, or {@code null} when the
     * file has never been a copy destination.
     */
    public static BMap<BString, Object> copyStatusInfo(ShareFileProperties p) {
        if (p.getCopyId() == null) {
            return null;
        }
        BMap<BString, Object> record = newRecord(RECORD_COPY_STATUS_INFO);
        record.put(COPY_ID, StringUtils.fromString(p.getCopyId()));
        record.put(COPY_STATUS, StringUtils.fromString(
                p.getCopyStatus() == null ? COPY_STATUS_PENDING : p.getCopyStatus().toString()));
        BMap<BString, Object> progress = copyProgress(p.getCopyProgress());
        if (progress != null) {
            record.put(COPY_PROGRESS, progress);
        }
        return record;
    }

    /**
     * Maps one listed item to an {@code Entry} record.
     *
     * @param item      the SDK item
     * @param parentPath the share-relative path of the directory that was listed, without a
     *                   trailing slash; empty for the share root
     * @return the {@code Entry} record
     */
    public static BMap<BString, Object> entry(ShareFileItem item, String parentPath) {
        BMap<BString, Object> record = newRecord(RECORD_ENTRY);
        String path = parentPath.isEmpty() ? "/" + item.getName() : "/" + parentPath + "/" + item.getName();
        record.put(PATH, StringUtils.fromString(path));
        record.put(NAME, StringUtils.fromString(item.getName()));
        record.put(IS_DIRECTORY, item.isDirectory());
        if (item.getFileSize() != null) {
            record.put(SIZE_BYTES, item.getFileSize());
        }
        record.put(ID, StringUtils.fromString(item.getId() == null ? "" : item.getId()));
        if (item.getProperties() != null) {
            if (item.getProperties().getETag() != null) {
                record.put(E_TAG, StringUtils.fromString(item.getProperties().getETag()));
            }
            if (item.getProperties().getLastModified() != null) {
                record.put(LAST_MODIFIED, ValueUtils.toUtc(item.getProperties().getLastModified()));
            }
        }
        return record;
    }

    /**
     * Maps one listed file to a `FileInfo` record, the payload delivered to a listener handler.
     * The eTag and last-modified time come from the extended-info listing.
     *
     * @param item       the SDK item, which must be a file
     * @param parentPath the share-relative path of the directory that contains the file, without a
     *                   trailing slash; empty for the share root
     * @return the `FileInfo` record
     */
    public static BMap<BString, Object> fileInfo(ShareFileItem item, String parentPath) {
        BMap<BString, Object> record = newRecord(RECORD_FILE_INFO);
        String path = parentPath.isEmpty() ? "/" + item.getName() : "/" + parentPath + "/" + item.getName();
        record.put(FILE_INFO_PATH, StringUtils.fromString(path));
        record.put(FILE_INFO_NAME, StringUtils.fromString(item.getName()));
        Long sizeBytes = item.getFileSize();
        if (sizeBytes == null) {
            record.put(FILE_INFO_SIZE_BYTES, 0L);
        } else {
            record.put(FILE_INFO_SIZE_BYTES, sizeBytes);
        }
        String eTag = item.getProperties() == null || item.getProperties().getETag() == null
                ? "" : item.getProperties().getETag();
        record.put(FILE_INFO_E_TAG, StringUtils.fromString(eTag));
        java.time.OffsetDateTime lastModified = item.getProperties() == null
                ? null : item.getProperties().getLastModified();
        record.put(FILE_INFO_LAST_MODIFIED, ValueUtils.toUtc(lastModified == null
                ? java.time.OffsetDateTime.now(java.time.ZoneOffset.UTC) : lastModified));
        return record;
    }

    /** Maps one SDK range to a {@code Range} record. */
    public static BMap<BString, Object> range(ShareFileRange r) {
        BMap<BString, Object> record = newRecord(RECORD_RANGE);
        record.put(START_BYTE, r.getStart());
        Long end = r.getEnd();
        if (end == null) {
            end = r.getStart();
        }
        record.put(END_BYTE, end);
        return record;
    }

    /** Builds a {@code Range} record from explicit bounds. */
    public static BMap<BString, Object> range(long start, long end) {
        BMap<BString, Object> record = newRecord(RECORD_RANGE);
        record.put(START_BYTE, start);
        record.put(END_BYTE, end);
        return record;
    }

    /** Builds a {@code ShareSnapshotInfo} record. */
    public static BMap<BString, Object> shareSnapshotInfo(String snapshotId, String eTag,
            OffsetDateTime lastModified) {
        BMap<BString, Object> record = newRecord(RECORD_SHARE_SNAPSHOT_INFO);
        record.put(OptionsReader.SNAPSHOT_ID, StringUtils.fromString(snapshotId));
        record.put(E_TAG, StringUtils.fromString(eTag == null ? "" : eTag));
        record.put(LAST_MODIFIED, ValueUtils.toUtc(lastModified));
        return record;
    }

    /** Maps the SDK file-service configuration to a {@code ServiceProperties} record. */
    public static BMap<BString, Object> serviceProperties(ShareServiceProperties sdk) {
        BMap<BString, Object> record = newRecord(RECORD_SERVICE_PROPERTIES);
        if (sdk.getHourMetrics() != null) {
            record.put(HOUR_METRICS, metrics(sdk.getHourMetrics()));
        }
        if (sdk.getMinuteMetrics() != null) {
            record.put(MINUTE_METRICS, metrics(sdk.getMinuteMetrics()));
        }
        if (sdk.getCors() != null) {
            BArray rules = recordArray(RECORD_CORS_RULE);
            for (ShareCorsRule rule : sdk.getCors()) {
                BMap<BString, Object> ruleRecord = newRecord(RECORD_CORS_RULE);
                ruleRecord.put(ALLOWED_ORIGINS, StringUtils.fromString(rule.getAllowedOrigins()));
                ruleRecord.put(ALLOWED_METHODS, StringUtils.fromString(rule.getAllowedMethods()));
                ruleRecord.put(ALLOWED_HEADERS, StringUtils.fromString(rule.getAllowedHeaders()));
                ruleRecord.put(EXPOSED_HEADERS, StringUtils.fromString(rule.getExposedHeaders()));
                ruleRecord.put(MAX_AGE_IN_SECONDS, (long) rule.getMaxAgeInSeconds());
                rules.append(ruleRecord);
            }
            record.put(CORS, rules);
        }
        if (sdk.getProtocol() != null && sdk.getProtocol().getSmb() != null
                && sdk.getProtocol().getSmb().getMultichannel() != null) {
            BMap<BString, Object> protocol = newRecord(RECORD_PROTOCOL_SETTINGS);
            Boolean enabled = sdk.getProtocol().getSmb().getMultichannel().isEnabled();
            if (enabled != null) {
                protocol.put(SMB_MULTICHANNEL_ENABLED, enabled);
            }
            record.put(PROTOCOL, protocol);
        }
        return record;
    }

    private static BMap<BString, Object> metrics(ShareMetrics sdk) {
        BMap<BString, Object> record = newRecord(RECORD_METRICS);
        record.put(ENABLED, sdk.isEnabled());
        if (sdk.getVersion() != null) {
            record.put(VERSION, StringUtils.fromString(sdk.getVersion()));
        }
        if (sdk.isIncludeApis() != null) {
            record.put(INCLUDE_APIS, sdk.isIncludeApis());
        }
        ShareRetentionPolicy retention = sdk.getRetentionPolicy();
        if (retention != null && retention.isEnabled() && retention.getDays() != null) {
            record.put(RETENTION_DAYS, (long) retention.getDays());
        }
        return record;
    }

    /** Maps the SDK user-delegation key to a {@code UserDelegationKey} record. */
    public static BMap<BString, Object> userDelegationKey(UserDelegationKey key) {
        BMap<BString, Object> record = newRecord(RECORD_USER_DELEGATION_KEY);
        record.put(SIGNED_OBJECT_ID, StringUtils.fromString(key.getSignedObjectId()));
        record.put(SIGNED_TENANT_ID, StringUtils.fromString(key.getSignedTenantId()));
        record.put(SIGNED_START, ValueUtils.toUtc(key.getSignedStart()));
        record.put(SIGNED_EXPIRY, ValueUtils.toUtc(key.getSignedExpiry()));
        record.put(SIGNED_SERVICE, StringUtils.fromString(key.getSignedService()));
        record.put(SIGNED_VERSION, StringUtils.fromString(key.getSignedVersion()));
        record.put(VALUE, StringUtils.fromString(key.getValue()));
        return record;
    }

    /** Maps one SDK SMB-handle item to a {@code HandleInfo} record. */
    public static BMap<BString, Object> handleInfo(HandleItem item) {
        BMap<BString, Object> record = newRecord(RECORD_HANDLE_INFO);
        record.put(HANDLE_ID, StringUtils.fromString(item.getHandleId()));
        record.put(PATH, StringUtils.fromString("/" + (item.getPath() == null ? "" : item.getPath())));
        if (item.getFileId() != null) {
            record.put(OptionsReader.FILE_ID, StringUtils.fromString(item.getFileId()));
        }
        if (item.getSessionId() != null) {
            record.put(SESSION_ID, StringUtils.fromString(item.getSessionId()));
        }
        if (item.getClientIp() != null) {
            record.put(CLIENT_IP, StringUtils.fromString(item.getClientIp()));
        }
        if (item.getOpenTime() != null) {
            record.put(OPEN_TIME, ValueUtils.toUtc(item.getOpenTime()));
        }
        if (item.getLastReconnectTime() != null) {
            record.put(LAST_RECONNECT_TIME, ValueUtils.toUtc(item.getLastReconnectTime()));
        }
        return record;
    }

    /** Maps the SDK close-handles result to a {@code CloseHandlesInfo} record. */
    public static BMap<BString, Object> closeHandlesInfo(CloseHandlesInfo info) {
        BMap<BString, Object> record = newRecord(RECORD_CLOSE_HANDLES_INFO);
        record.put(CLOSED_HANDLES, (long) info.getClosedHandles());
        record.put(FAILED_HANDLES, (long) info.getFailedHandles());
        return record;
    }

    /** Maps one SDK stored-access-policy identifier to a {@code SignedIdentifier} record. */
    public static BMap<BString, Object> signedIdentifier(ShareSignedIdentifier identifier) {
        BMap<BString, Object> record = newRecord(RECORD_SIGNED_IDENTIFIER);
        record.put(ID, StringUtils.fromString(identifier.getId()));
        BMap<BString, Object> policy = newRecord(RECORD_ACCESS_POLICY);
        ShareAccessPolicy sdkPolicy = identifier.getAccessPolicy();
        if (sdkPolicy != null) {
            policy.put(PERMISSIONS,
                    StringUtils.fromString(sdkPolicy.getPermissions() == null ? "" : sdkPolicy.getPermissions()));
            if (sdkPolicy.getStartsOn() != null) {
                policy.put(STARTS_ON, ValueUtils.toUtc(sdkPolicy.getStartsOn()));
            }
            if (sdkPolicy.getExpiresOn() != null) {
                policy.put(EXPIRES_ON, ValueUtils.toUtc(sdkPolicy.getExpiresOn()));
            }
        }
        record.put(ACCESS_POLICY, policy);
        return record;
    }

    /** Maps the SDK range-diff listing to a {@code RangeDiff} record. */
    public static BMap<BString, Object> rangeDiff(ShareFileRangeList list) {
        BMap<BString, Object> record = newRecord(RECORD_RANGE_DIFF);
        BArray ranges = recordArray(RECORD_RANGE);
        for (FileRange r : list.getRanges()) {
            ranges.append(range(r.getStart(), r.getEnd()));
        }
        BArray clearRanges = recordArray(RECORD_RANGE);
        for (ClearRange r : list.getClearRanges()) {
            clearRanges.append(range(r.getStart(), r.getEnd()));
        }
        record.put(RANGES, ranges);
        record.put(CLEAR_RANGES, clearRanges);
        return record;
    }

    /** Creates an array value typed to the named module record. */
    public static BArray recordArray(String recordTypeName) {
        BMap<BString, Object> template = newRecord(recordTypeName);
        return ValueCreator.createArrayValue(TypeCreator.createArrayType(TypeUtils.getType(template)));
    }

    private static BMap<BString, Object> newRecord(String typeName) {
        return ValueCreator.createRecordValue(ModuleUtils.getModule(), typeName);
    }

    private static void putLeaseFields(BMap<BString, Object> record, LeaseStateType state,
                                       LeaseStatusType status, LeaseDurationType duration) {
        if (state == null || state == LeaseStateType.AVAILABLE) {
            return;
        }
        record.put(LEASE_STATE, StringUtils.fromString(state.toString()));
        if (status != null) {
            record.put(LEASE_STATUS, StringUtils.fromString(status.toString()));
        }
        if (duration != null) {
            record.put(LEASE_DURATION, StringUtils.fromString(duration.toString()));
        }
    }

    private static void putSmbProperties(BMap<BString, Object> record, FileSmbProperties smb) {
        if (smb == null) {
            return;
        }
        boolean hasContent = smb.getNtfsFileAttributes() != null || smb.getFilePermissionKey() != null
                || smb.getFileCreationTime() != null || smb.getFileLastWriteTime() != null
                || smb.getFileChangeTime() != null || smb.getFileId() != null || smb.getParentId() != null;
        if (!hasContent) {
            return;
        }
        BMap<BString, Object> smbRecord = newRecord(RECORD_SMB_PROPERTIES);
        EnumSet<NtfsFileAttributes> attributes = smb.getNtfsFileAttributes();
        if (attributes != null) {
            BArray array = ValueCreator.createArrayValue(
                    TypeCreator.createArrayType(PredefinedTypes.TYPE_STRING));
            for (NtfsFileAttributes attribute : attributes) {
                array.append(StringUtils.fromString(ntfsAttributeValue(attribute)));
            }
            smbRecord.put(OptionsReader.NTFS_FILE_ATTRIBUTES, array);
        }
        if (smb.getFilePermissionKey() != null) {
            smbRecord.put(OptionsReader.FILE_PERMISSION_KEY, StringUtils.fromString(smb.getFilePermissionKey()));
        }
        if (smb.getFileCreationTime() != null) {
            smbRecord.put(OptionsReader.FILE_CREATION_TIME, ValueUtils.toUtc(smb.getFileCreationTime()));
        }
        if (smb.getFileLastWriteTime() != null) {
            smbRecord.put(OptionsReader.FILE_LAST_WRITE_TIME, ValueUtils.toUtc(smb.getFileLastWriteTime()));
        }
        if (smb.getFileChangeTime() != null) {
            smbRecord.put(OptionsReader.FILE_CHANGE_TIME, ValueUtils.toUtc(smb.getFileChangeTime()));
        }
        if (smb.getFileId() != null) {
            smbRecord.put(OptionsReader.FILE_ID, StringUtils.fromString(smb.getFileId()));
        }
        if (smb.getParentId() != null) {
            smbRecord.put(OptionsReader.PARENT_ID, StringUtils.fromString(smb.getParentId()));
        }
        record.put(OptionsReader.SMB_PROPERTIES, smbRecord);
    }

    private static void putPosixProperties(BMap<BString, Object> record, FilePosixProperties posix) {
        if (posix == null) {
            return;
        }
        boolean hasContent = posix.getOwner() != null || posix.getGroup() != null
                || posix.getFileMode() != null || posix.getFileType() != null || posix.getLinkCount() != null;
        if (!hasContent) {
            return;
        }
        BMap<BString, Object> posixRecord = newRecord(RECORD_POSIX_PROPERTIES);
        if (posix.getOwner() != null) {
            posixRecord.put(OptionsReader.OWNER, StringUtils.fromString(posix.getOwner()));
        }
        if (posix.getGroup() != null) {
            posixRecord.put(OptionsReader.GROUP, StringUtils.fromString(posix.getGroup()));
        }
        if (posix.getFileMode() != null) {
            posixRecord.put(OptionsReader.FILE_MODE, StringUtils.fromString(posix.getFileMode()));
        }
        if (posix.getFileType() != null) {
            posixRecord.put(OptionsReader.FILE_TYPE, StringUtils.fromString(posix.getFileType().toString()));
        }
        if (posix.getLinkCount() != null) {
            posixRecord.put(OptionsReader.LINK_COUNT, posix.getLinkCount());
        }
        record.put(OptionsReader.POSIX_PROPERTIES, posixRecord);
    }

    private static String ntfsAttributeValue(NtfsFileAttributes attribute) {
        return switch (attribute) {
            case READ_ONLY -> OptionsReader.ATTRIBUTE_READ_ONLY;
            case HIDDEN -> OptionsReader.ATTRIBUTE_HIDDEN;
            case SYSTEM -> OptionsReader.ATTRIBUTE_SYSTEM;
            case NORMAL -> OptionsReader.ATTRIBUTE_NONE;
            case DIRECTORY -> OptionsReader.ATTRIBUTE_DIRECTORY;
            case ARCHIVE -> OptionsReader.ATTRIBUTE_ARCHIVE;
            case TEMPORARY -> OptionsReader.ATTRIBUTE_TEMPORARY;
            case OFFLINE -> OptionsReader.ATTRIBUTE_OFFLINE;
            case NOT_CONTENT_INDEXED -> OptionsReader.ATTRIBUTE_NOT_CONTENT_INDEXED;
            case NO_SCRUB_DATA -> OptionsReader.ATTRIBUTE_NO_SCRUB_DATA;
        };
    }
}
