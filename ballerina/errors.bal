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

# Structured detail carried by every connector error.
public type ErrorDetail record {|
    # The HTTP status code returned by Azure. Absent when the failure happened without a
    # server exchange (e.g. a `ProcessingError` raised client-side).
    int httpStatus?;
    # The Azure error code (e.g. `ShareNotFound`), or a connector-defined identifier for
    # client-side failures
    string errorCode;
|};

# The root error type for the connector. Every error raised by an `azure.storage.files`
# operation is a subtype of this type and carries an `ErrorDetail`.
public type Error distinct error<ErrorDetail>;

# The requested share, directory, or file was not found (HTTP 404).
public type NotFoundError distinct Error;

# The operation conflicts with the current state of the resource, e.g. creating a share that
# already exists (HTTP 409).
public type ConflictError distinct Error;

# Authentication or authorization failed, e.g. an invalid key or insufficient SAS
# permissions (HTTP 403).
public type AuthorizationError distinct Error;

# A precondition such as an ETag `If-Match`/`If-None-Match` condition or a lease-id
# requirement on a file operation was not met (HTTP 412).
public type PreconditionFailedError distinct Error;

# The requested byte range cannot be satisfied for the target file (HTTP 416).
public type RangeNotSatisfiableError distinct Error;

# The share is full: a write was rejected because the share's provisioned capacity is
# exhausted (HTTP 403).
public type QuotaExceededError distinct Error;

# A client-side failure occurred while preparing the request or decoding the response
# (no server round-trip, or a failure outside Azure's control).
public type ProcessingError distinct Error;
