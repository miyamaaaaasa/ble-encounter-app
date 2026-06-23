package com.example.ble_encounter

import android.app.NotificationManager
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.core.app.NotificationCompat
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.atomic.AtomicInteger

class GattChannel(private val context: Context) {

    private val tag = "GattChannel"
    private val server = GattServerManager(context)
    private val handler = Handler(Looper.getMainLooper())
    private val notifIdCounter = AtomicInteger(2000)

    fun handle(method: String, args: Map<String, Any?>, result: MethodChannel.Result) {
        when (method) {
            "startGattServer" -> {
                server.start(args["profileJson"] as? String ?: "{}")
                result.success(null)
            }
            "stopGattServer" -> {
                server.stop()
                result.success(null)
            }
            "updateProfile" -> {
                server.updateProfile(args["profileJson"] as? String ?: "{}")
                result.success(null)
            }
            "readPeerProfile" -> {
                val mac = args["mac"] as? String
                if (mac == null) {
                    result.error("INVALID_MAC", "MAC address required", null)
                    return
                }
                GattClientManager(context).readProfile(mac) { json ->
                    handler.post { result.success(json) }
                }
            }
            "showEncounterNotification" -> {
                showNotification(args["name"] as? String ?: "????")
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun showNotification(name: String) {
        try {
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            val notif = NotificationCompat.Builder(context, BleForegroundService.CHANNEL_ID)
                .setSmallIcon(android.R.drawable.ic_dialog_info)
                .setContentTitle("すれ違い！")
                .setContentText("$name さんとすれ違いました")
                .setPriority(NotificationCompat.PRIORITY_DEFAULT)
                .setAutoCancel(true)
                .build()
            nm.notify(notifIdCounter.getAndIncrement(), notif)
        } catch (e: Exception) {
            Log.w(tag, "Notification failed: ${e.message}")
        }
    }
}
