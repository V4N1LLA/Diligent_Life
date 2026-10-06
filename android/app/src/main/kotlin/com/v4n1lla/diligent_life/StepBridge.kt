package com.v4n1lla.diligent_life

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.hardware.Sensor
import android.hardware.SensorManager
import android.os.Build
import android.provider.Settings
import android.net.Uri
import io.flutter.plugin.common.MethodChannel

class StepBridge(private val activity: Activity) {
    private var pending: MethodChannel.Result? = null
    private val prefs get() = activity.getSharedPreferences("daily_steps", Context.MODE_PRIVATE)
    fun status(): Map<String, Any?> = mapOf(
        "supported" to (activity.getSystemService(SensorManager::class.java).getDefaultSensor(Sensor.TYPE_STEP_COUNTER) != null),
        "permission" to StepTrackingService.allowed(activity), "enabled" to prefs.getBoolean("enabled",false),
        "running" to StepTrackingService.running, "error" to StepTrackingService.error)
    private fun start(result: MethodChannel.Result) {
        try {
            if (status()["supported"] != true) { result.error("unsupported", "Step counter unavailable", null); return }
            StepTrackingService.start(activity)
            prefs.edit().putBoolean("enabled",true).apply()
            result.success(null)
        } catch (e: Exception) { result.error("steps", "Step service could not start", null) }
    }
    fun handle(method: String, result: MethodChannel.Result) {
        when(method) {
            "status" -> result.success(status())
            "settings" -> { activity.startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:${activity.packageName}"))); result.success(null) }
            "restore" -> {
                if (prefs.getBoolean("enabled",false) && StepTrackingService.allowed(activity)) start(result)
                else result.success(null)
            }
            "enable" -> {
                if (pending != null) { result.error("busy", "Permission request pending", null); return }
                if (Build.VERSION.SDK_INT >= 29 && !StepTrackingService.allowed(activity)) {
                    pending = result; activity.requestPermissions(arrayOf(Manifest.permission.ACTIVITY_RECOGNITION), 141)
                } else start(result)
            }
            "disable" -> {
                prefs.edit().putBoolean("enabled",false).putBoolean("rebase",true).apply()
                activity.stopService(Intent(activity,StepTrackingService::class.java))
                result.success(null)
            }
            "flush" -> StepTrackingService.flush { ok -> if (ok) result.success(null) else result.error("storage", "Could not store steps", null) }
            "suspend" -> StepTrackingService.pauseRecording { ok -> if (ok) result.success(null) else result.error("storage", "Could not pause steps", null) }
            "resume" -> { StepTrackingService.resume(); result.success(null) }
            else -> result.notImplemented()
        }
    }
    fun permissionResult(code: Int) {
        if (code != 141) return
        val result = pending ?: return
        pending = null
        if (StepTrackingService.allowed(activity)) start(result) else result.success(null)
    }
}
