package com.posflutter.pos_app

import android.app.Activity
import android.content.Intent
import android.database.Cursor
import android.net.Uri
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {
    companion object {
        private const val BACKUP_CHANNEL = "com.posflutter.pos_app/backup_saf"
        private const val PRODUCT_IMPORT_CHANNEL =
            "com.posflutter.pos_app/product_import_saf"

        private const val REQUEST_SAVE_BACKUP = 41001
        private const val REQUEST_PICK_BACKUP = 41002
        private const val REQUEST_PICK_CATALOG = 41003

        private const val MAX_CATALOG_BYTES = 20 * 1024 * 1024
    }

    private var pendingResult: MethodChannel.Result? = null
    private var pendingBackupBytes: ByteArray? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            BACKUP_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "saveBackup" -> handleSaveBackup(call, result)
                "pickBackup" -> handlePickBackup(result)
                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            PRODUCT_IMPORT_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "pickCatalogFile" -> handlePickCatalog(result)
                else -> result.notImplemented()
            }
        }
    }

    private fun handleSaveBackup(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        if (!reserveResult(result)) {
            return
        }

        val fileName = call.argument<String>("fileName")
        val bytes = call.argument<ByteArray>("bytes")

        if (fileName.isNullOrBlank() || bytes == null || bytes.isEmpty()) {
            clearPending()
            result.error(
                "INVALID_ARGUMENTS",
                "El nombre o contenido del respaldo es inválido.",
                null,
            )
            return
        }

        pendingBackupBytes = bytes

        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "application/octet-stream"
            putExtra(Intent.EXTRA_TITLE, fileName)
        }

        launchPicker(
            intent,
            REQUEST_SAVE_BACKUP,
            result,
            "SAVE_PICKER_ERROR",
            "No fue posible abrir el selector para guardar el respaldo.",
        )
    }

    private fun handlePickBackup(result: MethodChannel.Result) {
        if (!reserveResult(result)) {
            return
        }

        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "application/octet-stream"
        }

        launchPicker(
            intent,
            REQUEST_PICK_BACKUP,
            result,
            "RESTORE_PICKER_ERROR",
            "No fue posible abrir el selector de respaldos.",
        )
    }

    private fun handlePickCatalog(result: MethodChannel.Result) {
        if (!reserveResult(result)) {
            return
        }

        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "*/*"
            putExtra(
                Intent.EXTRA_MIME_TYPES,
                arrayOf(
                    "text/csv",
                    "text/comma-separated-values",
                    "application/csv",
                    "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
                    "application/octet-stream",
                ),
            )
        }

        launchPicker(
            intent,
            REQUEST_PICK_CATALOG,
            result,
            "CATALOG_PICKER_ERROR",
            "No fue posible abrir el selector de archivos de catálogo.",
        )
    }

    private fun launchPicker(
        intent: Intent,
        requestCode: Int,
        result: MethodChannel.Result,
        errorCode: String,
        errorMessage: String,
    ) {
        try {
            startActivityForResult(intent, requestCode)
        } catch (exception: Exception) {
            clearPending()
            result.error(
                errorCode,
                errorMessage,
                exception.message,
            )
        }
    }

    private fun reserveResult(result: MethodChannel.Result): Boolean {
        if (pendingResult != null) {
            result.error(
                "OPERATION_IN_PROGRESS",
                "Ya existe una operación de archivo en curso.",
                null,
            )
            return false
        }

        pendingResult = result
        return true
    }

    override fun onActivityResult(
        requestCode: Int,
        resultCode: Int,
        data: Intent?,
    ) {
        if (
            requestCode != REQUEST_SAVE_BACKUP &&
            requestCode != REQUEST_PICK_BACKUP &&
            requestCode != REQUEST_PICK_CATALOG
        ) {
            super.onActivityResult(requestCode, resultCode, data)
            return
        }

        val result = pendingResult

        if (result == null) {
            clearPending()
            return
        }

        if (resultCode != Activity.RESULT_OK) {
            clearPending()
            result.success(null)
            return
        }

        val uri = data?.data

        if (uri == null) {
            clearPending()
            result.error(
                "MISSING_URI",
                "Android no devolvió el documento seleccionado.",
                null,
            )
            return
        }

        when (requestCode) {
            REQUEST_SAVE_BACKUP -> completeSave(uri, result)
            REQUEST_PICK_BACKUP -> completeBackupPick(uri, result)
            REQUEST_PICK_CATALOG -> completeCatalogPick(uri, result)
        }
    }

    private fun completeSave(
        uri: Uri,
        result: MethodChannel.Result,
    ) {
        val bytes = pendingBackupBytes

        if (bytes == null || bytes.isEmpty()) {
            clearPending()
            result.error(
                "MISSING_BACKUP_BYTES",
                "No existe contenido de respaldo pendiente.",
                null,
            )
            return
        }

        try {
            contentResolver.openOutputStream(uri, "w").use { output ->
                requireNotNull(output) {
                    "No fue posible abrir el documento para escritura."
                }

                output.write(bytes)
                output.flush()
            }

            clearPending()
            result.success(uri.toString())
        } catch (exception: Exception) {
            clearPending()
            result.error(
                "SAVE_FAILED",
                "No fue posible guardar el respaldo seleccionado.",
                exception.message,
            )
        }
    }

    private fun completeBackupPick(
        uri: Uri,
        result: MethodChannel.Result,
    ) {
        var temporaryFile: File? = null

        try {
            val displayName = queryDisplayName(uri)
                ?: "backup_${System.currentTimeMillis()}.db"

            val safeName = sanitizeFileName(displayName, "backup.db")

            temporaryFile = File(
                cacheDir,
                "picked_${System.currentTimeMillis()}_$safeName",
            )

            contentResolver.openInputStream(uri).use { input ->
                requireNotNull(input) {
                    "No fue posible abrir el respaldo seleccionado."
                }

                FileOutputStream(temporaryFile).use { output ->
                    input.copyTo(output)
                    output.flush()
                }
            }

            if (!temporaryFile.exists() || temporaryFile.length() <= 0L) {
                temporaryFile.delete()
                clearPending()
                result.error(
                    "EMPTY_BACKUP",
                    "El respaldo seleccionado está vacío.",
                    null,
                )
                return
            }

            val payload = hashMapOf<String, Any>(
                "name" to safeName,
                "path" to temporaryFile.absolutePath,
            )

            clearPending()
            result.success(payload)
        } catch (exception: Exception) {
            temporaryFile?.delete()
            clearPending()
            result.error(
                "READ_FAILED",
                "No fue posible leer el respaldo seleccionado.",
                exception.message,
            )
        }
    }

    private fun completeCatalogPick(
        uri: Uri,
        result: MethodChannel.Result,
    ) {
        try {
            val displayName = queryDisplayName(uri)
                ?: throw IllegalArgumentException(
                    "El archivo seleccionado no tiene un nombre válido.",
                )

            val safeName = sanitizeFileName(displayName, "catalog")
            val extension = safeName
                .substringAfterLast('.', "")
                .lowercase()

            if (extension != "csv" && extension != "xlsx") {
                clearPending()
                result.error(
                    "INVALID_CATALOG_TYPE",
                    "Solo se permiten archivos CSV o XLSX.",
                    null,
                )
                return
            }

            val bytes = contentResolver.openInputStream(uri).use { input ->
                requireNotNull(input) {
                    "No fue posible abrir el archivo seleccionado."
                }

                val output = ByteArrayOutputStream()
                val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
                var total = 0

                while (true) {
                    val read = input.read(buffer)

                    if (read < 0) {
                        break
                    }

                    total += read

                    if (total > MAX_CATALOG_BYTES) {
                        throw IllegalArgumentException(
                            "El archivo seleccionado supera el límite de 20 MB.",
                        )
                    }

                    output.write(buffer, 0, read)
                }

                output.toByteArray()
            }

            if (bytes.isEmpty()) {
                clearPending()
                result.error(
                    "EMPTY_CATALOG",
                    "El archivo seleccionado está vacío.",
                    null,
                )
                return
            }

            val payload = hashMapOf<String, Any>(
                "name" to safeName,
                "bytes" to bytes,
            )

            clearPending()
            result.success(payload)
        } catch (exception: IllegalArgumentException) {
            clearPending()
            result.error(
                "INVALID_CATALOG",
                exception.message ?: "El archivo seleccionado no es válido.",
                null,
            )
        } catch (exception: Exception) {
            clearPending()
            result.error(
                "CATALOG_READ_FAILED",
                "No fue posible leer el archivo seleccionado.",
                exception.message,
            )
        }
    }

    private fun queryDisplayName(uri: Uri): String? {
        var cursor: Cursor? = null

        return try {
            cursor = contentResolver.query(
                uri,
                arrayOf(OpenableColumns.DISPLAY_NAME),
                null,
                null,
                null,
            )

            if (cursor != null && cursor.moveToFirst()) {
                val index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)

                if (index >= 0) {
                    cursor.getString(index)
                } else {
                    null
                }
            } else {
                null
            }
        } finally {
            cursor?.close()
        }
    }

    private fun sanitizeFileName(
        name: String,
        fallback: String,
    ): String {
        val sanitized = name
            .substringAfterLast('/')
            .substringAfterLast('\\')
            .replace(Regex("[^A-Za-z0-9._-]"), "_")
            .take(120)

        return if (sanitized.isBlank()) {
            fallback
        } else {
            sanitized
        }
    }

    private fun clearPending() {
        pendingResult = null
        pendingBackupBytes = null
    }
}