package com.qusadprod.sing_box

import android.content.Context
import android.content.SharedPreferences
import com.google.gson.Gson
import com.google.gson.reflect.TypeToken
import java.util.concurrent.CopyOnWriteArraySet

/**
 * Manager for managing blocking of applications and domains
 * Stores lists of blocked applications and domains
 * Difference from BypassManager:
 * - Bypass = exclude from VPN (traffic goes directly)
 * - Block = block traffic (traffic doesn't pass at all)
 */
class BlockManager(private val context: Context) {
    private val prefs: SharedPreferences = context.getSharedPreferences("sing_box_block", Context.MODE_PRIVATE)
    private val gson = Gson()
    
    // Blocked lists in memory for quick access
    private val blockedApps = CopyOnWriteArraySet<String>()
    private val blockedDomains = CopyOnWriteArraySet<String>()
    
    init {
        loadFromPreferences()
    }
    
    // ========== Blocked Apps ==========
    
    /**
     * Add application to blocking list
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
     * Remove application from blocking list
     */
    fun removeBlockedApp(packageName: String): Boolean {
        if (blockedApps.remove(packageName)) {
            saveAppsToPreferences()
            return true
        }
        return false
    }
    
    /**
     * Get list of blocked applications
     */
    fun getBlockedApps(): List<String> {
        return blockedApps.toList()
    }
    
    // ========== Blocked Domains ==========
    
    /**
     * Add domain to blocking list
     */
    fun addBlockedDomain(domain: String): Boolean {
        if (domain.isBlank()) {
            return false
        }
        // Domain normalization (remove http://, https://, www.)
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
     * Remove domain from blocking list
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
     * Get list of blocked domains
     */
    fun getBlockedDomains(): List<String> {
        return blockedDomains.toList()
    }
    
    // ========== Helper Methods ==========
    
    /**
     * Domain normalization (removes protocol, www, slashes)
     */
    private fun normalizeDomain(domain: String): String {
        var normalized = domain.trim().lowercase()
        
        // Remove protocol
        normalized = normalized.removePrefix("http://")
        normalized = normalized.removePrefix("https://")
        
        // Remove www.
        normalized = normalized.removePrefix("www.")
        
        // Remove slashes and spaces at the end
        normalized = normalized.trimEnd('/', ' ')
        
        // Remove path (keep only domain)
        val pathIndex = normalized.indexOf('/')
        if (pathIndex > 0) {
            normalized = normalized.substring(0, pathIndex)
        }
        
        return normalized
    }
    
    /**
     * Load lists from SharedPreferences
     */
    private fun loadFromPreferences() {
        // Load apps
        val appsJson = prefs.getString("blocked_apps", "[]")
        val appsType = object : TypeToken<List<String>>() {}.type
        val appsList: List<String> = gson.fromJson(appsJson, appsType) ?: emptyList()
        blockedApps.addAll(appsList)
        
        // Load domains
        val domainsJson = prefs.getString("blocked_domains", "[]")
        val domainsType = object : TypeToken<List<String>>() {}.type
        val domainsList: List<String> = gson.fromJson(domainsJson, domainsType) ?: emptyList()
        blockedDomains.addAll(domainsList)
    }
    
    /**
     * Save applications list to SharedPreferences
     */
    private fun saveAppsToPreferences() {
        val appsJson = gson.toJson(blockedApps.toList())
        prefs.edit().putString("blocked_apps", appsJson).apply()
    }
    
    /**
     * Save domains list to SharedPreferences
     */
    private fun saveDomainsToPreferences() {
        val domainsJson = gson.toJson(blockedDomains.toList())
        prefs.edit().putString("blocked_domains", domainsJson).apply()
    }
}

