import Foundation
import Libbox
#if SWIFT_PACKAGE
    import SingBoxShared
#endif

/// Conversions of libbox objects into platform channel payloads
/// (`doc/platform_channel.md`).
enum LibboxConverters {
    static func status(_ message: LibboxStatusMessage) -> [String: Any] {
        [
            "uplink": message.uplink,
            "downlink": message.downlink,
            "uplinkTotal": message.uplinkTotal,
            "downlinkTotal": message.downlinkTotal,
            "connectionsIn": Int(message.connectionsIn),
            "connectionsOut": Int(message.connectionsOut),
            "memory": message.memory,
            "goroutines": Int(message.goroutines),
            "trafficAvailable": message.trafficAvailable,
        ]
    }

    static func groupItem(_ item: LibboxOutboundGroupItem) -> [String: Any] {
        [
            "tag": item.tag,
            "type": item.type,
            "urlTestTime": item.urlTestTime,
            "urlTestDelay": Int(item.urlTestDelay),
        ]
    }

    static func groups(_ iterator: LibboxOutboundGroupIteratorProtocol) -> [[String: Any]] {
        var groups: [[String: Any]] = []
        while iterator.hasNext() {
            guard let group = iterator.next() else { continue }
            var items: [[String: Any]] = []
            if let itemIterator = group.getItems() {
                while itemIterator.hasNext() {
                    if let item = itemIterator.next() {
                        items.append(groupItem(item))
                    }
                }
            }
            groups.append([
                "tag": group.tag,
                "type": group.type,
                "selectable": group.selectable,
                "selected": group.selected,
                "isExpand": group.isExpand,
                "items": items,
            ])
        }
        return groups
    }

    static func outbounds(_ iterator: LibboxOutboundGroupItemIteratorProtocol) -> [[String: Any]] {
        var items: [[String: Any]] = []
        while iterator.hasNext() {
            if let item = iterator.next() {
                items.append(groupItem(item))
            }
        }
        return items
    }

    static func logs(_ iterator: LibboxLogIteratorProtocol) -> [[String: Any]] {
        var entries: [[String: Any]] = []
        while iterator.hasNext() {
            if let entry = iterator.next() {
                entries.append(["level": Int(entry.level), "message": entry.message])
            }
        }
        return entries
    }

    static func connection(_ connection: LibboxConnection) -> [String: Any] {
        var processName = ""
        if let info = connection.processInfo {
            processName = info.processPath
            if processName.isEmpty, let names = info.packageNames()?.toArray(), let first = names.first {
                processName = first
            }
        }
        return [
            "id": connection.id_,
            "inbound": connection.inbound,
            "inboundType": connection.inboundType,
            "ipVersion": Int(connection.ipVersion),
            "network": connection.network,
            "source": connection.source,
            "destination": connection.destination,
            "domain": connection.domain,
            "protocol": connection.protocol,
            "user": connection.user,
            "fromOutbound": connection.fromOutbound,
            "createdAt": connection.createdAt,
            "closedAt": connection.closedAt,
            "uplink": connection.uplink,
            "downlink": connection.downlink,
            "uplinkTotal": connection.uplinkTotal,
            "downlinkTotal": connection.downlinkTotal,
            "rule": connection.rule,
            "outbound": connection.outbound,
            "outboundType": connection.outboundType,
            "chain": connection.chain()?.toArray() ?? [],
            "processName": processName,
        ]
    }

    /// Snapshot of all connections (active and recently closed), newest first.
    static func connections(_ store: LibboxConnections) -> [[String: Any]] {
        store.filterState(Int32(LibboxConnectionStateAll))
        store.sortByDate()
        var result: [[String: Any]] = []
        if let iterator = store.iterator() {
            while iterator.hasNext() {
                if let item = iterator.next() {
                    result.append(connection(item))
                }
            }
        }
        return result
    }

    static func networkQualityProgress(_ progress: LibboxNetworkQualityProgress) -> [String: Any] {
        [
            "type": "progress",
            "phase": Int(progress.phase),
            "downloadCapacity": progress.downloadCapacity,
            "uploadCapacity": progress.uploadCapacity,
            "downloadRPM": Int(progress.downloadRPM),
            "uploadRPM": Int(progress.uploadRPM),
            "idleLatencyMs": Int(progress.idleLatencyMs),
            "elapsedMs": progress.elapsedMs,
            "downloadCapacityAccuracy": Int(progress.downloadCapacityAccuracy),
            "uploadCapacityAccuracy": Int(progress.uploadCapacityAccuracy),
            "downloadRPMAccuracy": Int(progress.downloadRPMAccuracy),
            "uploadRPMAccuracy": Int(progress.uploadRPMAccuracy),
        ]
    }

    static func networkQualityResult(_ result: LibboxNetworkQualityResult) -> [String: Any] {
        [
            "type": "result",
            "downloadCapacity": result.downloadCapacity,
            "uploadCapacity": result.uploadCapacity,
            "downloadRPM": Int(result.downloadRPM),
            "uploadRPM": Int(result.uploadRPM),
            "idleLatencyMs": Int(result.idleLatencyMs),
            "downloadCapacityAccuracy": Int(result.downloadCapacityAccuracy),
            "uploadCapacityAccuracy": Int(result.uploadCapacityAccuracy),
            "downloadRPMAccuracy": Int(result.downloadRPMAccuracy),
            "uploadRPMAccuracy": Int(result.uploadRPMAccuracy),
        ]
    }

    static func stunProgress(_ progress: LibboxSTUNTestProgress) -> [String: Any] {
        [
            "type": "progress",
            "phase": Int(progress.phase),
            "externalAddr": progress.externalAddr,
            "latencyMs": Int(progress.latencyMs),
            "natMapping": Int(progress.natMapping),
            "natFiltering": Int(progress.natFiltering),
        ]
    }

    static func stunResult(_ result: LibboxSTUNTestResult) -> [String: Any] {
        [
            "type": "result",
            "externalAddr": result.externalAddr,
            "latencyMs": Int(result.latencyMs),
            "natMapping": Int(result.natMapping),
            "natFiltering": Int(result.natFiltering),
            "natTypeSupported": result.natTypeSupported,
        ]
    }
}
