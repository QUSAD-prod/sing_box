package com.qusadprod.sing_box

import android.content.Context
import android.content.SharedPreferences
import com.google.gson.Gson
import com.google.gson.reflect.TypeToken
import java.util.concurrent.CopyOnWriteArraySet

/**
 * Manager for managing DNS servers
 * Stores list of DNS servers
 */
class DnsManager(private val context: Context) {
    private val prefs: SharedPreferences = context.getSharedPreferences("sing_box_dns", Context.MODE_PRIVATE)
    private val gson = Gson()
    
    // DNS servers in memory for quick access
    private val dnsServers = CopyOnWriteArraySet<String>()
    
    // Key for storing in SharedPreferences
    private val keyDnsServers = "dns_servers"
    
    init {
        loadFromPreferences()
    }
    
    /**
     * Add DNS server
     */
    fun addDnsServer(dnsServer: String): Boolean {
        if (isValidDnsServer(dnsServer) && dnsServers.add(dnsServer)) {
            saveToPreferences()
            return true
        }
        return false
    }
    
    /**
     * Remove DNS server
     */
    fun removeDnsServer(dnsServer: String): Boolean {
        if (dnsServers.remove(dnsServer)) {
            saveToPreferences()
            return true
        }
        return false
    }
    
    /**
     * Get list of DNS servers
     */
    fun getDnsServers(): List<String> {
        return dnsServers.toList()
    }
    
    /**
     * Set DNS servers (replace all)
     */
    fun setDnsServers(servers: List<String>): Boolean {
        // Validate all servers
        val validServers = servers.filter { isValidDnsServer(it) }
        if (validServers.size != servers.size) {
            return false // Invalid servers found
        }
        
        dnsServers.clear()
        dnsServers.addAll(validServers)
        saveToPreferences()
        return true
    }
    
    /**
     * Validate DNS server (IPv4 or IPv6)
     */
    private fun isValidDnsServer(dnsServer: String): Boolean {
        if (dnsServer.isBlank()) return false
        
        // Check IPv4 (e.g., "8.8.8.8")
        val ipv4Pattern = Regex("^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$")
        if (ipv4Pattern.matches(dnsServer)) {
            return true
        }
        
        // Check IPv6 (simplified, but covers main cases)
        // Support full addresses, compressed addresses (::), localhost (::1)
        if (dnsServer.contains(":")) {
            // Basic IPv6 format check
            val ipv6Parts = dnsServer.split(":")
            if (ipv6Parts.size in 2..8) {
                // Check that all parts are valid hex numbers or empty (for ::)
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
     * Load DNS servers from SharedPreferences
     */
    private fun loadFromPreferences() {
        val dnsJson = prefs.getString(keyDnsServers, "[]")
        val dnsType = object : TypeToken<List<String>>() {}.type
        val dnsList: List<String> = gson.fromJson(dnsJson, dnsType) ?: emptyList()
        
        // If list is empty, use default values
        if (dnsList.isEmpty()) {
            dnsServers.addAll(listOf("8.8.8.8", "1.1.1.1")) // Google DNS and Cloudflare DNS
            saveToPreferences()
        } else {
            dnsServers.addAll(dnsList)
        }
    }
    
    /**
     * Save DNS servers to SharedPreferences
     */
    private fun saveToPreferences() {
        val dnsJson = gson.toJson(dnsServers.toList())
        prefs.edit().putString(keyDnsServers, dnsJson).apply()
    }
}

