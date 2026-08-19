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
import java.util.List;

/**
 * Reads the Ballerina option records into the SDK's option and property classes. Every reader
 * accepts the record as a {@code BMap} and tolerates absent optional fields.
 */
public final class OptionsReader {

    // Field names of the option and content-header records; the options schema other
    // classes reference.
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
    public static final BString RECURSIVE = StringUtils.fromString("recursive");
    public static final BString PAGE_SIZE = StringUtils.fromString("pageSize");
    public static final BString INCLUDE_EXTENDED_INFO = StringUtils.fromString("includeExtendedInfo");
    public static final BString REPLACE_IF_EXISTS = StringUtils.fromString("replaceIfExists");
    public static final BString CONTENT_HEADERS = StringUtils.fromString("contentHeaders");
    public static final BString RANGE = StringUtils.fromString("range");
    public static final BString FILE_FORMAT = StringUtils.fromString("fileFormat");
    public static final BString CONTENT_TYPE = StringUtils.fromString("contentType");
    public static final BString CONTENT_ENCODING = StringUtils.fromString("contentEncoding");
    public static final BString CONTENT_LANGUAGE = StringUtils.fromString("contentLanguage");
    public static final BString CONTENT_DISPOSITION = StringUtils.fromString("contentDisposition");
    public static final BString CACHE_CONTROL = StringUtils.fromString("cacheControl");
    public static final BString CONTENT_MD5 = StringUtils.fromString("contentMd5");

    private OptionsReader() {
    }

    /**
     * The options shared by the download-shaped operations.
     *
     * @param range      the byte range to read, or {@code null} for the whole file
     * @param snapshotId the share snapshot to read from, or {@code null} for the live share
     */
    public record DownloadArgs(Object range, String snapshotId) {
    }

    /** Reads the download-shaped options record, tolerating its absence. */
    public static DownloadArgs downloadArgs(Object options) {
        if (options == null) {
            return new DownloadArgs(null, null);
        }
        @SuppressWarnings("unchecked")
        BMap<BString, Object> record = (BMap<BString, Object>) options;
        return new DownloadArgs(record.get(RANGE), ValueUtils.optString(record, SNAPSHOT_ID));
    }

    /** Converts a {@code ContentHeaders} record to the SDK header class; {@code null} when absent. */
    public static ShareFileHttpHeaders contentHeaders(Object value) {
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
                throw FilesErrorCreator.clientError("contentMd5 must be base64-encoded", e);
            }
        }
        return headers;
    }

    /** Converts a {@code Range} record to the SDK range; {@code null} when absent. */
    public static ShareFileRange range(Object value) {
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
    public static ShareServiceProperties serviceProperties(BMap<BString, Object> record) {
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

}
