// Copyright (c) 2026 WSO2 LLC. (https://www.wso2.com) All Rights Reserved.
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

# Account-level client for Azure Files. Manages the shares within a storage account
# (create, list, delete, restore). For operations scoped to a single share, use `Client`.
#
# The client is `isolated` and holds only immutable configuration, so its operations are
# safe to invoke concurrently.
public isolated client class AdminClient {

    # Initializes the account-level client for the given storage account.
    #
    # + config - The connection configuration (account name and authentication)
    # + return - An `Error` if the client could not be initialized, otherwise `()`
    public isolated function init(ConnectionConfig config) returns Error? {
        return;
    }

    # Lists the shares in the storage account.
    #
    # + options - Optional filtering and listing options
    # + return - A stream of `ShareInfo`, or an `Error`
    isolated remote function listShares(ShareListOptions? options = ())
            returns stream<ShareInfo, Error?>|Error {
        return notImplemented();
    }

    # Creates a new share in the storage account.
    #
    # + shareName - The name of the share to create
    # + options - Optional creation options (quota, tier, protocols, metadata)
    # + return - An `Error` if the share could not be created, otherwise `()`
    isolated remote function createShare(string shareName, ShareCreateOptions? options = ())
            returns Error? {
        return notImplemented();
    }

    # Deletes a share from the storage account.
    #
    # + shareName - The name of the share to delete
    # + options - Optional deletion options (snapshot handling, lease id)
    # + return - An `Error` if the share could not be deleted, otherwise `()`
    isolated remote function deleteShare(string shareName, ShareDeleteOptions? options = ())
            returns Error? {
        return notImplemented();
    }

    # Restores a previously soft-deleted share.
    #
    # + deletedShareName - The name of the soft-deleted share
    # + deletedShareVersion - The version of the soft-deleted share (from `ShareInfo.version`)
    # + return - An `Error` if the share could not be restored, otherwise `()`
    isolated remote function undeleteShare(string deletedShareName, string deletedShareVersion)
            returns Error? {
        return notImplemented();
    }

    # Closes the client and releases any underlying resources.
    #
    # + return - An `Error` if the client could not be closed, otherwise `()`
    isolated remote function close() returns Error? {
        return;
    }
}
