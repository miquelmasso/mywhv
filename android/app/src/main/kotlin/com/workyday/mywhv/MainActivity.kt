package com.workyday.mywhv

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.provider.Settings
import androidx.core.view.WindowCompat
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val runtimeDeviceChannelName = "workyday/runtime_device"
    private val locationSettingsChannelName = "workyday/location_settings"

    override fun onCreate(savedInstanceState: Bundle?) {
        WindowCompat.setDecorFitsSystemWindows(window, false)
        super.onCreate(savedInstanceState)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            runtimeDeviceChannelName,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "isIosSimulator" -> result.success(false)
                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            locationSettingsChannelName,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "openLocationPermissionSettings" -> result.success(
                    openLocationPermissionSettings(),
                )
                else -> result.notImplemented()
            }
        }
    }

    private fun openLocationPermissionSettings(): Boolean {
        return try {
            val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                data = Uri.fromParts("package", packageName, null)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
            true
        } catch (exception: Exception) {
            false
        }
    }
}
