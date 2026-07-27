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

import io.ballerina.compiler.api.symbols.MethodSymbol;
import io.ballerina.compiler.api.symbols.ModuleSymbol;
import io.ballerina.compiler.api.symbols.ParameterSymbol;
import io.ballerina.compiler.api.symbols.Qualifier;
import io.ballerina.compiler.api.symbols.Symbol;
import io.ballerina.compiler.api.symbols.TypeDescKind;
import io.ballerina.compiler.api.symbols.TypeSymbol;
import io.ballerina.compiler.api.symbols.UnionTypeSymbol;
import io.ballerina.compiler.syntax.tree.FunctionDefinitionNode;
import io.ballerina.compiler.syntax.tree.ParameterNode;
import io.ballerina.compiler.syntax.tree.RequiredParameterNode;
import io.ballerina.lib.azure.storage.files.plugin.PluginConstants.CompilationErrors;
import io.ballerina.projects.plugins.SyntaxNodeAnalysisContext;
import io.ballerina.tools.diagnostics.Diagnostic;
import io.ballerina.tools.diagnostics.DiagnosticFactory;
import io.ballerina.tools.diagnostics.DiagnosticInfo;
import io.ballerina.tools.diagnostics.DiagnosticSeverity;
import io.ballerina.tools.diagnostics.Location;

import java.util.Optional;

import static io.ballerina.compiler.api.symbols.TypeDescKind.TYPE_REFERENCE;
import static io.ballerina.compiler.syntax.tree.SyntaxKind.QUALIFIED_NAME_REFERENCE;
import static io.ballerina.lib.azure.storage.files.plugin.PluginConstants.CALLER;
import static io.ballerina.lib.azure.storage.files.plugin.PluginConstants.CompilationErrors.INVALID_RETURN_TYPE_ERROR_OR_NIL;
import static io.ballerina.lib.azure.storage.files.plugin.PluginConstants.FILE_INFO;

/**
 * Shared helpers for the listener compiler plugin: diagnostic construction, module-identity and
 * remote-qualifier checks, parameter-type resolution, and the {@code error?} return validation.
 */
public final class PluginUtils {

    private PluginUtils() {
    }

    public static void reportErrorDiagnostic(SyntaxNodeAnalysisContext context, CompilationErrors error,
                                             Location location) {
        context.reportDiagnostic(getDiagnostic(error, DiagnosticSeverity.ERROR, location));
    }

    public static void reportErrorDiagnostic(SyntaxNodeAnalysisContext context, CompilationErrors error,
                                             Location location, Object... args) {
        context.reportDiagnostic(getDiagnostic(error, DiagnosticSeverity.ERROR, location, args));
    }

    public static Diagnostic getDiagnostic(CompilationErrors error, DiagnosticSeverity severity, Location location) {
        DiagnosticInfo diagnosticInfo = new DiagnosticInfo(error.getErrorCode(), error.getError(), severity);
        return DiagnosticFactory.createDiagnostic(diagnosticInfo, location);
    }

    public static Diagnostic getDiagnostic(CompilationErrors error, DiagnosticSeverity severity, Location location,
                                           Object... args) {
        String message = String.format(error.getError(), args);
        DiagnosticInfo diagnosticInfo = new DiagnosticInfo(error.getErrorCode(), message, severity);
        return DiagnosticFactory.createDiagnostic(diagnosticInfo, location);
    }

    public static boolean validateModuleId(ModuleSymbol moduleSymbol) {
        if (moduleSymbol == null) {
            return false;
        }
        String moduleName = moduleSymbol.id().moduleName();
        String orgName = moduleSymbol.id().orgName();
        return moduleName.equals(PluginConstants.PACKAGE_PREFIX) && orgName.equals(PluginConstants.PACKAGE_ORG);
    }

    public static boolean isRemoteFunction(SyntaxNodeAnalysisContext context,
                                           FunctionDefinitionNode functionDefinitionNode) {
        MethodSymbol methodSymbol = getMethodSymbol(context, functionDefinitionNode);
        return methodSymbol != null && methodSymbol.qualifiers().contains(Qualifier.REMOTE);
    }

    public static MethodSymbol getMethodSymbol(SyntaxNodeAnalysisContext context,
                                               FunctionDefinitionNode functionDefinitionNode) {
        Optional<Symbol> symbol = context.semanticModel().symbol(functionDefinitionNode);
        return symbol.map(value -> (MethodSymbol) value).orElse(null);
    }

    /**
     * Validates that a parameter is of type {@code files:FileInfo}.
     *
     * @param parameterNode the parameter to validate
     * @param context       the analysis context
     * @return {@code true} if the parameter is the connector's {@code FileInfo}
     */
    public static boolean validateFileInfoParameter(ParameterNode parameterNode, SyntaxNodeAnalysisContext context) {
        return validateQualifiedParameter(parameterNode, context, FILE_INFO);
    }

    /**
     * Validates that a parameter is of type {@code files:Caller}.
     *
     * @param parameterNode the parameter to validate
     * @param context       the analysis context
     * @return {@code true} if the parameter is the connector's {@code Caller}
     */
    public static boolean validateCallerParameter(ParameterNode parameterNode, SyntaxNodeAnalysisContext context) {
        return validateQualifiedParameter(parameterNode, context, CALLER);
    }

    private static boolean validateQualifiedParameter(ParameterNode parameterNode, SyntaxNodeAnalysisContext context,
                                                      String expectedTypeName) {
        if (!(parameterNode instanceof RequiredParameterNode requiredParameterNode)) {
            return false;
        }
        if (requiredParameterNode.typeName().kind() != QUALIFIED_NAME_REFERENCE) {
            return false;
        }
        Optional<TypeSymbol> typeSymbol = getParameterTypeSymbol(parameterNode, context);
        if (typeSymbol.isEmpty()) {
            return false;
        }
        Optional<ModuleSymbol> moduleSymbol = typeSymbol.get().getModule();
        if (moduleSymbol.isEmpty() || !validateModuleId(moduleSymbol.get())) {
            return false;
        }
        return typeSymbol.get().getName().map(expectedTypeName::equals).orElse(false);
    }

    public static Optional<TypeSymbol> getParameterTypeSymbol(ParameterNode parameterNode,
                                                              SyntaxNodeAnalysisContext context) {
        if (!(parameterNode instanceof RequiredParameterNode requiredParameterNode)) {
            return Optional.empty();
        }
        Optional<Symbol> symbol = context.semanticModel().symbol(requiredParameterNode);
        if (symbol.isEmpty() || !(symbol.get() instanceof ParameterSymbol parameterSymbol)) {
            return Optional.empty();
        }
        return Optional.ofNullable(parameterSymbol.typeDescriptor());
    }

    public static String getParameterTypeSignature(ParameterNode parameterNode, SyntaxNodeAnalysisContext context) {
        return getParameterTypeSymbol(parameterNode, context).map(TypeSymbol::signature).orElse("unknown");
    }

    /**
     * Validates that a handler's return type is {@code error?} (nil, an error, or a union of
     * them), reporting a diagnostic otherwise.
     *
     * @param functionDefinitionNode the handler
     * @param context                the analysis context
     */
    public static void validateReturnTypeErrorOrNil(FunctionDefinitionNode functionDefinitionNode,
                                                    SyntaxNodeAnalysisContext context) {
        MethodSymbol methodSymbol = getMethodSymbol(context, functionDefinitionNode);
        if (methodSymbol == null) {
            return;
        }
        Optional<TypeSymbol> returnTypeDesc = methodSymbol.typeDescriptor().returnTypeDescriptor();
        if (returnTypeDesc.isEmpty()) {
            return;
        }
        TypeSymbol returnType = returnTypeDesc.get();
        TypeDescKind kind = returnType.typeKind();
        if (kind == TypeDescKind.NIL) {
            return;
        }
        if (kind == TypeDescKind.ERROR || (kind == TYPE_REFERENCE && isValidErrorTypeReference(returnType))) {
            return;
        }
        if (kind == TypeDescKind.UNION && returnType instanceof UnionTypeSymbol unionTypeSymbol) {
            for (TypeSymbol memberType : unionTypeSymbol.memberTypeDescriptors()) {
                TypeDescKind memberKind = memberType.typeKind();
                if (!(memberKind == TypeDescKind.NIL || memberKind == TypeDescKind.ERROR
                        || (memberKind == TYPE_REFERENCE && isValidErrorTypeReference(memberType)))) {
                    context.reportDiagnostic(getDiagnostic(INVALID_RETURN_TYPE_ERROR_OR_NIL, DiagnosticSeverity.ERROR,
                            functionDefinitionNode.functionSignature().location()));
                    return;
                }
            }
            return;
        }
        context.reportDiagnostic(getDiagnostic(INVALID_RETURN_TYPE_ERROR_OR_NIL, DiagnosticSeverity.ERROR,
                functionDefinitionNode.functionSignature().location()));
    }

    private static boolean isValidErrorTypeReference(TypeSymbol typeSymbol) {
        if (typeSymbol.typeKind() != TYPE_REFERENCE) {
            return false;
        }
        if (typeSymbol.signature().equals(PluginConstants.ERROR)) {
            return true;
        }
        Optional<ModuleSymbol> module = typeSymbol.getModule();
        return module.map(PluginUtils::validateModuleId).orElse(true);
    }
}
