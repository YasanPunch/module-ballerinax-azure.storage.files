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

import io.ballerina.compiler.api.symbols.ArrayTypeSymbol;
import io.ballerina.compiler.api.symbols.MapTypeSymbol;
import io.ballerina.compiler.api.symbols.StreamTypeSymbol;
import io.ballerina.compiler.api.symbols.TypeDescKind;
import io.ballerina.compiler.api.symbols.TypeReferenceTypeSymbol;
import io.ballerina.compiler.api.symbols.TypeSymbol;
import io.ballerina.compiler.syntax.tree.FunctionDefinitionNode;
import io.ballerina.compiler.syntax.tree.ParameterNode;
import io.ballerina.compiler.syntax.tree.SeparatedNodeList;
import io.ballerina.projects.plugins.SyntaxNodeAnalysisContext;

import java.util.Optional;

import static io.ballerina.compiler.api.symbols.TypeDescKind.ARRAY;
import static io.ballerina.compiler.api.symbols.TypeDescKind.BYTE;
import static io.ballerina.compiler.api.symbols.TypeDescKind.JSON;
import static io.ballerina.compiler.api.symbols.TypeDescKind.MAP;
import static io.ballerina.compiler.api.symbols.TypeDescKind.RECORD;
import static io.ballerina.compiler.api.symbols.TypeDescKind.STREAM;
import static io.ballerina.compiler.api.symbols.TypeDescKind.STRING;
import static io.ballerina.compiler.api.symbols.TypeDescKind.TYPE_REFERENCE;
import static io.ballerina.compiler.api.symbols.TypeDescKind.XML;
import static io.ballerina.lib.azure.storage.files.plugin.PluginConstants.CompilationErrors.CONTENT_METHOD_MUST_BE_REMOTE;
import static io.ballerina.lib.azure.storage.files.plugin.PluginConstants.CompilationErrors.INVALID_CALLER_PARAMETER;
import static io.ballerina.lib.azure.storage.files.plugin.PluginConstants.CompilationErrors.INVALID_CONTENT_PARAMETER_TYPE;
import static io.ballerina.lib.azure.storage.files.plugin.PluginConstants.CompilationErrors.INVALID_FILEINFO_PARAMETER;
import static io.ballerina.lib.azure.storage.files.plugin.PluginConstants.CompilationErrors.MANDATORY_PARAMETER_NOT_FOUND;
import static io.ballerina.lib.azure.storage.files.plugin.PluginConstants.CompilationErrors.TOO_MANY_PARAMETERS;
import static io.ballerina.lib.azure.storage.files.plugin.PluginConstants.ON_FILE_CSV_FUNC;
import static io.ballerina.lib.azure.storage.files.plugin.PluginConstants.ON_FILE_FUNC;
import static io.ballerina.lib.azure.storage.files.plugin.PluginConstants.ON_FILE_JSON_FUNC;
import static io.ballerina.lib.azure.storage.files.plugin.PluginConstants.ON_FILE_TEXT_FUNC;
import static io.ballerina.lib.azure.storage.files.plugin.PluginConstants.ON_FILE_XML_FUNC;
import static io.ballerina.lib.azure.storage.files.plugin.PluginUtils.isRemoteFunction;
import static io.ballerina.lib.azure.storage.files.plugin.PluginUtils.reportErrorDiagnostic;

/**
 * Validates one content handler's signature: it must be {@code remote}, 
 * 
 * its first parameter must carry the handler's content type;
 * onFile: {@code byte[]} or a byte stream; 
 * onFileText: {@code string}; 
 * onFileJson: {@code json}, a {@code map<json>}, a record, or an array of them;
 * onFileXml: {@code xml} or a record; 
 * onFileCsv: {@code string[][]}, a record array, or a stream of {@code string[]} or records), 
 * 
 * an optional second parameter must be {@code FileInfo}, 
 * an optional third must be {@code Caller}, 
 * and the return type must be {@code error?}.
 *
 *  checks each handler's exact signature (remote, correct content type for param 1,
 *  optional FileInfo/Caller params, error? return).
 */
public class ContentFunctionValidator {

    private final SyntaxNodeAnalysisContext context;
    private final FunctionDefinitionNode funcDefinitionNode;
    private final String contentMethodName;

    public ContentFunctionValidator(SyntaxNodeAnalysisContext context, FunctionDefinitionNode funcDefinitionNode,
                                    String contentMethodName) {
        this.context = context;
        this.funcDefinitionNode = funcDefinitionNode;
        this.contentMethodName = contentMethodName;
    }

    public void validate() {
        if (!isRemoteFunction(context, funcDefinitionNode)) {
            reportErrorDiagnostic(context, CONTENT_METHOD_MUST_BE_REMOTE, funcDefinitionNode.location(),
                    contentMethodName);
        }
        validateParameters(funcDefinitionNode.functionSignature().parameters());
        PluginUtils.validateReturnTypeErrorOrNil(funcDefinitionNode, context);
    }

    private void validateParameters(SeparatedNodeList<ParameterNode> parameters) {
        if (parameters.isEmpty()) {
            reportErrorDiagnostic(context, MANDATORY_PARAMETER_NOT_FOUND, funcDefinitionNode.location(),
                    contentMethodName, expectedContentType());
            return;
        }
        if (parameters.size() > 3) {
            reportErrorDiagnostic(context, TOO_MANY_PARAMETERS, funcDefinitionNode.location(), contentMethodName);
            return;
        }
        ParameterNode firstParameter = parameters.get(0);
        if (!validateContentParameter(firstParameter)) {
            reportErrorDiagnostic(context, INVALID_CONTENT_PARAMETER_TYPE, firstParameter.location(),
                    contentMethodName, expectedContentType(),
                    PluginUtils.getParameterTypeSignature(firstParameter, context));
        }
        if (parameters.size() == 1) {
            return;
        }
        if (parameters.size() == 2) {
            if (PluginUtils.validateFileInfoParameter(parameters.get(1), context)) {
                return;
            }
            if (!PluginUtils.validateCallerParameter(parameters.get(1), context)) {
                reportErrorDiagnostic(context, INVALID_FILEINFO_PARAMETER, parameters.get(1).location(),
                        contentMethodName);
            }
            return;
        }
        if (!PluginUtils.validateFileInfoParameter(parameters.get(1), context)) {
            reportErrorDiagnostic(context, INVALID_FILEINFO_PARAMETER, parameters.get(1).location(), contentMethodName);
            return;
        }
        if (!PluginUtils.validateCallerParameter(parameters.get(2), context)) {
            reportErrorDiagnostic(context, INVALID_CALLER_PARAMETER, parameters.get(2).location(), contentMethodName);
        }
    }

    /**
     * Validates the content parameter of a content handler.
     * 
     * Validates the declared type of the handler's first parameter (the content parameter)). 
     * Per handler: onFile → byte[], onFileText → string, onFileXml → xml,
     * onFileCsv → string[][], onFileJson → json | map<json> | record | array of those.
     * 
     * @param parameterNode the parameter node
     * @return true if the content parameter is valid, false otherwise
     */
    private boolean validateContentParameter(ParameterNode parameterNode) {
        Optional<TypeSymbol> typeSymbolOpt = PluginUtils.getParameterTypeSymbol(parameterNode, context);
        if (typeSymbolOpt.isEmpty()) {
            return false;
        }
        TypeSymbol typeSymbol = typeSymbolOpt.get();
        TypeDescKind typeKind = typeSymbol.typeKind();
        return switch (contentMethodName) {
            case ON_FILE_FUNC -> isByteArray(typeSymbol, typeKind) || isByteStream(typeSymbol, typeKind);
            case ON_FILE_TEXT_FUNC -> typeKind == STRING;
            case ON_FILE_JSON_FUNC -> isJsonObject(typeSymbol, typeKind) || isJsonObjectArray(typeSymbol, typeKind);
            case ON_FILE_XML_FUNC -> typeKind == XML || typeKind == RECORD || isRecordTypeReference(typeSymbol);
            case ON_FILE_CSV_FUNC -> isStringArrayOfArray(typeSymbol, typeKind)
                    || isRecordArray(typeSymbol, typeKind) || isCsvStream(typeSymbol, typeKind);
            default -> false;
        };
    }

    private boolean isJsonObject(TypeSymbol typeSymbol, TypeDescKind typeKind) {
        return typeKind == JSON || isJsonMap(typeSymbol, typeKind) || typeKind == RECORD
                || isRecordTypeReference(typeSymbol);
    }

    private boolean isJsonObjectArray(TypeSymbol typeSymbol, TypeDescKind typeKind) {
        if (typeKind != ARRAY) {
            return false;
        }
        TypeSymbol member = ((ArrayTypeSymbol) typeSymbol).memberTypeDescriptor();
        return isJsonObject(member, member.typeKind());
    }

    private boolean isByteArray(TypeSymbol typeSymbol, TypeDescKind typeKind) {
        return typeKind == ARRAY && ((ArrayTypeSymbol) typeSymbol).memberTypeDescriptor().typeKind() == BYTE;
    }

    private boolean isJsonMap(TypeSymbol typeSymbol, TypeDescKind typeKind) {
        return typeKind == MAP && ((MapTypeSymbol) typeSymbol).typeParam().typeKind() == JSON;
    }

    private boolean isStringArrayOfArray(TypeSymbol typeSymbol, TypeDescKind typeKind) {
        if (typeKind != ARRAY) {
            return false;
        }
        TypeSymbol member = ((ArrayTypeSymbol) typeSymbol).memberTypeDescriptor();
        return member.typeKind() == ARRAY && ((ArrayTypeSymbol) member).memberTypeDescriptor().typeKind() == STRING;
    }

    private boolean isByteStream(TypeSymbol typeSymbol, TypeDescKind typeKind) {
        if (typeKind != STREAM) {
            return false;
        }
        TypeSymbol itemType = ((StreamTypeSymbol) typeSymbol).typeParameter();
        return isByteArray(itemType, itemType.typeKind());
    }

    private boolean isRecordArray(TypeSymbol typeSymbol, TypeDescKind typeKind) {
        if (typeKind != ARRAY) {
            return false;
        }
        TypeSymbol member = ((ArrayTypeSymbol) typeSymbol).memberTypeDescriptor();
        return member.typeKind() == RECORD || isRecordTypeReference(member);
    }

    private boolean isCsvStream(TypeSymbol typeSymbol, TypeDescKind typeKind) {
        if (typeKind != STREAM) {
            return false;
        }
        TypeSymbol itemType = ((StreamTypeSymbol) typeSymbol).typeParameter();
        TypeDescKind itemKind = itemType.typeKind();
        if (itemKind == RECORD || isRecordTypeReference(itemType)) {
            return true;
        }
        return itemKind == ARRAY && ((ArrayTypeSymbol) itemType).memberTypeDescriptor().typeKind() == STRING;
    }

    private boolean isRecordTypeReference(TypeSymbol typeSymbol) {
        if (typeSymbol.typeKind() != TYPE_REFERENCE) {
            return false;
        }
        TypeSymbol referredType = ((TypeReferenceTypeSymbol) typeSymbol).typeDescriptor();
        return referredType != null && referredType.typeKind() == RECORD;
    }

    private String expectedContentType() {
        return switch (contentMethodName) {
            case ON_FILE_FUNC -> "byte[] or stream<byte[], error?>";
            case ON_FILE_TEXT_FUNC -> "string";
            case ON_FILE_JSON_FUNC -> "json, map<json>, a record, or an array of them";
            case ON_FILE_XML_FUNC -> "xml or a record";
            case ON_FILE_CSV_FUNC -> "string[][], record{}[], stream<string[], error?>, "
                    + "or stream<record{}, error?>";
            default -> "unknown";
        };
    }
}
