import Foundation
import Libbox
import Network

/// libbox default interface monitor backed by `NWPathMonitor`, shared by the
/// platform interfaces of the extension and of the app's probe core. Ported
/// from sing-box-for-apple (`ExtensionPlatformInterface`).
public final class SingBoxInterfaceMonitor {
    private let queue = DispatchQueue(label: "sing_box.path-monitor")
    private let lock = NSLock()
    private var monitor: NWPathMonitor?
    private var lastNetworkPath: String?

    public init() {}

    /// Starts monitoring and reports the default interface to `listener`;
    /// returns after the first update (libbox expects the first default
    /// interface before `startDefaultInterfaceMonitor` returns).
    public func start(_ listener: LibboxInterfaceUpdateListenerProtocol) {
        let monitor = NWPathMonitor()
        lock.lock()
        self.monitor?.cancel()
        self.monitor = monitor
        lastNetworkPath = nil
        lock.unlock()
        let semaphore = DispatchSemaphore(value: 0)
        var signaled = false
        monitor.pathUpdateHandler = { [weak self] path in
            self?.onPathUpdate(listener, path)
            if !signaled {
                signaled = true
                semaphore.signal()
            }
        }
        monitor.start(queue: queue)
        _ = semaphore.wait(timeout: .now() + 5)
    }

    /// Stops monitoring.
    public func close() {
        lock.lock()
        defer { lock.unlock() }
        monitor?.cancel()
        monitor = nil
        lastNetworkPath = nil
    }

    /// Index of the default (physical) interface, 0 when unknown or not
    /// monitoring.
    public var defaultInterfaceIndex: UInt32 {
        lock.lock()
        let monitor = monitor
        lock.unlock()
        guard let path = monitor?.currentPath, path.status != .unsatisfied else {
            return 0
        }
        return path.availableInterfaces.first.map { UInt32($0.index) } ?? 0
    }

    /// The available interfaces for libbox's `getInterfaces`.
    public func interfaces() throws -> LibboxNetworkInterfaceIteratorProtocol {
        lock.lock()
        let monitor = monitor
        lock.unlock()
        guard let monitor else {
            throw SingBoxError("path monitor not started")
        }
        let path = monitor.currentPath
        if path.status == .unsatisfied {
            return NetworkInterfaceIterator([])
        }
        var interfaces: [LibboxNetworkInterface] = []
        for item in path.availableInterfaces {
            let interface = LibboxNetworkInterface()
            interface.name = item.name
            interface.index = Int32(item.index)
            switch item.type {
            case .wifi:
                interface.type = LibboxInterfaceTypeWIFI
            case .cellular:
                interface.type = LibboxInterfaceTypeCellular
            case .wiredEthernet:
                interface.type = LibboxInterfaceTypeEthernet
            default:
                interface.type = LibboxInterfaceTypeOther
            }
            interfaces.append(interface)
        }
        return NetworkInterfaceIterator(interfaces)
    }

    private func onPathUpdate(_ listener: LibboxInterfaceUpdateListenerProtocol, _ path: Network.NWPath) {
        let description = describe(path)
        listener.updateNetworkPath(description)
        lock.lock()
        let unchanged = description == lastNetworkPath
        lastNetworkPath = description
        lock.unlock()
        if unchanged {
            return
        }
        guard path.status != .unsatisfied, let defaultInterface = path.availableInterfaces.first else {
            listener.updateDefaultInterface("", interfaceIndex: -1, isExpensive: false, isConstrained: false)
            return
        }
        // libbox resets connections when the default interface changes
        // (Wi-Fi <-> cellular).
        listener.updateDefaultInterface(
            defaultInterface.name,
            interfaceIndex: Int32(defaultInterface.index),
            isExpensive: path.isExpensive,
            isConstrained: path.isConstrained
        )
    }

    private func describe(_ path: Network.NWPath) -> String {
        var components: [String] = []
        switch path.status {
        case .satisfied:
            components.append("satisfied")
        case .unsatisfied:
            components.append("unsatisfied")
        case .requiresConnection:
            components.append("requiresConnection")
        @unknown default:
            components.append("unknown")
        }
        if !path.availableInterfaces.isEmpty {
            components.append("interfaces=" + path.availableInterfaces.map { "\($0.name)#\($0.index)/\($0.type)" }.joined(separator: ","))
        }
        if !path.gateways.isEmpty {
            components.append("gateways=" + path.gateways.map { "\($0)" }.sorted().joined(separator: ","))
        }
        if path.supportsIPv4 { components.append("ipv4") }
        if path.supportsIPv6 { components.append("ipv6") }
        if path.supportsDNS { components.append("dns") }
        if path.isExpensive { components.append("expensive") }
        if path.isConstrained { components.append("constrained") }
        return components.joined(separator: " ")
    }

    private final class NetworkInterfaceIterator: NSObject, LibboxNetworkInterfaceIteratorProtocol {
        private var iterator: IndexingIterator<[LibboxNetworkInterface]>
        private var current: LibboxNetworkInterface?

        init(_ array: [LibboxNetworkInterface]) {
            iterator = array.makeIterator()
        }

        func hasNext() -> Bool {
            current = iterator.next()
            return current != nil
        }

        func next() -> LibboxNetworkInterface? {
            current
        }
    }
}
