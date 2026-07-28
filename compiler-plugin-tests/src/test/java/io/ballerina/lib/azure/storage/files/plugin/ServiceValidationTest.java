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
    public void testValidTypedJsonService() {
        DiagnosticResult result = loadPackage("valid_on_file_json");
        assertEquals(result.errorCount(), 0, "expected no diagnostics for a valid onFileJson service");
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
    public void testValidTypedJsonMapArrayService() {
        DiagnosticResult result = loadPackage("valid_on_file_json_map_array");
        assertEquals(result.errorCount(), 0, "expected no diagnostics for an onFileJson map<json>[] service");
    }

    @Test
    public void testValidTypedJsonRecordArrayService() {
        DiagnosticResult result = loadPackage("valid_on_file_json_record_array");
        assertEquals(result.errorCount(), 0, "expected no diagnostics for an onFileJson record-array service");
    }

    @Test
    public void testInvalidOnFileJsonJsonArray() {
        DiagnosticResult result = loadPackage("invalid_on_file_json_json_array");
        assertEquals(result.errorCount(), 1);
        assertError(result, 0, "AZURE_FILES_106", "Invalid parameter type for onFileJson");
    }

    @Test
    public void testInvalidOnFileJsonBareJson() {
        DiagnosticResult result = loadPackage("invalid_on_file_json_bare");
        assertEquals(result.errorCount(), 1);
        assertError(result, 0, "AZURE_FILES_106", "Invalid parameter type for onFileJson");
    }

    @Test
    public void testValidServiceConfigService() {
        DiagnosticResult result = loadPackage("valid_service_config");
        assertEquals(result.errorCount(), 0, "expected no diagnostics for a valid annotated service");
    }

    @Test
    public void testMissingServiceConfigAnnotation() {
        DiagnosticResult result = loadPackage("invalid_missing_service_config");
        assertEquals(result.errorCount(), 1);
        assertError(result, 0, "AZURE_FILES_111", "Missing @files:ServiceConfig annotation");
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
}
