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

import ballerina/data.csv;
import ballerina/data.jsondata as _;
import ballerina/data.xmldata as _;
import ballerina/file;

// Binds CSV file content to the declared handler type through the data.csv module. Invoked from
// the native dispatcher, which supplies the handler's declared parameter type as the typedesc.
isolated function bindCsvContent(byte[] content, typedesc<string[][]|record {}[]> targetType,
        boolean laxDataBinding, FailSafeOptions? csvFailSafe, string fileNamePrefix)
        returns string[][]|record {}[]|error {
    csv:ParseOptions options = csvParseOptions(laxDataBinding);
    if targetType is typedesc<record {}[]> {
        // A record target maps its fields through the header row (the file's first row),
        // which the data.csv default already consumes.
    } else {
        // The string matrix keeps every row of the file, including the first.
        options.header = ();
    }
    if csvFailSafe is FailSafeOptions {
        string currentDir = file:getCurrentDir();
        options.failSafe = {
            fileOutputMode: {
                filePath: currentDir + "/" + fileNamePrefix + "_error.log",
                fileWriteOption: csv:APPEND,
                contentType: csvFailSafe.contentType
            }
        };
    }
    return csv:parseBytes(content, options, targetType);
}

// The CSV parse options shared by the materialized and stream binding paths: only the data
// projection toggle is set, everything else keeps the data.csv defaults.
isolated function csvParseOptions(boolean laxDataBinding) returns csv:ParseOptions {
    if laxDataBinding {
        return {allowDataProjection: {nilAsOptionalField: true, absentAsNilableType: true}};
    }
    return {allowDataProjection: false};
}
