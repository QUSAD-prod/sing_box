import Flutter
import Foundation
import Libbox
#if SWIFT_PACKAGE
    import SingBoxShared
#endif

/// Event channel backed by a libbox command client subscription (`stats`,
/// `logs`, `groups`, `outbounds`, `clash_mode`, `connections`).
///
/// While the tunnel is not running it retries every second and it reconnects
/// after the service restarts. It never reports "not running" errors. All
/// state is confined to the main thread.
final class CommandStreamHandler: NSObject, FlutterStreamHandler {
    enum Kind {
        case stats, logs, groups, outbounds, clashMode, connections

        var command: Int32 {
            switch self {
            case .stats: return LibboxCommandStatus
            case .logs: return LibboxCommandLog
            case .groups: return LibboxCommandGroup
            case .outbounds: return LibboxCommandOutbounds
            case .clashMode: return LibboxCommandClashMode
            case .connections: return LibboxCommandConnections
            }
        }
    }

    private let kind: Kind
    private let isServiceActive: () -> Bool
    private let connectQueue: DispatchQueue
    private var sink: FlutterEventSink?
    private var client: LibboxCommandClient?
    private var generation: UInt64 = 0
    private var connecting = false
    private var connected = false
    private var retryWork: DispatchWorkItem?

    // clash mode
    private var clashModes: [String] = []
    // connections
    private var connectionStore: LibboxConnections?
    private var lastConnectionsEmit: Date = .distantPast
    private var pendingConnectionsEmit: DispatchWorkItem?

    init(kind: Kind, isServiceActive: @escaping () -> Bool) {
        self.kind = kind
        self.isServiceActive = isServiceActive
        connectQueue = DispatchQueue(label: "sing_box.command.\(kind)")
    }

    // MARK: FlutterStreamHandler

    func onListen(withArguments _: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        sink = events
        teardown()
        attemptConnect()
        return nil
    }

    func onCancel(withArguments _: Any?) -> FlutterError? {
        sink = nil
        teardown()
        return nil
    }

    // MARK: Service state

    /// The tunnel status changed: connect right away instead of waiting for
    /// the next retry.
    func serviceStateChanged() {
        guard sink != nil, !connected, !connecting else { return }
        attemptConnect()
    }

    /// The service (re)started: subscriptions that do not notice a restart
    /// (the clash mode list is only sent on subscribe) are renewed.
    func serviceRestarted() {
        guard sink != nil else { return }
        if kind == .clashMode || !connected {
            teardown()
            attemptConnect()
        }
    }

    // MARK: Connection

    private func teardown() {
        generation &+= 1
        retryWork?.cancel()
        retryWork = nil
        pendingConnectionsEmit?.cancel()
        pendingConnectionsEmit = nil
        connecting = false
        connected = false
        connectionStore = nil
        if let client {
            self.client = nil
            connectQueue.async {
                try? client.disconnect()
            }
        }
    }

    private func scheduleRetry() {
        retryWork?.cancel()
        guard sink != nil else { return }
        let work = DispatchWorkItem { [weak self] in
            self?.retryWork = nil
            self?.attemptConnect()
        }
        retryWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: work)
    }

    private func attemptConnect() {
        guard sink != nil, !connecting, !connected else { return }
        retryWork?.cancel()
        retryWork = nil
        guard isServiceActive() else {
            scheduleRetry()
            return
        }
        connecting = true
        let token = generation
        let options = LibboxCommandClientOptions()
        options.addCommand(kind.command)
        options.statusInterval = Int64(NSEC_PER_SEC)
        guard let client = LibboxNewCommandClient(ClientHandler(self, token: token), options) else {
            connecting = false
            scheduleRetry()
            return
        }
        self.client = client
        connectQueue.async { [weak self] in
            var failure: Error?
            do {
                try client.connect()
            } catch {
                failure = error
            }
            DispatchQueue.main.async {
                guard let self, token == self.generation else {
                    if failure == nil {
                        try? client.disconnect()
                    }
                    return
                }
                self.connecting = false
                if failure != nil {
                    self.connected = false
                    self.client = nil
                    self.scheduleRetry()
                }
            }
        }
    }

    fileprivate func handle(token: UInt64, _ block: @escaping (CommandStreamHandler) -> Void) {
        DispatchQueue.main.async { [weak self] in
            guard let self, token == self.generation, self.sink != nil else { return }
            block(self)
        }
    }

    fileprivate func onConnected() {
        connected = true
        clashModes = []
        connectionStore = nil
    }

    fileprivate func onDisconnected() {
        connected = false
        connecting = false
        let client = client
        self.client = nil
        generation &+= 1
        if let client {
            connectQueue.async {
                try? client.disconnect()
            }
        }
        scheduleRetry()
    }

    fileprivate func send(_ event: Any) {
        sink?(event)
    }

    // MARK: Connections throttling

    fileprivate func apply(_ events: LibboxConnectionEvents) {
        let store = connectionStore ?? LibboxNewConnections()
        connectionStore = store
        store?.apply(events)
        scheduleConnectionsEmit()
    }

    private func scheduleConnectionsEmit() {
        guard pendingConnectionsEmit == nil else { return }
        let elapsed = Date().timeIntervalSince(lastConnectionsEmit)
        if elapsed >= 1 {
            emitConnections()
            return
        }
        let work = DispatchWorkItem { [weak self] in
            self?.pendingConnectionsEmit = nil
            self?.emitConnections()
        }
        pendingConnectionsEmit = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (1 - elapsed), execute: work)
    }

    private func emitConnections() {
        guard let store = connectionStore else { return }
        lastConnectionsEmit = Date()
        send(LibboxConverters.connections(store))
    }

    // MARK: Clash mode

    fileprivate func initializeClashMode(_ modes: [String], current: String) {
        clashModes = modes
        send(["modes": modes, "current": current])
    }

    fileprivate func updateClashMode(_ mode: String) {
        send(["modes": clashModes, "current": mode])
    }
}

/// Receives libbox callbacks on Go threads and forwards them to the main
/// thread. Payloads are converted before hopping threads because libbox
/// iterators must not be shared.
private final class ClientHandler: CoreCommandClientHandler, LibboxCommandClientHandlerProtocol {
    private weak var owner: CommandStreamHandler?
    private let token: UInt64

    init(_ owner: CommandStreamHandler, token: UInt64) {
        self.owner = owner
        self.token = token
    }

    private func dispatch(_ block: @escaping (CommandStreamHandler) -> Void) {
        owner?.handle(token: token, block)
    }

    func connected() {
        dispatch { $0.onConnected() }
    }

    func disconnected(_: String?) {
        dispatch { $0.onDisconnected() }
    }

    func clearLogs() {
        dispatch { $0.send(["type": "clear"]) }
    }

    func setDefaultLogLevel(_ level: Int32) {
        dispatch { $0.send(["type": "defaultLevel", "level": Int(level)]) }
    }

    func writeLogs(_ messageList: LibboxLogIteratorProtocol?) {
        guard let messageList else { return }
        let entries = LibboxConverters.logs(messageList)
        dispatch { $0.send(["type": "logs", "reset": false, "entries": entries]) }
    }

    func writeStatus(_ message: LibboxStatusMessage?) {
        guard let message else { return }
        let payload = LibboxConverters.status(message)
        dispatch { $0.send(payload) }
    }

    func writeGroups(_ message: LibboxOutboundGroupIteratorProtocol?) {
        guard let message else { return }
        let groups = LibboxConverters.groups(message)
        dispatch { $0.send(groups) }
    }

    func writeOutbounds(_ message: LibboxOutboundGroupItemIteratorProtocol?) {
        guard let message else { return }
        let outbounds = LibboxConverters.outbounds(message)
        dispatch { $0.send(outbounds) }
    }

    func initializeClashMode(_ modeList: LibboxStringIteratorProtocol?, currentMode: String?) {
        let modes = modeList?.toArray() ?? []
        let current = currentMode ?? ""
        dispatch { $0.initializeClashMode(modes, current: current) }
    }

    func updateClashMode(_ newMode: String?) {
        let mode = newMode ?? ""
        dispatch { $0.updateClashMode(mode) }
    }

    func write(_ events: LibboxConnectionEvents?) {
        guard let events else { return }
        dispatch { $0.apply(events) }
    }
}
