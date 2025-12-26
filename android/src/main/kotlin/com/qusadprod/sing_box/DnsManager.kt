package com.qusadprod.sing_box

import android.content.Context
import android.content.SharedPreferences
import com.google.gson.Gson
import com.google.gson.reflect.TypeToken
import java.util.concurrent.CopyOnWriteArraySet

/**
 * Менеджер для управления DNS серверами
 * Хранит список DNS серверов
 */
class DnsManager(private val context: Context) {
    private val prefs: SharedPreferences = context.getSharedPreferences("sing_box_dns", Context.MODE_PRIVATE)
    private val gson = Gson()
    
    // DNS серверы в памяти для быстрого доступа
    private val dnsServers = CopyOnWriteArraySet<String>()
    
    // Ключ для хранения в SharedPreferences
    private val keyDnsServers = "dns_servers"
    
    init {
        loadFromPreferences()
    }
    
    /**
     * Добавить DNS сервер
     */
    fun addDnsServer(dnsServer: String): Boolean {
        if (isValidDnsServer(dnsServer) && dnsServers.add(dnsServer)) {
            saveToPreferences()
            return true
        }
        return false
    }
    
    /**
     * Удалить DNS сервер
     */
    fun removeDnsServer(dnsServer: String): Boolean {
        if (dnsServers.remove(dnsServer)) {
            saveToPreferences()
            return true
        }
        return false
    }
    
    /**
     * Получить список DNS серверов
     */
    fun getDnsServers(): List<String> {
        return dnsServers.toList()
    }
    
    /**
     * Установить DNS серверы (заменить все)
     */
    fun setDnsServers(servers: List<String>): Boolean {
        // Валидируем все серверы
        val validServers = servers.filter { isValidDnsServer(it) }
        if (validServers.size != servers.size) {
            return false // Есть невалидные серверы
        }
        
        dnsServers.clear()
        dnsServers.addAll(validServers)
        saveToPreferences()
        return true
    }
    
    /**
     * Проверка валидности DNS сервера (IPv4 или IPv6)
     */
    private fun isValidDnsServer(dnsServer: String): Boolean {
        if (dnsServer.isBlank()) return false
        
        // Проверка IPv4 (например, "8.8.8.8")
        val ipv4Pattern = Regex("^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$")
        if (ipv4Pattern.matches(dnsServer)) {
            return true
        }
        
        // Проверка IPv6 (упрощенная, но покрывает основные случаи)
        // Поддерживаем полные адреса, сжатые адреса (::), localhost (::1)
        if (dnsServer.contains(":")) {
            // Базовая проверка IPv6 формата
            val ipv6Parts = dnsServer.split(":")
            if (ipv6Parts.size in 2..8) {
                // Проверяем, что все части являются валидными hex числами или пустыми (для ::)
                val allValid = ipv6Parts.all { part ->
                    part.isEmpty() || part.matches(Regex("^[0-9a-fA-F]{1,4}$"))
                }
                if (allValid) {
                    return true
                }
            }
        }
        
        return false
    }
    
    /**
     * Загрузка DNS серверов из SharedPreferences
     */
    private fun loadFromPreferences() {
        val dnsJson = prefs.getString(keyDnsServers, "[]")
        val dnsType = object : TypeToken<List<String>>() {}.type
        val dnsList: List<String> = gson.fromJson(dnsJson, dnsType) ?: emptyList()
        
        // Если список пуст, используем значения по умолчанию
        if (dnsList.isEmpty()) {
            dnsServers.addAll(listOf("8.8.8.8", "1.1.1.1")) // Google DNS и Cloudflare DNS
            saveToPreferences()
        } else {
            dnsServers.addAll(dnsList)
        }
    }
    
    /**
     * Сохранение DNS серверов в SharedPreferences
     */
    private fun saveToPreferences() {
        val dnsJson = gson.toJson(dnsServers.toList())
        prefs.edit().putString(keyDnsServers, dnsJson).apply()
    }
}

