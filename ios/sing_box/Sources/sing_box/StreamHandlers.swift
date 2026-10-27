import Flutter
import Foundation
import Libbox
import notify
import UIKit
#if SWIFT_PACKAGE
    import SingBoxShared
#endif

// MARK: - sing_box/status

final class StatusStreamHandler: NSObject, FlutterStreamHandler {
    private let controller: () -> TunnelController?
    private var listenerID: UUID?

    init(controller: @escaping () -> TunnelController?) {
        self.controller = controller
    }

    func onListen(withArguments _: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        MainActor.assumeIsolated {
            guard let controller = controller() else {
                events(TunnelState(status: "disconnected", startedAt: nil, error: nil).payload)
                return
            }
            if let listenerID {
                controller.removeListener(listenerID)
            }
            listenerID = controller.addListener { state in
                events(state.payload)
            }
        }
        return nil
    }

    func onCancel(withArguments _: Any?) -> FlutterError? {
        MainActor.assumeIsolated {
            if let listenerID {
                controller()?.removeListener(listenerID)
            }
            listenerID = nil
        }
        return nil
    }
}

// MARK: - sing_box/notifications

/// Delivers the notifications the extension queued in the app group
/// `UserDefaults` (signalled with a Darwin notification). Best effort.
final class NotificationStreamHandler: NSObject, FlutterStreamHandler {
    private let paths: () -> SingBoxPaths?
    private var sink: FlutterEventSink?
    private var token: Int32 = NOTIFY_TOKEN_INVALID
    private var foregroundObserver: NSObjectProtocol?

    init(paths: @escaping () -> SingBoxPaths?) {
        self.paths = paths
    }

    func onListen(withArguments _: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        sink = events
        stopObserving()
        if let paths = paths() {
            let name = SingBoxKeys.notificationDarwinName(appGroup: paths.appGroup)
            notify_register_dispatch(name, &token, DispatchQueue.main) { [weak self] _ in
                self?.drain()
            }
        }
        foregroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.drain()
        }
        DispatchQueue.main.async { [weak self] in
            self?.drain()
        }
        return nil
    }

    func onCancel(withArguments _: Any?) -> FlutterError? {
        sink = nil
        stopObserving()
        return nil
    }

    private func stopObserving() {
        if token != NOTIFY_TOKEN_INVALID {
            notify_cancel(token)
            token = NOTIFY_TOKEN_INVALID
        }
        if let foregroundObserver {
            NotificationCenter.default.removeObserver(foregroundObserver)
        }
        foregroundObserver = nil
    }

    private func drain() {
        guard let sink, let paths = paths() else { return }
        for payload in SingBoxNotificationQueue.drain(paths: paths) {
            sink(payload)
        }
    }
}

// MARK: - sing_box/network_quality and sing_box/stun

/// One-shot test stream: progress events, one result, end of stream.
final class OneShotTestStreamHandler: NSObject, FlutterStreamHandler {
    enum Kind {
        case networkQuality, stun
    }

    private let kind: Kind
    private let isServiceActive: () -> Bool
    private let queue: DispatchQueue
    private var sink: FlutterEventSink?
    private var generation: UInt64 = 0
    private var client: LibboxCommandClient?
    private var networkQualitySession: LibboxNetworkQualityTestSession?
    private var stunSession: LibboxSTUNTestSession?

    init(kind: Kind, isServiceActive: @escaping () -> Bool) {
        self.kind = kind
        self.isServiceActive = isServiceActive
        queue = DispatchQueue(label: "sing_box.test.\(kind)")
    }

    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        close()
        sink = events
        let token = generation
        let args = arguments as? [String: Any] ?? [:]
        guard isServiceActive() else {
            DispatchQueue.main.async { [weak self] in
                self?.finish(token: token, error: PluginError.serviceNotRunning().flutterError)
            }
            return nil
        }
        let networkQualityHandler = NetworkQualityHandler(self, token: token)
        let stunHandler = StunHandler(self, token: token)
        let kind = kind
        queue.async { [weak self] in
            guard let client = LibboxNewStandaloneCommandClient() else {
                DispatchQueue.main.async {
                    self?.finish(token: token, error: PluginError.commandFailed("cannot create command client").flutterError)
                }
                return
            }
            do {
                switch kind {
                case .networkQuality:
                    let session = try client.startNetworkQualityTest(
                        args.string("configUrl") ?? LibboxNetworkQualityDefaultConfigURL,
                        outboundTag: args.string("outboundTag") ?? "",
                        serial: args.bool("serial") ?? false,
                        maxRuntimeSeconds: Int32(args.int("maxRuntimeSeconds") ?? Int(LibboxNetworkQualityDefaultMaxRuntimeSeconds)),
                        http3: args.bool("http3") ?? false,
                        handler: networkQualityHandler
                    )
                    DispatchQueue.main.async {
                        self?.attach(token: token, client: client, networkQuality: session, stun: nil)
                    }
                case .stun:
                    let session = try client.startSTUNTest(
                        args.string("server") ?? LibboxSTUNDefaultServer,
                        outboundTag: args.string("outboundTag") ?? "",
                        handler: stunHandler
                    )
                    DispatchQueue.main.async {
                        self?.attach(token: token, client: client, networkQuality: nil, stun: session)
                    }
                }
            } catch {
                try? client.disconnect()
                DispatchQueue.main.async {
                    self?.finish(token: token, error: PluginError.commandFailed(error.localizedDescription).flutterError)
                }
            }
        }
        return nil
    }

    func onCancel(withArguments _: Any?) -> FlutterError? {
        close()
        return nil
    }

    private func attach(token: UInt64, client: LibboxCommandClient, networkQuality: LibboxNetworkQualityTestSession?, stun: LibboxSTUNTestSession?) {
        guard token == generation, sink != nil else {
            queue.async {
                try? networkQuality?.close()
                try? stun?.close()
                try? client.disconnect()
            }
            return
        }
        self.client = client
        networkQualitySession = networkQuality
        stunSession = stun
    }

    private func close() {
        generation &+= 1
        sink = nil
        let client = client
        let networkQuality = networkQualitySession
        let stun = stunSession
        self.client = nil
        networkQualitySession = nil
        stunSession = nil
        if client != nil || networkQuality != nil || stun != nil {
            queue.async {
                try? networkQuality?.close()
                try? stun?.close()
                try? client?.disconnect()
            }
        }
    }

    fileprivate func event(token: UInt64, _ payload: Any) {
        guard token == generation else { return }
        sink?(payload)
    }

    fileprivate func finish(token: UInt64, error: FlutterError?) {
        guard token == generation, let sink else { return }
        if let error {
            sink(error)
        }
        sink(FlutterEndOfEventStream)
        close()
    }

    fileprivate func finish(token: UInt64, result: Any) {
        guard token == generation, let sink else { return }
        sink(result)
        sink(FlutterEndOfEventStream)
        close()
    }
}

/// Base for the libbox test handlers: forwards to the main thread.
private class TestHandlerBase: NSObject {
    private weak var owner: OneShotTestStreamHandler?
    private let token: UInt64

    init(_ owner: OneShotTestStreamHandler, token: UInt64) {
        self.owner = owner
        self.token = token
    }

    func main(_ block: @escaping (OneShotTestStreamHandler, UInt64) -> Void) {
        let token = token
        DispatchQueue.main.async { [weak owner] in
            guard let owner else { return }
            block(owner, token)
        }
    }

    func onError(_ message: String?) {
        let error = PluginError.commandFailed(message ?? "test failed").flutterError
        main { $0.finish(token: $1, error: error) }
    }
}

private final class NetworkQualityHandler: TestHandlerBase, LibboxNetworkQualityTestHandlerProtocol {
    func onProgress(_ progress: LibboxNetworkQualityProgress?) {
        guard let progress else { return }
        let payload = LibboxConverters.networkQualityProgress(progress)
        main { $0.event(token: $1, payload) }
    }

    func onResult(_ result: LibboxNetworkQualityResult?) {
        guard let result else { return }
        let payload = LibboxConverters.networkQualityResult(result)
        main { $0.finish(token: $1, result: payload) }
    }
}

private final class StunHandler: TestHandlerBase, LibboxSTUNTestHandlerProtocol {
    func onProgress(_ progress: LibboxSTUNTestProgress?) {
        guard let progress else { return }
        let payload = LibboxConverters.stunProgress(progress)
        main { $0.event(token: $1, payload) }
    }

    func onResult(_ result: LibboxSTUNTestResult?) {
        guard let result else { return }
        let payload = LibboxConverters.stunResult(result)
        main { $0.finish(token: $1, result: payload) }
    }
}
