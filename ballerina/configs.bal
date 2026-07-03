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

# Shared Key authentication using one of the storage account's access keys.
public type SharedKeyAuth record {|
    # The storage account name (determines the service endpoint unless
    # `ClientConfiguration.endpoint` overrides it)
    string accountName;
    # A base64-encoded access key of the storage account
    string accountKey;
|};

# Shared Access Signature (SAS) authentication.
public type SasAuth record {|
    # The storage account name (determines the service endpoint unless
    # `ClientConfiguration.endpoint` overrides it)
    string accountName;
    # A SAS token scoped to the required resources and permissions
    string sasToken;
|};

# Connection-string authentication. The connection string itself carries the account name,
# key, and service endpoints, so no separate account name is needed.
public type ConnectionStringAuth record {|
    # An Azure Storage account connection string
    string connectionString;
|};

# Configuration for an `azure.storage.files` client (`Client` or `AdminClient`). Supplied to
# `init` as an included record parameter, so its fields are passed as named arguments.
public type ClientConfiguration record {|
    # The authentication method to use. Each auth record carries exactly the fields it needs
    # (e.g. `accountName` lives on `SharedKeyAuth`/`SasAuth` but not on `ConnectionStringAuth`),
    # so a missing field is a compile error, not a runtime failure.
    SharedKeyAuth|SasAuth|ConnectionStringAuth auth;
    # An explicit file-service endpoint URL, overriding the one derived from the auth record's
    # `accountName` (`https://{accountName}.file.core.windows.net`). Use for sovereign clouds
    # (e.g. `https://{account}.file.core.chinacloudapi.cn`), private endpoints with custom DNS,
    # or local test endpoints.
    string endpoint?;
|};
