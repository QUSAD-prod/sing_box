package com.qusadprod.sing_box.constant

/**
 * Константы действий для sing-box сервиса
 * Скопировано и адаптировано из sing-box-for-android
 */
object Action {
    const val SERVICE = "com.qusadprod.sing_box.SERVICE"
    const val SERVICE_CLOSE = "com.qusadprod.sing_box.SERVICE_CLOSE"
    const val OPEN_URL = "com.qusadprod.sing_box.SERVICE_OPEN_URL"
    
    // Broadcast actions для передачи статуса и статистики
    const val STATUS_UPDATE = "com.qusadprod.sing_box.STATUS_UPDATE"
    const val STATS_UPDATE = "com.qusadprod.sing_box.STATS_UPDATE"
    const val NOTIFICATION_UPDATE = "com.qusadprod.sing_box.NOTIFICATION_UPDATE"
    
    // Extra keys для Intent
    const val EXTRA_STATUS = "status"
    const val EXTRA_STATS = "stats"
    const val EXTRA_NOTIFICATION_IDENTIFIER = "extra_notification_identifier"
    const val EXTRA_NOTIFICATION_TYPE_NAME = "extra_notification_type_name"
    const val EXTRA_NOTIFICATION_TYPE_ID = "extra_notification_type_id"
    const val EXTRA_NOTIFICATION_TITLE = "extra_notification_title"
    const val EXTRA_NOTIFICATION_SUBTITLE = "extra_notification_subtitle"
    const val EXTRA_NOTIFICATION_BODY = "extra_notification_body"
    const val EXTRA_NOTIFICATION_OPEN_URL = "extra_notification_open_url"
    const val ACTION_RELOAD = "com.qusadprod.sing_box.RELOAD" // Added for VPN reload
}

