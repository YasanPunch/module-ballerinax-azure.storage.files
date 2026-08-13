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
import io.ballerina.lib.azure.storage.files.util.BallerinaAzureClient;
import io.ballerina.lib.azure.storage.files.util.ContentBinder;
import io.ballerina.lib.azure.storage.files.util.DataBindingOptions;
import io.ballerina.lib.azure.storage.files.util.FilesErrorCreator;
import io.ballerina.lib.azure.storage.files.util.OptionsReader;
import io.ballerina.runtime.api.Environment;
import io.ballerina.runtime.api.creators.ValueCreator;
import io.ballerina.runtime.api.types.ArrayType;
import io.ballerina.runtime.api.types.RecordType;
import io.ballerina.runtime.api.types.Type;
import io.ballerina.runtime.api.utils.TypeUtils;
import io.ballerina.runtime.api.values.BArray;
import io.ballerina.runtime.api.values.BError;
import io.ballerina.runtime.api.values.BObject;
import io.ballerina.runtime.api.values.BString;
import io.ballerina.runtime.api.values.BTypedesc;

import java.io.ByteArrayOutputStream;

/**
 * Typed content reads: download a file's full content and bind it to the caller-directed target
 * type through the data.jsondata, data.xmldata, and data.csv modules. Binding is strict (the
 * listener's {@code laxDataBinding} does not apply to client reads) and always runs on the
 * extern's own strand, after the network call has returned from {@link BallerinaAzureClient#invoke}.
 */
public final class TypedReadOps {

    private TypedReadOps() {
    }

    /** Downloads a file's full content (or a range of it) into a Ballerina byte array. */
    public static Object readFileBytes(Environment env, BObject clientObj, BString path, Object options) {
        return BallerinaAzureClient.invoke(env, () -> {
            OptionsReader.DownloadArgs args = OptionsReader.downloadArgs(options);
            ShareFileClient client = FileOps.fileClient(clientObj, path, args.snapshotId());
            ByteArrayOutputStream out = new ByteArrayOutputStream();
            if (args.range() == null) {
                client.download(out);
            } else {
                client.downloadWithResponse(out, OptionsReader.range(args.range()), null, null, null);
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
            return ContentBinder.bindJson((BArray) bytes,
                    TypeUtils.getReferredType(targetType.getDescribingType()), false,
                    "the file content does not bind to the target JSON type");
        } catch (BError e) {
            return e;
        }
    }

    public static Object getFileXml(Environment env, BObject clientObj, BString path, Object options,
                                    BTypedesc targetType) {
        Object bytes = readFileBytes(env, clientObj, path, options);
        if (bytes instanceof BError) {
            return bytes;
        }
        try {
            return ContentBinder.bindXml((BArray) bytes,
                    TypeUtils.getReferredType(targetType.getDescribingType()), false,
                    "the file content does not bind to the target XML type",
                    "the file content is not valid XML");
        } catch (BError e) {
            return e;
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
        return (BObject) caller.getObjectValue(BallerinaAzureClient.CALLER_CLIENT_FIELD);
    }

    private static BError bindingFailure(String kind, BError cause) {
        return FilesErrorCreator.clientError("the file content does not bind to the target "
                + kind + " type: " + cause.getErrorMessage(), cause);
    }
}
