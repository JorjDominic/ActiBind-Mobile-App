package com.example.actibind

import android.accessibilityservice.AccessibilityService
import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.view.accessibility.AccessibilityEvent
import android.widget.Toast

class ChildModeAccessibilityService : AccessibilityService() {
    private var redirectInFlight = false
    private val mainHandler = Handler(Looper.getMainLooper())
    private val releaseRedirectGuard = Runnable { redirectInFlight = false }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event == null || (
                event.eventType != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED &&
                    event.eventType != AccessibilityEvent.TYPE_WINDOWS_CHANGED
            )
        ) return
        val openedPackage = event.packageName?.toString() ?: return
        if (openedPackage == packageName) {
            // The protected activity is visible again, so a subsequent Home or
            // Recents press must be handled immediately rather than being dropped
            // by a fixed debounce window.
            mainHandler.removeCallbacks(releaseRedirectGuard)
            redirectInFlight = false
            return
        }

        val preferences = getSharedPreferences("actibind_child_mode", Context.MODE_PRIVATE)
        if (!preferences.getBoolean("personal_mode_active", false)) return
        val allowed = preferences.getStringSet("allowed_packages", emptySet()).orEmpty()
        if (openedPackage in allowed) return
        val restricted = preferences.getStringSet("restricted_packages", emptySet()).orEmpty()
        if (openedPackage !in restricted) return

        // Window-change events often arrive in bursts for one exit. Suppress only
        // while the redirect is pending; seeing ActiBind above releases the guard.
        if (redirectInFlight) return
        redirectInFlight = true
        // Fallback in case an OEM does not emit ActiBind's window event after the
        // activity launch or silently rejects the background start.
        mainHandler.postDelayed(releaseRedirectGuard, 1_000)

        try {
            startActivity(Intent(this, MainActivity::class.java).apply {
                addFlags(
                    Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_CLEAR_TOP or
                        Intent.FLAG_ACTIVITY_REORDER_TO_FRONT or
                        Intent.FLAG_ACTIVITY_SINGLE_TOP,
                )
                putExtra("blocked_package", openedPackage)
            })
        } catch (_: Exception) {
            // Do not leave the guard latched if Android rejects a background
            // activity start; the next accessibility event should retry.
            mainHandler.removeCallbacks(releaseRedirectGuard)
            redirectInFlight = false
            return
        }
        Toast.makeText(this, "This app is restricted in Child Mode", Toast.LENGTH_SHORT).show()
    }

    override fun onInterrupt() = Unit
}
