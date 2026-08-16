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

import ballerina/data.xmldata;

// Resolves the serialization format of record content: an explicit override wins,
// otherwise the destination path's extension decides.
isolated function resolveUploadFormat(string destinationPath, FileFormat? override) returns FileFormat? {
    if override is FileFormat {
        return override;
    }
    string lower = destinationPath.toLowerAscii();
    if lower.endsWith(".json") {
        return JSON;
    }
    if lower.endsWith(".xml") {
        return XML;
    }
    if lower.endsWith(".csv") {
        return CSV;
    }
    return ();
}

// Serializes a single record as a JSON or an XML document per the resolved format.
// A single record is never CSV, and an unresolvable format is refused.
isolated function serializeRecord(record {} content, string destinationPath,
        FileFormat? override) returns string|Error {
    FileFormat? format = resolveUploadFormat(destinationPath, override);
    if format is JSON {
        return content.toJsonString();
    }
    if format is XML {
        xml|xmldata:Error document = xmldata:toXml(content);
        if document is xmldata:Error {
            return error Error("record {} content could not be serialized as XML: " + document.message(), document);
        }
        return document.toString();
    }
    if format is CSV {
        return error Error("record {} content cannot be serialized as CSV");
    }
    return error Error("record {} content requires a '.json' or '.xml' extension in the "
            + "destination path, or an explicit fileFormat");
}

// Serializes a record array as CSV rows: the first record's field names form the header
// row, values are stringified in header order, and a nil member becomes an empty cell.
// A record array is only CSV; any other resolved format is refused.
isolated function serializeRecordArray(record {}[] content, string destinationPath,
        FileFormat? override) returns string[][]|Error {
    FileFormat? format = resolveUploadFormat(destinationPath, override);
    if format !is CSV {
        return error Error("record {}[] content requires CSV format");
    }
    if content.length() == 0 {
        return [];
    }
    string[] header = content[0].keys();
    string[][] rows = [header];
    foreach record {} entry in content {
        string[] row = [];
        foreach string fieldName in header {
            anydata value = entry[fieldName];
            row.push(value is () ? "" : value.toString());
        }
        rows.push(row);
    }
    return rows;
}
