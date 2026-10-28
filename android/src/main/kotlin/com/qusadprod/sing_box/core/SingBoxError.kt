package com.qusadprod.sing_box.core

/**
 * Error codes of `doc/platform_channel.md`. Thrown inside the plugin and
 * converted into `result.error(code, message, null)` / `EventSink.error`.
 */
internal class SingBoxError(val code: String, message: String?) : Exception(message) {
    companion object {
        const val NOT_INITIALIZED = "NOT_INITIALIZED"
        const val INVALID_ARGUMENT = "INVALID_ARGUMENT"
        const val INVALID_CONFIG = "INVALID_CONFIG"
        const val PERMISSION_DENIED = "PERMISSION_DENIED"
        const val SERVICE_NOT_RUNNING = "SERVICE_NOT_RUNNING"
        const val START_FAILED = "START_FAILED"
        const val COMMAND_FAILED = "COMMAND_FAILED"
        const val UNSUPPORTED = "UNSUPPORTED"
        const val NO_ACTIVITY = "NO_ACTIVITY"
        const val INTERNAL = "INTERNAL"

        fun notInitialized() = SingBoxError(NOT_INITIALIZED, "sing_box: initialize() has not been called")

        fun invalidArgument(message: String) = SingBoxError(INVALID_ARGUMENT, message)

        fun notRunning() = SingBoxError(SERVICE_NOT_RUNNING, "sing-box service is not running")

        fun noActivity() = SingBoxError(NO_ACTIVITY, "This operation requires an attached Activity")

        fun permissionDenied() = SingBoxError(PERMISSION_DENIED, "VPN permission has not been granted")
    }
}

/** Best effort human readable message of a libbox (Go) exception. */
internal val Throwable.libboxMessage: String
    get() = message?.takeIf { it.isNotBlank() } ?: toString()
