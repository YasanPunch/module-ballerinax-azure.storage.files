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

// A minimal in-memory mock of the Azure Files REST service ("FileREST"), speaking just enough
// of the wire protocol for the real azure-storage-file-share SDK to run against it via the
// SharedKeyConfig.serviceUrl override. Authentication headers are ignored. Any path whose last
// segment has the form `__err-<status>-<AzureErrorCode>` short-circuits into that error
// response, which is how the error-mapping tests drive specific Azure error codes.

import ballerina/http;
import ballerina/url;

const int MOCK_PORT = 9099;
const string LAST_MODIFIED = "Wed, 01 Jul 2026 10:00:00 GMT";

type MockFile record {|
    int size;
    byte[] content;
    map<string> metadata;
    map<string> contentHeaders;
    string etag;
    string copyId?;
    string? leaseId = ();
    string? linkText = ();
|};

type MockDir record {|
    map<string> metadata;
    string etag;
|};

type MockShare record {|
    map<string> metadata = {};
    int quota = 5120;
    string accessTier = "TransactionOptimized";
    string etag;
    map<MockFile> files = {};
    map<MockDir> dirs = {};
    string? leaseId = ();
    string leaseDuration = "infinite";
    string aclXml = "<?xml version=\"1.0\" encoding=\"utf-8\"?><SignedIdentifiers />";
    map<string> permissions = {};
|};

type MockResponse record {|
    int status;
    map<string> headers = {};
    byte[] body = [];
    string contentType = "application/octet-stream";
|};

map<MockShare> mockShares = {};
map<MockShare> mockDeletedShares = {};
// Keyed "{share}\n{snapshotId}"; each value is a deep copy of the share at snapshot time.
map<MockShare> mockShareSnapshots = {};
int mockEtagCounter = 0;
int mockCopyCounter = 0;
int mockLeaseCounter = 0;
int mockSnapshotCounter = 0;
int mockPermissionCounter = 0;
string mockServicePropsXml = string `<?xml version="1.0" encoding="utf-8"?><StorageServiceProperties />`;

function snapshotKey(string shareName, string snapshotId) returns string {
    return shareName + "\n" + snapshotId;
}

// Resolves the live share, or the stored snapshot copy when the request carries a
// sharesnapshot query parameter.
function resolveShare(string shareName, string snapshotParam) returns MockShare? {
    if snapshotParam == "" {
        return mockShares[shareName];
    }
    return mockShareSnapshots[snapshotKey(shareName, snapshotParam)];
}

listener http:Listener mockListener = new (MOCK_PORT);

// Azure always answers with an explicit Content-Length; auto-chunking would drop it on
// large responses and the SDK reads the file size from that header.
@http:ServiceConfig {chunking: http:CHUNKING_NEVER}
service / on mockListener {
    resource function 'default [string... segments](http:Request req) returns http:Response {
        string method = req.method;
        string comp = req.getQueryParamValue("comp") ?: "";
        string restype = req.getQueryParamValue("restype") ?: "";
        string include = req.getQueryParamValue("include") ?: "";
        string prefix = req.getQueryParamValue("prefix") ?: "";
        string snapshotParam = req.getQueryParamValue("sharesnapshot") ?: "";
        string prevSnapshotParam = req.getQueryParamValue("prevsharesnapshot") ?: "";
        map<string> headers = {};
        foreach string name in req.getHeaderNames() {
            string|error value = req.getHeader(name);
            if value is string {
                headers[name.toLowerAscii()] = value;
            }
        }
        byte[] payload = [];
        var binaryPayload = req.getBinaryPayload();
        if binaryPayload is byte[] {
            payload = binaryPayload;
        }
        MockResponse mock = dispatch(method, segments, comp, restype, include, prefix,
                snapshotParam, prevSnapshotParam, headers, payload);
        http:Response response = new;
        response.statusCode = mock.status;
        if mock.body.length() > 0 {
            response.setBinaryPayload(mock.body, mock.contentType);
        }
        foreach [string, string] [name, value] in mock.headers.entries() {
            response.setHeader(name, value);
        }
        return response;
    }
}

// The service is deliberately non-isolated, so requests dispatch serially and the
// module-level state needs no locking.
function dispatch(string method, string[] segments, string comp, string restype,
        string include, string prefix, string snapshotParam, string prevSnapshotParam,
        map<string> headers, byte[] payload) returns MockResponse {
    // Forced-error escape hatch for the error-mapping tests.
    foreach string segment in segments {
        if segment.startsWith("__err-") {
            string[] parts = re `-`.split(segment);
            if parts.length() >= 3 {
                int status = checkpanic int:fromString(parts[1]);
                return errorResponse(status, parts[2]);
            }
        }
    }
    if segments.length() == 0 {
        if restype == "service" && comp == "properties" {
            if method == "PUT" {
                mockServicePropsXml = checkpanic string:fromBytes(payload);
                return okResponse(202);
            }
            return {
                status: 200,
                headers: {"x-ms-request-id": "mock"},
                body: mockServicePropsXml.toBytes(),
                contentType: "application/xml"
            };
        }
        if restype == "service" && comp == "userdelegationkey" && method == "POST" {
            string body = checkpanic string:fromBytes(payload);
            string signedStart = extractTag(body, "Start");
            string signedExpiry = extractTag(body, "Expiry");
            return xmlResponse(string `<UserDelegationKey><SignedOid>mock-oid</SignedOid><SignedTid>mock-tid</SignedTid><SignedStart>${signedStart}</SignedStart><SignedExpiry>${signedExpiry}</SignedExpiry><SignedService>f</SignedService><SignedVersion>2025-05-05</SignedVersion><Value>bW9jay11ZGstdmFsdWU=</Value></UserDelegationKey>`);
        }
        if method == "GET" && comp == "list" {
            return listSharesResponse(prefix, include);
        }
        return errorResponse(400, "InvalidQueryParameterValue");
    }
    string shareName = segments[0];
    string path = joinPath(segments);
    // restype=directory must win over the one-segment share fallback: a root-directory
    // listing addresses /{share}?restype=directory&comp=list with a single segment.
    if restype == "directory" {
        return directoryDispatch(method, shareName, path, comp, include, prefix,
                snapshotParam, headers);
    }
    if restype == "share" || (segments.length() == 1 && comp != "") {
        return shareDispatch(method, shareName, comp, snapshotParam, headers, payload);
    }
    return fileDispatch(method, shareName, path, comp, restype, snapshotParam,
            prevSnapshotParam, headers, payload);
}

function extractTag(string body, string tag) returns string {
    int? tagStart = body.indexOf("<" + tag + ">");
    int? tagEnd = body.indexOf("</" + tag + ">");
    if tagStart is () || tagEnd is () {
        return "";
    }
    return body.substring(tagStart + tag.length() + 2, tagEnd);
}

function joinPath(string[] segments) returns string {
    string result = "";
    foreach int i in 1 ..< segments.length() {
        result = result == "" ? segments[i] : result + "/" + segments[i];
    }
    return result;
}

function nextEtag() returns string {
    mockEtagCounter += 1;
    return string `"0x${mockEtagCounter}"`;
}

function errorResponse(int status, string code) returns MockResponse {
    string body = string `<?xml version="1.0" encoding="utf-8"?><Error><Code>${code}</Code><Message>Mock error: ${code}</Message></Error>`;
    return {
        status,
        headers: {"x-ms-error-code": code, "x-ms-request-id": "mock"},
        body: body.toBytes(),
        contentType: "application/xml"
    };
}

function okResponse(int status, map<string> extraHeaders = {}) returns MockResponse {
    // x-ms-request-server-encrypted is unconditionally unboxed by the SDK's write-response
    // header models, so every mutation response must carry it.
    map<string> headers = {
        "ETag": nextEtag(),
        "Last-Modified": LAST_MODIFIED,
        "x-ms-request-id": "mock",
        "x-ms-request-server-encrypted": "true"
    };
    foreach [string, string] [name, value] in extraHeaders.entries() {
        headers[name] = value;
    }
    return {status, headers};
}

function xmlResponse(string body) returns MockResponse {
    return {
        status: 200,
        headers: {"x-ms-request-id": "mock"},
        body: (string `<?xml version="1.0" encoding="utf-8"?>` + body).toBytes(),
        contentType: "application/xml"
    };
}

function metadataFrom(map<string> headers) returns map<string> {
    map<string> result = {};
    foreach [string, string] [name, value] in headers.entries() {
        if name.startsWith("x-ms-meta-") {
            result[name.substring(10)] = value;
        }
    }
    return result;
}

function metadataHeaders(map<string> metadata) returns map<string> {
    map<string> result = {};
    foreach [string, string] [name, value] in metadata.entries() {
        result["x-ms-meta-" + name] = value;
    }
    return result;
}

// ---------------------------------------------------------------------------
// Shares
// ---------------------------------------------------------------------------

function shareDispatch(string method, string shareName, string comp, string snapshotParam,
        map<string> headers, byte[] payload) returns MockResponse {
    if method == "PUT" && comp == "undelete" {
        string deletedName = headers["x-ms-deleted-share-name"] ?: shareName;
        if !mockDeletedShares.hasKey(deletedName) {
            return errorResponse(404, "ShareNotFound");
        }
        MockShare share = mockDeletedShares.remove(deletedName);
        mockShares[shareName] = share;
        return okResponse(201);
    }
    if method == "PUT" && comp == "" {
        if mockShares.hasKey(shareName) {
            return errorResponse(409, "ShareAlreadyExists");
        }
        MockShare share = {etag: nextEtag(), metadata: metadataFrom(headers)};
        string? quota = headers["x-ms-share-quota"];
        if quota is string {
            share.quota = checkpanic int:fromString(quota);
        }
        string? tier = headers["x-ms-access-tier"];
        if tier is string {
            share.accessTier = tier;
        }
        mockShares[shareName] = share;
        return okResponse(201);
    }
    if !mockShares.hasKey(shareName) {
        return errorResponse(404, "ShareNotFound");
    }
    MockShare share = mockShares.get(shareName);
    if method == "PUT" && comp == "snapshot" {
        mockSnapshotCounter += 1;
        string snapshotId = string `2026-07-19T00:00:00.${mockSnapshotCounter}Z`;
        MockShare copy = share.clone();
        map<string> snapshotMetadata = metadataFrom(headers);
        if snapshotMetadata.length() > 0 {
            copy.metadata = snapshotMetadata;
        }
        mockShareSnapshots[snapshotKey(shareName, snapshotId)] = copy;
        return okResponse(201, {"x-ms-snapshot": snapshotId});
    }
    if method == "DELETE" && snapshotParam != "" {
        if !mockShareSnapshots.hasKey(snapshotKey(shareName, snapshotParam)) {
            return errorResponse(404, "ShareSnapshotNotFound");
        }
        _ = mockShareSnapshots.remove(snapshotKey(shareName, snapshotParam));
        return okResponse(202);
    }
    if method == "PUT" && comp == "lease" {
        var [response, newLeaseId, apply] = leaseAction(share.leaseId, headers);
        if apply {
            share.leaseId = newLeaseId;
            if (headers["x-ms-lease-action"] ?: "") == "acquire" {
                share.leaseDuration = (headers["x-ms-lease-duration"] ?: "-1") == "-1"
                    ? "infinite" : "fixed";
            }
        }
        return response;
    }
    if method == "PUT" && comp == "metadata" {
        share.metadata = metadataFrom(headers);
        share.etag = nextEtag();
        return okResponse(200);
    }
    if method == "PUT" && comp == "properties" {
        string? quota = headers["x-ms-share-quota"];
        if quota is string {
            share.quota = checkpanic int:fromString(quota);
        }
        string? tier = headers["x-ms-access-tier"];
        if tier is string {
            share.accessTier = tier;
        }
        share.etag = nextEtag();
        return okResponse(200);
    }
    if comp == "acl" {
        if method == "PUT" {
            share.aclXml = checkpanic string:fromBytes(payload);
            return okResponse(200);
        }
        return {
            status: 200,
            headers: {"x-ms-request-id": "mock"},
            body: share.aclXml.toBytes(),
            contentType: "application/xml"
        };
    }
    if comp == "filepermission" {
        if method == "PUT" {
            string bodyText = checkpanic string:fromBytes(payload);
            json body = checkpanic bodyText.fromJsonString();
            if body is map<json> && body["permission"] is string {
                mockPermissionCounter += 1;
                string key = string `mock-permission-key-${mockPermissionCounter}`;
                share.permissions[key] = <string>body["permission"];
                return okResponse(201, {"x-ms-file-permission-key": key});
            }
            return errorResponse(400, "InvalidHeaderValue");
        }
        string requestedKey = headers["x-ms-file-permission-key"] ?: "";
        string? sddl = share.permissions[requestedKey];
        if sddl is () {
            return errorResponse(404, "ResourceNotFound");
        }
        return {
            status: 200,
            headers: {"x-ms-request-id": "mock"},
            body: string `{"permission":${sddl.toJsonString()}}`.toBytes(),
            contentType: "application/json"
        };
    }
    if comp == "listhandles" {
        return listHandlesResponse(share, "");
    }
    if method == "PUT" && comp == "forceclosehandles" {
        return forceCloseHandlesResponse(share, "");
    }
    if (method == "GET" || method == "HEAD") && comp == "stats" {
        int usage = 0;
        foreach MockFile file in share.files {
            usage += file.size;
        }
        return xmlResponse(string `<ShareStats><ShareUsageBytes>${usage}</ShareUsageBytes></ShareStats>`);
    }
    if (method == "GET" || method == "HEAD") && comp == "" {
        map<string> extra = metadataHeaders(share.metadata);
        extra["x-ms-share-quota"] = share.quota.toString();
        extra["x-ms-access-tier"] = share.accessTier;
        string? shareLeaseId = share.leaseId;
        extra["x-ms-lease-state"] = shareLeaseId is string ? "leased" : "available";
        extra["x-ms-lease-status"] = shareLeaseId is string ? "locked" : "unlocked";
        if shareLeaseId is string {
            extra["x-ms-lease-duration"] = share.leaseDuration;
        }
        MockResponse response = okResponse(200, extra);
        response.headers["ETag"] = share.etag;
        return response;
    }
    if method == "DELETE" {
        _ = mockShares.remove(shareName);
        mockDeletedShares[shareName] = share;
        return okResponse(202);
    }
    return errorResponse(400, "InvalidQueryParameterValue");
}

function listSharesResponse(string prefix, string include) returns MockResponse {
    string entries = "";
    foreach [string, MockShare] [name, share] in mockShares.entries() {
        if prefix != "" && !name.startsWith(prefix) {
            continue;
        }
        entries += shareElement(name, share, false, include.includes("metadata"));
        if include.includes("snapshots") {
            foreach [string, MockShare] [key, snapshotShare] in mockShareSnapshots.entries() {
                string[] parts = re `\n`.split(key);
                if parts[0] == name {
                    entries += shareElement(name, snapshotShare, false,
                            include.includes("metadata"), parts[1]);
                }
            }
        }
    }
    if include.includes("deleted") {
        foreach [string, MockShare] [name, share] in mockDeletedShares.entries() {
            if prefix != "" && !name.startsWith(prefix) {
                continue;
            }
            entries += shareElement(name, share, true, include.includes("metadata"));
        }
    }
    return xmlResponse(string `<EnumerationResults ServiceEndpoint="http://localhost:${MOCK_PORT}/"><Shares>${entries}</Shares><NextMarker /></EnumerationResults>`);
}

function shareElement(string name, MockShare share, boolean deleted,
        boolean includeMetadata, string snapshotId = "") returns string {
    string metadata = "";
    if includeMetadata && share.metadata.length() > 0 {
        string items = "";
        foreach [string, string] [key, value] in share.metadata.entries() {
            items += string `<${key}>${value}</${key}>`;
        }
        metadata = string `<Metadata>${items}</Metadata>`;
    }
    string deletedElements = deleted ? "<Deleted>true</Deleted><Version>01D1MOCK</Version>" : "";
    string snapshotElement = snapshotId == "" ? "" : string `<Snapshot>${snapshotId}</Snapshot>`;
    return string `<Share><Name>${name}</Name>${snapshotElement}${deletedElements}<Properties><Last-Modified>${LAST_MODIFIED}</Last-Modified><Etag>${share.etag}</Etag><Quota>${share.quota}</Quota><AccessTier>${share.accessTier}</AccessTier></Properties>${metadata}</Share>`;
}

// ---------------------------------------------------------------------------
// Directories
// ---------------------------------------------------------------------------

function parentExists(MockShare share, string path) returns boolean {
    int? slash = path.lastIndexOf("/");
    if slash is () {
        return true;
    }
    return share.dirs.hasKey(path.substring(0, slash));
}

function directoryDispatch(string method, string shareName, string path, string comp,
        string include, string prefix, string snapshotParam, map<string> headers)
        returns MockResponse {
    MockShare? resolved = resolveShare(shareName, snapshotParam);
    if resolved is () {
        return errorResponse(404,
                snapshotParam == "" ? "ShareNotFound" : "ShareSnapshotNotFound");
    }
    MockShare share = resolved;
    if method == "PUT" && comp == "rename" {
        return renameEntry(share, shareName, path, headers, true);
    }
    if method == "PUT" && comp == "" {
        if path == "" || share.dirs.hasKey(path) {
            return errorResponse(409, "ResourceAlreadyExists");
        }
        if !parentExists(share, path) {
            return errorResponse(404, "ParentNotFound");
        }
        share.dirs[path] = {metadata: metadataFrom(headers), etag: nextEtag()};
        return okResponse(201);
    }
    if path != "" && !share.dirs.hasKey(path) {
        return errorResponse(404, "ResourceNotFound");
    }
    if method == "PUT" && comp == "metadata" {
        MockDir dir = share.dirs.get(path);
        dir.metadata = metadataFrom(headers);
        dir.etag = nextEtag();
        return okResponse(200);
    }
    if method == "PUT" && comp == "properties" {
        if path != "" && !share.dirs.hasKey(path) {
            return errorResponse(404, "ResourceNotFound");
        }
        return okResponse(200);
    }
    if comp == "listhandles" {
        return listHandlesResponse(share, path);
    }
    if method == "PUT" && comp == "forceclosehandles" {
        return forceCloseHandlesResponse(share, path);
    }
    if method == "GET" && comp == "list" {
        return listDirectoryResponse(shareName, share, path, prefix, include);
    }
    if method == "GET" || method == "HEAD" {
        map<string> extra = {"x-ms-server-encrypted": "true", "x-ms-file-attributes": "Directory"};
        string etag = nextEtag();
        if path != "" {
            MockDir dir = share.dirs.get(path);
            etag = dir.etag;
            foreach [string, string] [name, value] in metadataHeaders(dir.metadata).entries() {
                extra[name] = value;
            }
        }
        MockResponse response = okResponse(200, extra);
        response.headers["ETag"] = etag;
        return response;
    }
    if method == "DELETE" {
        foreach string filePath in share.files.keys() {
            if filePath.startsWith(path + "/") {
                return errorResponse(409, "DirectoryNotEmpty");
            }
        }
        foreach string dirPath in share.dirs.keys() {
            if dirPath.startsWith(path + "/") {
                return errorResponse(409, "DirectoryNotEmpty");
            }
        }
        _ = share.dirs.remove(path);
        return okResponse(202);
    }
    return errorResponse(400, "InvalidQueryParameterValue");
}

function directChildName(string parent, string entryPath) returns string? {
    string prefix = parent == "" ? "" : parent + "/";
    if !entryPath.startsWith(prefix) || entryPath == parent {
        return ();
    }
    string rest = entryPath.substring(prefix.length());
    return rest.includes("/") ? () : rest;
}

function listDirectoryResponse(string shareName, MockShare share, string path,
        string prefix, string include) returns MockResponse {
    boolean extended = include.includes("Etag") || include.includes("Timestamps");
    string entries = "";
    foreach [string, MockDir] [dirPath, dir] in share.dirs.entries() {
        string? name = directChildName(path, dirPath);
        if name is string && (prefix == "" || name.startsWith(prefix)) {
            string properties = extended
                ? string `<Properties><Last-Modified>${LAST_MODIFIED}</Last-Modified><Etag>${dir.etag}</Etag></Properties>`
                : "<Properties />";
            entries += string `<Directory><Name>${name}</Name><FileId>1</FileId>${properties}</Directory>`;
        }
    }
    foreach [string, MockFile] [filePath, file] in share.files.entries() {
        string? name = directChildName(path, filePath);
        if name is string && (prefix == "" || name.startsWith(prefix)) {
            string extendedProperties = extended
                ? string `<Last-Modified>${LAST_MODIFIED}</Last-Modified><Etag>${file.etag}</Etag>`
                : "";
            entries += string `<File><Name>${name}</Name><FileId>2</FileId><Properties><Content-Length>${file.size}</Content-Length>${extendedProperties}</Properties></File>`;
        }
    }
    return xmlResponse(string `<EnumerationResults ServiceEndpoint="http://localhost:${MOCK_PORT}/" ShareName="${shareName}" DirectoryPath="${path}"><Entries>${entries}</Entries><NextMarker /></EnumerationResults>`);
}

// ---------------------------------------------------------------------------
// Files
// ---------------------------------------------------------------------------

function fileDispatch(string method, string shareName, string path, string comp,
        string restype, string snapshotParam, string prevSnapshotParam, map<string> headers,
        byte[] payload) returns MockResponse {
    MockShare? resolved = resolveShare(shareName, snapshotParam);
    if resolved is () {
        return errorResponse(404,
                snapshotParam == "" ? "ShareNotFound" : "ShareSnapshotNotFound");
    }
    MockShare share = resolved;
    if restype == "hardlink" && method == "PUT" {
        // The target header is the share-relative path of the existing file, not including
        // the share name (a leading slash, if any, is tolerated).
        string targetHeader = checkpanic url:decode(headers["x-ms-file-target-file"] ?: "", "UTF-8");
        string targetKey = targetHeader.startsWith("/") ? targetHeader.substring(1) : targetHeader;
        if !share.files.hasKey(targetKey) {
            return errorResponse(404, "ResourceNotFound");
        }
        // Storing the same record makes both paths one file, which is what a hard link is.
        share.files[path] = share.files.get(targetKey);
        return okResponse(201);
    }
    if restype == "symboliclink" {
        if method == "PUT" {
            share.files[path] = {
                size: 0,
                content: [],
                metadata: metadataFrom(headers),
                contentHeaders: {},
                etag: nextEtag(),
                linkText: checkpanic url:decode(headers["x-ms-link-text"] ?: "", "UTF-8")
            };
            return okResponse(201);
        }
        MockFile? linkFile = share.files[path];
        if linkFile is () {
            return errorResponse(404, "ResourceNotFound");
        }
        string? linkText = linkFile.linkText;
        if linkText is () {
            return errorResponse(409, "InvalidResourceType");
        }
        return okResponse(200, {"x-ms-link-text": linkText});
    }
    if method == "PUT" && comp == "rename" {
        return renameEntry(share, shareName, path, headers, false);
    }
    if method == "PUT" && comp == "range" {
        return putRange(share, path, headers, payload);
    }
    if comp == "listhandles" {
        return listHandlesResponse(share, path);
    }
    if method == "PUT" && comp == "forceclosehandles" {
        return forceCloseHandlesResponse(share, path);
    }
    if method == "PUT" && comp == "copy" {
        // Abort copy: every mock copy completes synchronously, so there is nothing pending.
        return errorResponse(409, "NoPendingCopyOperation");
    }
    if method == "PUT" && headers.hasKey("x-ms-copy-source") {
        return startCopy(share, path, headers);
    }
    if method == "PUT" && comp == "" && (headers["x-ms-type"] ?: "") == "file" {
        if !parentExists(share, path) {
            return errorResponse(404, "ParentNotFound");
        }
        int size = checkpanic int:fromString(headers["x-ms-content-length"] ?: "0");
        map<string> contentHeaders = {};
        foreach string headerName in ["x-ms-content-type", "x-ms-content-encoding",
                "x-ms-content-language", "x-ms-content-disposition", "x-ms-cache-control",
                "x-ms-content-md5"] {
            string? value = headers[headerName];
            if value is string {
                contentHeaders[headerName.substring(5)] = value;
            }
        }
        share.files[path] = {
            size,
            content: zeros(size),
            metadata: metadataFrom(headers),
            contentHeaders,
            etag: nextEtag()
        };
        return okResponse(201);
    }
    if !share.files.hasKey(path) {
        return errorResponse(404, "ResourceNotFound");
    }
    MockFile file = share.files.get(path);
    if method == "PUT" && comp == "lease" {
        var [response, newLeaseId, apply] = leaseAction(file.leaseId, headers);
        if apply {
            file.leaseId = newLeaseId;
        }
        return response;
    }
    if method == "PUT" && comp == "metadata" {
        file.metadata = metadataFrom(headers);
        file.etag = nextEtag();
        return okResponse(200);
    }
    if method == "PUT" && comp == "properties" {
        map<string> contentHeaders = {};
        foreach string headerName in ["x-ms-content-type", "x-ms-content-encoding",
                "x-ms-content-language", "x-ms-content-disposition", "x-ms-cache-control",
                "x-ms-content-md5"] {
            string? value = headers[headerName];
            if value is string {
                contentHeaders[headerName.substring(5)] = value;
            }
        }
        file.contentHeaders = contentHeaders;
        string? newLength = headers["x-ms-content-length"];
        if newLength is string {
            int size = checkpanic int:fromString(newLength);
            if size < file.size {
                file.content = file.content.slice(0, size);
            } else if size > file.size {
                byte[] grown = file.content.clone();
                grown.setLength(size);
                file.content = grown;
            }
            file.size = size;
        }
        file.etag = nextEtag();
        return okResponse(200);
    }
    if method == "GET" && comp == "rangelist" {
        if prevSnapshotParam != "" {
            MockShare? baseline = resolveShare(shareName, prevSnapshotParam);
            if baseline is () {
                return errorResponse(404, "ShareSnapshotNotFound");
            }
            return rangeDiffResponse(file, baseline.files[path]);
        }
        return rangeListResponse(file);
    }
    if method == "HEAD" || (method == "GET" && comp == "") {
        return downloadOrProps(method, file, headers);
    }
    if method == "DELETE" {
        _ = share.files.remove(path);
        return okResponse(202);
    }
    return errorResponse(400, "InvalidQueryParameterValue");
}

function zeros(int size) returns byte[] {
    byte[] content = [];
    content.setLength(size);
    return content;
}

function fileHeaders(MockFile file) returns map<string> {
    map<string> result = metadataHeaders(file.metadata);
    result["ETag"] = file.etag;
    result["Last-Modified"] = LAST_MODIFIED;
    result["x-ms-request-id"] = "mock";
    result["x-ms-type"] = "File";
    result["x-ms-server-encrypted"] = "true";
    result["Content-Type"] = file.contentHeaders["content-type"] ?: "application/octet-stream";
    string? encoding = file.contentHeaders["content-encoding"];
    if encoding is string {
        result["Content-Encoding"] = encoding;
    }
    string? language = file.contentHeaders["content-language"];
    if language is string {
        result["Content-Language"] = language;
    }
    string? disposition = file.contentHeaders["content-disposition"];
    if disposition is string {
        result["Content-Disposition"] = disposition;
    }
    string? cacheControl = file.contentHeaders["cache-control"];
    if cacheControl is string {
        result["Cache-Control"] = cacheControl;
    }
    string? md5 = file.contentHeaders["content-md5"];
    if md5 is string {
        result["Content-MD5"] = md5;
    }
    string? copyId = file.copyId;
    if copyId is string {
        result["x-ms-copy-id"] = copyId;
        result["x-ms-copy-status"] = "success";
        result["x-ms-copy-progress"] = string `${file.size}/${file.size}`;
        result["x-ms-copy-source"] = "http://localhost:9099/mock";
    }
    string? fileLeaseId = file.leaseId;
    if fileLeaseId is string {
        result["x-ms-lease-state"] = "leased";
        result["x-ms-lease-status"] = "locked";
        result["x-ms-lease-duration"] = "infinite";
    } else {
        result["x-ms-lease-state"] = "available";
        result["x-ms-lease-status"] = "unlocked";
    }
    return result;
}

// The shared lease protocol: one PUT with an x-ms-lease-action header drives the whole
// lifecycle. Returns the response, the lease id after the action, and whether to apply it.
function leaseAction(string? current, map<string> headers) returns [MockResponse, string?, boolean] {
    string action = headers["x-ms-lease-action"] ?: "";
    if action == "acquire" {
        if current is string {
            return [errorResponse(409, "LeaseAlreadyPresent"), (), false];
        }
        mockLeaseCounter += 1;
        string id = headers["x-ms-proposed-lease-id"] ?: string `mock-lease-${mockLeaseCounter}`;
        return [okResponse(201, {"x-ms-lease-id": id}), id, true];
    }
    if current is () {
        return [errorResponse(409, "LeaseNotPresentWithLeaseOperation"), (), false];
    }
    if action == "break" {
        string breakPeriod = headers["x-ms-lease-break-period"] ?: "0";
        return [okResponse(202, {"x-ms-lease-time": breakPeriod}), (), true];
    }
    string presented = headers["x-ms-lease-id"] ?: "";
    if presented != current {
        return [errorResponse(409, "LeaseIdMismatchWithLeaseOperation"), (), false];
    }
    if action == "renew" {
        return [okResponse(200, {"x-ms-lease-id": current}), current, true];
    }
    if action == "release" {
        return [okResponse(200), (), true];
    }
    if action == "change" {
        string proposed = headers["x-ms-proposed-lease-id"] ?: current;
        return [okResponse(200, {"x-ms-lease-id": proposed}), proposed, true];
    }
    return [errorResponse(400, "InvalidHeaderValue"), (), false];
}

function downloadOrProps(string method, MockFile file, map<string> headers)
        returns MockResponse {
    map<string> responseHeaders = fileHeaders(file);
    if method == "HEAD" {
        // The listener recomputes Content-Length from the entity, so the properties response
        // must carry the real content; the transport strips the body for HEAD.
        return {status: 200, headers: responseHeaders, body: file.content.clone()};
    }
    string? rangeHeader = headers["x-ms-range"] ?: headers["range"];
    if rangeHeader is () {
        return {status: 200, headers: responseHeaders, body: file.content.clone()};
    }
    string spec = rangeHeader.substring(6); // strip "bytes="
    string[] bounds = re `-`.split(spec);
    int rangeStart = checkpanic int:fromString(bounds[0]);
    int rangeEnd = bounds.length() > 1 && bounds[1] != "" ? checkpanic int:fromString(bounds[1]) : file.size - 1;
    if rangeStart >= file.size {
        return errorResponse(416, "InvalidRange");
    }
    int clampedEnd = rangeEnd >= file.size ? file.size - 1 : rangeEnd;
    byte[] slice = file.content.slice(rangeStart, clampedEnd + 1);
    responseHeaders["Content-Range"] = string `bytes ${rangeStart}-${clampedEnd}/${file.size}`;
    return {status: 206, headers: responseHeaders, body: slice};
}

function putRange(MockShare share, string path, map<string> headers, byte[] payload)
        returns MockResponse {
    if !share.files.hasKey(path) {
        return errorResponse(404, "ResourceNotFound");
    }
    MockFile file = share.files.get(path);
    string rangeHeader = headers["x-ms-range"] ?: headers["range"] ?: "bytes=0-0";
    string[] bounds = re `-`.split(rangeHeader.substring(6));
    int rangeStart = checkpanic int:fromString(bounds[0]);
    int rangeEnd = checkpanic int:fromString(bounds[1]);
    if rangeEnd >= file.size {
        return errorResponse(416, "InvalidRange");
    }
    boolean clearWrite = (headers["x-ms-write"] ?: "update") == "clear";
    foreach int i in rangeStart ... rangeEnd {
        file.content[i] = clearWrite ? 0 : payload[i - rangeStart];
    }
    file.etag = nextEtag();
    return okResponse(201);
}

function rangeListResponse(MockFile file) returns MockResponse {
    // Report one whole-file range when any byte is nonzero; an empty list otherwise. Enough
    // for the tests without tracking written ranges byte-by-byte.
    boolean hasContent = false;
    foreach byte b in file.content {
        if b != 0 {
            hasContent = true;
            break;
        }
    }
    string ranges = hasContent && file.size > 0
        ? string `<Range><Start>0</Start><End>${file.size - 1}</End></Range>` : "";
    return xmlResponse(string `<Ranges>${ranges}</Ranges>`);
}

// SMB handles: any file whose name is held.txt reports one canned open handle; everything
// else reports none. Enough to exercise listing, per-handle close, and recursive close.
function heldHandlePaths(MockShare share, string path) returns string[] {
    if share.files.hasKey(path) {
        return path.endsWith("held.txt") ? [path] : [];
    }
    string[] matches = [];
    foreach string filePath in share.files.keys() {
        if filePath.endsWith("held.txt") && (path == "" || filePath.startsWith(path + "/")) {
            matches.push(filePath);
        }
    }
    return matches;
}

function listHandlesResponse(MockShare share, string path) returns MockResponse {
    string entries = "";
    foreach string heldPath in heldHandlePaths(share, path) {
        entries += string `<Handle><HandleId>1</HandleId><Path>${heldPath}</Path><FileId>2</FileId><SessionId>3</SessionId><ClientIp>10.0.0.1</ClientIp><OpenTime>${LAST_MODIFIED}</OpenTime></Handle>`;
    }
    return xmlResponse(string `<EnumerationResults><Entries>${entries}</Entries><NextMarker /></EnumerationResults>`);
}

function forceCloseHandlesResponse(MockShare share, string path) returns MockResponse {
    int closed = heldHandlePaths(share, path).length();
    return okResponse(200, {
        "x-ms-number-of-handles-closed": closed.toString(),
        "x-ms-number-of-handles-failed": "0"
    });
}

// Byte-scan diff between the live file and its snapshot baseline: contiguous regions where
// the live content differs and is nonzero become Ranges, regions where snapshot content was
// overwritten with zeros become ClearRanges.
function rangeDiffResponse(MockFile live, MockFile? baseline) returns MockResponse {
    byte[] snapContent = baseline is MockFile ? baseline.content : [];
    string ranges = "";
    string clearRanges = "";
    int i = 0;
    while i < live.size {
        byte liveByte = live.content[i];
        byte snapByte = i < snapContent.length() ? snapContent[i] : 0;
        if liveByte != snapByte && liveByte != 0 {
            int rangeStart = i;
            while i < live.size && live.content[i] != 0
                    && live.content[i] != (i < snapContent.length() ? snapContent[i] : 0) {
                i += 1;
            }
            ranges += string `<Range><Start>${rangeStart}</Start><End>${i - 1}</End></Range>`;
        } else if liveByte == 0 && snapByte != 0 {
            int clearStart = i;
            while i < live.size && live.content[i] == 0
                    && (i < snapContent.length() ? snapContent[i] : 0) != 0 {
                i += 1;
            }
            clearRanges += string `<ClearRange><Start>${clearStart}</Start><End>${i - 1}</End></ClearRange>`;
        } else {
            i += 1;
        }
    }
    return xmlResponse(string `<Ranges>${ranges}${clearRanges}</Ranges>`);
}

function startCopy(MockShare share, string path, map<string> headers) returns MockResponse {
    string sourceHeader = checkpanic url:decode(headers["x-ms-copy-source"] ?: "", "UTF-8");
    // The source URL has the form http://host:port/{share}/{path...}.
    int schemeEnd = sourceHeader.indexOf("://") is int ? <int>sourceHeader.indexOf("://") + 3 : 0;
    int? hostEnd = sourceHeader.indexOf("/", schemeEnd);
    if hostEnd is () {
        return errorResponse(404, "CannotVerifyCopySource");
    }
    string sourceFull = sourceHeader.substring(hostEnd + 1);
    int? firstSlash = sourceFull.indexOf("/");
    if firstSlash is () {
        return errorResponse(404, "CannotVerifyCopySource");
    }
    string sourceShareName = sourceFull.substring(0, firstSlash);
    string sourcePath = sourceFull.substring(firstSlash + 1);
    if !mockShares.hasKey(sourceShareName) {
        return errorResponse(404, "CannotVerifyCopySource");
    }
    MockShare sourceShare = mockShares.get(sourceShareName);
    if !sourceShare.files.hasKey(sourcePath) {
        return errorResponse(404, "CannotVerifyCopySource");
    }
    MockFile sourceFile = sourceShare.files.get(sourcePath);
    mockCopyCounter += 1;
    string copyId = string `copy-${mockCopyCounter}`;
    map<string> metadata = metadataFrom(headers);
    share.files[path] = {
        size: sourceFile.size,
        content: sourceFile.content.clone(),
        metadata: metadata.length() > 0 ? metadata : sourceFile.metadata.clone(),
        contentHeaders: sourceFile.contentHeaders.clone(),
        etag: nextEtag(),
        copyId
    };
    return okResponse(202, {"x-ms-copy-id": copyId, "x-ms-copy-status": "success"});
}

function renameEntry(MockShare share, string shareName, string destinationPath,
        map<string> headers, boolean isDirectory) returns MockResponse {
    string sourceHeader = checkpanic url:decode(headers["x-ms-file-rename-source"] ?: "", "UTF-8");
    int schemeEnd = sourceHeader.indexOf("://") is int ? <int>sourceHeader.indexOf("://") + 3 : 0;
    int? hostEnd = sourceHeader.indexOf("/", schemeEnd);
    if hostEnd is () {
        return errorResponse(404, "ResourceNotFound");
    }
    string sourceFull = sourceHeader.substring(hostEnd + 1);
    int? firstSlash = sourceFull.indexOf("/");
    if firstSlash is () {
        return errorResponse(404, "ResourceNotFound");
    }
    string sourcePath = sourceFull.substring(firstSlash + 1);
    boolean replaceIfExists = (headers["x-ms-file-rename-replace-if-exists"] ?: "false") == "true";
    if share.dirs.hasKey(destinationPath) {
        return errorResponse(409, "ResourceAlreadyExists");
    }
    if share.files.hasKey(destinationPath) && !replaceIfExists {
        return errorResponse(409, "ResourceAlreadyExists");
    }
    if isDirectory {
        if !share.dirs.hasKey(sourcePath) {
            return errorResponse(404, "ResourceNotFound");
        }
        MockDir dir = share.dirs.remove(sourcePath);
        share.dirs[destinationPath] = dir;
        // Move the subtree with the directory.
        foreach string dirPath in share.dirs.keys() {
            if dirPath.startsWith(sourcePath + "/") {
                MockDir child = share.dirs.remove(dirPath);
                share.dirs[destinationPath + dirPath.substring(sourcePath.length())] = child;
            }
        }
        foreach string filePath in share.files.keys() {
            if filePath.startsWith(sourcePath + "/") {
                MockFile child = share.files.remove(filePath);
                share.files[destinationPath + filePath.substring(sourcePath.length())] = child;
            }
        }
    } else {
        if !share.files.hasKey(sourcePath) {
            return errorResponse(404, "ResourceNotFound");
        }
        MockFile file = share.files.remove(sourcePath);
        if share.files.hasKey(destinationPath) {
            _ = share.files.remove(destinationPath);
        }
        share.files[destinationPath] = file;
    }
    return okResponse(200);
}


