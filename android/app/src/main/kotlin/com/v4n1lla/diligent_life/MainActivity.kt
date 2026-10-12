package com.v4n1lla.diligent_life

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.app.Activity
import android.content.Intent
import java.io.File

class MainActivity : FlutterActivity() {
    private var backupResult: MethodChannel.Result? = null
    private var exportPath: String? = null
    private var activityNotices: ActivityNotificationBridge? = null
    private val steps by lazy { StepBridge(this) }
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "diligent_life/home_widget")
            .setMethodCallHandler { call, result ->
                if (call.method == "publish") {
                    ActivityWidget.publish(this, call.arguments as? Map<*, *> ?: emptyMap<String, Any>())
                    result.success(null)
                } else if (call.method == "refresh") {
                    ActivityWidget.request(this, true)
                    result.success(null)
                } else result.notImplemented()
            }
        val notices = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "diligent_life/activity_notifications")
        activityNotices = ActivityNotificationBridge(this, notices).also { bridge ->
            notices.setMethodCallHandler { call, result -> bridge.handle(call.method, call.arguments, result) }
            bridge.accept(intent)
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "diligent_life/steps")
            .setMethodCallHandler { call, result -> steps.handle(call.method,result,call.argument<Number>("goal")?.toInt()) }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "diligent_life/gallery")
            .setMethodCallHandler { call, result ->
                if(call.method == "save") GalleryBridge.save(this,call,result) else result.notImplemented()
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "diligent_life/backup")
            .setMethodCallHandler { call, result ->
                if (backupResult != null) {
                    result.error("busy", "A document picker is already open", null)
                } else if (call.method == "save" || call.method == "pick") {
                    backupResult = result
                    exportPath = if (call.method == "save") call.argument<String>("path") else null
                    val intent = if (call.method == "save") {
                        Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                            type = "application/octet-stream"
                            putExtra(Intent.EXTRA_TITLE, call.argument<String>("name"))
                        }
                    } else Intent(Intent.ACTION_OPEN_DOCUMENT).apply { type = "*/*" }
                    intent.addCategory(Intent.CATEGORY_OPENABLE)
                    intent.putExtra(Intent.EXTRA_LOCAL_ONLY, true)
                    try { startActivityForResult(intent, 5105) }
                    catch (e: Exception) { backupResult = null; result.error("picker", e.message, null) }
                } else result.notImplemented()
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "diligent_life/lifecycle")
            .setMethodCallHandler { call, result ->
                if (call.method == "moveToBackground") {
                    moveTaskToBack(true)
                    result.success(null)
                } else {
                    result.notImplemented()
                }
            }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        activityNotices?.accept(intent)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode,permissions,grantResults)
        steps.permissionResult(requestCode)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != 5105) return
        val result = backupResult ?: return
        val source = exportPath
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            backupResult = null
            result.success(if (source == null) null else false)
            return
        }
        Thread {
            var temporary: File? = null
            try {
                val value: Any = if (source != null) {
                    contentResolver.openOutputStream(uri, "wt").use { output ->
                        requireNotNull(output)
                        File(source).inputStream().use { it.copyTo(output) }
                    }
                    true
                } else {
                    val file = File.createTempFile("diligent-import-", ".diligent", cacheDir)
                    temporary = file
                    contentResolver.openInputStream(uri).use { input ->
                        requireNotNull(input)
                        file.outputStream().use { input.copyTo(it) }
                    }
                    file.absolutePath
                }
                runOnUiThread { backupResult = null; result.success(value) }
            } catch (e: Exception) {
                temporary?.delete()
                runOnUiThread { backupResult = null; result.error("file", e.message, null) }
            }
        }.start()
    }
}
