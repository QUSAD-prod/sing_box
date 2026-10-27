package com.qusadprod.sing_box.core

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import io.nekohasekai.libbox.StringIterator

/** Java iterator adapter for libbox `StringIterator` arguments. */
internal class StringArray(private val values: List<String>) : StringIterator {
    private var index = 0

    override fun len(): Int = values.size

    override fun hasNext(): Boolean = index < values.size

    override fun next(): String = values[index++]
}

internal fun StringIterator?.toList(): List<String> {
    if (this == null) return emptyList()
    val result = mutableListOf<String>()
    while (hasNext()) result.add(next())
    return result
}

internal object Text {
    private val ansi = Regex("\u001B\\[[0-9;?]*[ -/]*[@-~]")

    /** libbox colours log lines on Android only; strip ANSI escapes for parity with iOS. */
    fun stripAnsi(value: String): String = if (value.indexOf('\u001B') < 0) value else ansi.replace(value, "")
}

internal object AppInfo {
    fun label(context: Context): String = runCatching {
        context.applicationInfo.loadLabel(context.packageManager).toString()
    }.getOrNull()?.takeIf { it.isNotBlank() } ?: context.packageName

    /**
     * Resolves a drawable (or mipmap) resource name of the host app; falls back
     * to the application icon.
     */
    fun iconResource(context: Context, name: String?): Int {
        if (!name.isNullOrBlank()) {
            val res = context.resources
            for (type in arrayOf("drawable", "mipmap")) {
                val id = res.getIdentifier(name, type, context.packageName)
                if (id != 0) return id
            }
        }
        val appIcon = context.applicationInfo.icon
        return if (appIcon != 0) appIcon else android.R.drawable.ic_lock_lock
    }

    fun launchIntent(context: Context): Intent? =
        context.packageManager.getLaunchIntentForPackage(context.packageName)?.apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT)
        }

    val immutableFlag: Int = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0

    fun launchPendingIntent(context: Context, requestCode: Int = 0): PendingIntent? {
        val intent = launchIntent(context) ?: return null
        return PendingIntent.getActivity(
            context,
            requestCode,
            intent,
            immutableFlag or PendingIntent.FLAG_UPDATE_CURRENT,
        )
    }
}
