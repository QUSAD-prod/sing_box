package com.qusadprod.sing_box

import android.content.Context
import android.content.SharedPreferences
import com.google.gson.Gson
import com.google.gson.reflect.TypeToken
import java.util.concurrent.CopyOnWriteArraySet

/**
 * Менеджер для управления блокировкой приложений и доменов
 * Хранит списки заблокированных приложений и доменов
 * Отличие от BypassManager:
 * - Bypass = исключение из VPN (трафик идет напрямую)
 * - Block = блокировка трафика (трафик не проходит вообще)
 */
class BlockManager(private val context: Context) {
    private val prefs: SharedPreferences = context.getSharedPreferences("sing_box_block", Context.MODE_PRIVATE)
    private val gson = Gson()
    
    // Блокированные списки в памяти для быстрого доступа
    private val blockedApps = CopyOnWriteArraySet<String>()
    private val blockedDomains = CopyOnWriteArraySet<String>()
    
    init {
        loadFromPreferences()
    }
    
    // ========== Blocked Apps ==========
    
    /**
     * Добавить приложение в блокировку
     */
    fun addBlockedApp(packageName: String): Boolean {
        if (packageName.isBlank()) {
            return false
        }
        if (blockedApps.add(packageName)) {
            saveAppsToPreferences()
            return true
        }
        return false
    }
    
    /**
     * Удалить приложение из блокировки
     */
    fun removeBlockedApp(packageName: String): Boolean {
        if (blockedApps.remove(packageName)) {
            saveAppsToPreferences()
            return true
        }
        return false
    }
    
    /**
     * Получить список заблокированных приложений
     */
    fun getBlockedApps(): List<String> {
        return blockedApps.toList()
    }
    
    // ========== Blocked Domains ==========
    
    /**
     * Добавить домен в блокировку
     */
    fun addBlockedDomain(domain: String): Boolean {
        if (domain.isBlank()) {
            return false
        }
        // Нормализация домена (убираем http://, https://, www.)
        val normalizedDomain = normalizeDomain(domain)
        if (normalizedDomain.isBlank()) {
            return false
        }
        if (blockedDomains.add(normalizedDomain)) {
            saveDomainsToPreferences()
            return true
        }
        return false
    }
    
    /**
     * Удалить домен из блокировки
     */
    fun removeBlockedDomain(domain: String): Boolean {
        val normalizedDomain = normalizeDomain(domain)
        if (blockedDomains.remove(normalizedDomain)) {
            saveDomainsToPreferences()
            return true
        }
        return false
    }
    
    /**
     * Получить список заблокированных доменов
     */
    fun getBlockedDomains(): List<String> {
        return blockedDomains.toList()
    }
    
    // ========== Вспомогательные методы ==========
    
    /**
     * Нормализация домена (убирает протокол, www, слэши)
     */
    private fun normalizeDomain(domain: String): String {
        var normalized = domain.trim().lowercase()
        
        // Убираем протокол
        normalized = normalized.removePrefix("http://")
        normalized = normalized.removePrefix("https://")
        
        // Убираем www.
        normalized = normalized.removePrefix("www.")
        
        // Убираем слэши и пробелы в конце
        normalized = normalized.trimEnd('/', ' ')
        
        // Убираем путь (оставляем только домен)
        val pathIndex = normalized.indexOf('/')
        if (pathIndex > 0) {
            normalized = normalized.substring(0, pathIndex)
        }
        
        return normalized
    }
    
    /**
     * Загрузка списков из SharedPreferences
     */
    private fun loadFromPreferences() {
        // Загрузка apps
        val appsJson = prefs.getString("blocked_apps", "[]")
        val appsType = object : TypeToken<List<String>>() {}.type
        val appsList: List<String> = gson.fromJson(appsJson, appsType) ?: emptyList()
        blockedApps.addAll(appsList)
        
        // Загрузка domains
        val domainsJson = prefs.getString("blocked_domains", "[]")
        val domainsType = object : TypeToken<List<String>>() {}.type
        val domainsList: List<String> = gson.fromJson(domainsJson, domainsType) ?: emptyList()
        blockedDomains.addAll(domainsList)
    }
    
    /**
     * Сохранение списка приложений в SharedPreferences
     */
    private fun saveAppsToPreferences() {
        val appsJson = gson.toJson(blockedApps.toList())
        prefs.edit().putString("blocked_apps", appsJson).apply()
    }
    
    /**
     * Сохранение списка доменов в SharedPreferences
     */
    private fun saveDomainsToPreferences() {
        val domainsJson = gson.toJson(blockedDomains.toList())
        prefs.edit().putString("blocked_domains", domainsJson).apply()
    }
}

