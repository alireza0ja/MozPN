package com.example.moz_pn

import android.content.Intent
import android.net.VpnService
import android.os.ParcelFileDescriptor
import android.util.Log

class MyVpnService : VpnService() {
    private var vpnInterface: ParcelFileDescriptor? = null

    /* 
     * INSTRUCTIONS FOR TUN2SOCKS INTEGRATION:
     * 1. Add 'implementation "eu.faircode:netguard:2.2.19"' or similar 
     *    OR include 'libhev-socks5-tunnel.so' in your jniLibs folder.
     * 2. This blueprint uses a conceptual 'Tunneler' object which represents 
     *     the JNI wrapper for the tun2socks engine.
     */

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == "START_VPN") {
            startVpn()
        } else if (intent?.action == "STOP_VPN") {
            stopVpn()
        }
        return START_STICKY
    }

    private fun startVpn() {
        val builder = Builder()
        builder.setSession("MozPN")
            .addAddress("10.0.0.2", 24)
            .addDnsServer("8.8.8.8")
            .addRoute("0.0.0.0", 0) 
            // Optional: Exclude the local proxy port from the VPN tunnel to avoid loops
            // .addDisallowedApplication("com.example.moz_pn") 

        vpnInterface = builder.establish()
        Log.d("MozPN", "VPN TUN Interface established.")

        // Start the native tun2socks engine
        // This engine will read from the TUN file descriptor and 
        // forward TCP/UDP traffic to our Dart SOCKS5 server at 127.0.0.1:1080.
        
        startNativeTunnel(vpnInterface!!.fileDescriptor.fd)
    }

    private fun startNativeTunnel(fd: Int) {
        // This is where you call your JNI method.
        // Example with hev-socks5-tunnel:
        // HevSocks5Tunnel.start("127.0.0.1", 1080, fd)
        Log.d("MozPN", "Native tunnel engine started using FD: $fd")
    }

    private fun stopVpn() {
        // HevSocks5Tunnel.stop()
        vpnInterface?.close()
        vpnInterface = null
        stopSelf()
    }

    override fun onDestroy() {
        stopVpn()
        super.onDestroy()
    }
}
