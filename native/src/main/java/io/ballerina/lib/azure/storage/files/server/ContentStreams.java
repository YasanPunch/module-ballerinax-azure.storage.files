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

package io.ballerina.lib.azure.storage.files.server;

import io.ballerina.lib.azure.storage.files.util.FilesErrorCreator;
import io.ballerina.lib.azure.storage.files.util.ModuleUtils;
import io.ballerina.lib.azure.storage.files.util.SdkInvoker;
import io.ballerina.runtime.api.Runtime;
import io.ballerina.runtime.api.concurrent.StrandMetadata;
import io.ballerina.runtime.api.creators.TypeCreator;
import io.ballerina.runtime.api.creators.ValueCreator;
import io.ballerina.runtime.api.types.PredefinedTypes;
import io.ballerina.runtime.api.types.StreamType;
import io.ballerina.runtime.api.types.Type;
import io.ballerina.runtime.api.utils.StringUtils;
import io.ballerina.runtime.api.utils.TypeUtils;
import io.ballerina.runtime.api.values.BError;
import io.ballerina.runtime.api.values.BMap;
import io.ballerina.runtime.api.values.BObject;
import io.ballerina.runtime.api.values.BStream;
import io.ballerina.runtime.api.values.BString;

import java.io.IOException;
import java.io.InputStream;
import java.util.Arrays;

/**
 * Backs the listener's stream content forms: a chunked byte stream over the watched file's
 * service input stream, and the CSV row stream layered on top of it through the module's
 * {@code ContentCsvStream} class. The source input stream closes at the end of the file, on an
 * explicit {@code close()}, or when the CSV layer finishes.
 */
public final class ContentStreams {

    private static final String NATIVE_INPUT_STREAM = "inputStream";
    private static final String CONTENT_BYTE_STREAM_OBJECT = "ContentByteStream";
    private static final String NEW_CONTENT_CSV_STREAM_FUNCTION = "newContentCsvStream";
    private static final String CONTENT_STREAM_ENTRY_RECORD = "ContentStreamEntry";
    private static final BString FIELD_VALUE = StringUtils.fromString("value");
    private static final BString FIELD_IS_CLOSED = StringUtils.fromString("isClosed");
    // One service read per next() call.
    private static final int CHUNK_SIZE = 8192;

    private ContentStreams() {
    }

    /**
     * Creates the {@code stream<byte[], error?>} value handed to a stream content handler.
     *
     * @param content     the file's service input stream
     * @param elementType the stream's constrained type ({@code byte[]})
     * @return the Ballerina stream value
     */
    static Object createByteStream(InputStream content, Type elementType) {
        BObject iterator = ValueCreator.createObjectValue(ModuleUtils.getModule(), CONTENT_BYTE_STREAM_OBJECT);
        iterator.addNativeData(NATIVE_INPUT_STREAM, content);
        StreamType streamType = TypeCreator.createStreamType(elementType,
                TypeCreator.createUnionType(PredefinedTypes.TYPE_ERROR, PredefinedTypes.TYPE_NULL));
        return ValueCreator.createStreamValue(streamType, iterator);
    }

    /**
     * Creates the {@code stream<string[]|record{}, error?>} value handed to a CSV stream content
     * handler: a byte stream over the file wrapped by the module's {@code ContentCsvStream}. The
     * wrapping object is constructed through the runtime on a real strand, because its
     * initialization runs the data.csv stream construction.
     *
     * @param runtime        the Ballerina runtime
     * @param content        the file's service input stream
     * @param elementType    the stream's constrained type (a {@code string[]} or a record)
     * @param laxDataBinding whether relaxed data projection applies
     * @return the Ballerina stream value
     */
    static Object createCsvStream(Runtime runtime, InputStream content, Type elementType, boolean laxDataBinding) {
        Type byteArrayType = TypeCreator.createArrayType(PredefinedTypes.TYPE_BYTE);
        BStream byteStream = (BStream) createByteStream(content, byteArrayType);
        Object iterator = runtime.callFunction(ModuleUtils.getModule(), NEW_CONTENT_CSV_STREAM_FUNCTION,
                new StrandMetadata(true, null),
                ValueCreator.createTypedescValue(TypeUtils.getReferredType(elementType)),
                byteStream, laxDataBinding);
        if (iterator instanceof BError e) {
            throw FilesErrorCreator.processingError(
                    "CSV stream binding could not be created: " + e.getErrorMessage(), e);
        }
        StreamType streamType = TypeCreator.createStreamType(elementType,
                TypeCreator.createUnionType(PredefinedTypes.TYPE_ERROR, PredefinedTypes.TYPE_NULL));
        return ValueCreator.createStreamValue(streamType, (BObject) iterator);
    }

    /**
     * Reads the next chunk of the file. Bound from {@code ContentByteStream.next}.
     *
     * @param iterator the Ballerina iterator object
     * @return the next chunk entry, {@code null} at the end of the file, or an error
     */
    public static Object byteStreamNext(BObject iterator) {
        InputStream inputStream = (InputStream) iterator.getNativeData(NATIVE_INPUT_STREAM);
        try {
            byte[] buffer = new byte[CHUNK_SIZE];
            int read = inputStream.read(buffer);
            if (read == -1) {
                inputStream.close();
                iterator.set(FIELD_IS_CLOSED, true);
                return null;
            }
            byte[] chunk = read < CHUNK_SIZE ? Arrays.copyOfRange(buffer, 0, read) : buffer;
            BMap<BString, Object> entry = ValueCreator.createRecordValue(
                    ModuleUtils.getModule(), CONTENT_STREAM_ENTRY_RECORD);
            entry.put(FIELD_VALUE, ValueCreator.createArrayValue(chunk));
            return entry;
        } catch (IOException e) {
            return FilesErrorCreator.processingError("failed to read the file content stream: "
                    + SdkInvoker.describe(e), e);
        }
    }

    /**
     * Closes the file's input stream. Bound from {@code ContentByteStream.close}.
     *
     * @param iterator the Ballerina iterator object
     * @return {@code null}, or an error when the source could not be closed
     */
    public static Object close(BObject iterator) {
        Object inputStream = iterator.getNativeData(NATIVE_INPUT_STREAM);
        if (inputStream != null) {
            try {
                ((InputStream) inputStream).close();
            } catch (IOException e) {
                return FilesErrorCreator.processingError("failed to close the file content stream: "
                        + SdkInvoker.describe(e), e);
            }
        }
        return null;
    }
}
