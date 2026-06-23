package com.example.ble_encounter

import android.content.Intent
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val advertiserChannelName = "com.example.ble_encounter/ble_advertiser"
    private val gattChannelName = "com.example.ble_encounter/gatt"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val bleAdvertiser = BleAdvertiserChannel(applicationContext)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, advertiserChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startAdvertise" -> {
                        val peerId = call.argument<ByteArray>("peerId")
                        val profilePayload = call.argument<ByteArray>("profilePayload") ?: ByteArray(0)
                        if (peerId == null) result.error("INVALID_ARG", "peerId is null", null)
                        else bleAdvertiser.startAdvertise(peerId, profilePayload, result)
                    }
                    "stopAdvertise" -> bleAdvertiser.stopAdvertise(result)
                    "startForegroundService" -> {
                        val intent = Intent(this, BleForegroundService::class.java).apply {
                            action = BleForegroundService.ACTION_START
                        }
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) startForegroundService(intent)
                        else startService(intent)
                        result.success(null)
                    }
                    "stopForegroundService" -> {
                        startService(Intent(this, BleForegroundService::class.java).apply {
                            action = BleForegroundService.ACTION_STOP
                        })
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }

        val gattChannel = GattChannel(applicationContext)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, gattChannelName)
            .setMethodCallHandler { call, result ->
                @Suppress("UNCHECKED_CAST")
                val args = call.arguments as? Map<String, Any?> ?: emptyMap()
                gattChannel.handle(call.method, args, result)
            }
    }
}
