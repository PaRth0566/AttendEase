package com.parthm.attendease

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.OpenableColumns
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val updateChannel = "com.parthm.attendease/update_installer"
    private val incomingPdfChannel = "com.parthm.attendease/incoming_pdf"

    /** The channel Dart listens on, once the engine is up. Null before that. */
    private var incomingPdf: MethodChannel? = null

    /**
     * A PDF read from an intent that Dart has not collected yet.
     *
     * Cold start needs this: the launch intent is delivered in onCreate, well
     * before configureFlutterEngine runs, so there is nobody to push it to. Dart
     * pulls it with getInitialPdf instead, which clears the field — otherwise a
     * later resume would replay the same import.
     */
    private var pendingPdf: Map<String, Any?>? = null

    /**
     * Cap on an incoming file. A semester report is a few hundred KB; anything
     * past this is not one, and reading it into a byte array to hand across the
     * channel would be the expensive way to find that out.
     */
    private val maxPdfBytes = 25L * 1024 * 1024

    private companion object {
        /** Marks an intent whose PDF has already been handed to Dart. */
        const val EXTRA_PDF_CONSUMED = "com.parthm.attendease.PDF_CONSUMED"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, updateChannel)
            .setMethodCallHandler { call, result ->
                if (call.method != "installApk") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val path = call.argument<String>("path")
                if (path.isNullOrBlank()) {
                    result.error("INVALID_PATH", "The downloaded APK path is missing.", null)
                    return@setMethodCallHandler
                }
                try {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                        !packageManager.canRequestPackageInstalls()
                    ) {
                        startActivity(
                            Intent(
                                Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                                Uri.parse("package:$packageName")
                            )
                        )
                        result.error(
                            "INSTALL_PERMISSION_REQUIRED",
                            "Allow AttendEase to install updates, then tap Update again.",
                            null
                        )
                        return@setMethodCallHandler
                    }
                    val apk = File(path)
                    if (!apk.exists() || apk.length() == 0L) {
                        result.error("APK_MISSING", "The downloaded update file is missing.", null)
                        return@setMethodCallHandler
                    }
                    val uri = FileProvider.getUriForFile(
                        this,
                        "$packageName.update_provider",
                        apk
                    )
                    val intent = Intent(Intent.ACTION_VIEW).apply {
                        setDataAndType(uri, "application/vnd.android.package-archive")
                        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    }
                    startActivity(intent)
                    result.success(true)
                } catch (error: Exception) {
                    result.error("INSTALL_FAILED", "Android could not open the update installer.", null)
                }
            }

        incomingPdf =
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, incomingPdfChannel).apply {
                setMethodCallHandler { call, result ->
                    when (call.method) {
                        "getInitialPdf" -> {
                            result.success(pendingPdf)
                            pendingPdf = null
                        }
                        else -> result.notImplemented()
                    }
                }
            }

        // The launch intent. Parked rather than pushed: this runs during
        // onCreate, so Dart's main() has not registered its handler yet and a
        // push here would land on nobody. Dart pulls it with getInitialPdf.
        consumeIntent(intent, push = false)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        // singleTop: a PDF tapped while AttendEase is already running lands here
        // rather than in a new instance. Dart is listening by now, so push.
        setIntent(intent)
        consumeIntent(intent, push = true)
    }

    /**
     * Pulls a PDF out of [intent] and either pushes it to Dart or parks it for
     * the next getInitialPdf.
     *
     * The read happens now, not on demand: the read permission the chooser
     * grants is scoped to this intent's delivery, so deferring it until Dart
     * asks is how a content:// URI turns into a SecurityException.
     */
    private fun consumeIntent(intent: Intent?, push: Boolean) {
        if (intent == null) return
        // The activity holds onto its intent, so a recreated activity — process
        // death, or any configuration change that outlives the portrait lock —
        // would read the same URI a second time and prompt to import a report
        // the user already dealt with. Mark it instead.
        if (intent.getBooleanExtra(EXTRA_PDF_CONSUMED, false)) return
        val uri = extractPdfUri(intent) ?: return
        intent.putExtra(EXTRA_PDF_CONSUMED, true)
        val payload = readPdf(uri) ?: return
        val channel = incomingPdf
        if (push && channel != null) {
            channel.invokeMethod("onPdfReceived", payload)
        } else {
            pendingPdf = payload
        }
    }

    private fun extractPdfUri(intent: Intent?): Uri? {
        if (intent == null) return null
        return when (intent.action) {
            Intent.ACTION_VIEW -> intent.data
            Intent.ACTION_SEND ->
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
                } else {
                    @Suppress("DEPRECATION")
                    intent.getParcelableExtra(Intent.EXTRA_STREAM)
                }
            Intent.ACTION_SEND_MULTIPLE -> {
                val list = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM, Uri::class.java)
                } else {
                    @Suppress("DEPRECATION")
                    intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)
                }
                // One report at a time — merging several has semantics of its own.
                list?.firstOrNull()
            }
            else -> null
        }
    }

    /**
     * Reads [uri] into a byte array plus its display name, or null if it cannot
     * be read. A failure is reported as "nothing arrived" rather than a crash:
     * the user tapped a file, and an unreadable one is a normal outcome.
     */
    private fun readPdf(uri: Uri): Map<String, Any?>? {
        return try {
            val size = querySize(uri)
            if (size != null && size > maxPdfBytes) return null
            val bytes = contentResolver.openInputStream(uri)?.use { it.readBytes() }
                ?: return null
            if (bytes.isEmpty() || bytes.size > maxPdfBytes) return null
            // Trust the bytes, not the name or the declared type. WhatsApp and
            // Drive hand over opaque URIs with no .pdf anywhere in them
            // (content://com.whatsapp.provider.media/item/4eb68bb2-...), so the
            // file's own header is the only reliable way to tell a PDF from
            // whatever else the broad intent filters let through. Anything that
            // is not a PDF is dropped here rather than reaching the parser and
            // becoming a confusing "can't read this" dialog the user did not ask
            // for.
            if (!looksLikePdf(bytes)) return null
            mapOf("bytes" to bytes, "name" to (queryName(uri) ?: "report.pdf"))
        } catch (error: Exception) {
            null
        }
    }

    /** Whether [bytes] starts with the PDF magic number, `%PDF-`. */
    private fun looksLikePdf(bytes: ByteArray): Boolean {
        val magic = byteArrayOf(0x25, 0x50, 0x44, 0x46, 0x2D) // %PDF-
        if (bytes.size < magic.size) return false
        // Some producers pad with junk before the header, so scan a short
        // prefix rather than insisting it sits at offset zero.
        val limit = minOf(bytes.size - magic.size, 1024)
        for (start in 0..limit) {
            if (magic.indices.all { bytes[start + it] == magic[it] }) return true
        }
        return false
    }

    private fun querySize(uri: Uri): Long? = queryColumn(uri, OpenableColumns.SIZE) {
        if (it.isNull(0)) null else it.getLong(0)
    }

    private fun queryName(uri: Uri): String? = queryColumn(uri, OpenableColumns.DISPLAY_NAME) {
        if (it.isNull(0)) null else it.getString(0)
    } ?: uri.lastPathSegment?.substringAfterLast('/')

    private fun <T> queryColumn(
        uri: Uri,
        column: String,
        read: (android.database.Cursor) -> T?,
    ): T? = try {
        contentResolver.query(uri, arrayOf(column), null, null, null)?.use { cursor ->
            if (cursor.moveToFirst()) read(cursor) else null
        }
    } catch (error: Exception) {
        null
    }
}
