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
import com.azure.storage.file.share.ShareServiceClient;
import com.azure.storage.file.share.models.ShareFileItem;
import com.azure.storage.file.share.models.ShareStorageException;
import com.azure.storage.file.share.options.ShareListFilesAndDirectoriesOptions;
import com.azure.xml.XmlReader;
import io.ballerina.lib.azure.storage.files.util.ClientInit;
import io.ballerina.lib.azure.storage.files.util.ErrorMapper;
import io.ballerina.lib.azure.storage.files.util.FilesErrorCreator;
import io.ballerina.lib.azure.storage.files.util.ModuleUtils;
import io.ballerina.lib.azure.storage.files.util.Ops;
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
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.RejectedExecutionException;
import java.util.concurrent.TimeUnit;
import java.util.regex.Pattern;
import java.util.regex.PatternSyntaxException;

import javax.xml.stream.XMLStreamException;

/**
 * Native backing of the polling {@code Listener}. It builds the SDK clients at initialization,
 * reads the attached service's {@code @files:ServiceConfig} and per-handler
 * {@code @files:FunctionConfig} annotations, lists the watched path on each poll (driven by a
 * {@code ballerina/task} job on the Ballerina side), and dispatches each present file to the
 * matching content handler on a virtual thread.
 */
public final class ShareListenerAdaptor {

    private static final Logger LOG = LoggerFactory.getLogger(ShareListenerAdaptor.class);

    // Native-data key under which the per-listener context is stored on the listener object.
    private static final String NATIVE_LISTENER_CONTEXT = "listenerContext";

    // The Caller object type and the ListenerConfiguration fields this class reads.
    private static final String CALLER_OBJECT = "Caller";
    private static final BString LAX_DATA_BINDING = StringUtils.fromString("laxDataBinding");
    private static final BString CSV_FAIL_SAFE = StringUtils.fromString("csvFailSafe");
    // The module-level Ballerina helper that binds CSV content on a real strand.
    private static final String BIND_CSV_CONTENT_FUNCTION = "bindCsvContent";

    // The listener annotation vocabulary: annotation tag suffixes and the record fields of
    // ServiceConfiguration, FunctionConfiguration, and Move.
    private static final String SERVICE_CONFIG_ANNOTATION = "ServiceConfig";
    private static final String FUNCTION_CONFIG_ANNOTATION = "FunctionConfig";
    private static final BString SERVICE_CONFIG_PATH = StringUtils.fromString("path");
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
    private static final Set<String> HANDLER_NAMES =
            Set.of(ON_FILE, ON_FILE_TEXT, ON_FILE_JSON, ON_FILE_XML, ON_FILE_CSV);
    private static final Map<String, String> EXTENSION_HANDLERS = Map.of(
            "json", ON_FILE_JSON, "xml", ON_FILE_XML, "csv", ON_FILE_CSV, "txt", ON_FILE_TEXT);

    // The bounded wait for in-flight handlers on a graceful stop.
    private static final long AWAIT_SECONDS = 30L;

    private ShareListenerAdaptor() {
    }

    /**
     * Initializes the listener: builds the SDK clients, creates the single {@code Caller} bound to
     * the watched share, and stores the polling context on the listener object.
     *
     * @param env         the Ballerina runtime environment
     * @param listenerObj the Ballerina listener object
     * @param shareName   the share to watch
     * @param config      the {@code ListenerConfiguration} record
     * @return {@code null} on success, or the validation error
     */
    public static Object initListener(Environment env, BObject listenerObj, BString shareName,
                                      BMap<BString, Object> config) {
        try {
            String share = shareName.getValue().strip();
            if (share.isEmpty()) {
                return FilesErrorCreator.processingError("shareName must not be empty", null);
            }
            // Azure's XmlReader (from azure-xml library) resolves its StAX factory in a static
            // initializer using the calling thread's context classloader; force that to happen
            // here, on the init strand, so a poll thread can never be the first to trigger it
            // and poison the class.
            try (XmlReader ignored = XmlReader.fromString("<x/>")) {
                // initialization only
            } catch (XMLStreamException | RuntimeException | Error e) {
                return FilesErrorCreator.processingError(
                        "XML support could not be initialized: " + Ops.describe(e), e);
            }
            ShareServiceClient serviceClient = ClientInit.buildServiceClient(config);
            ShareClient shareClient = serviceClient.getShareClient(share);

            listenerObj.addNativeData(Ops.NATIVE_SERVICE_CLIENT, serviceClient);
            listenerObj.addNativeData(Ops.NATIVE_SHARE_CLIENT, shareClient);

            // we don't need connection options here. 
            BObject caller = ValueCreator.createObjectValue(ModuleUtils.getModule(), CALLER_OBJECT, shareName);
            // The Ballerina Caller.init takes only shareName because the Caller never builds a
            // connection: the already-built ShareServiceClient/ShareClient (constructed by
            // ClientInit.buildServiceClient(config) from the full config: auth, retry, transport,
            // TLS) attach to the Caller as native data. Every Caller remote op reads those
            // native-data clients — the same statics Client uses — so auth/retry/transport are
            // all carried.
            caller.addNativeData(Ops.NATIVE_SERVICE_CLIENT, serviceClient);
            caller.addNativeData(Ops.NATIVE_SHARE_CLIENT, shareClient);

            // Add the listener context to the listener object.
            boolean laxDataBinding = Boolean.TRUE.equals(config.get(LAX_DATA_BINDING));
            @SuppressWarnings("unchecked")
            BMap<BString, Object> csvFailSafe = (BMap<BString, Object>) config.get(CSV_FAIL_SAFE);
            listenerObj.addNativeData(NATIVE_LISTENER_CONTEXT,
                    new ListenerContext(env.getRuntime(), caller, laxDataBinding, csvFailSafe));
            return null;
        } catch (BError e) {
            return e;
        } catch (Exception e) {
            return FilesErrorCreator.processingError(Ops.describe(e), e);
        }
    }

    /**
     * Attaches the single service to the listener, reading its watch configuration and handlers.
     * A second attach fails: one service per listener.
     *
     * @param env         the Ballerina runtime environment
     * @param listenerObj the Ballerina listener object
     * @param service     the service being attached
     * @return {@code null} on success, or the validation error
     */
    public static Object attachService(Environment env, BObject listenerObj, BObject service) {
        ListenerContext ctx = context(listenerObj);
        // If the listener is not initialized, return an error.
        if (ctx == null) {
            return FilesErrorCreator.processingError("the listener is not initialized", null);
        }
        // If a service is already attached to the listener, return an error.
        if (ctx.service != null) {
            return FilesErrorCreator.processingError(
                    "Only one service can be attached to a files:Listener", null);
        }
        try {
            // Parse the service's watch configuration and handler set, then attach it.
            ctx.serviceContext = parseService(service);
            ctx.service = service;
            return null;
        } catch (BError e) {
            return e;
        } catch (Exception e) {
            return FilesErrorCreator.processingError(Ops.describe(e), e);
        }
    }

    /**
     * Detaches the service from the listener.
     *
     * @param env         the Ballerina runtime environment
     * @param listenerObj the Ballerina listener object
     * @param service     the service being detached
     * @return an error if the given service is not the attached one, otherwise {@code null}
     */
    public static Object detachService(Environment env, BObject listenerObj, BObject service) {
        ListenerContext ctx = context(listenerObj);
        if (ctx == null || ctx.service != service) {
            return FilesErrorCreator.processingError("the given service is not attached to this listener", null);
        }
        ctx.service = null;
        ctx.serviceContext = null;
        return null;
    }

    /**
     * Step 1. (poll → scan → consider → dispatch)
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
        return Ops.invoke(env, () -> {
            ListenerContext ctx = context(listenerObj);
            ServiceContext serviceContext = ctx == null ? null : ctx.serviceContext;
            if (ctx == null || ctx.stopped || ctx.service == null || serviceContext == null) {
                return null;
            }
            try {
                scan(listenerObj, ctx, serviceContext);
            } catch (Throwable e) {
                BError mapped = mapScanFailure(e);
                invokeOnError(ctx, mapped);
                return mapped;
            }
            return null;
        });
    }

    // Maps a scan failure to the module's typed error: Azure service failures go through the
    // code-keyed mapper, and anything else becomes a ProcessingError.
    private static BError mapScanFailure(Throwable e) {
        if (e instanceof ShareStorageException storageException) {
            return ErrorMapper.toBError(storageException);
        }
        if (e instanceof BError bError) {
            return bError;
        }
        return FilesErrorCreator.processingError(Ops.describe(e), e);
    }

    /**
     * Invokes the service's optional {@code onError} handler with the given error, on a dispatch
     * virtual thread. onError is a notification hook: its own failure is printed and swallowed,
     * and it never alters the listener's consume behavior or polling cadence.
     *
     * @param ctx   the listener context
     * @param error the error to hand to the handler
     */
    private static void invokeOnError(ListenerContext ctx, BError error) {
        BObject service = ctx.service;
        ServiceContext serviceContext = ctx.serviceContext;
        int arity = serviceContext == null ? 0 : serviceContext.onErrorArity();
        if (service == null || arity == 0 || ctx.stopped) {
            return;
        }
        try {
            ctx.dispatchExecutor.execute(() -> {
                try {
                    ObjectType serviceType = (ObjectType) TypeUtils.getReferredType(TypeUtils.getType(service));
                    boolean isConcurrentSafe = serviceType.isIsolated() && serviceType.isIsolated(ON_ERROR);
                    StrandMetadata metadata = new StrandMetadata(isConcurrentSafe, null);
                    Object[] args = arity >= 2 ? new Object[]{error, ctx.caller} : new Object[]{error};
                    Object result = ctx.runtime.callMethod(service, ON_ERROR, metadata, args);
                    if (result instanceof BError handlerError) {
                        handlerError.printStackTrace();
                    }
                } catch (BError handlerPanic) {
                    handlerPanic.printStackTrace();
                } catch (RuntimeException e) {
                    LOG.warn("azure.storage.files listener: onError invocation failed", e);
                }
            });
        } catch (RejectedExecutionException e) {
            // The executor is shutting down; the notification is dropped with the listener.
        }
    }

    /**
     * Stops the listener: marks the context stopped and shuts down the dispatch executor. A graceful
     * stop waits a bounded time for in-flight handlers to finish; an immediate stop interrupts them.
     *
     * @param listenerObj the Ballerina listener object
     * @param graceful    whether to drain in-flight handlers ({@code true}) or interrupt them
     * @return {@code null}
     */
    public static Object stopListener(BObject listenerObj, boolean graceful) {
        ListenerContext ctx = context(listenerObj);
        if (ctx == null) {
            return null;
        }
        ctx.stopped = true;
        if (!graceful) {
            ctx.dispatchExecutor.shutdownNow();
            return null;
        }
        ctx.dispatchExecutor.shutdown();
        try {
            if (!ctx.dispatchExecutor.awaitTermination(AWAIT_SECONDS, TimeUnit.SECONDS)) {
                LOG.warn("azure.storage.files listener: timed out waiting for in-flight handlers to finish");
            }
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
        }
        return null;
    }

    /**
     * Step 2. (poll → scan → consider → dispatch)
     * Scans the watched path for files and directories.
     * Iterative DFS with an explicit ArrayDeque (no recursion), listing with extended info + timestamps + ETags. 
     * Directories are pushed only if recursive; files go to consider. Checks ctx.stopped each iteration.
     * 
     * @param listenerObj    the Ballerina listener object
     * @param ctx            the listener context
     * @param serviceContext the attached service's watch configuration
     */
    private static void scan(BObject listenerObj, ListenerContext ctx, ServiceContext serviceContext) {
        ShareClient share = Ops.shareClient(listenerObj);
        Deque<String> pending = new ArrayDeque<>();
        pending.push(serviceContext.watchedPath());
        while (!pending.isEmpty()) {
            if (ctx.stopped) {
                return;
            }
            String directory = pending.pop();
            ShareDirectoryClient directoryClient = directory.isEmpty()
                    ? share.getRootDirectoryClient() : share.getDirectoryClient(directory);
            ShareListFilesAndDirectoriesOptions options = new ShareListFilesAndDirectoriesOptions()
                    .setIncludeExtendedInfo(true)
                    .setIncludeTimestamps(true)
                    .setIncludeETag(true);
            for (ShareFileItem item : directoryClient.listFilesAndDirectories(options, null, null)) {
                String childPath = directory.isEmpty() ? item.getName() : directory + "/" + item.getName();
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

    /**
     * Step 3. (poll → scan → consider → dispatch)
     * Considers a file for dispatching. Checks the service's file name pattern and minimum file
     * age filters. Adds to ctx.inProgress and dispatches on a virtual thread.
     *
     * @param listenerObj    the Ballerina listener object
     * @param ctx            the listener context
     * @param serviceContext the attached service's watch configuration
     * @param item           the file item
     * @param path           the file path
     */
    private static void consider(BObject listenerObj, ListenerContext ctx, ServiceContext serviceContext,
                                 ShareFileItem item, String path) {
        String name = item.getName();
        // Service-level name-pattern filter: Skip if name doesn't match pattern.
        if (serviceContext.fileNamePattern() != null && !serviceContext.fileNamePattern().matcher(name).matches()) {
            return;
        }
        // Min-age filter: Skip if too young.
        if (serviceContext.minFileAgeSeconds() != null && item.getProperties() != null
                && item.getProperties().getLastModified() != null) {
            long age = Duration.between(item.getProperties().getLastModified().toInstant(), Instant.now())
                    .getSeconds();
            if (age < serviceContext.minFileAgeSeconds()) {
                return;
            }
        }
        // The in-progress guard: Add to inProgress and dispatch.
        String eTag = item.getProperties() == null || item.getProperties().getETag() == null
                ? "" : item.getProperties().getETag();
        // Create a deduplication key for the file.
        String key = path + "|" + eTag;
        // Add the key to keySet and return if already in progress or stopped.
        if (ctx.stopped || !ctx.inProgress.add(key)) {
            return;
        }
        try {
            // Dispatch the file on a virtual thread.
            ctx.dispatchExecutor.execute(() -> dispatch(listenerObj, ctx, serviceContext, item, path, key));
        } catch (RejectedExecutionException e) {
            // Remove the key from inProgress if the dispatch is rejected.
            ctx.inProgress.remove(key);
        }
    }

    /**
     * Step 4. (poll → scan → consider → dispatch).
     * Dispatches a file to the handler.
     * 
     * @param listenerObj    the Ballerina listener object
     * @param ctx            the listener context
     * @param serviceContext the attached service's watch configuration and handler set
     * @param item           the file item
     * @param path           the file path
     * @param key            the deduplication key
     */
    private static void dispatch(BObject listenerObj, ListenerContext ctx, ServiceContext serviceContext,
                                 ShareFileItem item, String path, String key) {
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
                // A stream handler skips the eager download: the file is read chunk by chunk as
                // the handler drains the stream.
                InputStream inputStream;
                try {
                    inputStream = Ops.shareClient(listenerObj).getFileClient(path).openInputStream();
                } catch (RuntimeException e) {
                    // If the file cannot be opened, log the error and return to try again next poll.
                    LOG.warn("azure.storage.files listener: cannot read {}; will retry next poll", path, e);
                    return;
                }
                try {
                    content = ON_FILE_CSV.equals(handler.methodName())
                            ? ContentStreamOps.createCsvStream(ctx.runtime, inputStream,
                                    streamContentType.getConstrainedType(), ctx.laxDataBinding)
                            : ContentStreamOps.createByteStream(inputStream,
                                    streamContentType.getConstrainedType());
                } catch (RuntimeException e) {
                    closeQuietly(inputStream);
                    handleBindingFailure(listenerObj, ctx, serviceContext, handler, path, e);
                    return;
                }
            } else {
                byte[] bytes;
                // Download the file.
                try {
                    bytes = download(listenerObj, path);
                } catch (RuntimeException e) {
                    // If the file cannot be read, log the error and return to try again next poll.
                    LOG.warn("azure.storage.files listener: cannot read {}; will retry next poll", path, e);
                    return;
                }
                try {
                    // Bind the content to the handler.
                    content = bindContent(ctx, handler, bytes, item.getName());
                } catch (RuntimeException e) {
                    handleBindingFailure(listenerObj, ctx, serviceContext, handler, path, e);
                    return;
                }
            }

            // Create the file info record, including the file name, size, and last modified time.
            int slash = path.lastIndexOf('/');
            String parentPath = slash < 0 ? "" : path.substring(0, slash);
            BMap<BString, Object> fileInfo = RecordMapper.fileInfo(item, parentPath);

            // Invoke the handler.
            Object result = invokeHandler(ctx, service, handler, content, fileInfo);
            if (result instanceof BError error) {
                // The handler already saw its own error, so onError is not notified; the error is
                // printed so the failure stays visible without a logging backend.
                error.printStackTrace();
                // Post-process (afterError) the file.
                postProcess(listenerObj, serviceContext, handler.afterError(), path);
            } else {
                // Post-process (afterProcess) the file.
                postProcess(listenerObj, serviceContext, handler.afterProcess(), path);
            }
        } catch (Throwable e) {
            // If the dispatch fails, log the error and remove the key from inProgress.
            LOG.error("azure.storage.files listener: unexpected dispatch failure for {}", path, e);
        } finally {
            // Remove the key from inProgress.
            ctx.inProgress.remove(key);
        }
    }

    // A content-binding failure notifies onError (when declared) and post-processes (afterError)
    // the file; without an onError the error is printed so the failure stays visible.
    private static void handleBindingFailure(BObject listenerObj, ListenerContext ctx,
                                             ServiceContext serviceContext, HandlerConfig handler,
                                             String path, RuntimeException e) {
        BError bindingError = e instanceof BError bError
                ? bError : FilesErrorCreator.processingError(Ops.describe(e), e);
        if (serviceContext.onErrorArity() == 0) {
            bindingError.printStackTrace();
        }
        invokeOnError(ctx, bindingError);
        postProcess(listenerObj, serviceContext, handler.afterError(), path);
    }

    private static void closeQuietly(InputStream inputStream) {
        try {
            inputStream.close();
        } catch (IOException e) {
            LOG.debug("azure.storage.files listener: failed to close a content stream", e);
        }
    }

    private static HandlerConfig resolveHandler(ServiceContext serviceContext, String fileName) {
        for (HandlerConfig handler : serviceContext.handlers().values()) {
            Pattern routing = handler.routingPattern();
            // If routing pattern is set and matches the file name, return the handler.
            if (routing != null && routing.matcher(fileName).matches()) {
                return handler;
            }
        }
        // If no routing pattern matches, try extension mapping (such as "onFileJson" for "file.json").
        String mapped = EXTENSION_HANDLERS.get(extension(fileName));
        // If a mapped handler is found, return it.
        if (mapped != null && serviceContext.handlers().containsKey(mapped)) {
            return serviceContext.handlers().get(mapped);
        }
        // If no mapping is found, return the default handler.
        return serviceContext.handlers().get(ON_FILE);
    }

    private static Object bindContent(ListenerContext ctx, HandlerConfig handler, byte[] bytes, String fileName) {
        switch (handler.methodName()) {
            // Convert the bytes to a string and return it.
            case ON_FILE_TEXT:
                return StringUtils.fromString(new String(bytes, StandardCharsets.UTF_8));
            // Bind the bytes to the handler's declared JSON target type.
            case ON_FILE_JSON:
                return ContentBinder.bindJson(bytes, handler.contentType(), ctx.laxDataBinding);
            // Bind the bytes to the handler's declared XML target type.
            case ON_FILE_XML:
                return ContentBinder.bindXml(bytes, handler.contentType(), ctx.laxDataBinding);
            // Bind the bytes to the handler's declared CSV target type.
            case ON_FILE_CSV:
                return bindCsv(ctx, handler, bytes, fileName);
            default:
                return ValueCreator.createArrayValue(bytes);
        }
    }

    // Binds CSV content on a real Ballerina strand through the module-level bindCsvContent helper,
    // because the data.csv parser needs the runtime environment of a strand.
    private static Object bindCsv(ListenerContext ctx, HandlerConfig handler, byte[] bytes, String fileName) {
        String prefix = fileName.replaceAll("\\.[^.]+$", "");
        Object result = ctx.runtime.callFunction(ModuleUtils.getModule(), BIND_CSV_CONTENT_FUNCTION,
                new StrandMetadata(true, null),
                ValueCreator.createArrayValue(bytes),
                ValueCreator.createTypedescValue(TypeUtils.getReferredType(handler.contentType())),
                ctx.laxDataBinding,
                ctx.csvFailSafe,
                StringUtils.fromString(prefix));
        if (result instanceof BError bError) {
            throw FilesErrorCreator.processingError("content does not bind to the '" + ON_FILE_CSV
                    + "' handler's declared type: " + bError.getErrorMessage(), bError);
        }
        return result;
    }

    /**
     * Invokes the handler.
     * 
     * @param ctx         the listener context
     * @param service     the service
     * @param handler     the handler config
     * @param content     the content
     * @param fileInfo    the file info
     * @return the result of the handler invocation
     */
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

    /**
     * Post-processes the file.
     * 
     * @param listenerObj    the Ballerina listener object
     * @param serviceContext the attached service's watch configuration
     * @param action         the post-process action
     * @param path           the file path
     */
    private static void postProcess(BObject listenerObj, ServiceContext serviceContext, PostAction action,
                                    String path) {
        // If the action is null, return.
        if (action == null) {
            return;
        }
        try {
            // Get the share client.
            ShareClient share = Ops.shareClient(listenerObj);
            // If the action is a delete, delete the file.
            if (action.isDelete()) {
                share.getFileClient(path).delete();
                return;
            }
            // If the action is a move, move the file.
            String moveRoot = Ops.directoryPath(StringUtils.fromString(action.moveTo()));
            // If the action is a move and subdirectories are preserved, join the move root and the relative path.
            String destination = action.preserveSubDirs()
                    ? join(moveRoot, relativeTo(path, serviceContext.watchedPath()))
                    : join(moveRoot, path.substring(path.lastIndexOf('/') + 1));
            int slash = destination.lastIndexOf('/');
            ensureDirectory(share, slash < 0 ? "" : destination.substring(0, slash));
            share.getFileClient(path).rename(destination);
        } catch (RuntimeException e) {
            // If the post-process fails, log the error and continue. So handler can run again next poll.
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
        Ops.shareClient(listenerObj).getFileClient(path).download(out);
        return out.toByteArray();
    }

    /**
     * Parses the attached service's watch configuration and handler set.
     *
     * @param service the service being attached
     * @return the immutable per-attach service context
     */
    private static ServiceContext parseService(BObject service) {
        // Get the service type.
        ObjectType serviceType = (ObjectType) TypeUtils.getReferredType(TypeUtils.getType(service));
        // Get the service config annotation.
        BMap<BString, Object> config = annotation(serviceType.getAnnotations(), SERVICE_CONFIG_ANNOTATION);
        // If the service config annotation is not present, throw an error.
        if (config == null) {
            throw FilesErrorCreator.processingError(
                    "the service must declare @files:ServiceConfig with a watched path", null);
        }
        // Get the path value from the service config annotation.
        Object pathValue = config.get(SERVICE_CONFIG_PATH);
        // If the path value is not present or is empty, throw an error.
        if (pathValue == null || ((BString) pathValue).getValue().strip().isEmpty()) {
            throw FilesErrorCreator.processingError("@files:ServiceConfig requires a non-empty path", null);
        }
        String watchedPath = Ops.directoryPath((BString) pathValue);
        // The recursive flag defaults to true when absent.
        Object recursiveValue = config.get(SERVICE_CONFIG_RECURSIVE);
        boolean recursive = recursiveValue == null || (Boolean) recursiveValue;
        // The file name pattern is optional.
        Object patternValue = config.get(FILE_NAME_PATTERN);
        Pattern fileNamePattern = patternValue == null ? null : compile(((BString) patternValue).getValue());
        // The minimum file age is optional.
        Object ageValue = config.get(SERVICE_CONFIG_MIN_FILE_AGE);
        Double minFileAgeSeconds = ageValue == null ? null : ((BDecimal) ageValue).floatValue();

        // Create a map of handlers.
        Map<String, HandlerConfig> handlers = new LinkedHashMap<>();
        // Iterate over the methods.
        int onErrorArity = 0;
        for (MethodType method : serviceType.getMethods()) {
            // Get the method name.
            String name = method.getName();
            if (ON_ERROR.equals(name)) {
                onErrorArity = method.getParameters().length;
                continue;
            }
            if (!HANDLER_NAMES.contains(name)) {
                continue;
            }
            // Get the method config annotation.
            BMap<BString, Object> functionConfig = annotation(method.getAnnotations(), FUNCTION_CONFIG_ANNOTATION);
            // If the method config annotation is not present, set the routing pattern to null.
            Pattern routing = null;
            // If the method config annotation is not present, set the after process action to null.
            PostAction afterProcess = null;
            PostAction afterError = null;

            if (functionConfig != null) {
                // Get the file name pattern value from the method config annotation.
                Object routingPatternValue = functionConfig.get(FILE_NAME_PATTERN);
                // If the file name pattern value is not present, set the routing pattern to null.
                if (routingPatternValue != null) {
                    routing = compile(((BString) routingPatternValue).getValue());
                }
                // Get the after process action from the method config annotation.
                afterProcess = readAction(functionConfig, FUNCTION_CONFIG_AFTER_PROCESS);
                // Get the after error action from the method config annotation.
                afterError = readAction(functionConfig, FUNCTION_CONFIG_AFTER_ERROR);
            }
            // Get the parameters of the method.
            Parameter[] params = method.getParameters();
            // If the second parameter is a caller, set the second parameter is caller flag to true.
            boolean secondIsCaller = params.length >= 2
                    && CALLER_OBJECT.equals(TypeUtils.getReferredType(params[1].type).getName());
            // Get the content type of the method.
            Type contentType = params.length >= 1 ? params[0].type : null;
            // Create a new handler config and add it to the handlers map.
            handlers.put(name, new HandlerConfig(name, routing, afterProcess, afterError,
                    params.length, secondIsCaller, contentType));
        }
        return new ServiceContext(watchedPath, recursive, fileNamePattern, minFileAgeSeconds,
                handlers, onErrorArity);
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
            throw FilesErrorCreator.processingError("unknown post-process action: " + action.getValue(), null);
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
            throw FilesErrorCreator.processingError("invalid regular expression: " + pattern, e);
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
     * Per-listener mutable state: the SDK dispatch machinery, the parsed watch configuration, the
     * and the attached service.
     */
    private static final class ListenerContext {

        private final Runtime runtime;
        private final BObject caller;
        private final boolean laxDataBinding;
        private final BMap<BString, Object> csvFailSafe;
        private final ExecutorService dispatchExecutor = Executors.newVirtualThreadPerTaskExecutor();
        private final Set<String> inProgress = ConcurrentHashMap.newKeySet();
        private volatile BObject service;
        private volatile ServiceContext serviceContext;
        private volatile boolean stopped;

        private ListenerContext(Runtime runtime, BObject caller,
                                boolean laxDataBinding, BMap<BString, Object> csvFailSafe) {
            this.runtime = runtime;
            this.caller = caller;
            this.laxDataBinding = laxDataBinding;
            this.csvFailSafe = csvFailSafe;
        }
    }

    // The attached service's parsed watch configuration and handler set, immutable per attach:
    // set when the service attaches and cleared when it detaches.
    private record ServiceContext(String watchedPath, boolean recursive, Pattern fileNamePattern,
                                  Double minFileAgeSeconds, Map<String, HandlerConfig> handlers,
                                  int onErrorArity) {
    }

    // One content handler: its resolved routing pattern, post-process actions, the shape of its
    // parameter list (how many it declares, and whether a two-parameter handler's second parameter
    // is the Caller rather than the FileInfo), and its declared content parameter type (used to
    // bind typed content, e.g. a map<json>, a record, or an array of them for onFileJson).
    private record HandlerConfig(String methodName, Pattern routingPattern,
                                 PostAction afterProcess, PostAction afterError,
                                 int arity, boolean secondParamIsCaller, Type contentType) {
    }

    // A post-process action: a delete, or a move to a target directory.
    private record PostAction(boolean isDelete, String moveTo, boolean preserveSubDirs) {
    }
}
