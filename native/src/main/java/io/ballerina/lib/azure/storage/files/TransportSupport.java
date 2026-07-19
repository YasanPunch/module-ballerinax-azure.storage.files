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

import com.azure.core.http.ProxyOptions;
import com.azure.core.http.netty.NettyAsyncHttpClientBuilder;
import com.azure.storage.common.policy.RequestRetryOptions;
import com.azure.storage.common.policy.RetryPolicyType;
import io.ballerina.runtime.api.values.BArray;
import io.ballerina.runtime.api.values.BDecimal;
import io.ballerina.runtime.api.values.BMap;
import io.ballerina.runtime.api.values.BString;
import io.netty.handler.ssl.SslContext;
import io.netty.handler.ssl.SslContextBuilder;
import reactor.netty.http.client.HttpClient;
import reactor.netty.resources.ConnectionProvider;

import javax.net.ssl.CertPathTrustManagerParameters;
import javax.net.ssl.KeyManagerFactory;
import javax.net.ssl.SNIHostName;
import javax.net.ssl.SSLEngine;
import javax.net.ssl.SSLParameters;
import javax.net.ssl.TrustManagerFactory;
import java.io.File;
import java.io.FileInputStream;
import java.io.IOException;
import java.io.InputStream;
import java.net.InetSocketAddress;
import java.security.GeneralSecurityException;
import java.security.KeyStore;
import java.security.cert.Certificate;
import java.security.cert.CertificateFactory;
import java.security.cert.CertPathBuilder;
import java.security.cert.PKIXBuilderParameters;
import java.security.cert.PKIXRevocationChecker;
import java.security.cert.X509CertSelector;
import java.time.Duration;
import java.util.Arrays;
import java.util.Collection;
import java.util.List;

/**
 * Maps the connector's {@code RetryConfig} and {@code TransportConfig} onto the SDK's retry
 * policy and its Netty transport. TLS settings ({@code SecureSocket}) are mapped with full
 * fidelity: trust material (PKCS12/JKS store or PEM file), client key material (store or
 * cert-and-key files), TLS versions, cipher suites, hostname verification, SNI override,
 * session flags and timeouts, and certificate revocation checking through the JDK's PKIX
 * checker.
 */
final class TransportSupport {

    private TransportSupport() {
    }

    static RequestRetryOptions retryOptions(BMap<BString, Object> retry) {
        String policy = retry.getStringValue(Constants.RETRY_POLICY_TYPE).getValue();
        return new RequestRetryOptions(
                "fixed".equals(policy) ? RetryPolicyType.FIXED : RetryPolicyType.EXPONENTIAL,
                ((Long) retry.get(Constants.MAX_TRIES)).intValue(),
                seconds(retry.get(Constants.TRY_TIMEOUT_SECONDS)),
                seconds(retry.get(Constants.RETRY_DELAY_SECONDS)),
                seconds(retry.get(Constants.MAX_RETRY_DELAY_SECONDS)),
                ValueUtils.optString(retry, Constants.SECONDARY_HOST_URL));
    }

    @SuppressWarnings("unchecked")
    static com.azure.core.http.HttpClient httpClient(BMap<BString, Object> transport) {
        BMap<BString, Object> pool = (BMap<BString, Object>) transport.get(Constants.CONNECTION_POOL);
        ConnectionProvider provider = ConnectionProvider.builder("azure-storage-files")
                .maxConnections(((Long) pool.get(Constants.MAX_CONNECTIONS)).intValue())
                .maxIdleTime(seconds(pool.get(Constants.IDLE_TIMEOUT_SECONDS)))
                .build();
        HttpClient reactorClient = HttpClient.create(provider);

        BMap<BString, Object> secureSocket = (BMap<BString, Object>) transport.get(Constants.SECURE_SOCKET);
        if (secureSocket != null) {
            reactorClient = applyTls(reactorClient, secureSocket);
        }

        NettyAsyncHttpClientBuilder builder = new NettyAsyncHttpClientBuilder(reactorClient)
                .connectTimeout(seconds(pool.get(Constants.CONNECT_TIMEOUT_SECONDS)))
                .readTimeout(seconds(pool.get(Constants.READ_TIMEOUT_SECONDS)));

        BMap<BString, Object> proxy = (BMap<BString, Object>) transport.get(Constants.PROXY);
        if (proxy != null) {
            builder.proxy(proxyOptions(proxy));
        }
        return builder.build();
    }

    private static ProxyOptions proxyOptions(BMap<BString, Object> proxy) {
        String type = proxy.getStringValue(Constants.PROXY_TYPE).getValue();
        ProxyOptions.Type proxyType = switch (type) {
            case "SOCKS4" -> ProxyOptions.Type.SOCKS4;
            case "SOCKS5" -> ProxyOptions.Type.SOCKS5;
            default -> ProxyOptions.Type.HTTP;
        };
        ProxyOptions options = new ProxyOptions(proxyType, new InetSocketAddress(
                proxy.getStringValue(Constants.HOST).getValue(),
                ((Long) proxy.get(Constants.PORT)).intValue()));
        String username = ValueUtils.optString(proxy, Constants.USERNAME);
        String password = ValueUtils.optString(proxy, Constants.PASSWORD);
        if (username != null && password != null) {
            options.setCredentials(username, password);
        }
        BArray nonProxyHosts = (BArray) proxy.get(Constants.NON_PROXY_HOSTS);
        if (nonProxyHosts != null && nonProxyHosts.size() > 0) {
            options.setNonProxyHosts(String.join("|", nonProxyHosts.getStringArray()));
        }
        return options;
    }

    @SuppressWarnings("unchecked")
    private static HttpClient applyTls(HttpClient reactorClient, BMap<BString, Object> secureSocket) {
        try {
            SslContextBuilder sslBuilder = SslContextBuilder.forClient();
            configureTrust(sslBuilder, secureSocket);
            configureKey(sslBuilder, secureSocket);

            BArray tlsVersions = (BArray) secureSocket.get(Constants.TLS_VERSIONS);
            if (tlsVersions != null && tlsVersions.size() > 0) {
                sslBuilder.protocols(tlsVersions.getStringArray());
            }
            BArray ciphers = (BArray) secureSocket.get(Constants.CIPHERS);
            if (ciphers != null && ciphers.size() > 0) {
                sslBuilder.ciphers(Arrays.asList(ciphers.getStringArray()));
            }
            Object sessionTimeout = secureSocket.get(Constants.SESSION_TIMEOUT_SECONDS);
            if (sessionTimeout != null) {
                sslBuilder.sessionTimeout(seconds(sessionTimeout).toSeconds());
            }
            SslContext sslContext = sslBuilder.build();

            boolean verifyHostName = secureSocket.getBooleanValue(Constants.VERIFY_HOST_NAME);
            boolean shareSession = secureSocket.getBooleanValue(Constants.SHARE_SESSION);
            String serverName = ValueUtils.optString(secureSocket, Constants.SERVER_NAME);
            Object handshakeTimeout = secureSocket.get(Constants.HANDSHAKE_TIMEOUT_SECONDS);

            return reactorClient.secure(spec -> {
                reactor.netty.tcp.SslProvider.Builder providerBuilder = spec.sslContext(sslContext)
                        .handlerConfigurator(handler -> {
                            SSLEngine engine = handler.engine();
                            SSLParameters parameters = engine.getSSLParameters();
                            if (!verifyHostName) {
                                parameters.setEndpointIdentificationAlgorithm(null);
                            }
                            if (serverName != null) {
                                parameters.setServerNames(List.of(new SNIHostName(serverName)));
                            }
                            engine.setSSLParameters(parameters);
                            if (!shareSession) {
                                engine.setEnableSessionCreation(false);
                            }
                        });
                if (handshakeTimeout != null) {
                    providerBuilder.handshakeTimeout(seconds(handshakeTimeout));
                }
            });
        } catch (GeneralSecurityException | IOException e) {
            throw FilesErrorCreator.processingError(
                    "invalid secureSocket configuration: " + Ops.describe(e), e);
        }
    }

    /**
     * Applies the trust side: a PKCS12/JKS truststore or a PEM certificate file, optionally
     * with revocation checking. Revocation runs through the JDK PKIX checker, which consumes
     * stapled OCSP responses when the server sends them and falls back to OCSP/CRL fetching.
     */
    private static void configureTrust(SslContextBuilder sslBuilder, BMap<BString, Object> secureSocket)
            throws GeneralSecurityException, IOException {
        Object cert = secureSocket.get(Constants.CERT);
        boolean validateRevocation = secureSocket.getBooleanValue(Constants.VALIDATE_REVOCATION);
        if (cert == null) {
            if (validateRevocation) {
                throw FilesErrorCreator.processingError(
                        "validateRevocation requires trust material (`cert`) to validate against", null);
            }
            return;
        }
        KeyStore trustStore;
        if (cert instanceof BString pemPath) {
            requireFile(pemPath.getValue(), "cert");
            if (!validateRevocation) {
                sslBuilder.trustManager(new File(pemPath.getValue()));
                return;
            }
            trustStore = pemToKeyStore(pemPath.getValue());
        } else {
            @SuppressWarnings("unchecked")
            BMap<BString, Object> store = (BMap<BString, Object>) cert;
            trustStore = loadKeyStore(store.getStringValue(Constants.PATH).getValue(),
                    store.getStringValue(Constants.PASSWORD).getValue());
        }
        TrustManagerFactory trustManagerFactory = TrustManagerFactory.getInstance("PKIX");
        if (validateRevocation) {
            CertPathBuilder certPathBuilder = CertPathBuilder.getInstance("PKIX");
            PKIXRevocationChecker revocationChecker =
                    (PKIXRevocationChecker) certPathBuilder.getRevocationChecker();
            PKIXBuilderParameters pkixParameters =
                    new PKIXBuilderParameters(trustStore, new X509CertSelector());
            pkixParameters.addCertPathChecker(revocationChecker);
            trustManagerFactory.init(new CertPathTrustManagerParameters(pkixParameters));
        } else {
            trustManagerFactory.init(trustStore);
        }
        sslBuilder.trustManager(trustManagerFactory);
    }

    private static void configureKey(SslContextBuilder sslBuilder, BMap<BString, Object> secureSocket)
            throws GeneralSecurityException, IOException {
        Object key = secureSocket.get(Constants.KEY);
        if (key == null) {
            return;
        }
        @SuppressWarnings("unchecked")
        BMap<BString, Object> keyRecord = (BMap<BString, Object>) key;
        if (keyRecord.containsKey(Constants.CERT_FILE)) {
            String certFile = keyRecord.getStringValue(Constants.CERT_FILE).getValue();
            String keyFile = keyRecord.getStringValue(Constants.KEY_FILE).getValue();
            requireFile(certFile, "key.certFile");
            requireFile(keyFile, "key.keyFile");
            sslBuilder.keyManager(new File(certFile), new File(keyFile),
                    ValueUtils.optString(keyRecord, Constants.KEY_PASSWORD));
            return;
        }
        String password = keyRecord.getStringValue(Constants.PASSWORD).getValue();
        KeyStore keyStore = loadKeyStore(keyRecord.getStringValue(Constants.PATH).getValue(), password);
        KeyManagerFactory keyManagerFactory =
                KeyManagerFactory.getInstance(KeyManagerFactory.getDefaultAlgorithm());
        keyManagerFactory.init(keyStore, password.toCharArray());
        sslBuilder.keyManager(keyManagerFactory);
    }

    private static KeyStore loadKeyStore(String path, String password)
            throws GeneralSecurityException, IOException {
        requireFile(path, "store path");
        for (String type : new String[] {"PKCS12", "JKS"}) {
            KeyStore store = KeyStore.getInstance(type);
            try (InputStream input = new FileInputStream(path)) {
                store.load(input, password.toCharArray());
                return store;
            } catch (IOException e) {
                // Wrong store format (or password); try the next type before giving up.
            }
        }
        throw FilesErrorCreator.processingError(
                "cannot load the certificate store at " + path + " as PKCS12 or JKS (check the password)", null);
    }

    private static KeyStore pemToKeyStore(String pemPath) throws GeneralSecurityException, IOException {
        KeyStore store = KeyStore.getInstance(KeyStore.getDefaultType());
        store.load(null, null);
        CertificateFactory factory = CertificateFactory.getInstance("X.509");
        try (InputStream input = new FileInputStream(pemPath)) {
            Collection<? extends Certificate> certificates = factory.generateCertificates(input);
            if (certificates.isEmpty()) {
                throw FilesErrorCreator.processingError("no certificates found in " + pemPath, null);
            }
            int index = 0;
            for (Certificate certificate : certificates) {
                store.setCertificateEntry("cert-" + index++, certificate);
            }
        }
        return store;
    }

    private static void requireFile(String path, String fieldName) {
        if (!new File(path).isFile()) {
            throw FilesErrorCreator.processingError(
                    fieldName + " does not point to a readable file: " + path, null);
        }
    }

    private static Duration seconds(Object decimalValue) {
        return Duration.ofMillis((long) (((BDecimal) decimalValue).floatValue() * 1000));
    }
}
