package com.qusadprod.sing_box.plugin

import com.qusadprod.sing_box.core.Text
import com.qusadprod.sing_box.core.toList
import io.nekohasekai.libbox.Connection
import io.nekohasekai.libbox.Connections
import io.nekohasekai.libbox.LogIterator
import io.nekohasekai.libbox.NetworkQualityProgress
import io.nekohasekai.libbox.NetworkQualityResult
import io.nekohasekai.libbox.OutboundGroup
import io.nekohasekai.libbox.OutboundGroupItem
import io.nekohasekai.libbox.OutboundGroupItemIterator
import io.nekohasekai.libbox.OutboundGroupIterator
import io.nekohasekai.libbox.STUNTestProgress
import io.nekohasekai.libbox.STUNTestResult
import io.nekohasekai.libbox.StatusMessage

/** Converts libbox objects into the payloads of `doc/platform_channel.md`. */
internal object Converters {
    fun status(message: StatusMessage): Map<String, Any?> = mapOf(
        "uplink" to message.uplink,
        "downlink" to message.downlink,
        "uplinkTotal" to message.uplinkTotal,
        "downlinkTotal" to message.downlinkTotal,
        "connectionsIn" to message.connectionsIn,
        "connectionsOut" to message.connectionsOut,
        "memory" to message.memory,
        "goroutines" to message.goroutines,
        "trafficAvailable" to message.trafficAvailable,
    )

    fun logEntries(messages: LogIterator): List<Map<String, Any?>> {
        val result = ArrayList<Map<String, Any?>>(messages.len().coerceAtLeast(0))
        while (messages.hasNext()) {
            val entry = messages.next() ?: continue
            result.add(mapOf("level" to entry.level, "message" to Text.stripAnsi(entry.message ?: "")))
        }
        return result
    }

    fun groups(groups: OutboundGroupIterator): List<Map<String, Any?>> {
        val result = mutableListOf<Map<String, Any?>>()
        while (groups.hasNext()) {
            val group = groups.next() ?: continue
            result.add(group(group))
        }
        return result
    }

    private fun group(group: OutboundGroup): Map<String, Any?> = mapOf(
        "tag" to group.tag,
        "type" to group.type,
        "selectable" to group.selectable,
        "selected" to group.selected,
        "isExpand" to group.isExpand,
        "items" to items(group.items),
    )

    fun items(items: OutboundGroupItemIterator?): List<Map<String, Any?>> {
        if (items == null) return emptyList()
        val result = mutableListOf<Map<String, Any?>>()
        while (items.hasNext()) {
            val item = items.next() ?: continue
            result.add(item(item))
        }
        return result
    }

    private fun item(item: OutboundGroupItem): Map<String, Any?> = mapOf(
        "tag" to item.tag,
        "type" to item.type,
        // libbox reports unix seconds; the contract uses epoch milliseconds.
        "urlTestTime" to if (item.urlTestTime > 0) item.urlTestTime * 1000 else 0L,
        "urlTestDelay" to item.urlTestDelay,
    )

    /** Snapshot of every tracked connection, newest first. */
    fun connections(connections: Connections): List<Map<String, Any?>> {
        connections.sortByDate()
        val iterator = connections.iterator()
        val result = mutableListOf<Map<String, Any?>>()
        while (iterator.hasNext()) {
            val connection = iterator.next() ?: continue
            result.add(connection(connection))
        }
        return result
    }

    private fun connection(connection: Connection): Map<String, Any?> {
        val process = connection.processInfo
        val processName = process?.let { info ->
            info.packageNames().toList().firstOrNull()?.takeIf { it.isNotBlank() }
                ?: info.processPath?.takeIf { it.isNotBlank() }
                ?: info.userName?.takeIf { it.isNotBlank() }
        }
        return mapOf(
            "id" to connection.id,
            "inbound" to connection.inbound,
            "inboundType" to connection.inboundType,
            "ipVersion" to connection.ipVersion,
            "network" to connection.network,
            "source" to connection.source,
            "destination" to connection.destination,
            "domain" to connection.domain,
            "protocol" to connection.protocol,
            "user" to connection.user,
            "fromOutbound" to connection.fromOutbound,
            "createdAt" to connection.createdAt,
            "closedAt" to connection.closedAt,
            "uplink" to connection.uplink,
            "downlink" to connection.downlink,
            "uplinkTotal" to connection.uplinkTotal,
            "downlinkTotal" to connection.downlinkTotal,
            "rule" to connection.rule,
            "outbound" to connection.outbound,
            "outboundType" to connection.outboundType,
            "chain" to connection.chain().toList(),
            "processName" to processName,
        )
    }

    fun networkQualityProgress(progress: NetworkQualityProgress): Map<String, Any?> = mapOf(
        "type" to "progress",
        "phase" to progress.phase,
        "downloadCapacity" to progress.downloadCapacity,
        "uploadCapacity" to progress.uploadCapacity,
        "downloadRPM" to progress.downloadRPM,
        "uploadRPM" to progress.uploadRPM,
        "idleLatencyMs" to progress.idleLatencyMs,
        "elapsedMs" to progress.elapsedMs,
        "downloadCapacityAccuracy" to progress.downloadCapacityAccuracy,
        "uploadCapacityAccuracy" to progress.uploadCapacityAccuracy,
        "downloadRPMAccuracy" to progress.downloadRPMAccuracy,
        "uploadRPMAccuracy" to progress.uploadRPMAccuracy,
    )

    fun networkQualityResult(result: NetworkQualityResult): Map<String, Any?> = mapOf(
        "type" to "result",
        "downloadCapacity" to result.downloadCapacity,
        "uploadCapacity" to result.uploadCapacity,
        "downloadRPM" to result.downloadRPM,
        "uploadRPM" to result.uploadRPM,
        "idleLatencyMs" to result.idleLatencyMs,
        "downloadCapacityAccuracy" to result.downloadCapacityAccuracy,
        "uploadCapacityAccuracy" to result.uploadCapacityAccuracy,
        "downloadRPMAccuracy" to result.downloadRPMAccuracy,
        "uploadRPMAccuracy" to result.uploadRPMAccuracy,
    )

    fun stunProgress(progress: STUNTestProgress): Map<String, Any?> = mapOf(
        "type" to "progress",
        "phase" to progress.phase,
        "externalAddr" to progress.externalAddr,
        "latencyMs" to progress.latencyMs,
        "natMapping" to progress.natMapping,
        "natFiltering" to progress.natFiltering,
    )

    fun stunResult(result: STUNTestResult): Map<String, Any?> = mapOf(
        "type" to "result",
        "externalAddr" to result.externalAddr,
        "latencyMs" to result.latencyMs,
        "natMapping" to result.natMapping,
        "natFiltering" to result.natFiltering,
        "natTypeSupported" to result.natTypeSupported,
    )
}
