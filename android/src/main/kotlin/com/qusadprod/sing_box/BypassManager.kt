package com.qusadprod.sing_box

import android.content.Context
import android.content.SharedPreferences
import com.google.gson.Gson
import com.google.gson.reflect.TypeToken
import java.util.concurrent.CopyOnWriteArraySet

/**
 * Менеджер для управления bypass списками
 * Хранит списки приложений, доменов и подсетей
 */
class BypassManager(private val context: Context) {
    private val prefs: SharedPreferences = context.getSharedPreferences("sing_box_bypass", Context.MODE_PRIVATE)
    private val gson = Gson()
    
    // Bypass списки в памяти для быстрого доступа
    private val bypassApps = CopyOnWriteArraySet<String>()
    private val bypassDomains = CopyOnWriteArraySet<String>()
    private val bypassSubnets = CopyOnWriteArraySet<String>()
    
    init {
        loadFromPreferences()
    }
    
    // ========== Bypass Apps ==========
    
    fun addAppToBypass(packageName: String): Boolean {
        if (bypassApps.add(packageName)) {
            saveAppsToPreferences()
            return true
        }
        return false
    }
    
    fun removeAppFromBypass(packageName: String): Boolean {
        if (bypassApps.remove(packageName)) {
            saveAppsToPreferences()
            return true
        }
        return false
    }
    
    fun getBypassApps(): List<String> {
        return bypassApps.toList()
    }
    
    // ========== Bypass Domains ==========
    
    fun addDomainToBypass(domain: String): Boolean {
        if (bypassDomains.add(domain)) {
            saveDomainsToPreferences()
            return true
        }
        return false
    }
    
    fun removeDomainFromBypass(domain: String): Boolean {
        if (bypassDomains.remove(domain)) {
            saveDomainsToPreferences()
            return true
        }
        return false
    }
    
    fun getBypassDomains(): List<String> {
        return bypassDomains.toList()
    }
    
    // ========== Bypass Subnets ==========
    
    fun addSubnetToBypass(subnet: String): Boolean {
        if (isValidSubnet(subnet) && bypassSubnets.add(subnet)) {
            saveSubnetsToPreferences()
            return true
        }
        return false
    }
    
    fun removeSubnetFromBypass(subnet: String): Boolean {
        if (bypassSubnets.remove(subnet)) {
            saveSubnetsToPreferences()
            return true
        }
        return false
    }
    
    fun getBypassSubnets(): List<String> {
        return bypassSubnets.toList()
    }
    
    // ========== Вспомогательные методы ==========
    
    private fun isValidSubnet(subnet: String): Boolean {
        // Простая проверка формата CIDR (например, "192.168.1.0/24")
        return subnet.matches(Regex("^\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}/\\d{1,2}$"))
    }
    
    private fun loadFromPreferences() {
        // Загрузка apps
        val appsJson = prefs.getString("bypass_apps", "[]")
        val appsType = object : TypeToken<List<String>>() {}.type
        val appsList: List<String> = gson.fromJson(appsJson, appsType) ?: emptyList()
        bypassApps.addAll(appsList)
        
        // Загрузка domains
        val domainsJson = prefs.getString("bypass_domains", "[]")
        val domainsType = object : TypeToken<List<String>>() {}.type
        val domainsList: List<String> = gson.fromJson(domainsJson, domainsType) ?: emptyList()
        bypassDomains.addAll(domainsList)
        
        // Загрузка subnets
        val subnetsJson = prefs.getString("bypass_subnets", "[]")
        val subnetsType = object : TypeToken<List<String>>() {}.type
        val subnetsList: List<String> = gson.fromJson(subnetsJson, subnetsType) ?: emptyList()
        bypassSubnets.addAll(subnetsList)
    }
    
    private fun saveAppsToPreferences() {
        val appsJson = gson.toJson(bypassApps.toList())
        prefs.edit().putString("bypass_apps", appsJson).apply()
    }
    
    private fun saveDomainsToPreferences() {
        val domainsJson = gson.toJson(bypassDomains.toList())
        prefs.edit().putString("bypass_domains", domainsJson).apply()
    }
    
    private fun saveSubnetsToPreferences() {
        val subnetsJson = gson.toJson(bypassSubnets.toList())
        prefs.edit().putString("bypass_subnets", subnetsJson).apply()
    }
}

