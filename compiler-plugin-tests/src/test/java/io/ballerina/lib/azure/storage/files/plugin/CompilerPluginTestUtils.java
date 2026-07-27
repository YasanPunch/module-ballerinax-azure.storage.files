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
import io.ballerina.projects.Package;
import io.ballerina.projects.PackageCompilation;
import io.ballerina.projects.ProjectEnvironmentBuilder;
import io.ballerina.projects.directory.BuildProject;
import io.ballerina.projects.environment.Environment;
import io.ballerina.projects.environment.EnvironmentBuilder;
import io.ballerina.tools.diagnostics.Diagnostic;

import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.List;

import static org.testng.Assert.assertEquals;
import static org.testng.Assert.assertTrue;

/**
 * Loads the sample listener projects through the Ballerina project API and exposes their
 * compilation diagnostics to the tests, so the listener compiler plugin runs exactly as it would
 * during a real package build.
 */
final class CompilerPluginTestUtils {

    static final Path RESOURCE_DIRECTORY = Paths.get("src", "test", "resources", "ballerina_sources")
            .toAbsolutePath();

    private CompilerPluginTestUtils() {
    }

    static DiagnosticResult loadPackage(String path) {
        Path projectDirPath = RESOURCE_DIRECTORY.resolve(path);
        BuildProject project = BuildProject.load(getEnvironmentBuilder(), projectDirPath);
        Package currentPackage = project.currentPackage();
        PackageCompilation compilation = currentPackage.getCompilation();
        return compilation.diagnosticResult();
    }

    static void assertError(DiagnosticResult result, int index, String expectedCode, String expectedMessage) {
        List<Diagnostic> errors = result.errors().stream().toList();
        assertTrue(errors.size() > index,
                "expected at least " + (index + 1) + " error(s), found " + errors.size());
        Diagnostic diagnostic = errors.get(index);
        assertEquals(diagnostic.diagnosticInfo().code(), expectedCode,
                "unexpected diagnostic code: " + diagnostic.message());
        assertTrue(diagnostic.message().contains(expectedMessage),
                "expected message to contain '" + expectedMessage + "', found: " + diagnostic.message());
    }

    private static ProjectEnvironmentBuilder getEnvironmentBuilder() {
        Environment environment = EnvironmentBuilder.getBuilder().setBallerinaHome(distributionPath()).build();
        return ProjectEnvironmentBuilder.getBuilder(environment);
    }

    private static Path distributionPath() {
        String home = System.getProperty("ballerina.home");
        if (home == null || home.isBlank()) {
            home = System.getenv("BALLERINA_HOME");
        }
        if (home == null || home.isBlank()) {
            home = resolveFromCli();
        }
        Path path = Paths.get(home);
        if (!Files.exists(path)) {
            throw new IllegalStateException("the Ballerina distribution was not found at: " + path);
        }
        return path;
    }

    private static String resolveFromCli() {
        try {
            Process process = new ProcessBuilder("bal", "home").redirectErrorStream(false).start();
            try (BufferedReader reader = new BufferedReader(
                    new InputStreamReader(process.getInputStream(), StandardCharsets.UTF_8))) {
                String line = reader.readLine();
                process.waitFor();
                if (line != null && !line.isBlank()) {
                    return line.trim();
                }
            }
        } catch (IOException e) {
            throw new IllegalStateException("unable to resolve the Ballerina distribution from the CLI", e);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            throw new IllegalStateException("interrupted while resolving the Ballerina distribution", e);
        }
        throw new IllegalStateException("the Ballerina distribution could not be resolved");
    }
}
