package com.yutan123.tidebot

import android.app.Application
import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.os.Build
import android.util.Log

/** Runs for headless Worker/receiver starts as well as normal UI launches. */
class TideApplication : Application() {
    private val availableNetworks = mutableSetOf<Network>()
    private val networkCallback = object : ConnectivityManager.NetworkCallback() {
        override fun onCapabilitiesChanged(network: Network, capabilities: NetworkCapabilities) {
            val usable = capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) &&
                (Build.VERSION.SDK_INT < Build.VERSION_CODES.M ||
                    capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED))
            val newlyAvailable = synchronized(availableNetworks) {
                if (usable) availableNetworks.add(network)
                else {
                    availableNetworks.remove(network)
                    false
                }
            }
            // Recover on usable network transitions, not signal/metering updates.
            if (newlyAvailable) requestRecovery()
        }

        override fun onLost(network: Network) {
            synchronized(availableNetworks) { availableNetworks.remove(network) }
        }
    }

    override fun onCreate() {
        super.onCreate()
        // WorkManager's initializer runs before Application.onCreate. Neither
        // recovery nor the watchdog requires an Activity or a persistent FGS.
        runCatching {
            TideEnhancedBackgroundWork.ensureScheduled(this)
            TideRecoveryWork.enqueue(this)
        }.onFailure { Log.e("TideRecovery", "Cannot register recovery", it) }
        runCatching {
            val connectivity = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                connectivity.registerDefaultNetworkCallback(networkCallback)
            } else {
                connectivity.registerNetworkCallback(NetworkRequest.Builder()
                    .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET).build(), networkCallback)
            }
        }.onFailure { Log.w("TideRecovery", "Network observer unavailable; periodic recovery remains active", it) }
    }

    private fun requestRecovery() {
        runCatching { TideRecoveryWork.enqueue(this) }
            .onFailure { Log.e("TideRecovery", "Cannot enqueue network recovery", it) }
    }
}