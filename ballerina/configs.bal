// Copyright (c) 2026, WSO2 LLC. (http://www.wso2.com).
//
// WSO2 LLC. licenses this file to you under the Apache License,
// Version 2.0 (the "License"); you may not use this file except
// in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing,
// software distributed under the License is distributed on an
// "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
// KIND, either express or implied.  See the License for the
// specific language governing permissions and limitations
// under the License.

import ballerina/crypto;

# Shared Key authentication using one of the storage account's access keys.
public type SharedKeyConfig record {|
    # The storage account name, used to sign requests and to derive the service URL
    string accountName;
    # A base64-encoded access key of the storage account
    string accountKey;
    # The file service endpoint URL, including the scheme. Omit to use the default
    # `https://{accountName}.file.core.windows.net`
    string serviceUrl?;
|};

# Shared Access Signature (SAS) authentication with a bare SAS token, as issued by
# `az storage share generate-sas` or the SAS-generation operations. For the Azure portal's
# ready-made "File service SAS URL", use `SasUrlConfig` instead.
public type SasConfig record {|
    # The name of the storage account the token belongs to (determines the service URL)
    string accountName;
    # A SAS token scoped to the required resources and permissions
    string sasToken;
|};

# Shared Access Signature (SAS) authentication with a full SAS URL, which carries the service
# URL and the SAS token in one string, as issued by the Azure portal.
public type SasUrlConfig record {|
    # A full file-service SAS URL, including the scheme and the SAS query string
    # (e.g. `https://{account}.file.core.windows.net/?sv=...&sig=...`)
    string sasUrl;
|};

# Connection-string authentication. The connection string carries the account name, the
# credential (an account key or a SAS token), and the service endpoints.
public type ConnectionStringConfig record {|
    # An Azure Storage connection string, as issued by the Azure portal, the Azure CLI, or
    # infrastructure tooling
    string connectionString;
|};

// ---------------------------------------------------------------------------
// Entra ID authentication
// ---------------------------------------------------------------------------

# The credential-kind discriminator value selecting `DefaultEntraIdConfig`.
public const DEFAULT_AZURE_CREDENTIAL = "default";

# The credential-kind discriminator value selecting `ManagedIdentityConfig`.
public const MANAGED_IDENTITY = "managed-identity";

# Microsoft Entra ID authentication through the default credential chain. The chain tries the
# environment, a managed identity, and developer sign-ins (Azure CLI, IDE accounts) in turn, so
# one configuration works both locally and when deployed.
public type DefaultEntraIdConfig record {|
    # Selects the default credential chain
    DEFAULT_AZURE_CREDENTIAL kind;
    # The storage account name (determines the service URL unless `serviceUrl` overrides it)
    string accountName;
    # The file service endpoint URL, including the scheme. Omit to use the default
    # `https://{accountName}.file.core.windows.net`
    string serviceUrl?;
|};

# Microsoft Entra ID authentication as an Azure managed identity, for workloads running on
# Azure compute (VMs, App Service, AKS, Functions).
public type ManagedIdentityConfig record {|
    # Selects the managed-identity credential
    MANAGED_IDENTITY kind;
    # The storage account name (determines the service URL unless `serviceUrl` overrides it)
    string accountName;
    # The client id of a user-assigned managed identity; omit to use the system-assigned
    # identity
    string clientId?;
    # The file service endpoint URL, including the scheme. Omit to use the default
    # `https://{accountName}.file.core.windows.net`
    string serviceUrl?;
|};

# Microsoft Entra ID authentication as a service principal with a client secret.
public type ClientSecretConfig record {|
    # The storage account name (determines the service URL unless `serviceUrl` overrides it)
    string accountName;
    # The Entra ID tenant (directory) id
    string tenantId;
    # The application (client) id of the service principal
    string clientId;
    # The client secret of the service principal
    string clientSecret;
    # The file service endpoint URL, including the scheme. Omit to use the default
    # `https://{accountName}.file.core.windows.net`
    string serviceUrl?;
|};

# Microsoft Entra ID authentication as a service principal with a client certificate.
public type ClientCertificateConfig record {|
    # The storage account name (determines the service URL unless `serviceUrl` overrides it)
    string accountName;
    # The Entra ID tenant (directory) id
    string tenantId;
    # The application (client) id of the service principal
    string clientId;
    # The path to the certificate file (PEM, or PFX when `certificatePassword` is set)
    string certificatePath;
    # The password protecting the certificate file, when it has one
    string certificatePassword?;
    # The file service endpoint URL, including the scheme. Omit to use the default
    # `https://{accountName}.file.core.windows.net`
    string serviceUrl?;
|};

# Microsoft Entra ID workload-identity authentication, for Kubernetes workloads federated
# with Entra ID.
public type WorkloadIdentityConfig record {|
    # The storage account name (determines the service URL unless `serviceUrl` overrides it)
    string accountName;
    # The Entra ID tenant (directory) id
    string tenantId;
    # The application (client) id federated with the workload
    string clientId;
    # The path to the file holding the federated service-account token
    string tokenFilePath;
    # The file service endpoint URL, including the scheme. Omit to use the default
    # `https://{accountName}.file.core.windows.net`
    string serviceUrl?;
|};

# Microsoft Entra ID authentication: one record per credential kind. Azure Files honors OAuth
# tokens only on requests carrying the backup intent, which the connector sets automatically.
# The intent bypasses file and directory ACLs and requires the identity to hold the
# `Storage File Data Privileged Reader` or `Storage File Data Privileged Contributor` role.
public type EntraIdConfig DefaultEntraIdConfig|ManagedIdentityConfig|ClientSecretConfig|
    ClientCertificateConfig|WorkloadIdentityConfig;

# The authentication configuration: one credential-artifact record (an account key, a bare SAS
# token, a full SAS URL, a connection string, or a Microsoft Entra ID identity).
public type AuthConfig SharedKeyConfig|SasConfig|SasUrlConfig|ConnectionStringConfig|EntraIdConfig;

// ---------------------------------------------------------------------------
// Resilience and transport
// ---------------------------------------------------------------------------

# The retry policy kinds: `EXPONENTIAL` grows the delay between tries exponentially;
# `FIXED` keeps the same delay between every try.
public enum RetryPolicyType {
    # Delays grow exponentially between tries
    EXPONENTIAL = "exponential",
    // FIXED is a module-level constant shared with LeaseDuration (enum members merge when
    // their values match), so its doc line lives on the LeaseDuration member.
    FIXED = "fixed"
}

# Retry behaviour for service requests. The defaults match the underlying Azure SDK's own
# defaults, so omitting the record leaves behaviour unchanged.
public type RetryConfig record {|
    # How the delay between tries grows
    RetryPolicyType retryPolicyType = EXPONENTIAL;
    # The maximum number of tries (the first attempt plus retries)
    int maxTries = 4;
    # The timeout applied to each individual try, in seconds
    decimal tryTimeoutSeconds = 60;
    # The base delay between tries, in seconds
    decimal retryDelaySeconds = 4;
    # The upper bound on the delay between tries, in seconds
    decimal maxRetryDelaySeconds = 120;
    # A secondary endpoint to retry reads against (geo-redundant accounts)
    string secondaryHostUrl?;
|};

# The proxy protocol kinds.
public enum ProxyType {
    # An HTTP proxy
    HTTP,
    # A SOCKS4 proxy
    SOCKS4,
    # A SOCKS5 proxy
    SOCKS5
}

# Routes the connector's traffic through a proxy server.
public type ProxyConfig record {|
    # The proxy protocol
    ProxyType proxyType;
    # The proxy host name or IP address
    string host;
    # The proxy port
    int port;
    # The user name, when the proxy requires authentication
    string username?;
    # The password, when the proxy requires authentication
    string password?;
    # Hosts reached directly, bypassing the proxy
    string[] nonProxyHosts = [];
|};

# Tunes the connector's HTTP connection pool.
public type ConnectionPoolConfig record {|
    # The maximum number of concurrent connections
    int maxConnections = 50;
    # How long an idle connection is kept before being closed, in seconds
    decimal idleTimeoutSeconds = 60;
    # The timeout for establishing a connection, in seconds
    decimal connectTimeoutSeconds = 10;
    # The timeout for reading a response, in seconds
    decimal readTimeoutSeconds = 60;
|};

# HTTP transport settings: proxying, connection pooling, and TLS.
public type TransportConfig record {|
    # Route traffic through this proxy
    ProxyConfig proxy?;
    # Connection-pool tuning
    ConnectionPoolConfig connectionPool = {};
    # Custom TLS settings (trust and key material, verification)
    SecureSocket secureSocket?;
|};

# Custom TLS settings for the connection to the service.
public type SecureSocket record {|
    # The trust material for verifying the server: a PKCS12 or JKS truststore, or the path
    # to a PEM certificate file. Omit to trust the platform's default certificate authorities
    crypto:TrustStore|string cert?;
    # The client's own identity for mutual TLS: a PKCS12 or JKS keystore, or a certificate
    # and private key pair. Omit when the server does not request a client certificate
    crypto:KeyStore|CertKey 'key?;
    # The TLS versions offered during the handshake (e.g. `TLSv1.3`, `TLSv1.2`). Omit to use
    # the platform defaults
    string[] tlsVersions?;
    # The cipher suites offered during the handshake. Omit to use the platform defaults
    string[] ciphers?;
    # Verify that the server certificate matches the host being called. Disabling this
    # removes protection against man-in-the-middle attacks, so it is meant for testing only
    boolean verifyHostName = true;
    # Allow TLS sessions to be reused across connections
    boolean shareSession = true;
    # Check the server certificate against revocation information: a stapled OCSP response
    # when the server sends one, otherwise an OCSP or CRL fetch. Requires `cert` to be set
    boolean validateRevocation = false;
    # The SNI (Server Name Indication) host name presented during the handshake; omit to use
    # the host being called
    string serverName?;
    # The TLS handshake timeout, in seconds
    decimal handshakeTimeoutSeconds?;
    # How long a TLS session stays reusable, in seconds
    decimal sessionTimeoutSeconds?;
|};

# A client certificate and private key pair, as files.
public type CertKey record {|
    # The path to the certificate file
    string certFile;
    # The path to the private key file
    string keyFile;
    # The password protecting the private key, when it has one
    string keyPassword?;
|};

# Configuration for an `azure.storage.files` client (`Client` or `AdminClient`).
public type ClientConfiguration record {|
    # The authentication configuration (see `AuthConfig`)
    AuthConfig auth;
    # Retry behaviour for service requests; omit for the service defaults
    RetryConfig retryConfig?;
    # HTTP transport settings (proxy, connection pool, TLS); omit for the defaults
    TransportConfig transportConfig?;
|};
