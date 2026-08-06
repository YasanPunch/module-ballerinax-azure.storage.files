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

import com.azure.storage.file.share.models.ShareStorageException;
import io.ballerina.runtime.api.values.BError;

import java.util.Set;

/**
 * Maps an Azure {@link ShareStorageException} to a typed Ballerina error, keyed on the Azure error
 * code string rather than the HTTP status alone (for example a full share and an authorization
 * failure are both HTTP 403 but map to different types).
 */
public final class ErrorMapper {

    private ErrorMapper() {
    }

    private static final Set<String> NOT_FOUND_CODES =
            Set.of("ShareNotFound", "ResourceNotFound", "ParentNotFound", "ShareSnapshotNotFound");
    private static final Set<String> CONFLICT_CODES =
            Set.of("ResourceAlreadyExists", "ShareAlreadyExists", "DirectoryNotEmpty", "ShareBeingDeleted",
                    "SharingViolation", "TotalSharesProvisionedCapacityExceedsAccountLimit",
                    "TotalSharesProvisionedIopsExceedsAccountLimit",
                    "ContainerQuotaDowngradeNotAllowed", "LeaseAlreadyPresent",
                    "LeaseIdMismatchWithLeaseOperation", "LeaseNotPresentWithLeaseOperation",
                    "LeaseIsBreakingAndCannotBeChanged", "LeaseIsBrokenAndCannotBeRenewed");
    private static final Set<String> PRECONDITION_CODES =
            Set.of("ConditionNotMet", "LeaseIdMissing", "LeaseIdMismatchWithFileOperation",
                    "LeaseNotPresentWithFileOperation", "LeaseLost");
    private static final Set<String> AUTHORIZATION_CODES =
            Set.of("AuthenticationFailed", "AuthorizationFailure", "InsufficientAccountPermissions", "ShareDisabled",
                    "AuthorizationPermissionMismatch", "AuthorizationSourceIPMismatch", "AuthorizationProtocolMismatch",
                    "AuthorizationServiceMismatch", "AuthorizationResourceTypeMismatch", "InvalidAuthenticationInfo",
                    "AccountIsDisabled");
    private static final Set<String> QUOTA_CODES =
            Set.of("ShareSizeLimitReached", "SmbShareFull");

    /**
     * Converts a service exception into the matching typed Ballerina error.
     *
     * @param e the Azure service exception
     * @return the Ballerina error
     */
    public static BError toBError(ShareStorageException e) {
        String code = e.getErrorCode() == null ? "" : e.getErrorCode().toString();
        String message = e.getServiceMessage() == null ? e.getMessage() : e.getServiceMessage();
        return FilesErrorCreator.storageError(typeName(code), message, e.getStatusCode(), code, e);
    }

    private static String typeName(String code) {
        if (NOT_FOUND_CODES.contains(code)) {
            return "NotFoundError";
        }
        if (CONFLICT_CODES.contains(code)) {
            return "ConflictError";
        }
        if (QUOTA_CODES.contains(code)) {
            return "QuotaExceededError";
        }
        if (AUTHORIZATION_CODES.contains(code)) {
            return "AuthorizationError";
        }
        if (PRECONDITION_CODES.contains(code)) {
            return "PreconditionFailedError";
        }
        if ("InvalidRange".equals(code)) {
            return "RangeNotSatisfiableError";
        }
        return "ServiceError";
    }
}
