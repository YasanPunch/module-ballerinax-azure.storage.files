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

import io.ballerina.compiler.api.symbols.AnnotationSymbol;
import io.ballerina.compiler.api.symbols.MethodSymbol;
import io.ballerina.compiler.api.symbols.Symbol;
import io.ballerina.compiler.syntax.tree.AnnotationNode;
import io.ballerina.compiler.syntax.tree.FunctionDefinitionNode;
import io.ballerina.compiler.syntax.tree.MetadataNode;
import io.ballerina.compiler.syntax.tree.Node;
import io.ballerina.compiler.syntax.tree.NodeList;
import io.ballerina.compiler.syntax.tree.ServiceDeclarationNode;
import io.ballerina.compiler.syntax.tree.SyntaxKind;
import io.ballerina.projects.plugins.SyntaxNodeAnalysisContext;
import io.ballerina.tools.diagnostics.DiagnosticSeverity;

import java.util.ArrayList;
import java.util.List;
import java.util.Optional;

import static io.ballerina.compiler.syntax.tree.SyntaxKind.RESOURCE_ACCESSOR_DEFINITION;
import static io.ballerina.lib.azure.storage.files.plugin.PluginConstants.CONTENT_HANDLERS;
import static io.ballerina.lib.azure.storage.files.plugin.PluginConstants.CompilationErrors.INVALID_REMOTE_FUNCTION;
import static io.ballerina.lib.azure.storage.files.plugin.PluginConstants.CompilationErrors.MISSING_SERVICE_CONFIG_ANNOTATION;
import static io.ballerina.lib.azure.storage.files.plugin.PluginConstants.CompilationErrors.NO_VALID_REMOTE_METHOD;
import static io.ballerina.lib.azure.storage.files.plugin.PluginConstants.CompilationErrors.RESOURCE_FUNCTION_NOT_ALLOWED;
import static io.ballerina.lib.azure.storage.files.plugin.PluginConstants.SERVICE_CONFIG_ANNOTATION;
import static io.ballerina.lib.azure.storage.files.plugin.PluginUtils.getDiagnostic;
import static io.ballerina.lib.azure.storage.files.plugin.PluginUtils.getMethodSymbol;
import static io.ballerina.lib.azure.storage.files.plugin.PluginUtils.isRemoteFunction;

/**
 * Validates a listener service's members: resource functions are rejected, every remote method
 * must be one of the content handlers, at least one content handler must be present, and each
 * declared handler's signature is checked by {@link ContentFunctionValidator}.
 */
public class ServiceValidator {

    public void validate(SyntaxNodeAnalysisContext context) {
        ServiceDeclarationNode serviceDeclarationNode = (ServiceDeclarationNode) context.node();
        if (!hasServiceConfigAnnotation(context, serviceDeclarationNode)) {
            context.reportDiagnostic(getDiagnostic(MISSING_SERVICE_CONFIG_ANNOTATION,
                    DiagnosticSeverity.ERROR, serviceDeclarationNode.location()));
        }
        NodeList<Node> members = serviceDeclarationNode.members();

        List<FunctionDefinitionNode> contentMethods = new ArrayList<>();
        List<String> contentMethodNames = new ArrayList<>();

        for (Node node : members) {
            if (node.kind() == RESOURCE_ACCESSOR_DEFINITION) {
                context.reportDiagnostic(getDiagnostic(RESOURCE_FUNCTION_NOT_ALLOWED,
                        DiagnosticSeverity.ERROR, node.location()));
                continue;
            }
            if (node.kind() != SyntaxKind.OBJECT_METHOD_DEFINITION) {
                continue;
            }
            FunctionDefinitionNode functionDefinitionNode = (FunctionDefinitionNode) node;
            MethodSymbol methodSymbol = getMethodSymbol(context, functionDefinitionNode);
            if (methodSymbol == null) {
                continue;
            }
            Optional<String> functionName = methodSymbol.getName();
            if (functionName.isEmpty()) {
                continue;
            }
            String name = functionName.get();
            if (CONTENT_HANDLERS.contains(name)) {
                contentMethods.add(functionDefinitionNode);
                contentMethodNames.add(name);
            } else if (isRemoteFunction(context, functionDefinitionNode)) {
                context.reportDiagnostic(getDiagnostic(INVALID_REMOTE_FUNCTION,
                        DiagnosticSeverity.ERROR, functionDefinitionNode.location(), name));
            }
        }

        if (contentMethods.isEmpty()) {
            context.reportDiagnostic(getDiagnostic(NO_VALID_REMOTE_METHOD,
                    DiagnosticSeverity.ERROR, serviceDeclarationNode.location()));
            return;
        }

        for (int i = 0; i < contentMethods.size(); i++) {
            new ContentFunctionValidator(context, contentMethods.get(i), contentMethodNames.get(i)).validate();
        }
    }

    // The watched path has no home other than @files:ServiceConfig (no listener-level fallback),
    // so the annotation itself is mandatory; its required 'path' field is then enforced by the
    // type checker.
    private boolean hasServiceConfigAnnotation(SyntaxNodeAnalysisContext context,
                                               ServiceDeclarationNode serviceDeclarationNode) {
        Optional<MetadataNode> metadata = serviceDeclarationNode.metadata();
        if (metadata.isEmpty()) {
            return false;
        }
        for (AnnotationNode annotation : metadata.get().annotations()) {
            Optional<Symbol> symbol = context.semanticModel().symbol(annotation);
            if (symbol.isEmpty() || !(symbol.get() instanceof AnnotationSymbol annotationSymbol)) {
                continue;
            }
            boolean isServiceConfig = annotationSymbol.getName()
                    .map(SERVICE_CONFIG_ANNOTATION::equals).orElse(false);
            boolean isOurModule = annotationSymbol.getModule()
                    .map(PluginUtils::validateModuleId).orElse(false);
            if (isServiceConfig && isOurModule) {
                return true;
            }
        }
        return false;
    }
}
