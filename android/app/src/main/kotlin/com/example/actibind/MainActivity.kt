package com.example.actibind

import android.app.AppOpsManager
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.Drawable
import android.os.Process
import android.provider.Settings
import android.util.LruCache
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val channelName = "com.example.actibind/usage_stats"
    private val usageExecutor = Executors.newSingleThreadExecutor()
    private val iconCache = LruCache<String, ByteArray>(64)
    @Volatile private var labelCache: Map<String, String>? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "hasPermission" -> result.success(hasUsageStatsPermission())
                    "openSettings" -> {
                        startActivity(Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS))
                        result.success(null)
                    }
                    "getUsageStats" -> {
                        val start = call.argument<Number>("start")?.toLong()
                        val end = call.argument<Number>("end")?.toLong()
                        if (start == null || end == null) {
                            result.error("INVALID_RANGE", "A start and end time are required", null)
                        } else if (!hasUsageStatsPermission()) {
                            result.error("PERMISSION_DENIED", "Usage access has not been granted", null)
                        } else {
                            usageExecutor.execute {
                                try {
                                    val rows = queryUsageStats(start, end)
                                    runOnUiThread { result.success(rows) }
                                } catch (error: Exception) {
                                    runOnUiThread {
                                        result.error(
                                            "USAGE_QUERY_FAILED",
                                            "Unable to read usage activity",
                                            error.message,
                                        )
                                    }
                                }
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.example.actibind/home_widgets",
        ).setMethodCallHandler { call, result ->
            if (call.method != "updateWidgets") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            @Suppress("UNCHECKED_CAST")
            ActiBindWidgetUpdater.update(applicationContext, call.arguments as? Map<String, Any?> ?: emptyMap())
            result.success(null)
        }
        val childMode = ChildModePolicyManager(this)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.example.actibind/child_mode",
        ).setMethodCallHandler { call, result ->
            @Suppress("UNCHECKED_CAST")
            val packages = call.argument<List<String>>("restrictedPackages") ?: emptyList()
            val allowedPackages = call.argument<List<String>>("allowedPackages") ?: emptyList()
            when (call.method) {
                "capabilities" -> result.success(childMode.capabilities())
                "installedApps" -> result.success(childMode.installedApps())
                "requestAdmin" -> {
                    childMode.requestAdmin()
                    result.success(null)
                }
                "openDeviceAdminSettings" -> {
                    childMode.openDeviceAdminSettings()
                    result.success(null)
                }
                "openAccessibilitySettings" -> {
                    childMode.openAccessibilitySettings()
                    result.success(null)
                }
                "start" -> result.success(childMode.start(packages, allowedPackages))
                "stop" -> result.success(childMode.stop(packages))
                "launchApp" -> {
                    val packageName = call.argument<String>("packageName")
                    result.success(packageName != null && childMode.launchApp(packageName))
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onDestroy() {
        usageExecutor.shutdownNow()
        super.onDestroy()
    }

    private fun hasUsageStatsPermission(): Boolean {
        val appOps = getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
        val mode = appOps.checkOpNoThrow(
            AppOpsManager.OPSTR_GET_USAGE_STATS,
            Process.myUid(),
            packageName,
        )
        return mode == AppOpsManager.MODE_ALLOWED
    }

    private fun queryUsageStats(start: Long, end: Long): List<Map<String, Any?>> {
        val manager = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        val packageManager = applicationContext.packageManager
        val installedLabels = labelCache ?: installedAppLabels(packageManager).also {
            labelCache = it
        }
        return manager.queryAndAggregateUsageStats(start, end)
            .values
            .asSequence()
            .filter { it.totalTimeInForeground > 0 && it.packageName != packageName }
            .sortedByDescending { it.totalTimeInForeground }
            .take(50)
            .mapIndexed { index, stats ->
                val label = installedLabels[stats.packageName] ?: try {
                    val info = packageManager.getApplicationInfo(stats.packageName, 0)
                    packageManager.getApplicationLabel(info).toString()
                } catch (_: Exception) {
                    readablePackageName(stats.packageName)
                }
                mapOf(
                    "packageName" to stats.packageName,
                    "appName" to label,
                    "foregroundMs" to stats.totalTimeInForeground,
                    "lastTimeUsed" to stats.lastTimeUsed,
                    // Only the most relevant rows need icons. Remaining rows still
                    // contribute to totals without bloating the platform message.
                    "icon" to if (index < 20) appIcon(packageManager, stats.packageName) else null,
                )
            }
            .toList()
    }

    private fun launcherAppLabels(packageManager: PackageManager): Map<String, String> {
        val intent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        return packageManager.queryIntentActivities(intent, PackageManager.MATCH_ALL)
            .associate { resolveInfo ->
                resolveInfo.activityInfo.packageName to resolveInfo.loadLabel(packageManager).toString()
            }
    }

    private fun installedAppLabels(packageManager: PackageManager): Map<String, String> {
        @Suppress("DEPRECATION")
        val labels = packageManager.getInstalledApplications(0)
            .associate { applicationInfo ->
                applicationInfo.packageName to packageManager.getApplicationLabel(applicationInfo).toString()
            }
            .toMutableMap()
        // Some managed profiles expose launcher activities without including them in
        // the ordinary installed-application result.
        labels.putAll(launcherAppLabels(packageManager))
        return labels
    }

    private fun readablePackageName(packageName: String): String {
        val ignored = setOf("com", "org", "net", "android", "app", "apps", "mobile", "ph")
        val candidate = packageName.split('.')
            .lastOrNull { part -> part.length > 2 && part.lowercase() !in ignored }
            ?: packageName.substringAfterLast('.')
        return candidate.replaceFirstChar { character ->
            if (character.isLowerCase()) character.titlecase() else character.toString()
        }
    }

    private fun appIcon(packageManager: PackageManager, packageName: String): ByteArray? {
        iconCache.get(packageName)?.let { return it }
        return try {
            drawableToPng(packageManager.getApplicationIcon(packageName)).also {
                iconCache.put(packageName, it)
            }
        } catch (_: Exception) {
            null
        }
    }

    private fun drawableToPng(drawable: Drawable): ByteArray {
        // Adaptive icons commonly report an invalid intrinsic size. Drawing all
        // icon types onto a fixed canvas also keeps the platform-channel payload small.
        val size = 96
        val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888).also { bitmap ->
            val canvas = Canvas(bitmap)
            drawable.setBounds(0, 0, canvas.width, canvas.height)
            drawable.draw(canvas)
        }
        return ByteArrayOutputStream().use { stream ->
            bitmap.compress(Bitmap.CompressFormat.PNG, 100, stream)
            stream.toByteArray()
        }
    }
}
