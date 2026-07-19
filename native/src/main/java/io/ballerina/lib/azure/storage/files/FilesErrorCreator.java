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

import io.ballerina.runtime.api.creators.ErrorCreator;
import io.ballerina.runtime.api.creators.ValueCreator;
import io.ballerina.runtime.api.utils.StringUtils;
import io.ballerina.runtime.api.values.BError;
import io.ballerina.runtime.api.values.BMap;
import io.ballerina.runtime.api.values.BString;

/**
 * Creates the typed Ballerina errors declared in {@code errors.bal}. Each error carries an
 * {@code ErrorDetail} record; the type name string must match the Ballerina error type exactly.
 */
public final class FilesErrorCreator {

    private FilesErrorCreator() {
    }

    static final String PROCESSING_ERROR = "ProcessingError";

    private static final String ERROR_DETAIL = "ErrorDetail";
    private static final BString HTTP_STATUS = StringUtils.fromString("httpStatus");
    private static final BString ERROR_CODE = StringUtils.fromString("errorCode");

    /**
     * Creates a typed error for a failure returned by the Azure service.
     *
     * @param typeName   the Ballerina error type name
     * @param message    the human-readable message
     * @param httpStatus the HTTP status returned by the service
     * @param errorCode  the Azure error code
     * @param cause      the originating Java exception
     * @return the Ballerina error
     */
    static BError storageError(String typeName, String message, int httpStatus, String errorCode, Throwable cause) {
        BMap<BString, Object> detail = ValueCreator.createRecordValue(ModuleUtils.getModule(), ERROR_DETAIL);
        detail.put(HTTP_STATUS, (long) httpStatus);
        detail.put(ERROR_CODE, StringUtils.fromString(errorCode));
        return ErrorCreator.createError(ModuleUtils.getModule(), typeName,
                StringUtils.fromString(message == null ? "" : message), toCause(cause), detail);
    }

    /**
     * Creates the error returned by operations or configuration paths that are not implemented
     * yet.
     *
     * @param what a short description of the unimplemented capability
     * @return the Ballerina error
     */
    static BError notImplemented(String what) {
        BMap<BString, Object> detail = ValueCreator.createRecordValue(ModuleUtils.getModule(), ERROR_DETAIL);
        detail.put(ERROR_CODE, StringUtils.fromString("NotImplemented"));
        return ErrorCreator.createError(ModuleUtils.getModule(), "Error",
                StringUtils.fromString(what + " is not implemented yet"), null, detail);
    }

    /**
     * Creates a client-side processing error, with no HTTP status (no server exchange occurred).
     *
     * @param message the human-readable message
     * @param cause   the originating Java exception
     * @return the Ballerina error
     */
    static BError processingError(String message, Throwable cause) {
        BMap<BString, Object> detail = ValueCreator.createRecordValue(ModuleUtils.getModule(), ERROR_DETAIL);
        detail.put(ERROR_CODE, StringUtils.fromString(PROCESSING_ERROR));
        return ErrorCreator.createError(ModuleUtils.getModule(), PROCESSING_ERROR,
                StringUtils.fromString(message == null ? "" : message), toCause(cause), detail);
    }

    private static BError toCause(Throwable cause) {
        if (cause == null) {
            return null;
        }
        String message = cause.getMessage() == null ? cause.getClass().getName() : cause.getMessage();
        return ErrorCreator.createError(StringUtils.fromString(message));
    }
}
