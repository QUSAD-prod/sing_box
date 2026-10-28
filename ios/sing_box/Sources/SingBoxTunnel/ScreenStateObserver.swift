import Foundation
import Libbox
import notify

/// Forwards display on/off to libbox so it can pause timers while the screen
/// is off and wake immediately when it turns on (ported from
/// sing-box-for-apple).
final class ScreenStateObserver {
    private let queue = DispatchQueue(label: "sing_box.screen-state")
    private var token: Int32 = NOTIFY_TOKEN_INVALID

    init(commandServer: LibboxCommandServer) {
        notify_register_dispatch("com.apple.iokit.hid.displayStatus", &token, queue) { [weak commandServer] token in
            guard let commandServer else { return }
            var state: UInt64 = 0
            notify_get_state(token, &state)
            commandServer.recordScreenState(state == 1)
            if state == 1 {
                commandServer.wakeNow()
            }
        }
    }

    func cancel() {
        if token != NOTIFY_TOKEN_INVALID {
            notify_cancel(token)
            token = NOTIFY_TOKEN_INVALID
        }
    }

    deinit {
        cancel()
    }
}
