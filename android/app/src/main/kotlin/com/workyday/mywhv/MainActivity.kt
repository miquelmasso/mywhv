package com.workyday.mywhv

import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val runtimeDeviceChannelName = "workyday/runtime_device"

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
    }
}
