package com.example.actibind

import android.app.Activity
import android.app.ActivityManager
import android.app.ActivityOptions
import android.app.admin.DevicePolicyManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import android.provider.Settings
import android.text.TextUtils
import android.graphics.Bitmap
import android.graphics.Canvas
import java.io.ByteArrayOutputStream

class ChildModePolicyManager(private val activity: Activity) {
    private val dpm = activity.getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
    private val admin = ComponentName(activity, ActiBindDeviceAdminReceiver::class.java)
    private val preferences = activity.getSharedPreferences("actibind_child_mode", Context.MODE_PRIVATE)

    fun capabilities(): Map<String, Any> {
        val owner = dpm.isDeviceOwnerApp(activity.packageName)
        val profileOwner = dpm.isProfileOwnerApp(activity.packageName)
        return mapOf(
            "isDeviceOwner" to owner,
            "isProfileOwner" to profileOwner,
            "isAdminActive" to dpm.isAdminActive(admin),
            "canSuspendPackages" to (owner || profileOwner),
            "canUseLockTask" to (owner || isLockTaskPermitted()),
            "isInLockTask" to isInLockTask(),
            "isAccessibilityEnabled" to isAccessibilityEnabled(),
        )
    }

    fun requestAdmin() {
        activity.startActivity(
            Intent(DevicePolicyManager.ACTION_ADD_DEVICE_ADMIN).apply {
                putExtra(DevicePolicyManager.EXTRA_DEVICE_ADMIN, admin)
                putExtra(
                    DevicePolicyManager.EXTRA_ADD_EXPLANATION,
                    "ActiBind uses device administration for parent-approved Child Mode controls.",
                )
            },
        )
    }

    fun openDeviceAdminSettings() {
        activity.startActivity(Intent(Settings.ACTION_SECURITY_SETTINGS))
    }

    fun openAccessibilitySettings() {
        activity.startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
    }

    fun installedApps(): List<Map<String, Any?>> {
        val packageManager = activity.packageManager
        val launcherIntent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        return packageManager.queryIntentActivities(launcherIntent, 0)
            .asSequence()
            .filter { it.activityInfo.packageName != activity.packageName }
            .distinctBy { it.activityInfo.packageName }
            .sortedBy { it.loadLabel(packageManager).toString().lowercase() }
            .map { info ->
                mapOf(
                    "packageName" to info.activityInfo.packageName,
                    "name" to info.loadLabel(packageManager).toString(),
                    "icon" to try {
                        val drawable = info.loadIcon(packageManager)
                        val size = 72
                        val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
                        drawable.setBounds(0, 0, size, size)
                        drawable.draw(Canvas(bitmap))
                        ByteArrayOutputStream().use { stream ->
                            bitmap.compress(Bitmap.CompressFormat.PNG, 90, stream)
                            stream.toByteArray()
                        }
                    } catch (_: Exception) {
                        null
                    },
                )
            }
            .toList()
    }

    fun start(restrictedPackages: List<String>, allowedPackages: List<String>): Map<String, Any> {
        val owner = dpm.isDeviceOwnerApp(activity.packageName)
        val profileOwner = dpm.isProfileOwnerApp(activity.packageName)
        val managed = owner || profileOwner
        val suspended = mutableListOf<String>()
        val failed = mutableListOf<String>()

        if (managed && Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            restrictedPackages
                .filter { it != activity.packageName }
                .forEach { packageName ->
                    try {
                        val failures = dpm.setPackagesSuspended(admin, arrayOf(packageName), true)
                        if (failures.isEmpty()) suspended.add(packageName) else failed.add(packageName)
                    } catch (_: Exception) {
                        failed.add(packageName)
                    }
                }
        } else {
            failed.addAll(restrictedPackages)
        }
        preferences.edit().putStringSet("suspended_packages", suspended.toSet()).apply()
        preferences.edit()
            .putBoolean("personal_mode_active", !managed)
            .putStringSet("allowed_packages", allowedPackages.toSet())
            .putStringSet(
                "restricted_packages",
                if (managed) restrictedPackages.toSet()
                else (restrictedPackages + homePackage() + SYSTEM_UI_PACKAGES)
                    .filter { it.isNotBlank() }
                    .toSet(),
            )
            .apply()

        var lockTaskStarted = false
        if (managed) {
            try {
                try {
                    dpm.setLockTaskPackages(
                        admin,
                        (allowedPackages + activity.packageName).distinct().toTypedArray(),
                    )
                } catch (_: SecurityException) {
                    // Some unaffiliated profile owners cannot configure lock task.
                }
                activity.startLockTask()
                lockTaskStarted = true
            } catch (_: Exception) {
                // The managed device does not support the requested lock-task policy.
            }
        }

        val personalProtection = !managed && isAccessibilityEnabled()

        return mapOf(
            "applied" to (lockTaskStarted || suspended.isNotEmpty() || personalProtection),
            "lockTaskStarted" to lockTaskStarted,
            "suspendedPackages" to suspended,
            "failedPackages" to failed,
            "message" to when {
                managed -> "Child Mode started with managed-device policies."
                personalProtection -> "Personal Device Protection started. Restricted apps will return to ActiBind."
                else -> "Device restrictions could not be applied. Device Owner or Profile Owner provisioning is required."
            },
        )
    }

    fun launchApp(packageName: String): Boolean {
        val intent = activity.packageManager.getLaunchIntentForPackage(packageName) ?: return false
        val managed = dpm.isDeviceOwnerApp(activity.packageName) || dpm.isProfileOwnerApp(activity.packageName)
        if (managed && !dpm.isLockTaskPermitted(packageName)) return false
        if (!managed && !isAccessibilityEnabled()) return false
        return try {
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            if (managed && Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                val options = ActivityOptions.makeBasic().setLockTaskEnabled(true)
                activity.startActivity(intent, options.toBundle())
            } else {
                activity.startActivity(intent)
            }
            true
        } catch (_: Exception) {
            false
        }
    }

    fun stop(restrictedPackages: List<String>): Map<String, Any> {
        val managed = dpm.isDeviceOwnerApp(activity.packageName) || dpm.isProfileOwnerApp(activity.packageName)
        val packagesToRelease = (restrictedPackages +
            preferences.getStringSet("suspended_packages", emptySet()).orEmpty()).distinct()
        if (managed && Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            try {
                dpm.setPackagesSuspended(admin, packagesToRelease.toTypedArray(), false)
            } catch (_: Exception) {
                // Continue so lock task can still be released.
            }
        }
        preferences.edit().remove("suspended_packages").apply()
        preferences.edit()
            .remove("personal_mode_active")
            .remove("allowed_packages")
            .remove("restricted_packages")
            .apply()
        try {
            activity.stopLockTask()
        } catch (_: Exception) {
            // The task was not pinned.
        }
        return mapOf("applied" to true, "message" to "Child Mode restrictions were released.")
    }

    private fun isLockTaskPermitted(): Boolean = dpm.isLockTaskPermitted(activity.packageName)

    private fun isInLockTask(): Boolean {
        val manager = activity.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            manager.lockTaskModeState != ActivityManager.LOCK_TASK_MODE_NONE
        } else {
            @Suppress("DEPRECATION") manager.isInLockTaskMode
        }
    }

    private fun isAccessibilityEnabled(): Boolean {
        val expected = ComponentName(activity, ChildModeAccessibilityService::class.java).flattenToString()
        val enabled = Settings.Secure.getString(
            activity.contentResolver,
            Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES,
        ) ?: return false
        return enabled.split(':').any { TextUtils.equals(it, expected) }
    }

    private fun homePackage(): String {
        val intent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME)
        return activity.packageManager.resolveActivity(intent, 0)?.activityInfo?.packageName.orEmpty()
    }

    private companion object {
        // Recents/Overview and the notification shade are hosted by System UI on
        // Android builds. Treating these surfaces as protected closes the common
        // escape path that does not produce a launcher-package accessibility event.
        val SYSTEM_UI_PACKAGES = setOf("com.android.systemui")
    }
}
