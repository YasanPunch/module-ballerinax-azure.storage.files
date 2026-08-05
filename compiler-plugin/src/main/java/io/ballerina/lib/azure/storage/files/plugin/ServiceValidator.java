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
import io.ballerina.compiler.syntax.tree.FunctionDefinitionNode;
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
import static io.ballerina.lib.azure.storage.files.plugin.PluginConstants.CompilationErrors.NO_VALID_REMOTE_METHOD;
import static io.ballerina.lib.azure.storage.files.plugin.PluginConstants.CompilationErrors.RESOURCE_FUNCTION_NOT_ALLOWED;
import static io.ballerina.lib.azure.storage.files.plugin.PluginUtils.getDiagnostic;
import static io.ballerina.lib.azure.storage.files.plugin.PluginUtils.getMethodSymbol;
import static io.ballerina.lib.azure.storage.files.plugin.PluginUtils.isRemoteFunction;

/**
 * Validates a listener service's members: resource functions are rejected, every remote method
 * must be one of the content handlers or the optional {@code onError}, at least one content
 * handler must be present, and each declared handler's signature is checked by
 * {@link ContentFunctionValidator} (content handlers) or {@link OnErrorFunctionValidator}. 
 * 
 * The watched path is the service's attach point (share root when absent), so no annotation is
 * required.
 *
 * Enforces: no resource functions, no unknown remote methods, ≥1 content handler
 */
public class ServiceValidator {

    /**
     * Validates a listener service's members.
     * 
     * @param context the syntax node analysis context
     */
    public void validate(SyntaxNodeAnalysisContext context) {
        // Get the service declaration node.
        ServiceDeclarationNode serviceDeclarationNode = (ServiceDeclarationNode) context.node();
        // Get the members of the service declaration.
        NodeList<Node> members = serviceDeclarationNode.members();
        // Create a list of content methods.
        List<FunctionDefinitionNode> contentMethods = new ArrayList<>();
        // Create a list of content method names.
        List<String> contentMethodNames = new ArrayList<>();

        // Iterate over the members.
        for (Node node : members) {
            // If the node is a resource accessor definition, report a diagnostic.
            if (node.kind() == RESOURCE_ACCESSOR_DEFINITION) {
                context.reportDiagnostic(getDiagnostic(RESOURCE_FUNCTION_NOT_ALLOWED,
                        DiagnosticSeverity.ERROR, node.location()));
                continue;
            }
            // If the node is not an object method definition, continue.
            if (node.kind() != SyntaxKind.OBJECT_METHOD_DEFINITION) {
                continue;
            }
            // Get the function definition node.
            FunctionDefinitionNode functionDefinitionNode = (FunctionDefinitionNode) node;
            // Get the method symbol.
            MethodSymbol methodSymbol = getMethodSymbol(context, functionDefinitionNode);
            // If the method symbol is null, continue.
            if (methodSymbol == null) {
                continue;
            }
            // Get the name of the method.
            Optional<String> functionName = methodSymbol.getName();
            if (functionName.isEmpty()) {
                continue;
            }
            String name = functionName.get();
            // If the method name is a content handler, add it to the content methods list.
            if (CONTENT_HANDLERS.contains(name)) {
                contentMethods.add(functionDefinitionNode);
                contentMethodNames.add(name);
            // If the method name is the onError handler, validate it separately.
            } else if (PluginConstants.ON_ERROR_FUNC.equals(name)) {
                // onError is validated separately and deliberately not added to contentMethods:
                // a service declaring only onError still fails the at-least-one-handler check.
                new OnErrorFunctionValidator(context, functionDefinitionNode).validate();
            } else if (isRemoteFunction(context, functionDefinitionNode)) {
                context.reportDiagnostic(getDiagnostic(INVALID_REMOTE_FUNCTION,
                        DiagnosticSeverity.ERROR, functionDefinitionNode.location(), name));
            }
        }

        // If there are no content methods, report a diagnostic.
        if (contentMethods.isEmpty()) {
            context.reportDiagnostic(getDiagnostic(NO_VALID_REMOTE_METHOD,
                    DiagnosticSeverity.ERROR, serviceDeclarationNode.location()));
            return;
        }

        // Validate each content method.
        for (int i = 0; i < contentMethods.size(); i++) {
            new ContentFunctionValidator(context, contentMethods.get(i), contentMethodNames.get(i)).validate();
        }
    }

}
