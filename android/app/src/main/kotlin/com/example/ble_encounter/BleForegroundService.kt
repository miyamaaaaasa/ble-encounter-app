package com.example.ble_encounter

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat

class BleForegroundService : Service() {

    companion object {
        const val ACTION_START = "com.example.ble_encounter.START"
        const val ACTION_STOP  = "com.example.ble_encounter.STOP"
        private const val NOTIFICATION_ID = 1001
        const val CHANNEL_ID = "ble_encounter_fg"
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                // BLE権限が未付与の端末（例: BLE非対応エミュレータ）で
                // connectedDevice型FGSを起動するとSecurityExceptionでクラッシュする。
                // 起動に失敗しても停止するだけにしてアプリ本体は生かす。
                try {
                    startForeground(NOTIFICATION_ID, buildNotification())
                } catch (e: Exception) {
                    android.util.Log.w("BleFgService", "startForeground failed: ${e.message}")
                    stopSelf()
                }
            }
            ACTION_STOP  -> {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                    stopForeground(STOP_FOREGROUND_REMOVE)
                } else {
                    @Suppress("DEPRECATION")
                    stopForeground(true)
                }
                stopSelf()
            }
        }
        return START_STICKY
    }

    private fun buildNotification(): Notification {
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
        val pendingIntent = PendingIntent.getActivity(
            this, 0, launchIntent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("すれ違い 検知中")
            .setContentText("バックグラウンドで近くの人を探しています")
            .setSmallIcon(android.R.drawable.ic_menu_compass)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "BLE すれ違い実験",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "画面オフ中もスキャン・アドバタイズを継続するための常駐通知"
                setShowBadge(false)
            }
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            nm.createNotificationChannel(channel)
        }
    }
}
