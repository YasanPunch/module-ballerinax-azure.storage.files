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
import com.azure.storage.file.share.models.NtfsFileAttributes;
import com.azure.storage.file.share.models.ShareFileHttpHeaders;
import com.azure.storage.file.share.models.ShareFileRange;
import io.ballerina.runtime.api.values.BArray;
import io.ballerina.runtime.api.values.BMap;
import io.ballerina.runtime.api.values.BString;

import java.util.Base64;
import java.util.EnumSet;

/**
 * Reads the Ballerina option records into the SDK's option and property classes. Every reader
 * accepts the record as a {@code BMap} and tolerates absent optional fields.
 */
final class OptionsReader {

    private OptionsReader() {
    }

    /** Converts a `ContentHeaders` record to the SDK header class; {@code null} when absent. */
    static ShareFileHttpHeaders contentHeaders(Object value) {
        if (value == null) {
            return null;
        }
        @SuppressWarnings("unchecked")
        BMap<BString, Object> record = (BMap<BString, Object>) value;
        ShareFileHttpHeaders headers = new ShareFileHttpHeaders()
                .setContentType(ValueUtils.optString(record, Constants.CONTENT_TYPE))
                .setContentEncoding(ValueUtils.optString(record, Constants.CONTENT_ENCODING))
                .setContentLanguage(ValueUtils.optString(record, Constants.CONTENT_LANGUAGE))
                .setContentDisposition(ValueUtils.optString(record, Constants.CONTENT_DISPOSITION))
                .setCacheControl(ValueUtils.optString(record, Constants.CACHE_CONTROL));
        String md5 = ValueUtils.optString(record, Constants.CONTENT_MD5);
        if (md5 != null) {
            try {
                headers.setContentMd5(Base64.getDecoder().decode(md5));
            } catch (IllegalArgumentException e) {
                throw FilesErrorCreator.processingError("contentMd5 must be base64-encoded", e);
            }
        }
        return headers;
    }

    /** Converts an `SmbProperties` record to the SDK class; {@code null} when absent. */
    static FileSmbProperties smbProperties(Object value) {
        if (value == null) {
            return null;
        }
        @SuppressWarnings("unchecked")
        BMap<BString, Object> record = (BMap<BString, Object>) value;
        FileSmbProperties smb = new FileSmbProperties()
                .setFilePermissionKey(ValueUtils.optString(record, Constants.FILE_PERMISSION_KEY));
        Object attributes = record.get(Constants.NTFS_FILE_ATTRIBUTES);
        if (attributes != null) {
            BArray array = (BArray) attributes;
            EnumSet<NtfsFileAttributes> set = EnumSet.noneOf(NtfsFileAttributes.class);
            for (int i = 0; i < array.size(); i++) {
                set.add(ntfsAttribute(array.getBString(i).getValue()));
            }
            smb.setNtfsFileAttributes(set);
        }
        Object creation = record.get(Constants.FILE_CREATION_TIME);
        if (creation != null) {
            smb.setFileCreationTime(ValueUtils.fromUtc((BArray) creation));
        }
        Object lastWrite = record.get(Constants.FILE_LAST_WRITE_TIME);
        if (lastWrite != null) {
            smb.setFileLastWriteTime(ValueUtils.fromUtc((BArray) lastWrite));
        }
        Object change = record.get(Constants.FILE_CHANGE_TIME);
        if (change != null) {
            smb.setFileChangeTime(ValueUtils.fromUtc((BArray) change));
        }
        return smb;
    }

    /** Converts a writable `PosixProperties` record to the SDK class; {@code null} when absent. */
    static FilePosixProperties posixProperties(Object value) {
        if (value == null) {
            return null;
        }
        @SuppressWarnings("unchecked")
        BMap<BString, Object> record = (BMap<BString, Object>) value;
        return new FilePosixProperties()
                .setOwner(ValueUtils.optString(record, Constants.OWNER))
                .setGroup(ValueUtils.optString(record, Constants.GROUP))
                .setFileMode(ValueUtils.optString(record, Constants.FILE_MODE));
    }

    /** Converts a `Range` record to the SDK range; {@code null} when absent. */
    static ShareFileRange range(Object value) {
        if (value == null) {
            return null;
        }
        @SuppressWarnings("unchecked")
        BMap<BString, Object> record = (BMap<BString, Object>) value;
        long start = (Long) record.get(Constants.START_BYTE);
        long end = (Long) record.get(Constants.END_BYTE);
        return new ShareFileRange(start, end);
    }

    private static NtfsFileAttributes ntfsAttribute(String value) {
        return switch (value) {
            case "ReadOnly" -> NtfsFileAttributes.READ_ONLY;
            case "Hidden" -> NtfsFileAttributes.HIDDEN;
            case "System" -> NtfsFileAttributes.SYSTEM;
            case "None" -> NtfsFileAttributes.NORMAL;
            case "Directory" -> NtfsFileAttributes.DIRECTORY;
            case "Archive" -> NtfsFileAttributes.ARCHIVE;
            case "Temporary" -> NtfsFileAttributes.TEMPORARY;
            case "Offline" -> NtfsFileAttributes.OFFLINE;
            case "NotContentIndexed" -> NtfsFileAttributes.NOT_CONTENT_INDEXED;
            case "NoScrubData" -> NtfsFileAttributes.NO_SCRUB_DATA;
            default -> throw FilesErrorCreator.processingError("unknown NTFS attribute: " + value, null);
        };
    }
}
