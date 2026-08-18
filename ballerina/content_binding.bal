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
// The jsondata import keeps the module in the dependency graph: the Java adaptor calls its
// natives directly (TypedReadOps and ContentBinder), with no Ballerina-side reference.
import ballerina/data.jsondata as _;

// Binds CSV file content to the declared handler type through the data.csv module. Invoked from
// the native dispatcher, which supplies the handler's declared parameter type as the typedesc.
// Each record maps its fields through the header row (the file's first row), which the
// data.csv default consumes.
isolated function bindCsvContent(byte[] content, typedesc<record {}[]> targetType,
        boolean laxDataBinding) returns record {}[]|error {
    return csv:parseBytes(content, csvParseOptions(laxDataBinding), targetType);
}

// The CSV parse options shared by the materialized and stream binding paths: only the data
// projection toggle is set, everything else keeps the data.csv defaults.
isolated function csvParseOptions(boolean laxDataBinding) returns csv:ParseOptions {
    if laxDataBinding {
        return {allowDataProjection: {nilAsOptionalField: true, absentAsNilableType: true}};
    }
    return {allowDataProjection: false};
}
