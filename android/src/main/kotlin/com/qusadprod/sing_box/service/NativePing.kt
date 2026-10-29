package com.qusadprod.sing_box.service

import android.os.ParcelFileDescriptor
import android.os.SystemClock
import android.system.ErrnoException
import android.system.Os
import android.system.OsConstants
import android.system.StructPollfd
import com.qusadprod.sing_box.core.SingBoxError
import java.io.FileDescriptor
import java.io.IOException
import java.net.Inet4Address
import java.net.Inet6Address
import java.net.InetAddress
import java.net.SocketTimeoutException

/**
 * TCP handshake and ICMP echo latency outside the tunnel (`pingServer`): while
 * the VPN runs the host is resolved by the underlying network (the system
 * resolver would answer through the tunnel, e.g. with FakeIP addresses) and
 * the sockets are protected from the VPN. Blocking: call off the main thread.
 */
internal object NativePing {
    /** Measures [host]; failures are reported in the result, see the contract. */
    fun ping(method: String, host: String, port: Int?, timeoutMs: Int): Map<String, Any?> {
        if (method != "tcp" && method != "icmp") {
            throw SingBoxError.invalidArgument("Unknown ping method \"$method\"")
        }
        if (method == "tcp" && (port == null || port !in 1..65535)) {
            throw SingBoxError.invalidArgument("Missing or invalid argument \"port\"")
        }
        val deadline = SystemClock.elapsedRealtime() + timeoutMs.coerceAtLeast(1)
        val remaining = { (deadline - SystemClock.elapsedRealtime()).coerceIn(1, Int.MAX_VALUE.toLong()).toInt() }
        val address = try {
            resolve(host)
        } catch (e: Exception) {
            return failure("Cannot resolve $host: ${describe(e)}", null)
        }
        return try {
            val milliseconds = if (method == "tcp") tcp(address, port!!, remaining) else icmp(address, remaining)
            mapOf("success" to true, "ping" to milliseconds, "address" to address.hostAddress)
        } catch (e: Exception) {
            failure(describe(e), address)
        }
    }

    private fun resolve(host: String): InetAddress {
        val all = if (SingBoxVpnService.instance != null) {
            val network = DefaultNetworkMonitor.defaultNetwork
                ?: throw IOException("no underlying network")
            network.getAllByName(host)
        } else {
            InetAddress.getAllByName(host)
        }
        return all.firstOrNull { it is Inet4Address } ?: all.firstOrNull() ?: throw IOException("no address")
    }

    private fun tcp(address: InetAddress, port: Int, remaining: () -> Int): Long {
        val fd = Os.socket(family(address), OsConstants.SOCK_STREAM, OsConstants.IPPROTO_TCP)
        try {
            protect(fd)
            Os.fcntlInt(fd, OsConstants.F_SETFL, OsConstants.O_NONBLOCK)
            val start = SystemClock.elapsedRealtimeNanos()
            try {
                Os.connect(fd, address, port)
            } catch (e: ErrnoException) {
                if (e.errno != OsConstants.EINPROGRESS) throw e
                if (!poll(fd, OsConstants.POLLOUT, remaining())) throw SocketTimeoutException("Timed out")
                try {
                    Os.getpeername(fd)
                } catch (notConnected: ErrnoException) {
                    // A read reports the pending error of the failed connect (SO_ERROR).
                    Os.read(fd, ByteArray(1), 0, 1)
                    throw notConnected
                }
            }
            return elapsedMillis(start)
        } finally {
            Os.close(fd)
        }
    }

    /** One echo request over an unprivileged ICMP datagram ("ping") socket. */
    private fun icmp(address: InetAddress, remaining: () -> Int): Long {
        val v6 = address is Inet6Address
        val fd = try {
            Os.socket(family(address), OsConstants.SOCK_DGRAM, if (v6) OsConstants.IPPROTO_ICMPV6 else OsConstants.IPPROTO_ICMP)
        } catch (e: ErrnoException) {
            throw IOException("ICMP is not available: ${describe(e)}")
        }
        try {
            protect(fd)
            // Type, code, checksum, identifier, sequence and some payload; the kernel
            // fills in the identifier and the checksum of ping sockets.
            val request = ByteArray(16)
            request[0] = (if (v6) ECHO_REQUEST_V6 else ECHO_REQUEST_V4).toByte()
            request[7] = 1
            val start = SystemClock.elapsedRealtimeNanos()
            Os.sendto(fd, request, 0, request.size, 0, address, 0)
            val reply = ByteArray(1500)
            while (true) {
                if (!poll(fd, OsConstants.POLLIN, remaining())) throw SocketTimeoutException("No ICMP reply")
                val read = Os.recvfrom(fd, reply, 0, reply.size, 0, null)
                if (read >= 8 && reply[0].toInt() and 0xff == if (v6) ECHO_REPLY_V6 else ECHO_REPLY_V4) {
                    return elapsedMillis(start)
                }
            }
        } finally {
            Os.close(fd)
        }
    }

    private fun family(address: InetAddress) =
        if (address is Inet6Address) OsConstants.AF_INET6 else OsConstants.AF_INET

    /** Keeps the socket out of the tunnel while the VPN runs. */
    private fun protect(fd: FileDescriptor) {
        val vpn = SingBoxVpnService.instance ?: return
        // protect() takes an int descriptor; a duplicate refers to the same socket.
        ParcelFileDescriptor.dup(fd).use { duplicate ->
            if (!vpn.protect(duplicate.fd)) throw IOException("cannot bypass the VPN")
        }
    }

    private fun poll(fd: FileDescriptor, events: Int, timeoutMs: Int): Boolean {
        val request = StructPollfd().apply {
            this.fd = fd
            this.events = events.toShort()
        }
        return Os.poll(arrayOf(request), timeoutMs) > 0
    }

    private fun elapsedMillis(startNanos: Long) = (SystemClock.elapsedRealtimeNanos() - startNanos) / 1_000_000

    private fun failure(error: String, address: InetAddress?): Map<String, Any?> =
        mapOf("success" to false, "error" to error, "address" to address?.hostAddress)

    private fun describe(e: Exception): String = when (e) {
        is ErrnoException -> Os.strerror(e.errno)
        is SocketTimeoutException -> e.message ?: "Timed out"
        else -> e.message ?: e.javaClass.simpleName
    }

    private const val ECHO_REQUEST_V4 = 8
    private const val ECHO_REPLY_V4 = 0
    private const val ECHO_REQUEST_V6 = 128
    private const val ECHO_REPLY_V6 = 129
}
