package com.keshabstudios.khorochdiary

import android.app.Activity
import android.content.Intent
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream

/** Storage Access Framework: the user explicitly chooses every file location. */
class MainActivity : FlutterActivity() {
    private val channelName = "com.keshabstudios.khorochdiary/backup_files"
    private val maxBytes = 10 * 1024 * 1024
    private val openRequest = 7811
    private val saveRequest = 7812
    private var pending: MethodChannel.Result? = null
    private var exportBytes: ByteArray? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).setMethodCallHandler { call, result ->
            if (pending != null) {
                result.error("busy", "Another file operation is in progress.", null)
                return@setMethodCallHandler
            }
            val intent: Intent
            val request: Int
            when (call.method) {
                "pick" -> {
                    intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                        addCategory(Intent.CATEGORY_OPENABLE)
                        type = "application/json"
                        putExtra(Intent.EXTRA_MIME_TYPES, arrayOf("application/json", "text/plain", "application/octet-stream"))
                    }
                    request = openRequest
                }
                "save" -> {
                    val bytes = call.argument<ByteArray>("bytes")
                    if (bytes == null || bytes.size > maxBytes) {
                        result.error("invalid", "Backup is too large or invalid.", null)
                        return@setMethodCallHandler
                    }
                    exportBytes = bytes
                    intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                        addCategory(Intent.CATEGORY_OPENABLE)
                        type = "application/json"
                        putExtra(Intent.EXTRA_TITLE, "khoroch-diary-backup.json")
                    }
                    request = saveRequest
                }
                else -> { result.notImplemented(); return@setMethodCallHandler }
            }
            pending = result
            try {
                @Suppress("DEPRECATION")
                startActivityForResult(intent, request)
            } catch (_: Exception) {
                pending = null
                exportBytes = null
                result.error("picker", "Unable to open the file chooser.", null)
            }
        }
    }

    @Deprecated("Android activity result API used for Flutter activity compatibility")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != openRequest && requestCode != saveRequest) return
        val callback = pending ?: return
        val bytes = exportBytes
        if (resultCode != Activity.RESULT_OK || data?.data == null) {
            pending = null
            exportBytes = null
            callback.success(null)
            return
        }
        val uri = data.data!!
        // Run provider I/O off the UI thread and hold pending until completion.
        Thread {
            try {
                val value: Any = if (requestCode == openRequest) {
                    contentResolver.openInputStream(uri)?.use { input ->
                        val output = ByteArrayOutputStream()
                        val buffer = ByteArray(8192)
                        var total = 0
                        while (true) {
                            val read = input.read(buffer)
                            if (read < 0) break
                            total += read
                            if (total > maxBytes) throw IllegalArgumentException("File too large")
                            output.write(buffer, 0, read)
                        }
                        output.toByteArray()
                    } ?: throw IllegalStateException("File unavailable")
                } else {
                    val content = bytes ?: throw IllegalStateException("Missing data")
                    contentResolver.openOutputStream(uri, "wt")?.use { it.write(content); it.flush() }
                        ?: throw IllegalStateException("File unavailable")
                    true
                }
                mainHandler.post { pending = null; exportBytes = null; callback.success(value) }
            } catch (_: Exception) {
                mainHandler.post { pending = null; exportBytes = null; callback.error("file", "Unable to read or write the selected file.", null) }
            }
        }.start()
    }
}
