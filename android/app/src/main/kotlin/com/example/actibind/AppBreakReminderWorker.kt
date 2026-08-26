package com.example.actibind

import android.Manifest
import android.app.AppOpsManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Process
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.Worker
import androidx.work.WorkerParameters
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.concurrent.TimeUnit

class AppBreakReminderWorker(
    context: Context,
    parameters: WorkerParameters,
) : Worker(context, parameters) {
    override fun doWork(): Result {
        if (!hasUsageAccess() || !canPostNotifications()) return Result.success()

        val now = System.currentTimeMillis()
        val calendar = java.util.Calendar.getInstance().apply {
            timeInMillis = now
            set(java.util.Calendar.HOUR_OF_DAY, 0)
            set(java.util.Calendar.MINUTE, 0)
            set(java.util.Calendar.SECOND, 0)
            set(java.util.Calendar.MILLISECOND, 0)
        }
        val usageManager = applicationContext
            .getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        val overLimit = usageManager.queryAndAggregateUsageStats(calendar.timeInMillis, now)
            .values
            .filter {
                it.packageName != applicationContext.packageName &&
                    it.totalTimeInForeground >= BREAK_THRESHOLD_MS
            }
        if (overLimit.isEmpty()) return Result.success()

        createChannel()
        val day = SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date(now))
        val preferences = applicationContext.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
        val packageManager = applicationContext.packageManager
        for (stats in overLimit) {
            val preferenceKey = "$day:${stats.packageName}"
            if (preferences.getBoolean(preferenceKey, false)) continue
            val appName = try {
                val info = packageManager.getApplicationInfo(stats.packageName, 0)
                packageManager.getApplicationLabel(info).toString()
            } catch (_: PackageManager.NameNotFoundException) {
                stats.packageName.substringAfterLast('.')
            }
            showNotification(
                id = (day + stats.packageName).hashCode().and(0x7fffffff),
                appName = appName,
                usageMinutes = stats.totalTimeInForeground / 60_000,
            )
            preferences.edit().putBoolean(preferenceKey, true).apply()
        }
        removeOldKeys(preferences, day)
        return Result.success()
    }

    private fun hasUsageAccess(): Boolean {
        val appOps = applicationContext.getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
        return appOps.checkOpNoThrow(
            AppOpsManager.OPSTR_GET_USAGE_STATS,
            Process.myUid(),
            applicationContext.packageName,
        ) == AppOpsManager.MODE_ALLOWED
    }

    private fun canPostNotifications(): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            applicationContext.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) return false
        return NotificationManagerCompat.from(applicationContext).areNotificationsEnabled()
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Wellbeing break reminders",
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "Reminders to take a break after extended app use"
            enableVibration(true)
        }
        applicationContext.getSystemService(NotificationManager::class.java)
            .createNotificationChannel(channel)
    }

    private fun showNotification(id: Int, appName: String, usageMinutes: Long) {
        val hours = usageMinutes / 60
        val minutes = usageMinutes % 60
        val duration = if (minutes == 0L) "$hours hours" else "${hours}h ${minutes}m"
        val openApp = PendingIntent.getActivity(
            applicationContext,
            id,
            Intent(applicationContext, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val notification = NotificationCompat.Builder(applicationContext, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("Time for a short break")
            .setContentText("You have used $appName for $duration today. Rest your eyes and stretch.")
            .setStyle(
                NotificationCompat.BigTextStyle().bigText(
                    "You have used $appName for $duration today. Rest your eyes, stretch, and come back when you are ready.",
                ),
            )
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(true)
            .setContentIntent(openApp)
            .build()
        NotificationManagerCompat.from(applicationContext).notify(id, notification)
    }

    private fun removeOldKeys(
        preferences: android.content.SharedPreferences,
        currentDay: String,
    ) {
        val editor = preferences.edit()
        preferences.all.keys.filterNot { it.startsWith("$currentDay:") }.forEach(editor::remove)
        editor.apply()
    }

    companion object {
        private const val WORK_NAME = "actibind_app_break_reminders"
        private const val PREFERENCES = "actibind_break_reminders"
        private const val CHANNEL_ID = "wellbeing_break_reminders_v1"
        private const val BREAK_THRESHOLD_MS = 2L * 60L * 60L * 1000L

        fun schedule(context: Context) {
            val workManager = WorkManager.getInstance(context)
            workManager.enqueueUniquePeriodicWork(
                WORK_NAME,
                ExistingPeriodicWorkPolicy.UPDATE,
                PeriodicWorkRequestBuilder<AppBreakReminderWorker>(15, TimeUnit.MINUTES).build(),
            )
            workManager.enqueue(OneTimeWorkRequestBuilder<AppBreakReminderWorker>().build())
        }
    }
}
