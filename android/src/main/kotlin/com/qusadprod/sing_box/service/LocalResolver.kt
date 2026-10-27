/*
 * Adapted from sing-box-for-android (SFA) bg/LocalResolver.kt (GPL-3.0-or-later).
 */
package com.qusadprod.sing_box.service

import android.net.DnsResolver
import android.os.Build
import android.os.CancellationSignal
import android.system.ErrnoException
import androidx.annotation.RequiresApi
import io.nekohasekai.libbox.ExchangeContext
import io.nekohasekai.libbox.LocalDNSTransport
import java.net.InetAddress
import java.net.UnknownHostException
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicReference

/**
 * `local` DNS transport of the core: resolves through the underlying default
 * network (bypassing the tunnel) with `DnsResolver` on Android 10+.
 */
internal object LocalResolver : LocalDNSTransport {
    private const val RCODE_NXDOMAIN = 3
    private val executor = Executors.newCachedThreadPool { runnable ->
        Thread(runnable, "sing-box-dns").apply { isDaemon = true }
    }

    override fun raw(): Boolean = Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q

    @RequiresApi(Build.VERSION_CODES.Q)
    override fun exchange(ctx: ExchangeContext, message: ByteArray) {
        val network = DefaultNetworkMonitor.defaultNetwork ?: error("missing default interface")
        val waiter = Waiter()
        val signal = CancellationSignal()
        ctx.onCancel {
            signal.cancel()
            waiter.fail(java.util.concurrent.CancellationException("dns query cancelled"))
        }
        DnsResolver.getInstance().rawQuery(
            network,
            message,
            DnsResolver.FLAG_NO_RETRY,
            executor,
            signal,
            object : DnsResolver.Callback<ByteArray> {
                override fun onAnswer(answer: ByteArray, rcode: Int) {
                    if (rcode == 0) ctx.rawSuccess(answer) else ctx.errorCode(rcode)
                    waiter.done()
                }

                override fun onError(error: DnsResolver.DnsException) {
                    val cause = error.cause
                    if (cause is ErrnoException) {
                        ctx.errnoCode(cause.errno)
                        waiter.done()
                    } else {
                        waiter.fail(error)
                    }
                }
            },
        )
        waiter.await()
    }

    override fun lookup(ctx: ExchangeContext, network: String, domain: String) {
        val defaultNetwork = DefaultNetworkMonitor.defaultNetwork ?: error("missing default interface")
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            val answer = try {
                defaultNetwork.getAllByName(domain)
            } catch (_: UnknownHostException) {
                ctx.errorCode(RCODE_NXDOMAIN)
                return
            }
            ctx.success(answer.mapNotNull { it.hostAddress }.joinToString("\n"))
            return
        }
        val waiter = Waiter()
        val signal = CancellationSignal()
        ctx.onCancel {
            signal.cancel()
            waiter.fail(java.util.concurrent.CancellationException("dns query cancelled"))
        }
        val callback = object : DnsResolver.Callback<List<InetAddress>> {
            override fun onAnswer(answer: List<InetAddress>, rcode: Int) {
                if (rcode == 0) {
                    ctx.success(answer.mapNotNull { it.hostAddress }.joinToString("\n"))
                } else {
                    ctx.errorCode(rcode)
                }
                waiter.done()
            }

            override fun onError(error: DnsResolver.DnsException) {
                val cause = error.cause
                if (cause is ErrnoException) {
                    ctx.errnoCode(cause.errno)
                    waiter.done()
                } else {
                    waiter.fail(error)
                }
            }
        }
        val type = when {
            network.endsWith("4") -> DnsResolver.TYPE_A
            network.endsWith("6") -> DnsResolver.TYPE_AAAA
            else -> null
        }
        val resolver = DnsResolver.getInstance()
        if (type != null) {
            resolver.query(defaultNetwork, domain, type, DnsResolver.FLAG_NO_RETRY, executor, signal, callback)
        } else {
            resolver.query(defaultNetwork, domain, DnsResolver.FLAG_NO_RETRY, executor, signal, callback)
        }
        waiter.await()
    }

    private class Waiter {
        private val latch = CountDownLatch(1)
        private val failure = AtomicReference<Throwable?>(null)

        fun done() = latch.countDown()

        fun fail(error: Throwable) {
            failure.compareAndSet(null, error)
            latch.countDown()
        }

        fun await() {
            latch.await()
            failure.get()?.let { throw it }
        }
    }
}
