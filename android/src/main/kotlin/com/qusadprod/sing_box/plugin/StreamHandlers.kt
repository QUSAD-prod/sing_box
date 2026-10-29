package com.qusadprod.sing_box.plugin

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import com.qusadprod.sing_box.core.CommandSession
import com.qusadprod.sing_box.core.CoreNotifications
import com.qusadprod.sing_box.core.LibboxRuntime
import com.qusadprod.sing_box.core.ServiceState
import com.qusadprod.sing_box.core.SingBoxError
import com.qusadprod.sing_box.core.libboxMessage
import io.flutter.plugin.common.EventChannel
import io.nekohasekai.libbox.ConnectionEvents
import io.nekohasekai.libbox.Libbox
import io.nekohasekai.libbox.LogIterator
import io.nekohasekai.libbox.NetworkQualityProgress
import io.nekohasekai.libbox.NetworkQualityResult
import io.nekohasekai.libbox.NetworkQualityTestHandler
import io.nekohasekai.libbox.OutboundGroupItemIterator
import io.nekohasekai.libbox.OutboundGroupIterator
import io.nekohasekai.libbox.STUNTestHandler
import io.nekohasekai.libbox.STUNTestProgress
import io.nekohasekai.libbox.STUNTestResult
import io.nekohasekai.libbox.StatusMessage
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

private const val TAG = "sing_box"

/** Main-thread wrapper of an [EventChannel.EventSink] that drops events after cancel. */
internal class MainSink {
    private val handler = Handler(Looper.getMainLooper())

    @Volatile
    private var sink: EventChannel.EventSink? = null

    val isActive: Boolean get() = sink != null

    fun attach(events: EventChannel.EventSink) {
        sink = events
    }

    fun detach() {
        sink = null
    }

    fun success(event: Any?) = post { it.success(event) }

    fun error(code: String, message: String?) = post { it.error(code, message, null) }

    fun endOfStream() = post {
        it.endOfStream()
        sink = null
    }

    private fun post(block: (EventChannel.EventSink) -> Unit) {
        if (Looper.myLooper() == Looper.getMainLooper()) {
            sink?.let(block)
        } else {
            handler.post { sink?.let(block) }
        }
    }
}

/** `sing_box/status`: the in-process service state, emitted on listen and on every change. */
internal class StatusStreamHandler : EventChannel.StreamHandler {
    private val sink = MainSink()
    private val listener = ServiceState.Listener { sink.success(it.toMap()) }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        sink.attach(events)
        ServiceState.addListener(listener)
        sink.success(ServiceState.current.toMap())
    }

    override fun onCancel(arguments: Any?) {
        ServiceState.removeListener(listener)
        sink.detach()
    }
}

/** `sing_box/notifications`: notifications sent by the core through the platform interface. */
internal class NotificationsStreamHandler : EventChannel.StreamHandler {
    private val sink = MainSink()
    private val listener = CoreNotifications.Listener { sink.success(it) }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        sink.attach(events)
        CoreNotifications.addListener(listener)
    }

    override fun onCancel(arguments: Any?) {
        CoreNotifications.removeListener(listener)
        sink.detach()
    }
}

/**
 * Event channel backed by a self-reconnecting libbox command client
 * ([CommandSession]). It stays silent while the service is stopped.
 */
internal abstract class CommandStreamHandler(private val scope: CoroutineScope) : EventChannel.StreamHandler {
    protected val sink = MainSink()
    private var session: CommandSession? = null

    protected abstract fun createSession(): CommandSession

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        sink.attach(events)
        session?.stop()
        session = createSession().also { it.start(scope) }
    }

    override fun onCancel(arguments: Any?) {
        session?.stop()
        session = null
        sink.detach()
    }
}

/** `sing_box/stats`: `CommandStatus` every second. */
internal class StatsStreamHandler(scope: CoroutineScope) : CommandStreamHandler(scope) {
    override fun createSession() = object : CommandSession(Libbox.CommandStatus) {
        override fun onStatus(message: StatusMessage) = sink.success(Converters.status(message))
    }
}

/** `sing_box/logs`: `CommandLog`. The first batch after (re)connecting replaces the buffer. */
internal class LogsStreamHandler(scope: CoroutineScope) : CommandStreamHandler(scope) {
    override fun createSession() = object : CommandSession(Libbox.CommandLog) {
        @Volatile
        private var reset = true

        override fun onConnected() {
            reset = true
        }

        override fun onLogs(messages: LogIterator) {
            val entries = Converters.logEntries(messages)
            val isReset = reset
            reset = false
            sink.success(mapOf("type" to "logs", "reset" to isReset, "entries" to entries))
        }

        override fun onClearLogs() = sink.success(mapOf("type" to "clear"))

        override fun onDefaultLogLevel(level: Int) =
            sink.success(mapOf("type" to "defaultLevel", "level" to level))
    }
}

/** `sing_box/groups`: `CommandGroup`. */
internal class GroupsStreamHandler(scope: CoroutineScope) : CommandStreamHandler(scope) {
    override fun createSession() = object : CommandSession(Libbox.CommandGroup, reconnectOnReload = true) {
        override fun onGroups(groups: OutboundGroupIterator) = sink.success(Converters.groups(groups))
    }
}

/** `sing_box/outbounds`: `CommandOutbounds`. */
internal class OutboundsStreamHandler(scope: CoroutineScope) : CommandStreamHandler(scope) {
    override fun createSession() = object : CommandSession(Libbox.CommandOutbounds, reconnectOnReload = true) {
        override fun onOutbounds(outbounds: OutboundGroupItemIterator) = sink.success(Converters.items(outbounds))
    }
}

/** `sing_box/clash_mode`: `CommandClashMode`. */
internal class ClashModeStreamHandler(scope: CoroutineScope) : CommandStreamHandler(scope) {
    override fun createSession() = object : CommandSession(Libbox.CommandClashMode, reconnectOnReload = true) {
        // libbox calls initializeClashMode from a goroutine on Android (sFixAndroidStack), so an
        // update can arrive first: hold it back instead of sending an empty mode list. The update
        // comes from the subscription opened after the status was read, so it is the newer mode.
        private var modes: List<String>? = null
        private var pendingMode: String? = null

        override fun onInitializeClashMode(modes: List<String>, current: String) {
            synchronized(this) {
                this.modes = modes
                val mode = pendingMode ?: current
                pendingMode = null
                sink.success(mapOf("modes" to modes, "current" to mode))
            }
        }

        override fun onClashMode(mode: String) {
            synchronized(this) {
                val modes = modes
                if (modes == null) {
                    pendingMode = mode
                } else {
                    sink.success(mapOf("modes" to modes, "current" to mode))
                }
            }
        }
    }
}

/**
 * `sing_box/connections`: applies `CommandConnections` events to a
 * `libbox.Connections` and emits a snapshot at most once per second; an empty
 * list when the service stops.
 */
internal class ConnectionsStreamHandler(scope: CoroutineScope) : CommandStreamHandler(scope) {
    override fun createSession() = object : CommandSession(Libbox.CommandConnections, reconnectOnReload = true) {
        private val lock = Any()
        private val handler = Handler(Looper.getMainLooper())
        private var connections = Libbox.newConnections()
        private var lastEmit = 0L
        private var scheduled = false

        override fun onConnectionEvents(events: ConnectionEvents) {
            synchronized(lock) { connections.applyEvents(events) }
            schedule()
        }

        override fun onDisconnected() {
            synchronized(lock) { connections = Libbox.newConnections() }
            sink.success(emptyList<Any>())
        }

        private fun schedule() {
            synchronized(lock) {
                if (scheduled) return
                scheduled = true
            }
            val delay = (lastEmit + INTERVAL_MS - SystemClock.elapsedRealtime()).coerceAtLeast(0)
            handler.postDelayed({ emit() }, delay)
        }

        private fun emit() {
            val snapshot = synchronized(lock) {
                scheduled = false
                Converters.connections(connections)
            }
            lastEmit = SystemClock.elapsedRealtime()
            sink.success(snapshot)
        }
    }

    private companion object {
        const val INTERVAL_MS = 1000L
    }
}

/**
 * One-shot test streams (`network_quality`, `stun`): through the running
 * service with a standalone command client, or directly (without the tunnel)
 * while the service is stopped. Emits progress, one result, then ends.
 */
internal abstract class OneShotTestStreamHandler(
    private val context: Context,
    private val scope: CoroutineScope,
) : EventChannel.StreamHandler {
    protected val sink = MainSink()
    private var cancel: (() -> Unit)? = null

    /** Starts the test; returns a function that cancels it. */
    protected abstract fun startThroughService(arguments: Map<*, *>): () -> Unit

    /** Starts the test without the tunnel; returns a function that cancels it. */
    protected abstract fun startDirect(arguments: Map<*, *>): () -> Unit

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        sink.attach(events)
        val args = arguments as? Map<*, *> ?: emptyMap<Any, Any>()
        scope.launch(Dispatchers.IO) {
            try {
                LibboxRuntime.ensureSetup(context)
                val stop = if (ServiceState.isRunning) startThroughService(args) else startDirect(args)
                if (sink.isActive) cancel = stop else runCatching(stop)
            } catch (e: Exception) {
                Log.w(TAG, "test stream", e)
                fail(e.libboxMessage)
            }
        }
    }

    override fun onCancel(arguments: Any?) {
        sink.detach()
        val stop = cancel
        cancel = null
        if (stop != null) scope.launch(Dispatchers.IO) { runCatching(stop) }
    }

    protected fun fail(message: String?) {
        sink.error(SingBoxError.COMMAND_FAILED, message ?: "test failed")
        sink.endOfStream()
    }

    protected fun finish(result: Map<String, Any?>) {
        sink.success(result)
        sink.endOfStream()
    }
}

internal class NetworkQualityStreamHandler(context: Context, scope: CoroutineScope) :
    OneShotTestStreamHandler(context, scope) {
    private fun handler() = object : NetworkQualityTestHandler {
        override fun onProgress(progress: NetworkQualityProgress?) {
            if (progress != null) sink.success(Converters.networkQualityProgress(progress))
        }

        override fun onResult(result: NetworkQualityResult?) {
            if (result != null) finish(Converters.networkQualityResult(result)) else fail("no result")
        }

        override fun onError(message: String?) = fail(message)
    }

    private fun Map<*, *>.configUrl() =
        (this["configUrl"] as? String)?.takeIf { it.isNotBlank() } ?: Libbox.NetworkQualityDefaultConfigURL

    private fun Map<*, *>.maxRuntime() =
        (this["maxRuntimeSeconds"] as? Number)?.toInt()?.takeIf { it > 0 } ?: Libbox.NetworkQualityDefaultMaxRuntimeSeconds

    override fun startThroughService(arguments: Map<*, *>): () -> Unit {
        val session = Libbox.newStandaloneCommandClient().startNetworkQualityTest(
            arguments.configUrl(),
            arguments["outboundTag"] as? String ?: "",
            arguments["serial"] as? Boolean ?: false,
            arguments.maxRuntime(),
            arguments["http3"] as? Boolean ?: false,
            handler(),
        )
        return { session.close() }
    }

    override fun startDirect(arguments: Map<*, *>): () -> Unit {
        val test = Libbox.newNetworkQualityTest()
        // start() blocks until the test finishes; run it on its own thread.
        Thread({
            runCatching {
                test.start(
                    arguments.configUrl(),
                    arguments["serial"] as? Boolean ?: false,
                    arguments.maxRuntime(),
                    arguments["http3"] as? Boolean ?: false,
                    handler(),
                )
            }.onFailure { fail(it.libboxMessage) }
        }, "sing-box-network-quality").start()
        return { test.cancel() }
    }
}

internal class StunStreamHandler(context: Context, scope: CoroutineScope) : OneShotTestStreamHandler(context, scope) {
    private fun handler() = object : STUNTestHandler {
        override fun onProgress(progress: STUNTestProgress?) {
            if (progress != null) sink.success(Converters.stunProgress(progress))
        }

        override fun onResult(result: STUNTestResult?) {
            if (result != null) finish(Converters.stunResult(result)) else fail("no result")
        }

        override fun onError(message: String?) = fail(message)
    }

    private fun Map<*, *>.server() = (this["server"] as? String)?.takeIf { it.isNotBlank() } ?: Libbox.STUNDefaultServer

    override fun startThroughService(arguments: Map<*, *>): () -> Unit {
        val session = Libbox.newStandaloneCommandClient().startSTUNTest(
            arguments.server(),
            arguments["outboundTag"] as? String ?: "",
            handler(),
        )
        return { session.close() }
    }

    override fun startDirect(arguments: Map<*, *>): () -> Unit {
        val test = Libbox.newSTUNTest()
        Thread({
            runCatching { test.start(arguments.server(), handler()) }.onFailure { fail(it.libboxMessage) }
        }, "sing-box-stun").start()
        return { test.cancel() }
    }
}
