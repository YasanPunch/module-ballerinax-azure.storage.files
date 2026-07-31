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

package io.ballerina.lib.azure.storage.files.plugin;

import java.util.Set;

/**
 * Constants for the {@code azure.storage.files} listener compiler plugin: the module identity
 * used to recognize the connector's listener, the content-handler names, the parameter type
 * names, and the diagnostic catalog.
 */
public final class PluginConstants {

    private PluginConstants() {
    }

    // The listener's package identity (org and module name).
    public static final String PACKAGE_ORG = "ballerinax";
    public static final String PACKAGE_PREFIX = "azure.storage.files";

    // The content-handler function names.
    public static final String ON_FILE_FUNC = "onFile";
    public static final String ON_FILE_TEXT_FUNC = "onFileText";
    public static final String ON_FILE_JSON_FUNC = "onFileJson";
    public static final String ON_FILE_XML_FUNC = "onFileXml";
    public static final String ON_FILE_CSV_FUNC = "onFileCsv";

    // The optional error-notification handler name. Not a content handler: it does not count
    // toward the at-least-one-content-handler requirement.
    public static final String ON_ERROR_FUNC = "onError";

    /** The set of allowed content-handler names. */
    public static final Set<String> CONTENT_HANDLERS = Set.of(
            ON_FILE_FUNC, ON_FILE_TEXT_FUNC, ON_FILE_JSON_FUNC, ON_FILE_XML_FUNC, ON_FILE_CSV_FUNC);

    // Parameter type names.
    public static final String CALLER = "Caller";
    public static final String FILE_INFO = "FileInfo";
    public static final String ERROR_TYPE = "Error";

    // The required service annotation.
    public static final String SERVICE_CONFIG_ANNOTATION = "ServiceConfig";

    /**
     * The diagnostics the plugin can report, each paired with its stable code.
     */
    public enum CompilationErrors {
        INVALID_REMOTE_FUNCTION("Invalid remote method '%s'. A listener service allows only handlers: "
                + "onFile, onFileText, onFileJson, onFileXml, onFileCsv, onError.", "AZURE_FILES_101"),
        RESOURCE_FUNCTION_NOT_ALLOWED("Unsupported resource function.", "AZURE_FILES_102"),
        NO_VALID_REMOTE_METHOD("At least one handler must be added: onFile, onFileText, "
                + "onFileJson, onFileXml, or onFileCsv.", "AZURE_FILES_103"),
        CONTENT_METHOD_MUST_BE_REMOTE("'%s' handler must be declared as remote.", "AZURE_FILES_104"),
        MANDATORY_PARAMETER_NOT_FOUND("Missing parameter for '%s'. Expected '%s' as the first parameter.",
                "AZURE_FILES_105"),
        INVALID_CONTENT_PARAMETER_TYPE("Invalid parameter type for '%s'. Expected '%s', found '%s'.",
                "AZURE_FILES_106"),
        INVALID_FILEINFO_PARAMETER("Invalid parameter for '%s'. Optional second parameter must be 'FileInfo'.",
                "AZURE_FILES_107"),
        INVALID_CALLER_PARAMETER("Invalid parameter for '%s'. Optional third parameter must be 'Caller'.",
                "AZURE_FILES_108"),
        TOO_MANY_PARAMETERS("Too many parameters for '%s'. Handlers accept at most 3 parameters: "
                + "(content, fileInfo?, caller?).", "AZURE_FILES_109"),
        INVALID_RETURN_TYPE_ERROR_OR_NIL("Invalid return type. Expected 'error?' or 'files:Error?'.",
                "AZURE_FILES_110"),
        MISSING_SERVICE_CONFIG_ANNOTATION("Missing '@files:ServiceConfig' annotation. A listener service must "
                + "configure 'path'.", "AZURE_FILES_111"),
        INVALID_ON_ERROR_FIRST_PARAMETER("Invalid parameter for 'onError'. The first parameter must be "
                + "'error' or 'files:Error'.", "AZURE_FILES_112"),
        INVALID_ON_ERROR_SECOND_PARAMETER("Invalid parameter for 'onError'. Optional second parameter must be "
                + "'Caller'.", "AZURE_FILES_113"),
        TOO_MANY_PARAMETERS_ON_ERROR("Too many parameters for 'onError'. It accepts at most 2 parameters: "
                + "(error, caller?).", "AZURE_FILES_114");

        private final String error;
        private final String errorCode;

        CompilationErrors(String error, String errorCode) {
            this.error = error;
            this.errorCode = errorCode;
        }

        String getError() {
            return error;
        }

        String getErrorCode() {
            return errorCode;
        }
    }
}
