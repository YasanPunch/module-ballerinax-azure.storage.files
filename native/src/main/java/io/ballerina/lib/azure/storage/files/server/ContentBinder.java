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

import io.ballerina.lib.azure.storage.files.util.DataBindingOptions;
import io.ballerina.lib.azure.storage.files.util.FilesErrorCreator;
import io.ballerina.runtime.api.creators.ValueCreator;
import io.ballerina.runtime.api.types.Type;
import io.ballerina.runtime.api.utils.TypeUtils;
import io.ballerina.runtime.api.utils.XmlUtils;
import io.ballerina.runtime.api.values.BArray;
import io.ballerina.runtime.api.values.BError;
import io.ballerina.runtime.api.values.BMap;
import io.ballerina.runtime.api.values.BString;
import io.ballerina.runtime.api.values.BTypedesc;

import java.nio.charset.StandardCharsets;

/**
 * Binds typed listener content through the {@code ballerina/data.jsondata} and
 * {@code ballerina/data.xmldata} modules, honoring the listener's {@code laxDataBinding} setting.
 * A binding failure is thrown as the module's {@code ProcessingError}. CSV binding runs on a
 * Ballerina strand instead (see the module-level {@code bindCsvContent} helper), because the
 * data.csv parser needs the runtime environment.
 */
final class ContentBinder {

    private static final String XML_TYPE_NAME = "xml";

    private ContentBinder() {
    }

    /**
     * Binds JSON bytes to the handler's declared parameter type.
     *
     * @param bytes          the file content
     * @param targetType     the declared content parameter type
     * @param laxDataBinding whether relaxed data projection applies
     * @return the bound value
     */
    static Object bindJson(byte[] bytes, Type targetType, boolean laxDataBinding) {
        BArray byteArray = ValueCreator.createArrayValue(bytes);
        BMap<BString, Object> options = DataBindingOptions.jsonParseOptions(laxDataBinding);
        BTypedesc typedesc = ValueCreator.createTypedescValue(targetType);
        Object result;
        try {
            result = io.ballerina.lib.data.jsondata.json.Native.parseBytes(byteArray, options, typedesc);
        } catch (BError e) {
            throw bindingFailure("onFileJson", e);
        }
        if (result instanceof BError bError) {
            throw bindingFailure("onFileJson", bError);
        }
        return result;
    }

    /**
     * Binds XML bytes to the handler's declared parameter type. A bare {@code xml} target keeps
     * the plain document parse; a record target binds through data.xmldata.
     *
     * @param bytes          the file content
     * @param targetType     the declared content parameter type
     * @param laxDataBinding whether relaxed data projection applies
     * @return the bound value
     */
    static Object bindXml(byte[] bytes, Type targetType, boolean laxDataBinding) {
        if (XML_TYPE_NAME.equals(targetType.getQualifiedName())) {
            try {
                return XmlUtils.parse(new String(bytes, StandardCharsets.UTF_8));
            } catch (BError e) {
                throw FilesErrorCreator.processingError(
                        "content is not valid XML for the 'onFileXml' handler", e);
            }
        }
        BMap<BString, Object> options = DataBindingOptions.xmlSourceOptions(laxDataBinding);
        Object result;
        try {
            // The xmldata parser does not unwrap type references, so hand it the referred type.
            result = io.ballerina.lib.data.xmldata.xml.Native.parseBytes(ValueCreator.createArrayValue(bytes),
                    options, ValueCreator.createTypedescValue(TypeUtils.getReferredType(targetType)));
        } catch (BError e) {
            throw bindingFailure("onFileXml", e);
        }
        if (result instanceof BError bError) {
            throw bindingFailure("onFileXml", bError);
        }
        return result;
    }

    private static BError bindingFailure(String handlerName, BError cause) {
        return FilesErrorCreator.processingError("content does not bind to the '" + handlerName
                + "' handler's declared type: " + cause.getErrorMessage(), cause);
    }
}
