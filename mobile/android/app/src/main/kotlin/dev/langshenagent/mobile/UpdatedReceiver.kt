package dev.langshenagent.mobile

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.os.Build

/// After an update installed over the app, the "update" shared flag is
/// set: say so once, and open the app.
class UpdatedReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_MY_PACKAGE_REPLACED) return
        val prefs: SharedPreferences = context.getSharedPreferences("update", Context.MODE_PRIVATE)
        if (!prefs.getBoolean("updating", false)) return
        prefs.edit().remove("updating").apply()
        val manager = context.getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                NotificationChannel("update", "Updates", NotificationManager.IMPORTANCE_DEFAULT),
            )
        }
        val launch = context.packageManager.getLaunchIntentForPackage(context.packageName)
            ?.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK) ?: return
        val open = PendingIntent.getActivity(
            context, 0, launch,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val version = try {
            context.packageManager.getPackageInfo(context.packageName, 0).versionName
        } catch (_: Exception) {
            null
        } ?: ""
        val notification: Notification =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                Notification.Builder(context, "update")
            } else {
                @Suppress("DEPRECATION")
                Notification.Builder(context)
            }.setSmallIcon(android.R.drawable.stat_sys_download_done)
                .setContentTitle("LangshenAgent $version is installed")
                .setContentText("Tap to open it.")
                .setContentIntent(open)
                .setAutoCancel(true)
                .build()
        manager.notify(7101, notification)
    }
}
