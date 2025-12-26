package com.qusadprod.sing_box.ktx

import android.content.Context
import android.content.pm.PackageManager
import androidx.core.content.ContextCompat

/**
 * Проверка наличия разрешения
 * Скопировано и адаптировано из sing-box-for-android
 */
fun Context.hasPermission(permission: String): Boolean {
    return ContextCompat.checkSelfPermission(this, permission) == PackageManager.PERMISSION_GRANTED
}

