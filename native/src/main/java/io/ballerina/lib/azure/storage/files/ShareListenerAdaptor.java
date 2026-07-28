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

package io.ballerina.lib.azure.storage.files;

import com.azure.storage.file.share.ShareClient;
import com.azure.storage.file.share.ShareDirectoryClient;
import com.azure.storage.file.share.ShareServiceClient;
import com.azure.storage.file.share.models.ShareFileItem;
import com.azure.storage.file.share.models.ShareStorageException;
import com.azure.storage.file.share.options.ShareListFilesAndDirectoriesOptions;
import com.azure.xml.XmlReader;
import io.ballerina.runtime.api.Environment;
import io.ballerina.runtime.api.Runtime;
import io.ballerina.runtime.api.concurrent.StrandMetadata;
import io.ballerina.runtime.api.creators.TypeCreator;
import io.ballerina.runtime.api.creators.ValueCreator;
import io.ballerina.runtime.api.types.ArrayType;
import io.ballerina.runtime.api.types.MethodType;
import io.ballerina.runtime.api.types.ObjectType;
import io.ballerina.runtime.api.types.Parameter;
import io.ballerina.runtime.api.types.PredefinedTypes;
import io.ballerina.runtime.api.types.Type;
import io.ballerina.runtime.api.utils.JsonUtils;
import io.ballerina.runtime.api.utils.StringUtils;
import io.ballerina.runtime.api.utils.TypeUtils;
import io.ballerina.runtime.api.utils.XmlUtils;
import io.ballerina.runtime.api.values.BArray;
import io.ballerina.runtime.api.values.BDecimal;
import io.ballerina.runtime.api.values.BError;
import io.ballerina.runtime.api.values.BMap;
import io.ballerina.runtime.api.values.BObject;
import io.ballerina.runtime.api.values.BString;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.io.ByteArrayOutputStream;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.time.Instant;
import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.Deque;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.RejectedExecutionException;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicLong;
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
    private static final String NATIVE_LISTENER_CONTEXT = "azure.storage.files.native.listenerContext";

    // The Caller object type and the ListenerConfiguration field this class reads.
    private static final String CALLER_OBJECT = "Caller";
    private static final BString POLLING_INTERVAL = StringUtils.fromString("pollingInterval");

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
    private static final Set<String> HANDLER_NAMES =
            Set.of(ON_FILE, ON_FILE_TEXT, ON_FILE_JSON, ON_FILE_XML, ON_FILE_CSV);
    private static final Map<String, String> EXTENSION_HANDLERS = Map.of(
            "json", ON_FILE_JSON, "xml", ON_FILE_XML, "csv", ON_FILE_CSV, "txt", ON_FILE_TEXT);

    // Poll backoff cap and the bounded wait for in-flight handlers on stop.
    private static final long MAX_BACKOFF_MILLIS = 300_000L;
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
            // Azure's XmlReader resolves its StAX factory in a static initializer using the calling
            // thread's context classloader; force that to happen here, on the init strand, so a poll
            // thread can never be the first to trigger it and poison the class.
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
            BObject caller = ValueCreator.createObjectValue(ModuleUtils.getModule(), CALLER_OBJECT, shareName);
            caller.addNativeData(Ops.NATIVE_SERVICE_CLIENT, serviceClient);
            caller.addNativeData(Ops.NATIVE_SHARE_CLIENT, shareClient);
            double pollingSeconds = ((BDecimal) config.get(POLLING_INTERVAL)).floatValue();
            listenerObj.addNativeData(NATIVE_LISTENER_CONTEXT,
                    new ListenerContext(env.getRuntime(), caller, pollingSeconds));
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
        if (ctx == null) {
            return FilesErrorCreator.processingError("the listener is not initialized", null);
        }
        if (ctx.service != null) {
            return FilesErrorCreator.processingError(
                    "a service is already attached to this listener; one service per listener", null);
        }
        try {
            parseServiceConfig(ctx, service);
            parseHandlers(ctx, service);
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
        return null;
    }

    /**
     * Runs one poll of the watched path. Called on a Ballerina strand by the task job. Lists the
     * present files and dispatches each match on a virtual thread. Never throws: a listing failure
     * is turned into an exponential backoff.
     *
     * @param env         the Ballerina runtime environment
     * @param listenerObj the Ballerina listener object
     * @return {@code null}
     */
    public static Object poll(Environment env, BObject listenerObj) {
        return Ops.invoke(env, () -> {
            ListenerContext ctx = context(listenerObj);
            if (ctx == null || ctx.stopped || ctx.service == null) {
                return null;
            }
            if (System.currentTimeMillis() < ctx.nextAllowedPollMillis.get()) {
                return null;
            }
            try {
                scan(listenerObj, ctx);
                ctx.failureCount.set(0);
                ctx.nextAllowedPollMillis.set(0L);
            } catch (Throwable e) {
                int attempt = ctx.failureCount.incrementAndGet();
                long backoff = Math.min((long) (Math.pow(2, attempt) * ctx.pollingIntervalSeconds * 1000d),
                        MAX_BACKOFF_MILLIS);
                ctx.nextAllowedPollMillis.set(System.currentTimeMillis() + backoff);
                LOG.warn("azure.storage.files listener poll failed; backing off {} ms", backoff, e);
            }
            return null;
        });
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

    private static void scan(BObject listenerObj, ListenerContext ctx) {
        ShareClient share = Ops.shareClient(listenerObj);
        Deque<String> pending = new ArrayDeque<>();
        pending.push(ctx.watchedPath);
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
                    if (ctx.recursive) {
                        pending.push(childPath);
                    }
                } else {
                    consider(listenerObj, ctx, item, childPath);
                }
            }
        }
    }

    private static void consider(BObject listenerObj, ListenerContext ctx, ShareFileItem item, String path) {
        String name = item.getName();
        if (ctx.fileNamePattern != null && !ctx.fileNamePattern.matcher(name).matches()) {
            return;
        }
        if (ctx.minFileAgeSeconds != null && item.getProperties() != null
                && item.getProperties().getLastModified() != null) {
            long age = Duration.between(item.getProperties().getLastModified().toInstant(), Instant.now())
                    .getSeconds();
            if (age < ctx.minFileAgeSeconds) {
                return;
            }
        }
        String eTag = item.getProperties() == null || item.getProperties().getETag() == null
                ? "" : item.getProperties().getETag();
        String key = path + "|" + eTag;
        if (ctx.stopped || !ctx.inProgress.add(key)) {
            return;
        }
        try {
            ctx.dispatchExecutor.execute(() -> dispatch(listenerObj, ctx, item, path, key));
        } catch (RejectedExecutionException e) {
            ctx.inProgress.remove(key);
        }
    }

    private static void dispatch(BObject listenerObj, ListenerContext ctx, ShareFileItem item,
                                 String path, String key) {
        try {
            // Snapshot the service so a concurrent detach cannot null it mid-dispatch; if it is
            // already gone, leave the file unconsumed for a later poll.
            BObject service = ctx.service;
            if (ctx.stopped || service == null) {
                return;
            }
            HandlerConfig handler = resolveHandler(ctx, item.getName());
            if (handler == null) {
                LOG.debug("azure.storage.files listener: no handler for {}, skipping", path);
                return;
            }
            byte[] bytes;
            try {
                bytes = download(listenerObj, path);
            } catch (RuntimeException e) {
                LOG.warn("azure.storage.files listener: cannot read {}; will retry next poll", path, e);
                return;
            }
            Object content;
            try {
                content = bindContent(handler, bytes);
            } catch (RuntimeException e) {
                LOG.warn("azure.storage.files listener: content binding failed for {}", path, e);
                postProcess(listenerObj, ctx, handler.afterError(), path);
                return;
            }
            int slash = path.lastIndexOf('/');
            String parentPath = slash < 0 ? "" : path.substring(0, slash);
            BMap<BString, Object> fileInfo = RecordMapper.fileInfo(item, parentPath);
            Object result = invokeHandler(ctx, service, handler, content, fileInfo);
            if (result instanceof BError error) {
                LOG.warn("azure.storage.files listener: handler {} returned an error for {}",
                        handler.methodName(), path, error);
                postProcess(listenerObj, ctx, handler.afterError(), path);
            } else {
                postProcess(listenerObj, ctx, handler.afterProcess(), path);
            }
        } catch (Throwable e) {
            LOG.error("azure.storage.files listener: unexpected dispatch failure for {}", path, e);
        } finally {
            ctx.inProgress.remove(key);
        }
    }

    private static HandlerConfig resolveHandler(ListenerContext ctx, String fileName) {
        for (HandlerConfig handler : ctx.handlers.values()) {
            Pattern routing = handler.routingPattern();
            if (routing != null && routing.matcher(fileName).matches()) {
                return handler;
            }
        }
        String mapped = EXTENSION_HANDLERS.get(extension(fileName));
        if (mapped != null && ctx.handlers.containsKey(mapped)) {
            return ctx.handlers.get(mapped);
        }
        return ctx.handlers.get(ON_FILE);
    }

    private static Object bindContent(HandlerConfig handler, byte[] bytes) {
        switch (handler.methodName()) {
            case ON_FILE_TEXT:
                return StringUtils.fromString(new String(bytes, StandardCharsets.UTF_8));
            case ON_FILE_JSON:
                Object json = JsonUtils.parse(new String(bytes, StandardCharsets.UTF_8));
                try {
                    return JsonUtils.convertJSON(json, handler.contentType());
                } catch (BError e) {
                    throw FilesErrorCreator.processingError(
                            "content does not match the '" + ON_FILE_JSON + "' handler's declared type", e);
                }
            case ON_FILE_XML:
                return XmlUtils.parse(new String(bytes, StandardCharsets.UTF_8));
            case ON_FILE_CSV:
                return csvMatrix(new String(bytes, StandardCharsets.UTF_8));
            default:
                return ValueCreator.createArrayValue(bytes);
        }
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

    private static void postProcess(BObject listenerObj, ListenerContext ctx, PostAction action, String path) {
        if (action == null) {
            return;
        }
        try {
            ShareClient share = Ops.shareClient(listenerObj);
            if (action.isDelete()) {
                share.getFileClient(path).delete();
                return;
            }
            String moveRoot = Ops.directoryPath(StringUtils.fromString(action.moveTo()));
            String destination = action.preserveSubDirs()
                    ? join(moveRoot, relativeTo(path, ctx.watchedPath))
                    : join(moveRoot, path.substring(path.lastIndexOf('/') + 1));
            int slash = destination.lastIndexOf('/');
            ensureDirectory(share, slash < 0 ? "" : destination.substring(0, slash));
            share.getFileClient(path).rename(destination);
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
        Ops.shareClient(listenerObj).getFileClient(path).download(out);
        return out.toByteArray();
    }

    private static void parseServiceConfig(ListenerContext ctx, BObject service) {
        ObjectType serviceType = (ObjectType) TypeUtils.getReferredType(TypeUtils.getType(service));
        BMap<BString, Object> config = annotation(serviceType.getAnnotations(), SERVICE_CONFIG_ANNOTATION);
        if (config == null) {
            throw FilesErrorCreator.processingError(
                    "the service must declare @files:ServiceConfig with a watched path", null);
        }
        Object pathValue = config.get(SERVICE_CONFIG_PATH);
        if (pathValue == null || ((BString) pathValue).getValue().strip().isEmpty()) {
            throw FilesErrorCreator.processingError("@files:ServiceConfig requires a non-empty path", null);
        }
        ctx.watchedPath = Ops.directoryPath((BString) pathValue);
        Object recursiveValue = config.get(SERVICE_CONFIG_RECURSIVE);
        ctx.recursive = recursiveValue == null || (Boolean) recursiveValue;
        Object patternValue = config.get(FILE_NAME_PATTERN);
        if (patternValue != null) {
            ctx.fileNamePattern = compile(((BString) patternValue).getValue());
        }
        Object ageValue = config.get(SERVICE_CONFIG_MIN_FILE_AGE);
        if (ageValue != null) {
            ctx.minFileAgeSeconds = ((BDecimal) ageValue).floatValue();
        }
    }

    private static void parseHandlers(ListenerContext ctx, BObject service) {
        ObjectType serviceType = (ObjectType) TypeUtils.getReferredType(TypeUtils.getType(service));
        Map<String, HandlerConfig> handlers = new LinkedHashMap<>();
        for (MethodType method : serviceType.getMethods()) {
            String name = method.getName();
            if (!HANDLER_NAMES.contains(name)) {
                continue;
            }
            BMap<BString, Object> config = annotation(method.getAnnotations(), FUNCTION_CONFIG_ANNOTATION);
            Pattern routing = null;
            PostAction afterProcess = null;
            PostAction afterError = null;
            if (config != null) {
                Object patternValue = config.get(FILE_NAME_PATTERN);
                if (patternValue != null) {
                    routing = compile(((BString) patternValue).getValue());
                }
                afterProcess = readAction(config, FUNCTION_CONFIG_AFTER_PROCESS);
                afterError = readAction(config, FUNCTION_CONFIG_AFTER_ERROR);
            }
            Parameter[] params = method.getParameters();
            boolean secondIsCaller = params.length >= 2
                    && CALLER_OBJECT.equals(TypeUtils.getReferredType(params[1].type).getName());
            Type contentType = params.length >= 1 ? params[0].type : null;
            handlers.put(name, new HandlerConfig(name, routing, afterProcess, afterError,
                    params.length, secondIsCaller, contentType));
        }
        ctx.handlers = handlers;
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

    private static BArray csvMatrix(String text) {
        ArrayType rowType = TypeCreator.createArrayType(PredefinedTypes.TYPE_STRING);
        BArray matrix = ValueCreator.createArrayValue(TypeCreator.createArrayType(rowType));
        for (List<String> row : parseCsv(text)) {
            BArray rowArray = ValueCreator.createArrayValue(rowType);
            for (String cell : row) {
                rowArray.append(StringUtils.fromString(cell));
            }
            matrix.append(rowArray);
        }
        return matrix;
    }

    private static List<List<String>> parseCsv(String text) {
        List<List<String>> rows = new ArrayList<>();
        List<String> current = new ArrayList<>();
        StringBuilder field = new StringBuilder();
        boolean inQuotes = false;
        int i = 0;
        while (i < text.length()) {
            char c = text.charAt(i);
            if (inQuotes) {
                if (c == '"') {
                    if (i + 1 < text.length() && text.charAt(i + 1) == '"') {
                        field.append('"');
                        i++;
                    } else {
                        inQuotes = false;
                    }
                } else {
                    field.append(c);
                }
            } else if (c == '"') {
                inQuotes = true;
            } else if (c == ',') {
                current.add(field.toString());
                field.setLength(0);
            } else if (c == '\n' || c == '\r') {
                if (c == '\r' && i + 1 < text.length() && text.charAt(i + 1) == '\n') {
                    i++;
                }
                current.add(field.toString());
                field.setLength(0);
                rows.add(current);
                current = new ArrayList<>();
            } else {
                field.append(c);
            }
            i++;
        }
        if (field.length() > 0 || !current.isEmpty()) {
            current.add(field.toString());
            rows.add(current);
        }
        return rows;
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
     * attached service, and the poll backoff counters.
     */
    private static final class ListenerContext {

        private final Runtime runtime;
        private final BObject caller;
        private final double pollingIntervalSeconds;
        private final ExecutorService dispatchExecutor = Executors.newVirtualThreadPerTaskExecutor();
        private final Set<String> inProgress = ConcurrentHashMap.newKeySet();
        private final AtomicInteger failureCount = new AtomicInteger();
        private final AtomicLong nextAllowedPollMillis = new AtomicLong();
        private volatile BObject service;
        private volatile boolean stopped;
        private String watchedPath = "";
        private boolean recursive = true;
        private Pattern fileNamePattern;
        private Double minFileAgeSeconds;
        private Map<String, HandlerConfig> handlers = new LinkedHashMap<>();

        private ListenerContext(Runtime runtime, BObject caller, double pollingIntervalSeconds) {
            this.runtime = runtime;
            this.caller = caller;
            this.pollingIntervalSeconds = pollingIntervalSeconds;
        }
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
