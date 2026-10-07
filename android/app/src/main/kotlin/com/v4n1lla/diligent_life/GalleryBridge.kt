package com.v4n1lla.diligent_life

import android.app.Activity
import android.content.ContentValues
import android.os.Build
import android.provider.MediaStore
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

object GalleryBridge {
    fun save(activity: Activity, call: MethodCall, result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < 29) { result.error("unsupported", "Gallery save requires Android 10 or later", null); return }
        val bytes = call.argument<ByteArray>("bytes")
        if (bytes == null || bytes.size < 8 || bytes.size > 20_000_000) { result.error("image", "Invalid image", null); return }
        val name = (call.argument<String>("name") ?: "diligent-life.png").replace(Regex("[^a-zA-Z0-9_.-]"), "_").take(100)
        Thread {
            var uri: android.net.Uri? = null
            try {
                val values = ContentValues().apply {
                    put(MediaStore.Images.Media.DISPLAY_NAME, name)
                    put(MediaStore.Images.Media.MIME_TYPE, "image/png")
                    put(MediaStore.Images.Media.RELATIVE_PATH, "Pictures/Diligent Life")
                    put(MediaStore.Images.Media.IS_PENDING, 1)
                }
                val target = requireNotNull(activity.contentResolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values))
                uri = target
                requireNotNull(activity.contentResolver.openOutputStream(target)).use { it.write(bytes) }
                values.clear(); values.put(MediaStore.Images.Media.IS_PENDING,0)
                check(activity.contentResolver.update(target,values,null,null) == 1)
                activity.runOnUiThread { result.success(target.toString()) }
            } catch (e: Exception) {
                try { uri?.let { activity.contentResolver.delete(it,null,null) } } catch (_: Exception) { /* Preserve the original failure reply. */ }
                activity.runOnUiThread { result.error("gallery", "Image could not be saved", null) }
            }
        }.start()
    }
}
