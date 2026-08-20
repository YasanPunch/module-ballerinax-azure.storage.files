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

import io.ballerina.projects.DiagnosticResult;
import org.testng.annotations.Test;

import static io.ballerina.lib.azure.storage.files.plugin.CompilerPluginTestUtils.assertError;
import static io.ballerina.lib.azure.storage.files.plugin.CompilerPluginTestUtils.loadPackage;
import static org.testng.Assert.assertEquals;

/**
 * Compiles the sample listener services and asserts the diagnostics the listener compiler plugin
 * reports: valid handler sets produce none, and each malformed service produces its expected
 * {@code AZURE_FILES_1xx} diagnostic.
 */
public class ServiceValidationTest {

    @Test
    public void testValidOnFileService() {
        DiagnosticResult result = loadPackage("valid_on_file");
        assertEquals(result.errorCount(), 0, "expected no diagnostics for a valid onFile service");
    }

    @Test
    public void testInvalidOnFileJsonMap() {
        DiagnosticResult result = loadPackage("invalid_on_file_json_map");
        assertEquals(result.errorCount(), 1);
        assertError(result, 0, "AZURE_FILES_106", "Invalid parameter type for onFileJson");
    }

    @Test
    public void testValidMixedHandlerService() {
        DiagnosticResult result = loadPackage("valid_mixed");
        assertEquals(result.errorCount(), 0, "expected no diagnostics for a valid mixed-handler service");
    }

    @Test
    public void testValidTypedJsonRecordService() {
        DiagnosticResult result = loadPackage("valid_on_file_json_record");
        assertEquals(result.errorCount(), 0, "expected no diagnostics for an onFileJson record service");
    }

    @Test
    public void testInvalidOnFileJsonRecordArray() {
        DiagnosticResult result = loadPackage("invalid_on_file_json_record_array");
        assertEquals(result.errorCount(), 1);
        assertError(result, 0, "AZURE_FILES_106", "Invalid parameter type for onFileJson");
    }

    @Test
    public void testValidTypedJsonBareService() {
        DiagnosticResult result = loadPackage("valid_on_file_json_bare");
        assertEquals(result.errorCount(), 0);
    }

    @Test
    public void testValidServiceConfigService() {
        DiagnosticResult result = loadPackage("valid_service_config");
        assertEquals(result.errorCount(), 0, "expected no diagnostics for a valid annotated service");
    }

    @Test
    public void testServiceWithoutPathIsValid() {
        DiagnosticResult result = loadPackage("valid_no_path_defaults_root");
        assertEquals(result.errorCount(), 0,
                "expected no diagnostics for a service with no attach point (share-root default)");
    }

    @Test
    public void testInvalidContentParameterType() {
        DiagnosticResult result = loadPackage("invalid_content_type");
        assertEquals(result.errorCount(), 1);
        assertError(result, 0, "AZURE_FILES_106", "Invalid parameter type for onFile");
    }

    @Test
    public void testNoContentHandler() {
        DiagnosticResult result = loadPackage("invalid_no_handler");
        assertEquals(result.errorCount(), 1);
        assertError(result, 0, "AZURE_FILES_103", "At least one handler must be added");
    }

    @Test
    public void testUnknownRemoteMethod() {
        DiagnosticResult result = loadPackage("invalid_unknown_remote");
        assertEquals(result.errorCount(), 1);
        assertError(result, 0, "AZURE_FILES_101", "Invalid remote method onUpload");
    }

    @Test
    public void testResourceFunctionNotAllowed() {
        DiagnosticResult result = loadPackage("invalid_resource_function");
        assertEquals(result.errorCount(), 1);
        assertError(result, 0, "AZURE_FILES_102", "Unsupported resource function");
    }

    @Test
    public void testInvalidReturnType() {
        DiagnosticResult result = loadPackage("invalid_return_type");
        assertEquals(result.errorCount(), 1);
        assertError(result, 0, "AZURE_FILES_110", "Expected error?");
    }

    @Test
    public void testNonRemoteHandlerRejected() {
        DiagnosticResult result = loadPackage("invalid_non_remote_handler");
        assertEquals(result.errorCount(), 1);
        assertError(result, 0, "AZURE_FILES_104", "handler must be declared as remote");
    }

    @Test
    public void testMissingContentParameter() {
        DiagnosticResult result = loadPackage("invalid_missing_parameter");
        assertEquals(result.errorCount(), 1);
        assertError(result, 0, "AZURE_FILES_105", "Missing parameter for onFile");
    }

    @Test
    public void testInvalidSecondParameter() {
        DiagnosticResult result = loadPackage("invalid_second_parameter");
        assertEquals(result.errorCount(), 1);
        assertError(result, 0, "AZURE_FILES_107", "Optional second parameter must be FileInfo");
    }

    @Test
    public void testInvalidThirdParameter() {
        DiagnosticResult result = loadPackage("invalid_third_parameter");
        assertEquals(result.errorCount(), 1);
        assertError(result, 0, "AZURE_FILES_108", "Optional third parameter must be Caller");
    }

    @Test
    public void testTooManyParameters() {
        DiagnosticResult result = loadPackage("invalid_too_many_parameters");
        assertEquals(result.errorCount(), 1);
        assertError(result, 0, "AZURE_FILES_109", "Too many parameters for onFile");
    }

    @Test
    public void testValidReturnErrorAlias() {
        DiagnosticResult result = loadPackage("valid_return_error_alias");
        assertEquals(result.errorCount(), 0, "expected no diagnostics for a user-defined error return type");
    }

    @Test
    public void testInvalidReturnRecordReference() {
        DiagnosticResult result = loadPackage("invalid_return_record_ref");
        assertEquals(result.errorCount(), 1);
        assertError(result, 0, "AZURE_FILES_110", "Expected error?");
    }

    @Test
    public void testValidOnErrorService() {
        DiagnosticResult result = loadPackage("valid_on_error");
        assertEquals(result.errorCount(), 0, "expected no diagnostics for an onError with files:Error");
    }

    @Test
    public void testValidOnErrorBareErrorService() {
        DiagnosticResult result = loadPackage("valid_on_error_bare_error");
        assertEquals(result.errorCount(), 0, "expected no diagnostics for an onError with a bare error");
    }

    @Test
    public void testValidOnErrorWithCallerService() {
        DiagnosticResult result = loadPackage("valid_on_error_with_caller");
        assertEquals(result.errorCount(), 0, "expected no diagnostics for an onError with a Caller");
    }

    @Test
    public void testInvalidOnErrorFirstParameter() {
        DiagnosticResult result = loadPackage("invalid_on_error_first_param");
        assertEquals(result.errorCount(), 1);
        assertError(result, 0, "AZURE_FILES_112", "The first parameter must be");
    }

    @Test
    public void testValidContentTypeAliases() {
        DiagnosticResult result = loadPackage("valid_content_type_aliases");
        assertEquals(result.errorCount(), 0);
    }

    @Test
    public void testInvalidOnErrorNarrowErrorParameter() {
        DiagnosticResult result = loadPackage("invalid_on_error_narrow_error");
        assertEquals(result.errorCount(), 1);
        assertError(result, 0, "AZURE_FILES_112", "The first parameter must be");
    }

    @Test
    public void testInvalidOnErrorSecondParameter() {
        DiagnosticResult result = loadPackage("invalid_on_error_second_param");
        assertEquals(result.errorCount(), 1);
        assertError(result, 0, "AZURE_FILES_113", "Optional second parameter must be");
    }

    @Test
    public void testInvalidOnErrorTooManyParameters() {
        DiagnosticResult result = loadPackage("invalid_on_error_too_many_params");
        assertEquals(result.errorCount(), 1);
        assertError(result, 0, "AZURE_FILES_114", "Too many parameters for");
    }

    @Test
    public void testInvalidOnErrorNonRemote() {
        DiagnosticResult result = loadPackage("invalid_on_error_non_remote");
        assertEquals(result.errorCount(), 1);
        assertError(result, 0, "AZURE_FILES_104", "handler must be declared as remote");
    }

    @Test
    public void testInvalidOnErrorReturnType() {
        DiagnosticResult result = loadPackage("invalid_on_error_return_type");
        assertEquals(result.errorCount(), 1);
        assertError(result, 0, "AZURE_FILES_110", "Expected error?");
    }

    @Test
    public void testOnErrorOnlyServiceStillNeedsContentHandler() {
        DiagnosticResult result = loadPackage("invalid_on_error_only");
        assertEquals(result.errorCount(), 1);
        assertError(result, 0, "AZURE_FILES_103", "At least one handler must be added");
    }

    @Test
    public void testValidOnFileByteStreamService() {
        DiagnosticResult result = loadPackage("valid_on_file_stream");
        assertEquals(result.errorCount(), 0, "expected no diagnostics for an onFile byte stream service");
    }

    @Test
    public void testValidOnFileCsvRecordArrayService() {
        DiagnosticResult result = loadPackage("valid_on_file_csv_record_array");
        assertEquals(result.errorCount(), 0, "expected no diagnostics for an onFileCsv record-array service");
    }

    @Test
    public void testValidOnFileCsvRecordStreamService() {
        DiagnosticResult result = loadPackage("valid_on_file_csv_stream_record");
        assertEquals(result.errorCount(), 0, "expected no diagnostics for an onFileCsv record stream service");
    }

    @Test
    public void testValidOnFileXmlRecordService() {
        DiagnosticResult result = loadPackage("valid_on_file_xml_record");
        assertEquals(result.errorCount(), 0, "expected no diagnostics for an onFileXml record service");
    }

    @Test
    public void testInvalidOnFileStreamItemType() {
        DiagnosticResult result = loadPackage("invalid_on_file_stream_item");
        assertEquals(result.errorCount(), 1);
        assertError(result, 0, "AZURE_FILES_106", "Invalid parameter type for onFile");
    }

    @Test
    public void testInvalidOnFileCsvStreamItemType() {
        DiagnosticResult result = loadPackage("invalid_on_file_csv_stream_item");
        assertEquals(result.errorCount(), 1);
        assertError(result, 0, "AZURE_FILES_106", "Invalid parameter type for onFileCsv");
    }

    @Test
    public void testInvalidOnFileCsvScalarArray() {
        DiagnosticResult result = loadPackage("invalid_on_file_csv_scalar_array");
        assertEquals(result.errorCount(), 1);
        assertError(result, 0, "AZURE_FILES_106", "Invalid parameter type for onFileCsv");
    }

    @Test
    public void testInvalidOnFileCsvStringMatrix() {
        DiagnosticResult result = loadPackage("invalid_on_file_csv_string_matrix");
        assertEquals(result.errorCount(), 1);
        assertError(result, 0, "AZURE_FILES_106", "Invalid parameter type for onFileCsv");
    }

    @Test
    public void testInvalidOnFileCsvStringArrayStream() {
        DiagnosticResult result = loadPackage("invalid_on_file_csv_stream_string_array");
        assertEquals(result.errorCount(), 1);
        assertError(result, 0, "AZURE_FILES_106", "Invalid parameter type for onFileCsv");
    }
}
