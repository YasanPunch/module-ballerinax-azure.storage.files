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

import ballerina/io;
import ballerina/time;

import ballerinax/azure.storage.files;

configurable string accountName = ?;
configurable string accountKey = ?;
configurable string shareName = "handout-example";

public function main() returns error? {
    // Create the share if this is the first run.
    files:AdminClient admin = check new (auth = {accountName, accountKey});
    boolean shareExists = check admin->hasShare(shareName);
    if !shareExists {
        check admin->createShare(shareName);
    }
    check admin.close();

    // Upload the report to hand out.
    files:Client share = check new (shareName, auth = {accountName, accountKey});
    check share->uploadContent("Quarterly revenue is up 14%.", "/q2-summary.txt");

    // Mint a read-only shared access signature for that one file, expiring in 24 hours.
    time:Utc expiry = time:utcAddSeconds(time:utcNow(), 86400);
    string sasToken = check share.generateSas("/q2-summary.txt", {
        expiryTime: expiry,
        permissions: {read: true}
    });

    io:println("Hand out this URL; it grants read access to this file only, for 24 hours:");
    io:println(string `https://${accountName}.file.core.windows.net/${shareName}/q2-summary.txt?${sasToken}`);

    check share.close();
}
