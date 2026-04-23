package com.example.moz_pn

import android.content.Intent
import android.net.VpnService
import android.security.KeyChain
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.example.moz_pn/vpn"

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "startVpn" -> {
                    val intent = VpnService.prepare(this)
                    if (intent != null) {
                        startActivityForResult(intent, 0)
                    } else {
                        onActivityResult(0, RESULT_OK, null)
                    }
                    result.success(true)
                }
                "stopVpn" -> {
                    val intent = Intent(this, MyVpnService::class.java)
                    intent.action = "STOP_VPN"
                    startService(intent)
                    result.success(true)
                }
                "installCA" -> {
                    val certPath = call.argument<String>("path")
                    if (certPath != null) {
                        installCertificate(certPath)
                        result.success(true)
                    } else {
                        result.error("INVALID_PATH", "Certificate path is null", null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun installCertificate(path: String) {
        val file = File(path)
        if (file.exists()) {
            val intent = KeyChain.createInstallIntent()
            intent.putExtra(KeyChain.EXTRA_CERTIFICATE, file.readBytes())
            intent.putExtra(KeyChain.EXTRA_NAME, "MozPN Root CA")
            startActivity(intent)
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == 0 && resultCode == RESULT_OK) {
            val intent = Intent(this, MyVpnService::class.java)
            intent.action = "START_VPN"
            startService(intent)
        }
    }
}
