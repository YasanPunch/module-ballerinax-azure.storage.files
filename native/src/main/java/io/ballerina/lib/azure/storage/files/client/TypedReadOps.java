/*
 * Copyright (c) 2026, WSO2 LLC. (http://www.wso2.com).
 *
 * WSO2 LLC. licenses this file to you under the Apache License,
 * Version 2.0 (the "License"); you may not use this file except
 * in compliance with the License.
 * You may obtain a copy of the License at
 *
 *    http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing,
 * software distributed under the License is distributed on an
 * "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
 * KIND, either express or implied. See the License for the
 * specific language governing permissions and limitations
 * under the License.
 */

package io.ballerina.lib.azure.storage.files.client;

import com.azure.storage.file.share.ShareFileClient;
import io.ballerina.lib.azure.storage.files.util.DataBindingOptions;
import io.ballerina.lib.azure.storage.files.util.FilesErrorCreator;
import io.ballerina.lib.azure.storage.files.util.OptionsReader;
import io.ballerina.lib.azure.storage.files.util.SdkInvoker;
import io.ballerina.lib.azure.storage.files.util.ValueUtils;
import io.ballerina.runtime.api.Environment;
import io.ballerina.runtime.api.creators.ValueCreator;
import io.ballerina.runtime.api.types.ArrayType;
import io.ballerina.runtime.api.types.RecordType;
import io.ballerina.runtime.api.types.Type;
import io.ballerina.runtime.api.utils.TypeUtils;
import io.ballerina.runtime.api.utils.XmlUtils;
import io.ballerina.runtime.api.values.BArray;
import io.ballerina.runtime.api.values.BError;
import io.ballerina.runtime.api.values.BMap;
import io.ballerina.runtime.api.values.BObject;
import io.ballerina.runtime.api.values.BString;
import io.ballerina.runtime.api.values.BTypedesc;

import java.io.ByteArrayOutputStream;
import java.nio.charset.StandardCharsets;

/**
 * Typed content reads: download a file's full content and bind it to the caller-directed target
 * type through the data.jsondata, data.xmldata, and data.csv modules. Binding is strict (the
 * listener's {@code laxDataBinding} does not apply to client reads) and always runs on the
 * extern's own strand, after the network call has returned from {@link SdkInvoker#invoke}.
 */
public final class TypedReadOps {

    private static final String XML_TYPE_NAME = "xml";
    private static final BString CALLER_CLIENT_FIELD = io.ballerina.runtime.api.utils.StringUtils
            .fromString("client");

    private TypedReadOps() {
    }

    /** Downloads a file's full content (or a range of it) into a Ballerina byte array. */
    public static Object readFileBytes(Environment env, BObject clientObj, BString path, Object options) {
        return SdkInvoker.invoke(env, () -> {
            Object range = null;
            String snapshotId = null;
            if (options != null) {
                @SuppressWarnings("unchecked")
                BMap<BString, Object> record = (BMap<BString, Object>) options;
                range = record.get(OptionsReader.RANGE);
                snapshotId = ValueUtils.optString(record, OptionsReader.SNAPSHOT_ID);
            }
            ShareFileClient client = FileOps.fileClient(clientObj, path, snapshotId);
            ByteArrayOutputStream out = new ByteArrayOutputStream();
            if (range == null) {
                client.download(out);
            } else {
                client.downloadWithResponse(out, OptionsReader.range(range), null, null, null);
            }
            return ValueCreator.createArrayValue(out.toByteArray());
        });
    }

    public static Object getFileJson(Environment env, BObject clientObj, BString path, Object options,
                                     BTypedesc targetType) {
        Object bytes = readFileBytes(env, clientObj, path, options);
        if (bytes instanceof BError) {
            return bytes;
        }
        try {
            Object result = io.ballerina.lib.data.jsondata.json.Native.parseBytes((BArray) bytes,
                    DataBindingOptions.jsonParseOptions(false), targetType);
            return result instanceof BError bError ? bindingFailure("JSON", bError) : result;
        } catch (BError e) {
            return bindingFailure("JSON", e);
        }
    }

    public static Object getFileXml(Environment env, BObject clientObj, BString path, Object options,
                                    BTypedesc targetType) {
        Object bytes = readFileBytes(env, clientObj, path, options);
        if (bytes instanceof BError) {
            return bytes;
        }
        BArray byteArray = (BArray) bytes;
        Type described = TypeUtils.getReferredType(targetType.getDescribingType());
        if (XML_TYPE_NAME.equals(described.getQualifiedName())) {
            try {
                return XmlUtils.parse(new String(byteArray.getBytes(), StandardCharsets.UTF_8));
            } catch (BError e) {
                return FilesErrorCreator.processingError(
                        "the file content is not valid XML: " + e.getErrorMessage(), e);
            }
        }
        try {
            // The xmldata parser does not unwrap type references, so hand it the referred type.
            Object result = io.ballerina.lib.data.xmldata.xml.Native.parseBytes(byteArray,
                    DataBindingOptions.xmlSourceOptions(false), ValueCreator.createTypedescValue(described));
            return result instanceof BError bError ? bindingFailure("XML", bError) : result;
        } catch (BError e) {
            return bindingFailure("XML", e);
        }
    }

    public static Object getFileCsv(Environment env, BObject clientObj, BString path, Object options,
                                    BTypedesc targetType) {
        Object bytes = readFileBytes(env, clientObj, path, options);
        if (bytes instanceof BError) {
            return bytes;
        }
        Type described = TypeUtils.getReferredType(targetType.getDescribingType());
        boolean recordTarget = described instanceof ArrayType arrayType
                && TypeUtils.getReferredType(arrayType.getElementType()) instanceof RecordType;
        try {
            Object result = io.ballerina.lib.data.csvdata.csv.Native.parseBytes(env, (BArray) bytes,
                    DataBindingOptions.csvParseOptions(false, !recordTarget), targetType);
            return result instanceof BError bError ? bindingFailure("CSV", bError) : result;
        } catch (BError e) {
            return bindingFailure("CSV", e);
        }
    }

    public static Object callerGetFileJson(Environment env, BObject caller, BString path, Object options,
                                           BTypedesc targetType) {
        return getFileJson(env, callerClient(caller), path, options, targetType);
    }

    public static Object callerGetFileXml(Environment env, BObject caller, BString path, Object options,
                                          BTypedesc targetType) {
        return getFileXml(env, callerClient(caller), path, options, targetType);
    }

    public static Object callerGetFileCsv(Environment env, BObject caller, BString path, Object options,
                                          BTypedesc targetType) {
        return getFileCsv(env, callerClient(caller), path, options, targetType);
    }

    private static BObject callerClient(BObject caller) {
        return (BObject) caller.getObjectValue(CALLER_CLIENT_FIELD);
    }

    private static BError bindingFailure(String kind, BError cause) {
        return FilesErrorCreator.processingError("the file content does not bind to the target "
                + kind + " type: " + cause.getErrorMessage(), cause);
    }
}
