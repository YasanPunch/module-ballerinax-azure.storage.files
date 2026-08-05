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

import io.ballerina.compiler.api.SemanticModel;
import io.ballerina.compiler.api.symbols.ModuleSymbol;
import io.ballerina.compiler.api.symbols.ServiceDeclarationSymbol;
import io.ballerina.compiler.api.symbols.Symbol;
import io.ballerina.compiler.api.symbols.TypeDescKind;
import io.ballerina.compiler.api.symbols.TypeSymbol;
import io.ballerina.compiler.api.symbols.UnionTypeSymbol;
import io.ballerina.compiler.syntax.tree.ServiceDeclarationNode;
import io.ballerina.projects.plugins.AnalysisTask;
import io.ballerina.projects.plugins.SyntaxNodeAnalysisContext;
import io.ballerina.tools.diagnostics.Diagnostic;
import io.ballerina.tools.diagnostics.DiagnosticSeverity;

import java.util.List;
import java.util.Optional;

import static io.ballerina.lib.azure.storage.files.plugin.PluginUtils.validateModuleId;

/**
 * Runs on every service declaration. It skips services whose package already has compilation
 * errors and services not attached to the connector's {@code Listener}.
 * 
 * Checks the service is attached to our Listener (otherwise it stays silent — it must not
 * fire on http/ftp services in the same file)
 */
public class ServiceAnalysisTask implements AnalysisTask<SyntaxNodeAnalysisContext> {

    private final ServiceValidator serviceValidator;

    /**
     * Constructs a new ServiceAnalysisTask.
     */
    public ServiceAnalysisTask() {
        // Delegate the handler-set validation to ServiceValidator.
        this.serviceValidator = new ServiceValidator();
    }

    /**
     * Performs the analysis task. It skips services whose package already has compilation
     * errors and services not attached to the listener.
     * 
     * @param context the syntax node analysis context
     */
    @Override
    public void perform(SyntaxNodeAnalysisContext context) {
        // If there are any compilation errors, return.
        for (Diagnostic diagnostic : context.semanticModel().diagnostics()) {
            if (diagnostic.diagnosticInfo().severity() == DiagnosticSeverity.ERROR) {
                return;
            }
        }
        // If the service is not an Azure Files service, return.
        if (!isAzureFilesService(context)) {
            return;
        }
        serviceValidator.validate(context);
    }

    /**
     * Checks if the service is an Azure Files service.
     * 
     * @param context the syntax node analysis context
     * @return true if the service is an Azure Files service, false otherwise
     */
    private boolean isAzureFilesService(SyntaxNodeAnalysisContext context) {
        // Get the semantic model.
        SemanticModel semanticModel = context.semanticModel();
        // Get the service declaration node.
        ServiceDeclarationNode serviceDeclarationNode = (ServiceDeclarationNode) context.node();
        // Get the symbol for the service declaration.
        Optional<Symbol> symbol = semanticModel.symbol(serviceDeclarationNode);
        // If the symbol is not present, return false.
        if (symbol.isEmpty()) {
            return false;
        }
        // Get the listener types for the service declaration.
        List<TypeSymbol> listeners = ((ServiceDeclarationSymbol) symbol.get()).listenerTypes();
        // If the listeners are empty, return false.
        if (listeners.isEmpty()) {
            return false;
        }
        for (TypeSymbol listener : listeners) {
            if (!isAzureFilesListener(listener)) {
                return false;
            }
        }
        return true;
    }

    /**
     * Checks if the listener is an Azure Files listener.
     * 
     * @param listener the listener type symbol
     * @return true if the listener is an Azure Files listener, false otherwise
     */
    private boolean isAzureFilesListener(TypeSymbol listener) {
        // If the listener is a union type, check if any of the member types are an Azure Files listener.
        if (listener.typeKind() == TypeDescKind.UNION) {
            for (TypeSymbol member : ((UnionTypeSymbol) listener).memberTypeDescriptors()) {
                // Get the module for the member type.
                Optional<ModuleSymbol> module = member.getModule();
                // If the module is present and the module ID is valid, return true.
                if (module.isPresent() && validateModuleId(module.get())) {
                    return true;
                }
            }
            return false;
        }
        // Get the module for the listener.
        Optional<ModuleSymbol> module = listener.getModule();
        // If the module is present and the module ID is valid, return true.
        return module.isPresent() && validateModuleId(module.get());
    }
}
