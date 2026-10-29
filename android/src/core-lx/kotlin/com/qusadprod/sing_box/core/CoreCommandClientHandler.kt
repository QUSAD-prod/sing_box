package com.qusadprod.sing_box.core

import io.nekohasekai.libbox.CommandClientHandler
import io.nekohasekai.libbox.DnsQuery

/**
 * The [CommandClientHandler] members that only the sing-box-lx libbox has (see
 * `src/core-standard` for the standard core).
 */
internal abstract class CoreCommandClientHandler : CommandClientHandler {
    // DNS-query events of the multiplexed CommandDNS; no session subscribes to them yet.
    override fun writeDNSQuery(query: DnsQuery?) {}
}
