/*
 * Copyright (c) 2026, WSO2 LLC. (https://www.wso2.com).
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

package io.ballerina.lib.azure.storage.files;

import com.azure.core.credential.AzureNamedKeyCredential;
import com.azure.core.credential.AzureSasCredential;
import com.azure.core.http.policy.HttpPipelinePolicy;
import com.azure.core.util.UrlBuilder;
import com.azure.storage.file.share.ShareServiceClient;
import com.azure.storage.file.share.ShareServiceClientBuilder;
import io.ballerina.runtime.api.values.BError;
import io.ballerina.runtime.api.values.BMap;
import io.ballerina.runtime.api.values.BObject;
import io.ballerina.runtime.api.values.BString;

import java.net.URI;
import java.net.URISyntaxException;
import java.util.Base64;

/**
 * Builds the SDK clients from the Ballerina {@code ClientConfiguration}. The union member is
 * selected structurally by the fields present on the auth record, mirroring the compiler's own
 * structural matching. Every mode is validated locally, with no call to Azure, so a
 * misconfiguration fails at {@code init} while initialization stays lazy.
 */
public final class ClientInit {

    private ClientInit() {
    }

    /**
     * Initializes the account-level {@code AdminClient}.
     *
     * @param self   the Ballerina client object
     * @param config the {@code ClientConfiguration} record
     * @return {@code null} on success, or the validation error
     */
    public static Object initAdminClient(BObject self, BMap<BString, Object> config) {
        try {
            self.addNativeData(Constants.NATIVE_SERVICE_CLIENT, buildServiceClient(config));
            return null;
        } catch (BError e) {
            return e;
        } catch (Exception e) {
            return FilesErrorCreator.processingError(Ops.describe(e), e);
        }
    }

    /**
     * Initializes the share-bound {@code Client}.
     *
     * @param self      the Ballerina client object
     * @param shareName the share the client is bound to
     * @param config    the {@code ClientConfiguration} record
     * @return {@code null} on success, or the validation error
     */
    public static Object initClient(BObject self, BString shareName, BMap<BString, Object> config) {
        try {
            String share = shareName.getValue().strip();
            if (share.isEmpty()) {
                return FilesErrorCreator.processingError("shareName must not be empty", null);
            }
            ShareServiceClient serviceClient = buildServiceClient(config);
            self.addNativeData(Constants.NATIVE_SERVICE_CLIENT, serviceClient);
            self.addNativeData(Constants.NATIVE_SHARE_CLIENT, serviceClient.getShareClient(share));
            return null;
        } catch (BError e) {
            return e;
        } catch (Exception e) {
            return FilesErrorCreator.processingError(Ops.describe(e), e);
        }
    }

    /**
     * Marks a client object closed; subsequent operations on it fail.
     *
     * @param self the Ballerina client object
     * @return {@code null}
     */
    public static Object closeClient(BObject self) {
        self.addNativeData(Constants.NATIVE_CLOSED, Boolean.TRUE);
        return null;
    }

    @SuppressWarnings("unchecked")
    private static ShareServiceClient buildServiceClient(BMap<BString, Object> config) {
        if (config.get(Constants.RETRY_CONFIG) != null) {
            throw FilesErrorCreator.notImplemented("retryConfig");
        }
        if (config.get(Constants.TRANSPORT_CONFIG) != null) {
            throw FilesErrorCreator.notImplemented("transportConfig");
        }
        BMap<BString, Object> auth = (BMap<BString, Object>) config.getMapValue(Constants.AUTH);
        ShareServiceClientBuilder builder = new ShareServiceClientBuilder();
        if (auth.containsKey(Constants.ACCOUNT_KEY)) {
            configureSharedKey(builder, auth);
        } else if (auth.containsKey(Constants.SAS_TOKEN)) {
            configureSas(builder, auth);
        } else if (auth.containsKey(Constants.SAS_URL)) {
            configureSasUrl(builder, auth);
        } else if (auth.containsKey(Constants.CONNECTION_STRING)) {
            configureConnectionString(builder, auth);
        } else {
            throw FilesErrorCreator.notImplemented("Microsoft Entra ID authentication");
        }
        try {
            return builder.buildClient();
        } catch (IllegalArgumentException | IllegalStateException e) {
            throw FilesErrorCreator.processingError("invalid client configuration: " + Ops.describe(e), e);
        }
    }

    private static void configureSharedKey(ShareServiceClientBuilder builder, BMap<BString, Object> auth) {
        String accountName = requireNonEmpty(auth, Constants.ACCOUNT_NAME);
        String accountKey = requireNonEmpty(auth, Constants.ACCOUNT_KEY);
        try {
            Base64.getDecoder().decode(accountKey);
        } catch (IllegalArgumentException e) {
            throw FilesErrorCreator.processingError("accountKey is not a valid base64 string", e);
        }
        String serviceUrl = ValueUtils.optString(auth, Constants.SERVICE_URL);
        builder.endpoint(serviceUrl == null ? defaultEndpoint(accountName) : validateUrl(serviceUrl, "serviceUrl"))
                .credential(new AzureNamedKeyCredential(accountName, accountKey));
        if (serviceUrl != null) {
            addPortOverride(builder, serviceUrl);
        }
    }

    /**
     * The SDK's endpoint parsing keeps only the URL's scheme and host, so an endpoint carrying
     * an explicit port (a private endpoint, a tunnel, or a local test service) would silently
     * lose it. This policy restores the configured authority on every outgoing request.
     */
    private static void addPortOverride(ShareServiceClientBuilder builder, String url) {
        URI uri = URI.create(url);
        int port = uri.getPort();
        if (port == -1) {
            return;
        }
        String scheme = uri.getScheme();
        String host = uri.getHost();
        HttpPipelinePolicy override = (context, next) -> {
            UrlBuilder requestUrl = UrlBuilder.parse(context.getHttpRequest().getUrl());
            requestUrl.setScheme(scheme).setHost(host).setPort(port);
            context.getHttpRequest().setUrl(requestUrl.toString());
            return next.process();
        };
        builder.addPolicy(override);
    }

    private static void configureSas(ShareServiceClientBuilder builder, BMap<BString, Object> auth) {
        String accountName = requireNonEmpty(auth, Constants.ACCOUNT_NAME);
        String sasToken = requireNonEmpty(auth, Constants.SAS_TOKEN);
        builder.endpoint(defaultEndpoint(accountName)).credential(new AzureSasCredential(sasToken));
    }

    private static void configureSasUrl(ShareServiceClientBuilder builder, BMap<BString, Object> auth) {
        String sasUrl = requireNonEmpty(auth, Constants.SAS_URL);
        URI uri;
        try {
            uri = new URI(sasUrl);
        } catch (URISyntaxException e) {
            throw FilesErrorCreator.processingError("sasUrl is not a valid URL", e);
        }
        if (uri.getScheme() == null || !(uri.getScheme().equals("https") || uri.getScheme().equals("http"))) {
            throw FilesErrorCreator.processingError("sasUrl must use the http or https scheme", null);
        }
        if (uri.getRawQuery() == null || !uri.getRawQuery().contains("sig=")) {
            throw FilesErrorCreator.processingError(
                    "sasUrl carries no SAS token (no `sig=` in its query); for a bare token use SasConfig", null);
        }
        String base = uri.getRawQuery() == null ? sasUrl : sasUrl.substring(0, sasUrl.indexOf('?'));
        builder.endpoint(base).credential(new AzureSasCredential(uri.getRawQuery()));
        addPortOverride(builder, base);
    }

    private static void configureConnectionString(ShareServiceClientBuilder builder, BMap<BString, Object> auth) {
        String connectionString = requireNonEmpty(auth, Constants.CONNECTION_STRING);
        if (!connectionString.contains("FileEndpoint=") && !connectionString.contains("AccountName=")) {
            throw FilesErrorCreator.processingError(
                    "the connection string must include FileEndpoint= or AccountName= so the file-service "
                            + "endpoint can be derived", null);
        }
        try {
            builder.connectionString(connectionString);
        } catch (IllegalArgumentException e) {
            throw FilesErrorCreator.processingError("invalid connection string: " + Ops.describe(e), e);
        }
        for (String pair : connectionString.split(";")) {
            if (pair.startsWith("FileEndpoint=")) {
                addPortOverride(builder, pair.substring("FileEndpoint=".length()));
            }
        }
    }

    private static String requireNonEmpty(BMap<BString, Object> record, BString field) {
        String value = ValueUtils.optString(record, field);
        if (value == null || value.strip().isEmpty()) {
            throw FilesErrorCreator.processingError(field.getValue() + " must not be empty", null);
        }
        return value.strip();
    }

    private static String defaultEndpoint(String accountName) {
        return "https://" + accountName + ".file.core.windows.net";
    }

    private static String validateUrl(String url, String fieldName) {
        try {
            URI uri = new URI(url);
            if (uri.getScheme() == null || !(uri.getScheme().equals("https") || uri.getScheme().equals("http"))) {
                throw FilesErrorCreator.processingError(fieldName + " must use the http or https scheme", null);
            }
            return url;
        } catch (URISyntaxException e) {
            throw FilesErrorCreator.processingError(fieldName + " is not a valid URL", e);
        }
    }
}
