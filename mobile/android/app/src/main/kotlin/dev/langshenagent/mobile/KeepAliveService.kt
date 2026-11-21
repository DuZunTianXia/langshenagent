package dev.langshenagent.mobile

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.net.wifi.WifiManager
import android.os.Build
import android.os.IBinder
import android.os.PowerManager

/// Keeps the link to the paired computers alive while the app is in the
/// background: Android kills what is not seen, and the connections are
/// the point of the app (there is no push service).
class KeepAliveService : Service() {
    private var wifiLock: WifiManager.WifiLock? = null
    private var wakeLock: PowerManager.WakeLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val title = intent?.getStringExtra("title") ?: "LangshenAgent"
        val text = intent?.getStringExtra("text") ?: ""
        val channelName = intent?.getStringExtra("channelName") ?: title
        val manager = getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel("keep_alive", channelName, NotificationManager.IMPORTANCE_LOW)
            channel.setShowBadge(false)
            manager.createNotificationChannel(channel)
        }
        val open = PendingIntent.getActivity(
            this, 0,
            Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val notification: Notification =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                Notification.Builder(this, "keep_alive")
            } else {
                @Suppress("DEPRECATION")
                Notification.Builder(this).setPriority(Notification.PRIORITY_MIN)
            }.setSmallIcon(android.R.drawable.stat_notify_sync)
                .setContentTitle(title)
                .setContentText(text)
                .setContentIntent(open)
                .setOngoing(true)
                .setShowWhen(false)
                .build()
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                startForeground(NOTIFICATION_ID, notification, android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }
            holdLocks()
            START_STICKY
        } catch (_: Exception) {
            stopSelf()
            START_STICKY
        }
    }

    /// Doze takes the CPU and the radio; a partial wake lock and a
    /// low-latency Wi-Fi lock keep the link answering while the phone
    /// sleeps (the app's traffic is LAN-local — there is no push).
    private fun holdLocks() {
        if (wakeLock == null) {
            wakeLock = (getSystemService(POWER_SERVICE) as PowerManager)
                .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "langshenagent:links")
                .apply {
                    setReferenceCounted(false)
                    acquire()
                }
        }
        if (wifiLock == null) {
            @Suppress("DEPRECATION")
            val mode =
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    WifiManager.WIFI_MODE_FULL_LOW_LATENCY
                } else {
                    WifiManager.WIFI_MODE_FULL_HIGH_PERF
                }
            wifiLock = (applicationContext.getSystemService(WIFI_SERVICE) as WifiManager)
                .createWifiLock(mode, "langshenagent:links")
                .apply {
                    setReferenceCounted(false)
                    acquire()
                }
        }
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        // Swiping the task away is not "stop": respawn immediately while
        // the process still lives (a restart from a dead process can't
        // raise a foreground service anymore). START_STICKY covers the
        // system killing us on its own.
        val restart = Intent(this, KeepAliveService::class.java)
            .putExtras(rootIntent?.extras ?: android.os.Bundle())
        try {
            startService(restart)
        } catch (_: Exception) {
            // The system brings us back via START_STICKY.
        }
        super.onTaskRemoved(rootIntent)
    }

    override fun onDestroy() {
        wifiLock?.let { if (it.isHeld) it.release() }
        wifiLock = null
        wakeLock?.let { if (it.isHeld) it.release() }
        wakeLock = null
        super.onDestroy()
    }

    companion object {
        const val NOTIFICATION_ID = 47100
    }
}
