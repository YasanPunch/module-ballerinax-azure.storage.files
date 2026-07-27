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

package io.ballerina.lib.azure.storage.files;

import com.azure.storage.file.share.FileSmbProperties;
import com.azure.storage.file.share.models.FilePosixProperties;
import com.azure.storage.file.share.models.NtfsFileAttributes;
import com.azure.storage.file.share.models.ShareCorsRule;
import com.azure.storage.file.share.models.ShareFileHttpHeaders;
import com.azure.storage.file.share.models.ShareFileRange;
import com.azure.storage.file.share.models.ShareMetrics;
import com.azure.storage.file.share.models.ShareProtocolSettings;
import com.azure.storage.file.share.models.ShareRetentionPolicy;
import com.azure.storage.file.share.models.ShareServiceProperties;
import com.azure.storage.file.share.models.ShareSmbSettings;
import com.azure.storage.file.share.models.SmbMultichannel;
import io.ballerina.runtime.api.utils.StringUtils;
import io.ballerina.runtime.api.values.BArray;
import io.ballerina.runtime.api.values.BMap;
import io.ballerina.runtime.api.values.BString;

import java.util.ArrayList;
import java.util.Base64;
import java.util.EnumSet;
import java.util.List;

/**
 * Reads the Ballerina option records into the SDK's option and property classes. Every reader
 * accepts the record as a {@code BMap} and tolerates absent optional fields.
 */
final class OptionsReader {

    // Field names of the option, content-header, SMB, and POSIX records. Owned here as
    // the options schema; other classes reference them from this class.
    // The Ballerina NtfsFileAttribute enum values.
    static final String ATTRIBUTE_READ_ONLY = "ReadOnly";
    static final String ATTRIBUTE_HIDDEN = "Hidden";
    static final String ATTRIBUTE_SYSTEM = "System";
    static final String ATTRIBUTE_NONE = "None";
    static final String ATTRIBUTE_DIRECTORY = "Directory";
    static final String ATTRIBUTE_ARCHIVE = "Archive";
    static final String ATTRIBUTE_TEMPORARY = "Temporary";
    static final String ATTRIBUTE_OFFLINE = "Offline";
    static final String ATTRIBUTE_NOT_CONTENT_INDEXED = "NotContentIndexed";
    static final String ATTRIBUTE_NO_SCRUB_DATA = "NoScrubData";
    static final BString PREFIX = StringUtils.fromString("prefix");
    static final BString INCLUDE_METADATA = StringUtils.fromString("includeMetadata");
    static final BString INCLUDE_SNAPSHOTS = StringUtils.fromString("includeSnapshots");
    static final BString INCLUDE_DELETED = StringUtils.fromString("includeDeleted");
    static final BString METADATA = StringUtils.fromString("metadata");
    static final BString QUOTA_IN_GB = StringUtils.fromString("quotaInGb");
    static final BString ACCESS_TIER = StringUtils.fromString("accessTier");
    static final BString ENABLED_PROTOCOLS = StringUtils.fromString("enabledProtocols");
    static final BString ROOT_SQUASH = StringUtils.fromString("rootSquash");
    static final BString DELETE_SNAPSHOTS = StringUtils.fromString("deleteSnapshots");
    static final BString SNAPSHOT_ID = StringUtils.fromString("snapshotId");
    static final BString LEASE_ID = StringUtils.fromString("leaseId");
    static final BString FILE_PERMISSION = StringUtils.fromString("filePermission");
    static final BString SMB_PROPERTIES = StringUtils.fromString("smbProperties");
    static final BString POSIX_PROPERTIES = StringUtils.fromString("posixProperties");
    static final BString RECURSIVE = StringUtils.fromString("recursive");
    static final BString PAGE_SIZE = StringUtils.fromString("pageSize");
    static final BString INCLUDE_EXTENDED_INFO = StringUtils.fromString("includeExtendedInfo");
    static final BString REPLACE_IF_EXISTS = StringUtils.fromString("replaceIfExists");
    static final BString IGNORE_READ_ONLY = StringUtils.fromString("ignoreReadOnly");
    static final BString CONTENT_HEADERS = StringUtils.fromString("contentHeaders");
    static final BString RANGE = StringUtils.fromString("range");
    static final BString PERMISSION_COPY_MODE = StringUtils.fromString("permissionCopyMode");
    static final BString CONTENT_TYPE = StringUtils.fromString("contentType");
    static final BString CONTENT_ENCODING = StringUtils.fromString("contentEncoding");
    static final BString CONTENT_LANGUAGE = StringUtils.fromString("contentLanguage");
    static final BString CONTENT_DISPOSITION = StringUtils.fromString("contentDisposition");
    static final BString CACHE_CONTROL = StringUtils.fromString("cacheControl");
    static final BString CONTENT_MD5 = StringUtils.fromString("contentMd5");
    static final BString NTFS_FILE_ATTRIBUTES = StringUtils.fromString("ntfsFileAttributes");
    static final BString FILE_PERMISSION_KEY = StringUtils.fromString("filePermissionKey");
    static final BString FILE_CREATION_TIME = StringUtils.fromString("fileCreationTime");
    static final BString FILE_LAST_WRITE_TIME = StringUtils.fromString("fileLastWriteTime");
    static final BString FILE_CHANGE_TIME = StringUtils.fromString("fileChangeTime");
    static final BString FILE_ID = StringUtils.fromString("fileId");
    static final BString PARENT_ID = StringUtils.fromString("parentId");
    static final BString OWNER = StringUtils.fromString("owner");
    static final BString GROUP = StringUtils.fromString("group");
    static final BString FILE_MODE = StringUtils.fromString("fileMode");
    static final BString FILE_TYPE = StringUtils.fromString("fileType");
    static final BString LINK_COUNT = StringUtils.fromString("linkCount");

    private OptionsReader() {
    }

    /** Converts a {@code ContentHeaders} record to the SDK header class; {@code null} when absent. */
    static ShareFileHttpHeaders contentHeaders(Object value) {
        if (value == null) {
            return null;
        }
        @SuppressWarnings("unchecked")
        BMap<BString, Object> record = (BMap<BString, Object>) value;
        ShareFileHttpHeaders headers = new ShareFileHttpHeaders()
                .setContentType(ValueUtils.optString(record, CONTENT_TYPE))
                .setContentEncoding(ValueUtils.optString(record, CONTENT_ENCODING))
                .setContentLanguage(ValueUtils.optString(record, CONTENT_LANGUAGE))
                .setContentDisposition(ValueUtils.optString(record, CONTENT_DISPOSITION))
                .setCacheControl(ValueUtils.optString(record, CACHE_CONTROL));
        String md5 = ValueUtils.optString(record, CONTENT_MD5);
        if (md5 != null) {
            try {
                headers.setContentMd5(Base64.getDecoder().decode(md5));
            } catch (IllegalArgumentException e) {
                throw FilesErrorCreator.processingError("contentMd5 must be base64-encoded", e);
            }
        }
        return headers;
    }

    /** Converts an {@code SmbProperties} record to the SDK class; {@code null} when absent. */
    static FileSmbProperties smbProperties(Object value) {
        if (value == null) {
            return null;
        }
        @SuppressWarnings("unchecked")
        BMap<BString, Object> record = (BMap<BString, Object>) value;
        FileSmbProperties smb = new FileSmbProperties()
                .setFilePermissionKey(ValueUtils.optString(record, FILE_PERMISSION_KEY));
        Object attributes = record.get(NTFS_FILE_ATTRIBUTES);
        if (attributes != null) {
            BArray array = (BArray) attributes;
            EnumSet<NtfsFileAttributes> set = EnumSet.noneOf(NtfsFileAttributes.class);
            for (int i = 0; i < array.size(); i++) {
                set.add(ntfsAttribute(array.getBString(i).getValue()));
            }
            smb.setNtfsFileAttributes(set);
        }
        Object creation = record.get(FILE_CREATION_TIME);
        if (creation != null) {
            smb.setFileCreationTime(ValueUtils.fromUtc((BArray) creation));
        }
        Object lastWrite = record.get(FILE_LAST_WRITE_TIME);
        if (lastWrite != null) {
            smb.setFileLastWriteTime(ValueUtils.fromUtc((BArray) lastWrite));
        }
        Object change = record.get(FILE_CHANGE_TIME);
        if (change != null) {
            smb.setFileChangeTime(ValueUtils.fromUtc((BArray) change));
        }
        return smb;
    }

    /** Converts a writable {@code PosixProperties} record to the SDK class; {@code null} when absent. */
    static FilePosixProperties posixProperties(Object value) {
        if (value == null) {
            return null;
        }
        @SuppressWarnings("unchecked")
        BMap<BString, Object> record = (BMap<BString, Object>) value;
        return new FilePosixProperties()
                .setOwner(ValueUtils.optString(record, OWNER))
                .setGroup(ValueUtils.optString(record, GROUP))
                .setFileMode(ValueUtils.optString(record, FILE_MODE));
    }

    /** Converts a {@code Range} record to the SDK range; {@code null} when absent. */
    static ShareFileRange range(Object value) {
        if (value == null) {
            return null;
        }
        @SuppressWarnings("unchecked")
        BMap<BString, Object> record = (BMap<BString, Object>) value;
        long start = (Long) record.get(RecordMapper.START_BYTE);
        long end = (Long) record.get(RecordMapper.END_BYTE);
        return new ShareFileRange(start, end);
    }

    /** Converts a {@code ServiceProperties} record to the SDK model. */
    static ShareServiceProperties serviceProperties(BMap<BString, Object> record) {
        ShareServiceProperties sdk = new ShareServiceProperties();
        Object hourMetrics = record.get(RecordMapper.HOUR_METRICS);
        if (hourMetrics != null) {
            sdk.setHourMetrics(metrics(hourMetrics));
        }
        Object minuteMetrics = record.get(RecordMapper.MINUTE_METRICS);
        if (minuteMetrics != null) {
            sdk.setMinuteMetrics(metrics(minuteMetrics));
        }
        Object cors = record.get(RecordMapper.CORS);
        if (cors != null) {
            List<ShareCorsRule> rules = new ArrayList<>();
            BArray ruleArray = (BArray) cors;
            for (int i = 0; i < ruleArray.size(); i++) {
                @SuppressWarnings("unchecked")
                BMap<BString, Object> rule = (BMap<BString, Object>) ruleArray.get(i);
                rules.add(new ShareCorsRule()
                        .setAllowedOrigins(rule.getStringValue(RecordMapper.ALLOWED_ORIGINS).getValue())
                        .setAllowedMethods(rule.getStringValue(RecordMapper.ALLOWED_METHODS).getValue())
                        .setAllowedHeaders(rule.getStringValue(RecordMapper.ALLOWED_HEADERS).getValue())
                        .setExposedHeaders(rule.getStringValue(RecordMapper.EXPOSED_HEADERS).getValue())
                        .setMaxAgeInSeconds(Math.toIntExact((Long) rule.get(RecordMapper.MAX_AGE_IN_SECONDS))));
            }
            sdk.setCors(rules);
        }
        Object protocol = record.get(RecordMapper.PROTOCOL);
        if (protocol != null) {
            @SuppressWarnings("unchecked")
            BMap<BString, Object> protocolRecord = (BMap<BString, Object>) protocol;
            Object multichannelEnabled = protocolRecord.get(RecordMapper.SMB_MULTICHANNEL_ENABLED);
            if (multichannelEnabled != null) {
                sdk.setProtocol(new ShareProtocolSettings().setSmb(new ShareSmbSettings()
                        .setMultichannel(new SmbMultichannel().setEnabled((Boolean) multichannelEnabled))));
            }
        }
        return sdk;
    }

    private static ShareMetrics metrics(Object value) {
        @SuppressWarnings("unchecked")
        BMap<BString, Object> record = (BMap<BString, Object>) value;
        String version = ValueUtils.optString(record, RecordMapper.VERSION);
        ShareMetrics sdk = new ShareMetrics()
                .setEnabled(record.getBooleanValue(RecordMapper.ENABLED))
                .setVersion(version == null ? "1.0" : version);
        Object includeApis = record.get(RecordMapper.INCLUDE_APIS);
        if (includeApis != null) {
            sdk.setIncludeApis((Boolean) includeApis);
        }
        Object retentionDays = record.get(RecordMapper.RETENTION_DAYS);
        ShareRetentionPolicy retention = new ShareRetentionPolicy().setEnabled(retentionDays != null);
        if (retentionDays != null) {
            retention.setDays(Math.toIntExact((Long) retentionDays));
        }
        sdk.setRetentionPolicy(retention);
        return sdk;
    }

    private static NtfsFileAttributes ntfsAttribute(String value) {
        return switch (value) {
            case ATTRIBUTE_READ_ONLY -> NtfsFileAttributes.READ_ONLY;
            case ATTRIBUTE_HIDDEN -> NtfsFileAttributes.HIDDEN;
            case ATTRIBUTE_SYSTEM -> NtfsFileAttributes.SYSTEM;
            case ATTRIBUTE_NONE -> NtfsFileAttributes.NORMAL;
            case ATTRIBUTE_DIRECTORY -> NtfsFileAttributes.DIRECTORY;
            case ATTRIBUTE_ARCHIVE -> NtfsFileAttributes.ARCHIVE;
            case ATTRIBUTE_TEMPORARY -> NtfsFileAttributes.TEMPORARY;
            case ATTRIBUTE_OFFLINE -> NtfsFileAttributes.OFFLINE;
            case ATTRIBUTE_NOT_CONTENT_INDEXED -> NtfsFileAttributes.NOT_CONTENT_INDEXED;
            case ATTRIBUTE_NO_SCRUB_DATA -> NtfsFileAttributes.NO_SCRUB_DATA;
            default -> throw FilesErrorCreator.processingError("unknown NTFS attribute: " + value, null);
        };
    }
}
