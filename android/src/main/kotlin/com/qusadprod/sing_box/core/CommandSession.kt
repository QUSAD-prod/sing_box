package com.qusadprod.sing_box.core

import android.util.Log
import io.nekohasekai.libbox.CommandClient
import io.nekohasekai.libbox.CommandClientOptions
import io.nekohasekai.libbox.ConnectionEvents
import io.nekohasekai.libbox.Libbox
import io.nekohasekai.libbox.LogIterator
import io.nekohasekai.libbox.OutboundGroupItemIterator
import io.nekohasekai.libbox.OutboundGroupIterator
import io.nekohasekai.libbox.StatusMessage
import io.nekohasekai.libbox.StringIterator
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeoutOrNull
import kotlin.coroutines.coroutineContext

/**
 * A libbox command-client subscription (one `Libbox.Command*`) that keeps
 * itself connected: it waits while the service is stopped, retries every
 * second while the command server is unreachable and reconnects after the
 * service restarts (contract: "Event channels"). Callbacks of stale
 * connections are dropped. Callbacks run on Go threads.
 */
internal abstract class CommandSession(
    private val command: Int,
    /** Reconnect after every successful reload (for streams bound to a box instance). */
    private val reconnectOnReload: Boolean = false,
) {
    private val lock = Any()
    private var job: Job? = null
    private var client: CommandClient? = null
    private var epoch = 0L
    private val signal = Channel<Unit>(Channel.CONFLATED)
    private val stateListener = ServiceState.Listener { signal.trySend(Unit) }

    fun start(scope: CoroutineScope) {
        synchronized(lock) {
            if (job != null) return
            ServiceState.addListener(stateListener)
            job = scope.launch(Dispatchers.IO) { run() }
        }
    }

    fun stop() {
        val current: CommandClient?
        synchronized(lock) {
            ServiceState.removeListener(stateListener)
            job?.cancel()
            job = null
            epoch++
            current = client
            client = null
        }
        if (current != null) {
            Thread({ runCatching { current.disconnect() } }, "sing-box-disconnect").start()
        }
    }

    // Callbacks for subclasses (Go threads, only for the active connection).
    protected open fun onConnected() {}
    protected open fun onDisconnected() {}
    protected open fun onStatus(message: StatusMessage) {}
    protected open fun onLogs(messages: LogIterator) {}
    protected open fun onClearLogs() {}
    protected open fun onDefaultLogLevel(level: Int) {}
    protected open fun onGroups(groups: OutboundGroupIterator) {}
    protected open fun onOutbounds(outbounds: OutboundGroupItemIterator) {}
    protected open fun onInitializeClashMode(modes: List<String>, current: String) {}
    protected open fun onClashMode(mode: String) {}
    protected open fun onConnectionEvents(events: ConnectionEvents) {}

    private suspend fun run() {
        while (coroutineContext.isActive) {
            val state = ServiceState.current
            if (!LibboxRuntime.isSetup || state.status == ServiceStatus.Stopped) {
                withTimeoutOrNull(RETRY_MS) { signal.receive() }
                continue
            }
            val disconnected = Channel<Unit>(Channel.CONFLATED)
            val myEpoch: Long
            val newClient: CommandClient
            synchronized(lock) {
                if (job == null) return
                myEpoch = ++epoch
                val options = CommandClientOptions().apply {
                    addCommand(command)
                    statusInterval = STATUS_INTERVAL_NS
                }
                newClient = Libbox.newCommandClient(Handler(myEpoch, disconnected), options)
                client = newClient
            }
            val connected = try {
                newClient.connect()
                true
            } catch (e: Exception) {
                Log.v(TAG, "command $command: connect failed: ${e.message}")
                false
            }
            if (connected) {
                val generation = ServiceState.current.generation
                while (coroutineContext.isActive && isActive(myEpoch)) {
                    val now = ServiceState.current
                    if (now.status == ServiceStatus.Stopped) break
                    if (reconnectOnReload && now.generation != generation) break
                    if (disconnected.tryReceive().isSuccess) break
                    withTimeoutOrNull(RETRY_MS) { signal.receive() }
                    if (disconnected.tryReceive().isSuccess) break
                }
            }
            val stale: Boolean
            synchronized(lock) {
                stale = myEpoch != epoch
                if (!stale) {
                    epoch++
                    client = null
                }
            }
            runCatching { newClient.disconnect() }
            if (!stale && connected) onDisconnected()
            if (!coroutineContext.isActive) return
            delay(RETRY_MS)
        }
    }

    private fun isActive(epoch: Long): Boolean = synchronized(lock) { this.epoch == epoch && job != null }

    private inner class Handler(
        private val epoch: Long,
        private val disconnected: Channel<Unit>,
    ) : CoreCommandClientHandler() {
        private inline fun ifActive(block: () -> Unit) {
            if (isActive(epoch)) runCatching(block).onFailure { Log.w(TAG, "command $command handler", it) }
        }

        override fun connected() = ifActive { onConnected() }

        override fun disconnected(message: String?) {
            if (!isActive(epoch)) return
            Log.v(TAG, "command $command: disconnected: $message")
            disconnected.trySend(Unit)
            signal.trySend(Unit)
        }

        override fun writeStatus(message: StatusMessage?) = ifActive { if (message != null) onStatus(message) }

        override fun writeLogs(messageList: LogIterator?) = ifActive { if (messageList != null) onLogs(messageList) }

        override fun clearLogs() = ifActive { onClearLogs() }

        override fun setDefaultLogLevel(level: Int) = ifActive { onDefaultLogLevel(level) }

        override fun writeGroups(message: OutboundGroupIterator?) = ifActive { if (message != null) onGroups(message) }

        override fun writeOutbounds(message: OutboundGroupItemIterator?) =
            ifActive { if (message != null) onOutbounds(message) }

        override fun initializeClashMode(modeList: StringIterator?, currentMode: String?) =
            ifActive { onInitializeClashMode(modeList.toList(), currentMode ?: "") }

        override fun updateClashMode(newMode: String?) = ifActive { onClashMode(newMode ?: "") }

        override fun writeConnectionEvents(events: ConnectionEvents?) =
            ifActive { if (events != null) onConnectionEvents(events) }
    }

    companion object {
        private const val TAG = "sing_box"
        const val RETRY_MS = 1000L
        const val STATUS_INTERVAL_NS = 1_000_000_000L
    }
}
