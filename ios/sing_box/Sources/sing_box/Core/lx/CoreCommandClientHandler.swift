import Foundation
import Libbox

/// The `LibboxCommandClientHandlerProtocol` members that only the
/// sing-box-lx libbox has (see `Core/standard` for the standard core).
class CoreCommandClientHandler: NSObject {
    /// DNS-query events of the multiplexed CommandDNS; no stream subscribes
    /// to them yet.
    @objc func writeDNSQuery(_: LibboxDnsQuery?) {}
}
