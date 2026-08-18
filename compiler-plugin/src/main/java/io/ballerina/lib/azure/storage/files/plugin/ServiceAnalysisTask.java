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
 * Runs on every service declaration, skipping services whose package already has compilation
 * errors and services not attached to the connector's {@code Listener} (the plugin must not
 * fire on other listeners' services in the same file).
 */
public class ServiceAnalysisTask implements AnalysisTask<SyntaxNodeAnalysisContext> {

    private final ServiceValidator serviceValidator;

    /**
     * Constructs a new ServiceAnalysisTask.
     */
    public ServiceAnalysisTask() {
        this.serviceValidator = new ServiceValidator();
    }

    @Override
    public void perform(SyntaxNodeAnalysisContext context) {
        for (Diagnostic diagnostic : context.semanticModel().diagnostics()) {
            if (diagnostic.diagnosticInfo().severity() == DiagnosticSeverity.ERROR) {
                return;
            }
        }
        if (!isAzureFilesService(context)) {
            return;
        }
        serviceValidator.validate(context);
    }

    // True when the service's attached listener is this module's Listener.
    private boolean isAzureFilesService(SyntaxNodeAnalysisContext context) {
        SemanticModel semanticModel = context.semanticModel();
        ServiceDeclarationNode serviceDeclarationNode = (ServiceDeclarationNode) context.node();
        Optional<Symbol> symbol = semanticModel.symbol(serviceDeclarationNode);
        if (symbol.isEmpty()) {
            return false;
        }
        List<TypeSymbol> listeners = ((ServiceDeclarationSymbol) symbol.get()).listenerTypes();
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

    // True when the listener type symbol resolves to this module's Listener class.
    private boolean isAzureFilesListener(TypeSymbol listener) {
        if (listener.typeKind() == TypeDescKind.UNION) {
            for (TypeSymbol member : ((UnionTypeSymbol) listener).memberTypeDescriptors()) {
                Optional<ModuleSymbol> module = member.getModule();
                if (module.isPresent() && validateModuleId(module.get())) {
                    return true;
                }
            }
            return false;
        }
        Optional<ModuleSymbol> module = listener.getModule();
        return module.isPresent() && validateModuleId(module.get());
    }
}
