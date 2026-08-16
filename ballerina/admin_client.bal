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

import ballerina/jballerina.java;
import ballerina/time;

# Account-level client for Azure Files, managing the shares within a storage account.
public isolated client class AdminClient {

    # Initializes the account-level client for the given storage account.
    #
    # + config - The client configuration (authentication, retry, transport)
    # + return - An `Error` if the client could not be initialized, otherwise `()`
    public isolated function init(*ClientConfiguration config) returns Error? {
        return initAdminClient(self, config);
    }

    # Checks whether a share exists in the storage account. Returns `false` only when Azure
    # confirms the share is absent; an `Error` means the check itself failed.
    #
    # + shareName - The name of the share to check
    # + return - `true` if the share exists, `false` if not, or an `Error`
    isolated remote function hasShare(string shareName) returns boolean|Error = @java:Method {
        'class: "io.ballerina.lib.azure.storage.files.client.AdminOps"
    } external;

    # Lists the shares in the storage account.
    #
    # + options - Optional filtering and listing options
    # + return - An array of `ShareInfo`, or an `Error`
    isolated remote function listShares(ShareListOptions? options = ()) returns ShareInfo[]|Error = @java:Method {
        'class: "io.ballerina.lib.azure.storage.files.client.AdminOps"
    } external;

    # Creates a new share in the storage account.
    #
    # + shareName - The name of the share to create
    # + options - Optional creation options (quota, tier, protocols, metadata)
    # + return - An `Error` if the share could not be created, otherwise `()`
    isolated remote function createShare(string shareName, ShareCreateOptions? options = ())
            returns Error? = @java:Method {
        'class: "io.ballerina.lib.azure.storage.files.client.AdminOps"
    } external;

    # Deletes a share from the storage account.
    #
    # + shareName - The name of the share to delete
    # + options - Optional deletion options (snapshot handling, lease id)
    # + return - An `Error` if the share could not be deleted, otherwise `()`
    isolated remote function deleteShare(string shareName, ShareDeleteOptions? options = ())
            returns Error? = @java:Method {
        'class: "io.ballerina.lib.azure.storage.files.client.AdminOps"
    } external;

    # Restores a soft-deleted share.
    #
    # + shareName - The name of the soft-deleted share to restore
    # + version - The version of the soft-deleted share (from `ShareInfo.version`)
    # + return - An `Error` if the share could not be restored, otherwise `()`
    isolated remote function undeleteShare(string shareName, string version) returns Error? = @java:Method {
        'class: "io.ballerina.lib.azure.storage.files.client.AdminOps"
    } external;

    // -----------------------------------------------------------------------
    // Service configuration
    // -----------------------------------------------------------------------

    # Reads the account's file-service configuration (metrics and CORS rules).
    #
    # + return - The `ServiceProperties`, or an `Error`
    isolated remote function getServiceProperties() returns ServiceProperties|Error = @java:Method {
        'class: "io.ballerina.lib.azure.storage.files.client.AdminOps"
    } external;

    # Updates the account's file-service configuration. The record replaces the whole
    # configuration.
    #
    # + properties - The complete file-service configuration to apply
    # + return - An `Error` if the configuration could not be updated, otherwise `()`
    isolated remote function setServiceProperties(ServiceProperties properties) returns Error? = @java:Method {
        'class: "io.ballerina.lib.azure.storage.files.client.AdminOps"
    } external;

    // -----------------------------------------------------------------------
    // SAS
    // -----------------------------------------------------------------------

    # Gets a user-delegation key for signing user-delegation SAS tokens. Requires Microsoft
    # Entra ID credentials with the `Storage File Delegator` role.
    #
    # + startTime - The start of the key's validity period
    # + expiryTime - The end of the key's validity period (at most 7 days out)
    # + return - The `UserDelegationKey`, or an `Error`
    isolated remote function getUserDelegationKey(time:Utc startTime, time:Utc expiryTime)
            returns UserDelegationKey|Error = @java:Method {
        'class: "io.ballerina.lib.azure.storage.files.client.AdminOps"
    } external;

    # Generates an account-level SAS (Shared Access Signature) token. Requires shared key credentials.
    #
    # + values - What the SAS grants: validity window, permissions, and resource types
    # + return - The SAS token, or an `Error`
    public isolated function generateAccountSas(AccountSasSignatureValues values) returns string|Error = @java:Method {
        'class: "io.ballerina.lib.azure.storage.files.client.SasOps"
    } external;
}
