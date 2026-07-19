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

import com.azure.storage.file.share.FileSmbProperties;
import com.azure.storage.file.share.models.FilePosixProperties;
import com.azure.storage.file.share.models.LeaseDurationType;
import com.azure.storage.file.share.models.LeaseStateType;
import com.azure.storage.file.share.models.LeaseStatusType;
import com.azure.storage.file.share.models.NtfsFileAttributes;
import com.azure.storage.file.share.models.ShareDirectoryProperties;
import com.azure.storage.file.share.models.ShareFileCopyInfo;
import com.azure.storage.file.share.models.ShareFileItem;
import com.azure.storage.file.share.models.ShareFileProperties;
import com.azure.storage.file.share.models.ShareFileRange;
import com.azure.storage.file.share.models.ShareItem;
import com.azure.storage.file.share.models.ShareProperties;
import com.azure.storage.file.share.models.ShareProtocols;
import io.ballerina.runtime.api.creators.TypeCreator;
import io.ballerina.runtime.api.creators.ValueCreator;
import io.ballerina.runtime.api.types.PredefinedTypes;
import io.ballerina.runtime.api.utils.StringUtils;
import io.ballerina.runtime.api.utils.TypeUtils;
import io.ballerina.runtime.api.values.BArray;
import io.ballerina.runtime.api.values.BMap;
import io.ballerina.runtime.api.values.BString;

import java.util.Base64;
import java.util.EnumSet;

/**
 * Maps the SDK model classes to the Ballerina result records declared in {@code types.bal}.
 * Optional record fields are set only when the service supplied a value.
 */
final class RecordMapper {

    private RecordMapper() {
    }

    /** Maps one listed share to a `ShareInfo` record. */
    static BMap<BString, Object> shareInfo(ShareItem item) {
        BMap<BString, Object> record = newRecord(Constants.RECORD_SHARE_INFO);
        record.put(Constants.NAME, StringUtils.fromString(item.getName()));
        record.put(Constants.PROPERTIES, shareProperties(item.getProperties()));
        if (item.getMetadata() != null && !item.getMetadata().isEmpty()) {
            record.put(Constants.METADATA, ValueUtils.toBStringMap(item.getMetadata()));
        }
        if (item.getSnapshot() != null) {
            record.put(Constants.SNAPSHOT_ID, StringUtils.fromString(item.getSnapshot()));
        }
        if (item.isDeleted() != null) {
            record.put(Constants.IS_DELETED, item.isDeleted());
        }
        if (item.getVersion() != null) {
            record.put(Constants.VERSION, StringUtils.fromString(item.getVersion()));
        }
        return record;
    }

    /** Maps SDK share properties to a `ShareProperties` record. */
    static BMap<BString, Object> shareProperties(ShareProperties p) {
        BMap<BString, Object> record = newRecord(Constants.RECORD_SHARE_PROPERTIES);
        record.put(Constants.QUOTA_IN_GB, (long) p.getQuota());
        record.put(Constants.ACCESS_TIER, StringUtils.fromString(
                p.getAccessTier() == null ? "TransactionOptimized" : p.getAccessTier()));
        record.put(Constants.E_TAG, StringUtils.fromString(p.getETag()));
        record.put(Constants.LAST_MODIFIED, ValueUtils.toUtc(p.getLastModified()));
        if (p.getMetadata() != null && !p.getMetadata().isEmpty()) {
            record.put(Constants.METADATA, ValueUtils.toBStringMap(p.getMetadata()));
        }
        ShareProtocols protocols = p.getProtocols();
        if (protocols != null) {
            BArray array = ValueCreator.createArrayValue(
                    TypeCreator.createArrayType(PredefinedTypes.TYPE_STRING));
            if (protocols.isSmbEnabled()) {
                array.append(StringUtils.fromString("SMB"));
            }
            if (protocols.isNfsEnabled()) {
                array.append(StringUtils.fromString("NFS"));
            }
            if (array.size() > 0) {
                record.put(Constants.ENABLED_PROTOCOLS, array);
            }
        }
        if (p.getRootSquash() != null) {
            record.put(Constants.ROOT_SQUASH, StringUtils.fromString(p.getRootSquash().toString()));
        }
        putLeaseFields(record, p.getLeaseState(), p.getLeaseStatus(), p.getLeaseDuration());
        if (p.getProvisionedIops() != null) {
            record.put(Constants.PROVISIONED_IOPS, p.getProvisionedIops().longValue());
        }
        if (p.getProvisionedBandwidthMiBps() != null) {
            record.put(Constants.PROVISIONED_BANDWIDTH, p.getProvisionedBandwidthMiBps().longValue());
        }
        return record;
    }

    /** Maps SDK directory properties to a `DirectoryProperties` record. */
    static BMap<BString, Object> directoryProperties(ShareDirectoryProperties p) {
        BMap<BString, Object> record = newRecord(Constants.RECORD_DIRECTORY_PROPERTIES);
        record.put(Constants.E_TAG, StringUtils.fromString(p.getETag()));
        record.put(Constants.LAST_MODIFIED, ValueUtils.toUtc(p.getLastModified()));
        if (p.getMetadata() != null && !p.getMetadata().isEmpty()) {
            record.put(Constants.METADATA, ValueUtils.toBStringMap(p.getMetadata()));
        }
        record.put(Constants.IS_SERVER_ENCRYPTED, p.isServerEncrypted());
        putSmbProperties(record, p.getSmbProperties());
        putPosixProperties(record, p.getPosixProperties());
        return record;
    }

    /** Maps SDK file properties to a `FileProperties` record. */
    static BMap<BString, Object> fileProperties(ShareFileProperties p) {
        BMap<BString, Object> record = newRecord(Constants.RECORD_FILE_PROPERTIES);
        record.put(Constants.E_TAG, StringUtils.fromString(p.getETag()));
        record.put(Constants.LAST_MODIFIED, ValueUtils.toUtc(p.getLastModified()));
        record.put(Constants.CONTENT_LENGTH, p.getContentLength());
        record.put(Constants.CONTENT_TYPE, StringUtils.fromString(
                p.getContentType() == null ? "application/octet-stream" : p.getContentType()));
        if (p.getContentEncoding() != null) {
            record.put(Constants.CONTENT_ENCODING, StringUtils.fromString(p.getContentEncoding()));
        }
        if (p.getContentDisposition() != null) {
            record.put(Constants.CONTENT_DISPOSITION, StringUtils.fromString(p.getContentDisposition()));
        }
        if (p.getCacheControl() != null) {
            record.put(Constants.CACHE_CONTROL, StringUtils.fromString(p.getCacheControl()));
        }
        if (p.getContentMd5() != null) {
            record.put(Constants.CONTENT_MD5,
                    StringUtils.fromString(Base64.getEncoder().encodeToString(p.getContentMd5())));
        }
        if (p.getMetadata() != null && !p.getMetadata().isEmpty()) {
            record.put(Constants.METADATA, ValueUtils.toBStringMap(p.getMetadata()));
        }
        record.put(Constants.IS_SERVER_ENCRYPTED, Boolean.TRUE.equals(p.isServerEncrypted()));
        putLeaseFields(record, p.getLeaseState(), p.getLeaseStatus(), p.getLeaseDuration());
        if (p.getCopyStatus() != null) {
            record.put(Constants.COPY_STATUS, StringUtils.fromString(p.getCopyStatus().toString()));
        }
        if (p.getCopyId() != null) {
            record.put(Constants.COPY_ID, StringUtils.fromString(p.getCopyId()));
        }
        BMap<BString, Object> progress = copyProgress(p.getCopyProgress());
        if (progress != null) {
            record.put(Constants.COPY_PROGRESS, progress);
        }
        putSmbProperties(record, p.getSmbProperties());
        putPosixProperties(record, p.getPosixProperties());
        return record;
    }

    /**
     * Parses the service's {@code bytesCopied/totalBytes} copy-progress form into a
     * `CopyProgress` record; {@code null} when absent or unparseable.
     */
    static BMap<BString, Object> copyProgress(String raw) {
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
            BMap<BString, Object> record = newRecord(Constants.RECORD_COPY_PROGRESS);
            record.put(Constants.COPIED_BYTES, copied);
            record.put(Constants.TOTAL_BYTES, total);
            return record;
        } catch (NumberFormatException e) {
            return null;
        }
    }

    /** Builds a `CopyInfo` record from the copy-start snapshot values. */
    static BMap<BString, Object> copyInfo(String copyId, String copyStatus, String eTag,
                                          java.time.OffsetDateTime lastModified) {
        BMap<BString, Object> record = newRecord(Constants.RECORD_COPY_INFO);
        record.put(Constants.COPY_ID, StringUtils.fromString(copyId));
        record.put(Constants.COPY_STATUS, StringUtils.fromString(copyStatus));
        record.put(Constants.E_TAG, StringUtils.fromString(eTag));
        record.put(Constants.LAST_MODIFIED, ValueUtils.toUtc(lastModified));
        return record;
    }

    /**
     * Builds a `CopyStatusInfo` record from fetched file properties, or {@code null} when the
     * file has never been a copy destination.
     */
    static BMap<BString, Object> copyStatusInfo(ShareFileProperties p) {
        if (p.getCopyId() == null) {
            return null;
        }
        BMap<BString, Object> record = newRecord(Constants.RECORD_COPY_STATUS_INFO);
        record.put(Constants.COPY_ID, StringUtils.fromString(p.getCopyId()));
        record.put(Constants.COPY_STATUS, StringUtils.fromString(
                p.getCopyStatus() == null ? "pending" : p.getCopyStatus().toString()));
        BMap<BString, Object> progress = copyProgress(p.getCopyProgress());
        if (progress != null) {
            record.put(Constants.COPY_PROGRESS, progress);
        }
        return record;
    }

    /**
     * Maps one listed item to an `Entry` record.
     *
     * @param item      the SDK item
     * @param parentPath the share-relative path of the directory that was listed, without a
     *                   trailing slash; empty for the share root
     * @return the `Entry` record
     */
    static BMap<BString, Object> entry(ShareFileItem item, String parentPath) {
        BMap<BString, Object> record = newRecord(Constants.RECORD_ENTRY);
        String path = parentPath.isEmpty() ? "/" + item.getName() : "/" + parentPath + "/" + item.getName();
        record.put(Constants.PATH, StringUtils.fromString(path));
        record.put(Constants.NAME, StringUtils.fromString(item.getName()));
        record.put(Constants.IS_DIRECTORY, item.isDirectory());
        if (item.getFileSize() != null) {
            record.put(Constants.SIZE_BYTES, item.getFileSize());
        }
        record.put(Constants.ID, StringUtils.fromString(item.getId() == null ? "" : item.getId()));
        if (item.getProperties() != null) {
            if (item.getProperties().getETag() != null) {
                record.put(Constants.E_TAG, StringUtils.fromString(item.getProperties().getETag()));
            }
            if (item.getProperties().getLastModified() != null) {
                record.put(Constants.LAST_MODIFIED, ValueUtils.toUtc(item.getProperties().getLastModified()));
            }
        }
        return record;
    }

    /** Maps one SDK range to a `Range` record. */
    static BMap<BString, Object> range(ShareFileRange r) {
        BMap<BString, Object> record = newRecord(Constants.RECORD_RANGE);
        record.put(Constants.START_BYTE, r.getStart());
        record.put(Constants.END_BYTE, r.getEnd() == null ? r.getStart() : r.getEnd());
        return record;
    }

    /** Creates an array value typed to the named module record. */
    static BArray recordArray(String recordTypeName) {
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
        record.put(Constants.LEASE_STATE, StringUtils.fromString(state.toString()));
        if (status != null) {
            record.put(Constants.LEASE_STATUS, StringUtils.fromString(status.toString()));
        }
        if (duration != null) {
            record.put(Constants.LEASE_DURATION, StringUtils.fromString(duration.toString()));
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
        BMap<BString, Object> smbRecord = newRecord(Constants.RECORD_SMB_PROPERTIES);
        EnumSet<NtfsFileAttributes> attributes = smb.getNtfsFileAttributes();
        if (attributes != null) {
            BArray array = ValueCreator.createArrayValue(
                    TypeCreator.createArrayType(PredefinedTypes.TYPE_STRING));
            for (NtfsFileAttributes attribute : attributes) {
                array.append(StringUtils.fromString(ntfsAttributeValue(attribute)));
            }
            smbRecord.put(Constants.NTFS_FILE_ATTRIBUTES, array);
        }
        if (smb.getFilePermissionKey() != null) {
            smbRecord.put(Constants.FILE_PERMISSION_KEY, StringUtils.fromString(smb.getFilePermissionKey()));
        }
        if (smb.getFileCreationTime() != null) {
            smbRecord.put(Constants.FILE_CREATION_TIME, ValueUtils.toUtc(smb.getFileCreationTime()));
        }
        if (smb.getFileLastWriteTime() != null) {
            smbRecord.put(Constants.FILE_LAST_WRITE_TIME, ValueUtils.toUtc(smb.getFileLastWriteTime()));
        }
        if (smb.getFileChangeTime() != null) {
            smbRecord.put(Constants.FILE_CHANGE_TIME, ValueUtils.toUtc(smb.getFileChangeTime()));
        }
        if (smb.getFileId() != null) {
            smbRecord.put(Constants.FILE_ID, StringUtils.fromString(smb.getFileId()));
        }
        if (smb.getParentId() != null) {
            smbRecord.put(Constants.PARENT_ID, StringUtils.fromString(smb.getParentId()));
        }
        record.put(Constants.SMB_PROPERTIES, smbRecord);
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
        BMap<BString, Object> posixRecord = newRecord(Constants.RECORD_POSIX_PROPERTIES);
        if (posix.getOwner() != null) {
            posixRecord.put(Constants.OWNER, StringUtils.fromString(posix.getOwner()));
        }
        if (posix.getGroup() != null) {
            posixRecord.put(Constants.GROUP, StringUtils.fromString(posix.getGroup()));
        }
        if (posix.getFileMode() != null) {
            posixRecord.put(Constants.FILE_MODE, StringUtils.fromString(posix.getFileMode()));
        }
        if (posix.getFileType() != null) {
            posixRecord.put(Constants.FILE_TYPE, StringUtils.fromString(posix.getFileType().toString()));
        }
        if (posix.getLinkCount() != null) {
            posixRecord.put(Constants.LINK_COUNT, posix.getLinkCount());
        }
        record.put(Constants.POSIX_PROPERTIES, posixRecord);
    }

    private static String ntfsAttributeValue(NtfsFileAttributes attribute) {
        return switch (attribute) {
            case READ_ONLY -> "ReadOnly";
            case HIDDEN -> "Hidden";
            case SYSTEM -> "System";
            case NORMAL -> "None";
            case DIRECTORY -> "Directory";
            case ARCHIVE -> "Archive";
            case TEMPORARY -> "Temporary";
            case OFFLINE -> "Offline";
            case NOT_CONTENT_INDEXED -> "NotContentIndexed";
            case NO_SCRUB_DATA -> "NoScrubData";
        };
    }
}
