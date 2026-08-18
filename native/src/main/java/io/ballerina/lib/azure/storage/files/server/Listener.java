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

import com.azure.storage.file.share.ShareClient;
import com.azure.storage.file.share.ShareDirectoryClient;
import com.azure.storage.file.share.models.ShareFileItem;
import com.azure.storage.file.share.models.ShareStorageException;
import com.azure.storage.file.share.options.ShareFileRenameOptions;
import com.azure.storage.file.share.options.ShareListFilesAndDirectoriesOptions;
import com.azure.xml.XmlReader;
import io.ballerina.lib.azure.storage.files.util.BallerinaAzureClient;
import io.ballerina.lib.azure.storage.files.util.ContentBinder;
import io.ballerina.lib.azure.storage.files.util.FilesErrorCreator;
import io.ballerina.lib.azure.storage.files.util.ModuleUtils;
import io.ballerina.lib.azure.storage.files.util.RecordMapper;
import io.ballerina.runtime.api.Environment;
import io.ballerina.runtime.api.Runtime;
import io.ballerina.runtime.api.concurrent.StrandMetadata;
import io.ballerina.runtime.api.creators.ValueCreator;
import io.ballerina.runtime.api.types.MethodType;
import io.ballerina.runtime.api.types.ObjectType;
import io.ballerina.runtime.api.types.Parameter;
import io.ballerina.runtime.api.types.StreamType;
import io.ballerina.runtime.api.types.Type;
import io.ballerina.runtime.api.utils.StringUtils;
import io.ballerina.runtime.api.utils.TypeUtils;
import io.ballerina.runtime.api.values.BArray;
import io.ballerina.runtime.api.values.BDecimal;
import io.ballerina.runtime.api.values.BError;
import io.ballerina.runtime.api.values.BMap;
import io.ballerina.runtime.api.values.BObject;
import io.ballerina.runtime.api.values.BString;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.time.Instant;
import java.util.ArrayDeque;
import java.util.Deque;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;
import java.util.regex.Pattern;
import java.util.regex.PatternSyntaxException;

import javax.xml.stream.XMLStreamException;

/**
 * Native backing of the polling {@code Listener}. It reuses the SDK client behind the
 * {@code Caller} built by the Ballerina {@code init}, reads the attached service's
 * {@code @files:ServiceConfig} and per-handler {@code @files:FunctionConfig} annotations,
 * lists the watched path on each poll (driven by a {@code ballerina/task} job on the
 * Ballerina side), and dispatches each present file to the matching content handler on a
 * virtual thread.
 */
public final class Listener {

    private static final Logger LOG = LoggerFactory.getLogger(Listener.class);

    // Native-data key under which the per-listener context is stored on the listener object.
    private static final String NATIVE_LISTENER_CONTEXT = "listenerContext";

    // The Caller type name, matched against a handler's second parameter type.
    private static final String CALLER_TYPE_NAME = "Caller";

    private static final BString LAX_DATA_BINDING = StringUtils.fromString("laxDataBinding");
    // The module-level Ballerina helper that binds CSV content on a real strand.
    private static final String BIND_CSV_CONTENT_FUNCTION = "bindCsvContent";

    // The listener annotation vocabulary: annotation tag suffixes and the record fields of
    // ServiceConfiguration, FunctionConfiguration, and Move.
    private static final String SERVICE_CONFIG_ANNOTATION = "ServiceConfig";
    private static final String FUNCTION_CONFIG_ANNOTATION = "FunctionConfig";
    private static final BString SERVICE_CONFIG_RECURSIVE = StringUtils.fromString("recursive");
    private static final BString SERVICE_CONFIG_MIN_FILE_AGE = StringUtils.fromString("minFileAgeSeconds");
    private static final BString FILE_NAME_PATTERN = StringUtils.fromString("fileNamePattern");
    private static final BString FUNCTION_CONFIG_AFTER_PROCESS = StringUtils.fromString("afterProcess");
    private static final BString FUNCTION_CONFIG_AFTER_ERROR = StringUtils.fromString("afterError");
    private static final BString MOVE_MOVE_TO = StringUtils.fromString("moveTo");
    private static final BString MOVE_PRESERVE_SUB_DIRS = StringUtils.fromString("preserveSubDirs");
    // The Ballerina DELETE post-process action value.
    private static final String ACTION_DELETE = "DELETE";

    // The content-handler method names, and the extension-to-handler routing map.
    private static final String ON_FILE = "onFile";
    private static final String ON_FILE_TEXT = "onFileText";
    private static final String ON_FILE_JSON = "onFileJson";
    private static final String ON_FILE_XML = "onFileXml";
    private static final String ON_FILE_CSV = "onFileCsv";
    // The optional error-notification handler: not a content handler (no routing, no
    // afterProcess/afterError semantics of its own).
    private static final String ON_ERROR = "onError";
    private static final Map<String, String> EXTENSION_HANDLERS = Map.of(
            "json", ON_FILE_JSON, "xml", ON_FILE_XML, "csv", ON_FILE_CSV, "txt", ON_FILE_TEXT);
    // Routing patterns are checked in this fixed order (the typed handlers, then the onFile
    // catch-all), so overlapping patterns resolve the same way on every runtime, independent
    // of method enumeration order.
    private static final List<String> ROUTING_PATTERN_ORDER =
            List.of(ON_FILE_TEXT, ON_FILE_JSON, ON_FILE_XML, ON_FILE_CSV, ON_FILE);
    private static final Set<String> HANDLER_NAMES = Set.copyOf(ROUTING_PATTERN_ORDER);
    // The binding-failure message contexts handed to the shared ContentBinder.
    private static final String JSON_BIND_CONTEXT =
            "content does not bind to the '" + ON_FILE_JSON + "' handler's declared type";
    private static final String XML_BIND_CONTEXT =
            "content does not bind to the '" + ON_FILE_XML + "' handler's declared type";
    private static final String XML_PARSE_CONTEXT = "content is not valid XML for the '" + ON_FILE_XML + "' handler";

    private Listener() {
    }

    /**
     * Initializes the listener: stores the polling context, including the {@code Caller}
     * constructed by the Ballerina {@code init}, on the listener object. The listener reuses
     * the SDK client already built for the Caller's {@code Client}; no second connection
     * stack is created.
     *
     * @param listenerObj the Ballerina listener object
     * @param shareName   the share to watch
     * @param config      the {@code ListenerConfiguration} record
     * @param caller      the {@code Caller} built by the Ballerina {@code init}, handed to handlers
     * @return {@code null} on success, or the validation error
     */
    public static Object initListener(BObject listenerObj, BString shareName,
                                      BMap<BString, Object> config, BObject caller) {
        try {
            // azure-xml's XmlReader picks its StAX parser once per process and a failure there is
            // permanent; warming it up here surfaces that as a typed init error, not a dead poll loop.
            try (XmlReader ignored = XmlReader.fromString("<x/>")) {
                // initialization only
            } catch (XMLStreamException | RuntimeException | Error e) {
                return FilesErrorCreator.clientError("XML support could not be initialized: "
                        + BallerinaAzureClient.describe(e) + ". Retry initializing the listener.", e);
            }

            BObject client = caller.getObjectValue(BallerinaAzureClient.CALLER_CLIENT_FIELD);
            listenerObj.addNativeData(BallerinaAzureClient.NATIVE_SHARE_CLIENT,
                    BallerinaAzureClient.getShareClient(client));

            boolean laxDataBinding = Boolean.TRUE.equals(config.get(LAX_DATA_BINDING));
            listenerObj.addNativeData(NATIVE_LISTENER_CONTEXT,
                    new ListenerContext(caller, shareName.getValue(), laxDataBinding));
            return null;
        } catch (BError e) {
            return e;
        } catch (Exception e) {
            return FilesErrorCreator.clientError(BallerinaAzureClient.describe(e), e);
        }
    }

    /**
     * Attaches the single service to the listener, reading its watch configuration and handlers.
     * A second attach fails: one service per listener.
     *
     * @param listenerObj the Ballerina listener object
     * @param service     the service being attached
     * @param name        the name of the service
     * @return {@code null} on success, or the validation error
     */
    public static Object attachService(BObject listenerObj, BObject service, Object name) {
        ListenerContext ctx = context(listenerObj);
        if (ctx.service != null) {
            return FilesErrorCreator.clientError("Only one service can be attached to a files:Listener", null);
        }
        try {
            ctx.serviceContext = parseService(service, name);
            ctx.service = service;
            return null;
        } catch (BError e) {
            return e;
        } catch (Exception e) {
            return FilesErrorCreator.clientError(BallerinaAzureClient.describe(e), e);
        }
    }

    /**
     * Detaches the service from the listener.
     *
     * @param listenerObj the Ballerina listener object
     * @param service     the service being detached
     * @return an error if the given service is not the attached one, otherwise {@code null}
     */
    public static Object detachService(BObject listenerObj, BObject service) {
        ListenerContext ctx = context(listenerObj);
        if (ctx.service != service) {
            return FilesErrorCreator.clientError("the given service is not attached to this listener", null);
        }
        ctx.service = null;
        ctx.serviceContext = null;
        return null;
    }

    /**
     * Runs one poll of the watched path. Called on a Ballerina strand by the task job, which
     * drives the fixed polling cadence. Lists the present files and dispatches each match on a
     * virtual thread. A listing failure is mapped to the module's typed error and returned, so
     * the Ballerina poll service logs it and a declared {@code onError} receives it; the next
     * scheduled poll simply scans again.
     *
     * @param env         the Ballerina runtime environment
     * @param listenerObj the Ballerina listener object
     * @return {@code null} on success, or the mapped scan error
     */
    public static Object poll(Environment env, BObject listenerObj) {
        return BallerinaAzureClient.invoke(env, () -> {
            ListenerContext ctx = context(listenerObj);
            // Captured once so a detach on another thread cannot null it mid-poll.
            ServiceContext serviceContext = ctx.serviceContext;
            if (ctx.stopped || serviceContext == null) {
                return null;
            }
            ctx.runtime = env.getRuntime();
            try {
                scan(listenerObj, ctx, serviceContext);
            } catch (Throwable e) {
                BError mapped = BallerinaAzureClient.mapFailure(e);
                invokeOnError(ctx, mapped);
                return mapped;
            }
            return null;
        });
    }

    // Invokes the optional onError handler on a virtual thread. onError is a notification
    // hook: its own failure is printed and swallowed.
    private static void invokeOnError(ListenerContext ctx, BError error) {
        BObject service = ctx.service;
        ServiceContext serviceContext = ctx.serviceContext;
        int arity = serviceContext == null ? 0 : serviceContext.onErrorArity();
        if (service == null || arity == 0 || ctx.stopped) {
            return;
        }
        Thread.startVirtualThread(() -> {
            ObjectType serviceType = (ObjectType) TypeUtils.getReferredType(TypeUtils.getType(service));
            boolean isConcurrentSafe = serviceType.isIsolated() && serviceType.isIsolated(ON_ERROR);
            StrandMetadata metadata = new StrandMetadata(isConcurrentSafe, null);
            Object[] args = arity >= 2 ? new Object[]{error, ctx.caller} : new Object[]{error};

            Object result;
            // Deliberate last line of defense: a failing user onError handler must never take
            // down the dispatch thread.
            try {
                result = ctx.runtime.callMethod(service, ON_ERROR, metadata, args);
            } catch (BError handlerPanic) {
                handlerPanic.printStackTrace();
                return;
            } catch (RuntimeException e) {
                LOG.warn("azure.storage.files listener: onError invocation failed", e);
                return;
            }
            if (result instanceof BError handlerError) {
                handlerError.printStackTrace();
            }
        });
    }

    /**
     * Stops the listener by marking the context stopped, which ends the current scan at its
     * next iteration and blocks new dispatches. In-flight handler invocations run to
     * completion on their own virtual threads.
     *
     * @param listenerObj the Ballerina listener object
     * @return {@code null}
     */
    public static Object stopListener(BObject listenerObj) {
        ListenerContext ctx = context(listenerObj);
        if (ctx != null) {
            ctx.stopped = true;
        }
        return null;
    }

    // Scans the watched path (client-side DFS; the wire has no recursive listing), checking
    // ctx.stopped each iteration so a stop ends a long traversal early.
    private static void scan(BObject listenerObj, ListenerContext ctx, ServiceContext serviceContext) {
        ShareClient share = BallerinaAzureClient.getShareClient(listenerObj);
        Deque<String> pending = new ArrayDeque<>();
        pending.push(serviceContext.watchedPath());
        while (!pending.isEmpty()) {
            if (ctx.stopped) {
                return;
            }
            String directory = pending.pop();
            boolean atRoot = directory.isEmpty();
            ShareDirectoryClient directoryClient = atRoot
                    ? share.getRootDirectoryClient() : share.getDirectoryClient(directory);
            ShareListFilesAndDirectoriesOptions options = new ShareListFilesAndDirectoriesOptions()
                    .setIncludeExtendedInfo(true)
                    .setIncludeTimestamps(true)
                    .setIncludeETag(true);
            for (ShareFileItem item : directoryClient.listFilesAndDirectories(options, null, null)) {
                String childPath = atRoot ? item.getName() : directory + "/" + item.getName();
                if (item.isDirectory()) {
                    if (serviceContext.recursive()) {
                        pending.push(childPath);
                    }
                } else {
                    consider(listenerObj, ctx, serviceContext, item, childPath);
                }
            }
        }
    }

    // Applies the pattern and age filters, then dispatches on a virtual thread unless the file
    // is already in flight (at-least-once: a skipped file re-fires on a later poll).
    private static void consider(BObject listenerObj, ListenerContext ctx, ServiceContext serviceContext,
                                 ShareFileItem item, String path) {
        String name = item.getName();
        if (serviceContext.fileNamePattern() != null && !serviceContext.fileNamePattern().matcher(name).matches()) {
            return;
        }
        // The minimum-age filter skips files that may still be being written.
        if (serviceContext.minFileAgeSeconds() != null && item.getProperties() != null
                && item.getProperties().getLastModified() != null) {
            long age = Duration.between(item.getProperties().getLastModified().toInstant(), Instant.now()).getSeconds();
            if (age < serviceContext.minFileAgeSeconds()) {
                return;
            }
        }
        // The in-progress guard: a path whose dispatch is still running is not dispatched
        // again, even when an overwrite has given it a new ETag; the new version arrives on
        // a later poll once the current handling finishes.
        if (ctx.stopped || !ctx.inProgress.add(path)) {
            return;
        }
        Thread.startVirtualThread(() -> dispatch(listenerObj, ctx, serviceContext, item, path));
    }

    // Downloads or opens the content, binds it to the handler's declared type, invokes the
    // handler, and applies the configured post-process action.
    private static void dispatch(BObject listenerObj, ListenerContext ctx, ServiceContext serviceContext,
                                 ShareFileItem item, String path) {
        try {
            // Snapshot the service so a concurrent detach cannot null it mid-dispatch; if it is
            // already gone, leave the file unconsumed for a later poll.
            BObject service = ctx.service;
            if (ctx.stopped || service == null) {
                return;
            }
            HandlerConfig handler = resolveHandler(serviceContext, item.getName());
            if (handler == null) {
                LOG.debug("azure.storage.files listener: no handler for {}, skipping", path);
                return;
            }

            Object content;
            Type referredContentType = handler.contentType() == null
                    ? null : TypeUtils.getReferredType(handler.contentType());

            if (referredContentType instanceof StreamType streamContentType) {
                // A stream handler skips the eager download: the file is read chunk by chunk.
                InputStream inputStream;
                try {
                    inputStream = BallerinaAzureClient.getShareClient(listenerObj)
                            .getFileClient(path).openInputStream();
                } catch (RuntimeException e) {
                    LOG.warn("azure.storage.files listener: cannot read {}; will retry next poll", path, e);
                    return;
                }
                try {
                    content = ON_FILE_CSV.equals(handler.methodName())
                            ? ContentStreams.createCsvStream(ctx.runtime, inputStream,
                                    streamContentType.getConstrainedType(), ctx.laxDataBinding)
                            : ContentStreams.createByteStream(inputStream,
                                    streamContentType.getConstrainedType());
                } catch (RuntimeException e) {
                    closeQuietly(inputStream);
                    handleBindingFailure(listenerObj, ctx, serviceContext, handler, item, path, e);
                    return;
                }
            } else {
                byte[] bytes;
                try {
                    bytes = download(listenerObj, path);
                } catch (RuntimeException e) {
                    LOG.warn("azure.storage.files listener: cannot read {}; will retry next poll", path, e);
                    return;
                }
                try {
                    content = bindContent(ctx, handler, bytes);
                } catch (RuntimeException e) {
                    handleBindingFailure(listenerObj, ctx, serviceContext, handler, item, path, e);
                    return;
                }
            }

            int slash = path.lastIndexOf('/');
            String parentPath = slash < 0 ? "" : path.substring(0, slash);
            BMap<BString, Object> fileInfo = RecordMapper.fileInfo(item, parentPath, ctx.shareName);

            Object result = invokeHandler(ctx, service, handler, content, fileInfo);

            if (result instanceof BError error) {
                // The handler already saw its own error, so onError is not notified; the error is
                // printed so the failure stays visible without a logging backend.
                error.printStackTrace();
                postProcess(listenerObj, serviceContext, handler.afterError(), path, listedETag(item));
            } else {
                postProcess(listenerObj, serviceContext, handler.afterProcess(), path, listedETag(item));
            }
        } catch (Throwable e) {
            LOG.error("azure.storage.files listener: unexpected dispatch failure for {}", path, e);
        } finally {
            ctx.inProgress.remove(path);
        }
    }

    // A content-binding failure notifies onError (when declared) and post-processes (afterError)
    // the file; without an onError the error is printed so the failure stays visible.
    private static void handleBindingFailure(BObject listenerObj, ListenerContext ctx,
                                             ServiceContext serviceContext, HandlerConfig handler,
                                             ShareFileItem item, String path, RuntimeException e) {
        BError bindingError = e instanceof BError bError
                ? bError : FilesErrorCreator.clientError(BallerinaAzureClient.describe(e), e);
        if (serviceContext.onErrorArity() == 0) {
            bindingError.printStackTrace();
        }
        invokeOnError(ctx, bindingError);
        postProcess(listenerObj, serviceContext, handler.afterError(), path, listedETag(item));
    }

    private static String listedETag(ShareFileItem item) {
        return item.getProperties() == null ? null : item.getProperties().getETag();
    }

    // The SDK serves the listing's entity tag quoted and the properties read's unquoted, so
    // the two forms only compare equal once the quotes are stripped.
    private static String unquoteETag(String eTag) {
        if (eTag != null && eTag.length() >= 2 && eTag.startsWith("\"") && eTag.endsWith("\"")) {
            return eTag.substring(1, eTag.length() - 1);
        }
        return eTag;
    }

    private static void closeQuietly(InputStream inputStream) {
        try {
            inputStream.close();
        } catch (IOException e) {
            LOG.debug("azure.storage.files listener: failed to close a content stream", e);
        }
    }

    // Resolves the handler for a file: a per-handler routing pattern wins, then the extension
    // mapping, then the onFile fallback.
    private static HandlerConfig resolveHandler(ServiceContext serviceContext, String fileName) {
        for (String methodName : ROUTING_PATTERN_ORDER) {
            HandlerConfig handler = serviceContext.handlers().get(methodName);
            if (handler != null && handler.routingPattern() != null
                    && handler.routingPattern().matcher(fileName).matches()) {
                return handler;
            }
        }
        String mapped = EXTENSION_HANDLERS.get(extension(fileName));
        if (mapped != null && serviceContext.handlers().containsKey(mapped)) {
            return serviceContext.handlers().get(mapped);
        }
        return serviceContext.handlers().get(ON_FILE);
    }

    private static Object bindContent(ListenerContext ctx, HandlerConfig handler, byte[] bytes) {
        switch (handler.methodName()) {
            case ON_FILE_TEXT:
                return StringUtils.fromString(new String(bytes, StandardCharsets.UTF_8));
            case ON_FILE_JSON:
                return ContentBinder.bindJson(ValueCreator.createArrayValue(bytes),
                        handler.contentType(), ctx.laxDataBinding, JSON_BIND_CONTEXT);
            case ON_FILE_XML:
                return ContentBinder.bindXml(ValueCreator.createArrayValue(bytes),
                        handler.contentType(), ctx.laxDataBinding, XML_BIND_CONTEXT, XML_PARSE_CONTEXT);
            case ON_FILE_CSV:
                return bindCsv(ctx, handler, bytes);
            default:
                return ValueCreator.createArrayValue(bytes);
        }
    }

    // Binds CSV content on a real Ballerina strand through the module-level bindCsvContent helper,
    // because the data.csv parser needs the runtime environment of a strand.
    private static Object bindCsv(ListenerContext ctx, HandlerConfig handler, byte[] bytes) {
        Object result = ctx.runtime.callFunction(ModuleUtils.getModule(), BIND_CSV_CONTENT_FUNCTION,
                new StrandMetadata(true, null),
                ValueCreator.createArrayValue(bytes),
                ValueCreator.createTypedescValue(TypeUtils.getReferredType(handler.contentType())),
                ctx.laxDataBinding);
        if (result instanceof BError bError) {
            throw FilesErrorCreator.clientError("content does not bind to the '" + ON_FILE_CSV
                    + "' handler's declared type: " + bError.getErrorMessage(), bError);
        }
        return result;
    }

    private static Object invokeHandler(ListenerContext ctx, BObject service, HandlerConfig handler, Object content,
                                        BMap<BString, Object> fileInfo) {
        ObjectType serviceType = (ObjectType) TypeUtils.getReferredType(TypeUtils.getType(service));
        String methodName = handler.methodName();
        boolean isConcurrentSafe = serviceType.isIsolated() && serviceType.isIsolated(methodName);
        StrandMetadata metadata = new StrandMetadata(isConcurrentSafe, null);

        // The handler carries content plus the optional FileInfo and Caller, in that order; pass
        // only the parameters it declares (a two-parameter handler takes either one).
        Object[] args = switch (handler.arity()) {
            case 0 -> new Object[0];
            case 1 -> new Object[]{content};
            case 2 -> handler.secondParamIsCaller()
                    ? new Object[]{content, ctx.caller}
                    : new Object[]{content, fileInfo};
            default -> new Object[]{content, fileInfo, ctx.caller};
        };
        return ctx.runtime.callMethod(service, methodName, metadata, args);
    }

    // Applies a post-process action (delete, or move to a target directory). A failure is
    // logged and left alone so the file re-fires on a later poll.
    private static void postProcess(BObject listenerObj, ServiceContext serviceContext, PostAction action,
                                    String path, String expectedETag) {
        if (action == null) {
            return;
        }
        try {
            ShareClient share = BallerinaAzureClient.getShareClient(listenerObj);
            // A changed entity tag means content no dispatch has seen; leave the file for the
            // next poll. Azure Files has no conditional deletes or renames, so the moment
            // between this check and the action stays unguarded.
            if (expectedETag != null) {
                String currentETag = share.getFileClient(path).getProperties().getETag();
                if (!unquoteETag(expectedETag).equals(unquoteETag(currentETag))) {
                    LOG.debug("azure.storage.files listener: {} changed since dispatch; "
                            + "leaving it for the next poll", path);
                    return;
                }
            }
            if (action.isDelete()) {
                share.getFileClient(path).delete();
                return;
            }
            String moveRoot = BallerinaAzureClient.directoryPath(StringUtils.fromString(action.moveTo()));
            String destination = action.preserveSubDirs()
                    ? join(moveRoot, relativeTo(path, serviceContext.watchedPath()))
                    : join(moveRoot, path.substring(path.lastIndexOf('/') + 1));
            int slash = destination.lastIndexOf('/');
            ensureDirectory(share, slash < 0 ? "" : destination.substring(0, slash));
            // A same-named file already at the destination is replaced: a failing rename would
            // leave the source in the watched path, re-dispatching it on every later poll.
            share.getFileClient(path).renameWithResponse(
                    new ShareFileRenameOptions(destination).setReplaceIfExists(true), null, null);
        } catch (RuntimeException e) {
            LOG.warn("azure.storage.files listener: post-process failed for {}", path, e);
        }
    }

    private static void ensureDirectory(ShareClient share, String directoryPath) {
        if (directoryPath.isEmpty()) {
            return;
        }
        StringBuilder built = new StringBuilder();
        for (String segment : directoryPath.split("/")) {
            if (segment.isEmpty()) {
                continue;
            }
            if (built.length() > 0) {
                built.append('/');
            }
            built.append(segment);
            try {
                share.getDirectoryClient(built.toString()).createIfNotExists();
            } catch (ShareStorageException e) {
                LOG.debug("azure.storage.files listener: directory {} already exists", built, e);
            }
        }
    }

    private static byte[] download(BObject listenerObj, String path) {
        ByteArrayOutputStream out = new ByteArrayOutputStream();
        BallerinaAzureClient.getShareClient(listenerObj).getFileClient(path).download(out);
        return out.toByteArray();
    }

    // Parses the attached service's watch configuration and handler set; the watched path is
    // the service's attach point (nil watches the share root).
    private static ServiceContext parseService(BObject service, Object name) {
        String watchedPath = watchedPathFrom(name);
        ObjectType serviceType = (ObjectType) TypeUtils.getReferredType(TypeUtils.getType(service));
        // The filter annotation is optional; every filter has a default.
        BMap<BString, Object> config = annotation(serviceType.getAnnotations(), SERVICE_CONFIG_ANNOTATION);
        boolean recursive = true;
        Pattern fileNamePattern = null;
        Double minFileAgeSeconds = null;
        if (config != null) {
            Object recursiveValue = config.get(SERVICE_CONFIG_RECURSIVE);
            recursive = recursiveValue == null || (Boolean) recursiveValue;
            Object patternValue = config.get(FILE_NAME_PATTERN);
            fileNamePattern = patternValue == null ? null : compile(((BString) patternValue).getValue());
            Object ageValue = config.get(SERVICE_CONFIG_MIN_FILE_AGE);
            minFileAgeSeconds = ageValue == null ? null : ((BDecimal) ageValue).floatValue();
        }

        Map<String, HandlerConfig> handlers = new LinkedHashMap<>();
        int onErrorArity = 0;
        for (MethodType method : serviceType.getMethods()) {
            String methodName = method.getName();
            if (ON_ERROR.equals(methodName)) {
                onErrorArity = method.getParameters().length;
                continue;
            }
            if (!HANDLER_NAMES.contains(methodName)) {
                continue;
            }
            BMap<BString, Object> functionConfig = annotation(method.getAnnotations(), FUNCTION_CONFIG_ANNOTATION);
            Pattern routing = null;
            PostAction afterProcess = null;
            PostAction afterError = null;
            if (functionConfig != null) {
                Object routingPatternValue = functionConfig.get(FILE_NAME_PATTERN);
                if (routingPatternValue != null) {
                    routing = compile(((BString) routingPatternValue).getValue());
                }
                afterProcess = readAction(functionConfig, FUNCTION_CONFIG_AFTER_PROCESS);
                afterError = readAction(functionConfig, FUNCTION_CONFIG_AFTER_ERROR);
            }
            Parameter[] params = method.getParameters();
            boolean secondIsCaller = params.length >= 2
                    && CALLER_TYPE_NAME.equals(TypeUtils.getReferredType(params[1].type).getName());
            Type contentType = params.length >= 1 ? params[0].type : null;
            handlers.put(methodName, new HandlerConfig(methodName, routing, afterProcess, afterError,
                    params.length, secondIsCaller, contentType));
        }
        return new ServiceContext(watchedPath, recursive, fileNamePattern, minFileAgeSeconds, handlers, onErrorArity);
    }

    // Resolves the watched path from the attach point: segments join with a slash, strings
    // normalize to the internal share-relative form, nil or empty is the share root.
    private static String watchedPathFrom(Object name) {
        if (name instanceof BArray segments) {
            StringBuilder joined = new StringBuilder();
            for (int i = 0; i < segments.size(); i++) {
                if (joined.length() > 0) {
                    joined.append('/');
                }
                joined.append(segments.getBString(i).getValue());
            }
            return BallerinaAzureClient.directoryPath(StringUtils.fromString(joined.toString()));
        }
        if (name instanceof BString path) {
            String collapsed = path.getValue().strip();
            while (collapsed.contains("//")) {
                collapsed = collapsed.replace("//", "/");
            }
            return BallerinaAzureClient.directoryPath(StringUtils.fromString(collapsed));
        }
        return "";
    }

    private static PostAction readAction(BMap<BString, Object> config, BString key) {
        Object value = config.get(key);
        if (value == null) {
            return null;
        }
        if (value instanceof BString action) {
            if (ACTION_DELETE.equals(action.getValue())) {
                return new PostAction(true, null, false);
            }
            throw FilesErrorCreator.clientError("unknown post-process action: " + action.getValue(), null);
        }
        @SuppressWarnings("unchecked")
        BMap<BString, Object> move = (BMap<BString, Object>) value;
        String moveTo = move.getStringValue(MOVE_MOVE_TO).getValue();
        Object preserve = move.get(MOVE_PRESERVE_SUB_DIRS);
        return new PostAction(false, moveTo, preserve == null || (Boolean) preserve);
    }

    private static BMap<BString, Object> annotation(BMap<BString, Object> annotations, String suffix) {
        if (annotations == null) {
            return null;
        }
        for (BString key : annotations.getKeys()) {
            if (key.getValue().endsWith(suffix)) {
                Object value = annotations.get(key);
                if (value instanceof BMap) {
                    @SuppressWarnings("unchecked")
                    BMap<BString, Object> map = (BMap<BString, Object>) value;
                    return map;
                }
            }
        }
        return null;
    }

    private static Pattern compile(String pattern) {
        try {
            return Pattern.compile(pattern);
        } catch (PatternSyntaxException e) {
            throw FilesErrorCreator.clientError("invalid regular expression: " + pattern, e);
        }
    }

    private static String extension(String fileName) {
        int dot = fileName.lastIndexOf('.');
        return dot < 0 ? "" : fileName.substring(dot + 1).toLowerCase(Locale.ROOT);
    }

    private static String relativeTo(String path, String root) {
        if (root.isEmpty()) {
            return path;
        }
        String prefix = root + "/";
        return path.startsWith(prefix) ? path.substring(prefix.length()) : path;
    }

    private static String join(String base, String tail) {
        return base.isEmpty() ? tail : base + "/" + tail;
    }

    private static ListenerContext context(BObject listenerObj) {
        return (ListenerContext) listenerObj.getNativeData(NATIVE_LISTENER_CONTEXT);
    }

    /**
     * Per-listener mutable state: the Caller, the parsed watch configuration, and the attached
     * service.
     */
    private static final class ListenerContext {

        private final BObject caller;
        private final String shareName;
        private final boolean laxDataBinding;

        // Files whose dispatch is still running, keyed by path: one file, one invocation at
        // a time, regardless of version changes while handling runs.
        private final Set<String> inProgress = ConcurrentHashMap.newKeySet();

        // The Ballerina runtime, captured from the polling strand on each poll.
        private volatile Runtime runtime;

        private volatile BObject service;

        private volatile ServiceContext serviceContext;

        // The stopped flag: set by a stop, checked by the scan and dispatch paths.
        private volatile boolean stopped;

        private ListenerContext(BObject caller, String shareName, boolean laxDataBinding) {
            this.caller = caller;
            this.shareName = shareName;
            this.laxDataBinding = laxDataBinding;
        }
    }

    // The attached service's parsed watch configuration and handler set, immutable per attach:
    // set when the service attaches and cleared when it detaches.
    private record ServiceContext(String watchedPath, boolean recursive, Pattern fileNamePattern,
                                  Double minFileAgeSeconds, Map<String, HandlerConfig> handlers,
                                  int onErrorArity) {
    }

    // One content handler: its routing pattern, post-process actions, parameter-list shape,
    // and declared content parameter type.
    private record HandlerConfig(String methodName, Pattern routingPattern,
                                 PostAction afterProcess, PostAction afterError,
                                 int arity, boolean secondParamIsCaller, Type contentType) {
    }

    // A post-process action: a delete, or a move to a target directory.
    private record PostAction(boolean isDelete, String moveTo, boolean preserveSubDirs) {
    }
}
