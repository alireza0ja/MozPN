package com.example.moz_pn

import android.content.Intent
import android.net.VpnService
import android.net.Uri
import android.security.KeyChain
import android.os.Build
import android.os.Environment
import android.provider.Settings
import android.util.Log
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.example.moz_pn/vpn"

    private var pendingVpnResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "startVpn" -> {
                    val intent = VpnService.prepare(this)
                    if (intent != null) {
                        pendingVpnResult = result
                        startActivityForResult(intent, 0)
                    } else {
                        startVpnService()
                        result.success(true)
                    }
                }
                "stopVpn" -> {
                    stopVpnService()
                    result.success(true)
                }
                "installCA" -> {
                    val certData = call.argument<ByteArray>("certData")
                    if (certData != null) {
                        installCertificate(certData)
                        result.success(true)
                    } else {
                        result.error("INVALID_DATA", "Certificate data is null", null)
                    }
                }
                "requestStoragePermission" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                        try {
                            val intent = Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION)
                            intent.data = Uri.parse("package:$packageName")
                            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            startActivity(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            val intent = Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION)
                            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            startActivity(intent)
                            result.success(true)
                        }
                    } else {
                        result.success(true)
                    }
                }
                "checkStoragePermission" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                        result.success(Environment.isExternalStorageManager())
                    } else {
                        result.success(true)
                    }
                }
                "prepareVpn" -> {
                    val intent = VpnService.prepare(this)
                    if (intent != null) {
                        startActivityForResult(intent, 0)
                        result.success(false) // Needs permission
                    } else {
                        result.success(true) // Already has permission
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun startVpnService() {
        val intent = Intent(this, MyVpnService::class.java)
        intent.action = "START_VPN"
        startService(intent)
    }

    private fun stopVpnService() {
        val intent = Intent(this, MyVpnService::class.java)
        intent.action = "STOP_VPN"
        startService(intent)
    }

    private fun installCertificate(certData: ByteArray) {
        try {
            Log.d("MozPN", "Certificate size: ${certData.size} bytes")
            
            // Save certificate to external storage for backup/manual install
            val storageDir = Environment.getExternalStorageDirectory()
            val certFile = File(storageDir, "MozPN-CA.crt")
            
            try {
                certFile.writeBytes(certData)
                Log.d("MozPN", "✓ Certificate saved to: ${certFile.absolutePath}")
            } catch (e: Exception) {
                Log.e("MozPN", "Failed to save to root: ${e.message}")
                // Fallback to Downloads
                try {
                    val downloadsDir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
                    val fallbackFile = File(downloadsDir, "MozPN-CA.crt")
                    fallbackFile.writeBytes(certData)
                    Log.d("MozPN", "✓ Certificate saved to Downloads: ${fallbackFile.absolutePath}")
                } catch (ex: Exception) {
                    Log.e("MozPN", "Failed to save to Downloads: ${ex.message}")
                }
            }

            // Use KeyChain.createInstallIntent() with EXTRA_CERTIFICATE for CA cert
            try {
                val intent = KeyChain.createInstallIntent()
                // IMPORTANT: Use EXTRA_CERTIFICATE for CA certificates (not EXTRA_PKCS12)
                intent.putExtra(KeyChain.EXTRA_CERTIFICATE, certData)
                intent.putExtra(KeyChain.EXTRA_NAME, "MozPN Root CA")
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                startActivity(intent)
                Log.d("MozPN", "✓ Opened KeyChain install intent with EXTRA_CERTIFICATE")
            } catch (e: Exception) {
                Log.e("MozPN", "KeyChain intent failed: ${e.message}")
                e.printStackTrace()
                
                // Fallback: Open CA certificate settings manually
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    try {
                        val intent = Intent("android.settings.CA_CERTIFICATE_SETTINGS")
                        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        startActivity(intent)
                        Log.d("MozPN", "✓ Opened CA Certificate Settings (manual install)")
                    } catch (ex: Exception) {
                        Log.e("MozPN", "CA Settings failed: ${ex.message}")
                        // Final fallback
                        val fallback = Intent(Settings.ACTION_SECURITY_SETTINGS)
                        fallback.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        startActivity(fallback)
                    }
                } else {
                    // Android 10 and below
                    val fallback = Intent(Settings.ACTION_SECURITY_SETTINGS)
                    fallback.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    startActivity(fallback)
                }
            }
        } catch (e: Exception) {
            Log.e("MozPN", "Error installing certificate: ${e.message}")
            e.printStackTrace()
        }
    }

    private fun installCertificate(path: String) {
        val sourceFile = File(path)
        if (!sourceFile.exists()) return

        try {
            // 1. Save to Root for easiest user access (User Requested)
            try {
                val rootFile = File(Environment.getExternalStorageDirectory(), "MozPN-v2-CA.crt")
                sourceFile.copyTo(rootFile, overwrite = true)
                Log.d("MozPN", "✓ Saved to Root: ${rootFile.absolutePath}")
            } catch (e: Exception) {
                Log.e("MozPN", "Root save failed: ${e.message}")
            }
            
            // 2. Save to Downloads as backup
            try {
                val downloadFile = File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS), "MozPN-v2-CA.crt")
                sourceFile.copyTo(downloadFile, overwrite = true)
            } catch (e: Exception) {}

            // 3. Open the BEST settings screen based on Android version
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                // Android 11-14: Go directly to CA Certificate settings
                try {
                    val intent = Intent("android.settings.CA_CERTIFICATE_SETTINGS")
                    intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    startActivity(intent)
                    return
                } catch (e: Exception) {}
            }

            // Fallback for Android 7-10 or if the above failed
            try {
                val intent = KeyChain.createInstallIntent()
                intent.putExtra(KeyChain.EXTRA_CERTIFICATE, sourceFile.readBytes())
                intent.putExtra(KeyChain.EXTRA_NAME, "MozPN Root CA")
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                startActivity(intent)
            } catch (e: Exception) {
                val fallback = Intent(Settings.ACTION_SECURITY_SETTINGS)
                fallback.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                startActivity(fallback)
            }
        } catch (e: Exception) {
            Log.e("MozPN", "Error: ${e.message}")
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == 0) {
            if (resultCode == RESULT_OK) {
                startVpnService()
                pendingVpnResult?.success(true)
            } else {
                pendingVpnResult?.error("PERMISSION_DENIED", "VPN permission denied by user", null)
            }
            pendingVpnResult = null
        }
    }
}
