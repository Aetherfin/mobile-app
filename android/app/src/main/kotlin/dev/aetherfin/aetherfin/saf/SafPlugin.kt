package dev.aetherfin.aetherfin.saf

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.provider.DocumentsContract
import android.util.Log

import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import kotlinx.coroutines.*

/**
 * Platform channel for SAF (Storage Access Framework) operations.
 *
 * Methods:
 *   pickFolder()       → String? (tree URI)
 *   listAudioFiles(uri) → List<Map> (uri, name, size, lastModified)
 *   readMetadata(uri)  → Map (title, artist, album, etc.)
 *   readCoverArt(uri)  → ByteArray? (embedded cover art)
 */
class SafPlugin : FlutterPlugin, MethodChannel.MethodCallHandler,
    ActivityAware, PluginRegistry.ActivityResultListener {

    private lateinit var channel: MethodChannel
    private var activity: Activity? = null
    private lateinit var appContext: Context
    private var pendingResult: MethodChannel.Result? = null
    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())

    companion object {
        private const val CHANNEL = "aetherfin.saf"
        private const val PICK_FOLDER_REQUEST = 9001
        private const val PICK_FILE_REQUEST = 9002
        private val AUDIO_EXTENSIONS = setOf(
            "mp3", "flac", "opus", "ogg", "m4a", "wav", "aac", "wma",
            "alac", "aiff", "ape", "wv", "dsf", "dff"
        )
        private val IMAGE_EXTENSIONS = setOf(
            "jpg", "jpeg", "png", "webp", "bmp", "gif"
        )
        // Common album artwork filenames (lowercase, without extension)
        private val COVER_NAMES = setOf(
            "cover", "folder", "front", "album", "albumart",
            "albumartsmall", "thumb", "thumbnail", "art", "image"
        )
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        appContext = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, CHANNEL)
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        scope.cancel()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "pickFolder" -> pickFolder(result)
            "listAudioFiles" -> {
                val uri = call.argument<String>("uri")
                    ?: return result.error("INVALID_ARG", "uri required", null)
                scope.launch {
                    try {
                        val files = listAudioFiles(uri)
                        withContext(Dispatchers.Main) { result.success(files) }
                    } catch (e: Exception) {
                        withContext(Dispatchers.Main) {
                            result.error("SCAN_ERROR", e.message, null)
                        }
                    }
                }
            }
            "readMetadata" -> {
                val uri = call.argument<String>("uri")
                    ?: return result.error("INVALID_ARG", "uri required", null)
                scope.launch {
                    try {
                        val meta = readMetadata(uri)
                        withContext(Dispatchers.Main) { result.success(meta) }
                    } catch (e: Exception) {
                        withContext(Dispatchers.Main) {
                            result.error("META_ERROR", e.message, null)
                        }
                    }
                }
            }
            "readCoverArt" -> {
                val uri = call.argument<String>("uri")
                    ?: return result.error("INVALID_ARG", "uri required", null)
                scope.launch {
                    try {
                        val art = readCoverArt(uri)
                        withContext(Dispatchers.Main) { result.success(art) }
                    } catch (e: Exception) {
                        Log.e("SafPlugin", "readCoverArt handler error: ${e.message}", e)
                        withContext(Dispatchers.Main) { result.success(null) }
                    }
                }
            }
            "readLyrics" -> {
                val uri = call.argument<String>("uri")
                    ?: return result.error("INVALID_ARG", "uri required", null)
                scope.launch {
                    try {
                        val lyrics = readLyrics(uri)
                        withContext(Dispatchers.Main) { result.success(lyrics) }
                    } catch (e: java.lang.Exception) {
                        withContext(Dispatchers.Main) {
                            result.error("LYRICS_ERROR", e.message, null)
                        }
                    }
                }
            }
            "pickAndReadLrcFile" -> {
                pickFile(result)
            }
            "saveSidecarLrc" -> {
                val uri = call.argument<String>("uri")
                    ?: return result.error("INVALID_ARG", "uri required", null)
                val content = call.argument<String>("content")
                    ?: return result.error("INVALID_ARG", "content required", null)
                scope.launch {
                    try {
                        val success = saveSidecarLrc(uri, content)
                        withContext(Dispatchers.Main) { result.success(success) }
                    } catch (e: java.lang.Exception) {
                        withContext(Dispatchers.Main) {
                            result.error("WRITE_ERROR", e.message, null)
                        }
                    }
                }
            }
            "listFilesInParentFolder" -> {
                val uri = call.argument<String>("uri")
                    ?: return result.error("INVALID_ARG", "uri required", null)
                scope.launch {
                    try {
                        val files = listFilesInParentFolder(uri)
                        withContext(Dispatchers.Main) { result.success(files) }
                    } catch (e: Exception) {
                        withContext(Dispatchers.Main) {
                            result.error("LIST_ERROR", e.message, null)
                        }
                    }
                }
            }
            else -> result.notImplemented()
        }
    }

    // ── Folder picker ─────────────────────────────────────────────────────

    private fun pickFolder(result: MethodChannel.Result) {
        val act = activity
        if (act == null) {
            result.error("NO_ACTIVITY", "Activity not available", null)
            return
        }
        pendingResult = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
            addFlags(
                Intent.FLAG_GRANT_READ_URI_PERMISSION or
                Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION
            )
        }
        act.startActivityForResult(intent, PICK_FOLDER_REQUEST)
    }

    private fun pickFile(result: MethodChannel.Result) {
        val act = activity
        if (act == null) {
            result.error("NO_ACTIVITY", "Activity not available", null)
            return
        }
        pendingResult = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "*/*"
            putExtra(Intent.EXTRA_MIME_TYPES, arrayOf("text/*", "application/octet-stream"))
        }
        act.startActivityForResult(intent, PICK_FILE_REQUEST)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != PICK_FOLDER_REQUEST && requestCode != PICK_FILE_REQUEST) return false
        val result = pendingResult ?: return true
        pendingResult = null

        if (resultCode != Activity.RESULT_OK || data?.data == null) {
            result.success(null)
            return true
        }

        val uri = data.data!!
        if (requestCode == PICK_FOLDER_REQUEST) {
            try {
                // Only READ/WRITE flags are valid here. PERSISTABLE is
                // set on the launching intent (line 144-147), not on the
                // takePersistableUriPermission call itself.
                val flags = Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
                activity?.contentResolver?.takePersistableUriPermission(uri, flags)
            } catch (_: Exception) {
                // Some custom ROM document providers reject persistable
                // permissions entirely. The URI still works within this
                // session via the temporary grant from the SAF picker.
            }
            result.success(uri.toString())
        } else {
            scope.launch {
                try {
                    val content = activity?.contentResolver?.openInputStream(uri)?.use { inputStream ->
                        inputStream.bufferedReader(Charsets.UTF_8).use { it.readText() }
                    }
                    withContext(Dispatchers.Main) {
                        result.success(content)
                    }
                } catch (e: Exception) {
                    withContext(Dispatchers.Main) {
                        result.error("READ_ERROR", e.message, null)
                    }
                }
            }
        }
        return true
    }

    // ── List audio files ──────────────────────────────────────────────────

    private fun listAudioFiles(treeUriStr: String): List<Map<String, Any?>> {
        val ctx = activity ?: return emptyList()
        val treeUri = Uri.parse(treeUriStr)
        val rootDocumentId = DocumentsContract.getTreeDocumentId(treeUri)
        val results = mutableListOf<Map<String, Any?>>()
        scanDirectoryCursor(ctx, treeUri, rootDocumentId, results)
        return results
    }

    // ── List files in parent folder ───────────────────────────────────────

    private fun listFilesInParentFolder(fileUriStr: String): List<Map<String, Any?>> {
        val ctx = activity ?: return emptyList()
        val fileUri = Uri.parse(fileUriStr)
        val results = mutableListOf<Map<String, Any?>>()

        try {
            // Get the document ID and tree document ID
            val docId = DocumentsContract.getDocumentId(fileUri)
            val treeId = DocumentsContract.getTreeDocumentId(fileUri)
            val authority = fileUri.authority ?: return emptyList()

            // Find parent directory
            val lastSlash = docId.lastIndexOf('/')
            if (lastSlash == -1) return emptyList()

            val parentDocId = if (lastSlash > 0) {
                docId.substring(0, lastSlash)
            } else {
                treeId
            }

            // Build parent URI and list its children
            val parentUri = DocumentsContract.buildTreeDocumentUri(authority, treeId)
            val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(parentUri, parentDocId)

            val projection = arrayOf(
                DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                DocumentsContract.Document.COLUMN_DISPLAY_NAME,
                DocumentsContract.Document.COLUMN_SIZE,
                DocumentsContract.Document.COLUMN_LAST_MODIFIED,
                DocumentsContract.Document.COLUMN_MIME_TYPE
            )

            ctx.contentResolver.query(childrenUri, projection, null, null, null)?.use { cursor ->
                val idIdx = cursor.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_DOCUMENT_ID)
                val nameIdx = cursor.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_DISPLAY_NAME)
                val sizeIdx = cursor.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_SIZE)
                val dateIdx = cursor.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_LAST_MODIFIED)
                val mimeIdx = cursor.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_MIME_TYPE)

                while (cursor.moveToNext()) {
                    val childDocId = cursor.getString(idIdx) ?: continue
                    val name = cursor.getString(nameIdx) ?: continue
                    val mimeType = cursor.getString(mimeIdx)

                    // Skip directories
                    if (DocumentsContract.Document.MIME_TYPE_DIR == mimeType) continue

                    val ext = name.substringAfterLast('.', "").lowercase()
                    val isImage = ext in IMAGE_EXTENSIONS

                    val childUri = DocumentsContract.buildDocumentUriUsingTree(parentUri, childDocId)
                    results.add(mapOf(
                        "uri" to childUri.toString(),
                        "name" to name,
                        "size" to cursor.getLong(sizeIdx),
                        "lastModified" to cursor.getLong(dateIdx),
                        "isImage" to isImage,
                        "nameWithoutExt" to name.substringBeforeLast('.', "").lowercase(),
                    ))
                }
            }
        } catch (e: Exception) {
            Log.w("SafPlugin", "listFilesInParentFolder failed: ${e.message}")
        }

        return results
    }

    /**
     * Optimized directory scanner using raw ContentResolver cursor queries.
     *
     * [DocumentFile.listFiles()] creates a DocumentFile per child and makes
     * separate Binder round-trips for isDirectory, length(), lastModified(),
     * etc.  On large libraries (1000+ tracks) this takes minutes.
     *
     * This implementation fetches all child metadata in a single cursor query
     * per directory, reducing scan time by 10-50x.
     */
    private fun scanDirectoryCursor(
        ctx: android.content.Context,
        treeUri: Uri,
        parentDocumentId: String,
        results: MutableList<Map<String, Any?>>
    ) {
        val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(treeUri, parentDocumentId)
        val projection = arrayOf(
            DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            DocumentsContract.Document.COLUMN_SIZE,
            DocumentsContract.Document.COLUMN_LAST_MODIFIED,
            DocumentsContract.Document.COLUMN_MIME_TYPE
        )

        ctx.contentResolver.query(childrenUri, projection, null, null, null)?.use { cursor ->
            val idIdx = cursor.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_DOCUMENT_ID)
            val nameIdx = cursor.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_DISPLAY_NAME)
            val sizeIdx = cursor.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_SIZE)
            val dateIdx = cursor.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_LAST_MODIFIED)
            val mimeIdx = cursor.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_MIME_TYPE)

            while (cursor.moveToNext()) {
                val docId = cursor.getString(idIdx) ?: continue
                val name = cursor.getString(nameIdx) ?: continue
                val mimeType = cursor.getString(mimeIdx)

                if (DocumentsContract.Document.MIME_TYPE_DIR == mimeType) {
                    scanDirectoryCursor(ctx, treeUri, docId, results)
                } else {
                    val ext = name.substringAfterLast('.', "").lowercase()
                    if (ext in AUDIO_EXTENSIONS) {
                        val fileUri = DocumentsContract.buildDocumentUriUsingTree(treeUri, docId)
                        results.add(mapOf(
                            "uri" to fileUri.toString(),
                            "name" to name,
                            "size" to cursor.getLong(sizeIdx),
                            "lastModified" to cursor.getLong(dateIdx),
                        ))
                    }
                }
            }
        }
    }

    // ── Read metadata ─────────────────────────────────────────────────────

    private fun readMetadata(fileUriStr: String): Map<String, Any?> {
        val uri = Uri.parse(fileUriStr)
        val retriever = MediaMetadataRetriever()
        return try {
            retriever.setDataSource(appContext, uri)
            mapOf(
                "title" to retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_TITLE),
                "artist" to retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_ARTIST),
                "album" to retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_ALBUM),
                "albumArtist" to retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_ALBUMARTIST),
                "trackNumber" to retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_CD_TRACK_NUMBER),
                "duration" to retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION),
                "year" to retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_YEAR),
                "genre" to retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_GENRE),
                "bitrate" to retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_BITRATE),
                "sampleRate" to retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_SAMPLERATE),
                "mimeType" to retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_MIMETYPE),
            )
        } finally {
            retriever.release()
        }
    }

    // ── Read cover art ────────────────────────────────────────────────────

    private fun readCoverArt(fileUriStr: String): ByteArray? {
        val uri = Uri.parse(fileUriStr)

        // 1. Fast path: MediaMetadataRetriever
        val mmrResult = try {
            val retriever = MediaMetadataRetriever()
            try {
                retriever.setDataSource(appContext, uri)
                retriever.embeddedPicture
            } finally {
                try { retriever.release() } catch (_: Exception) {}
            }
        } catch (e: Exception) {
            Log.w("SafPlugin", "MMR readCoverArt failed for $uri: ${e.message}")
            null
        }
        if (mmrResult != null) return mmrResult

        // 2. Fallback: binary parsing via ContentResolver
        return try {
            appContext.contentResolver.openInputStream(uri)?.use { rawStream ->
                // Read up to 3MB — metadata is at the start of audio files
                val maxScanBytes = 3 * 1024 * 1024
                val baos = java.io.ByteArrayOutputStream(maxScanBytes)
                val buf = ByteArray(8192)
                var totalRead = 0
                while (totalRead < maxScanBytes) {
                    val r = rawStream.read(buf, 0, buf.size.coerceAtMost(maxScanBytes - totalRead))
                    if (r == -1) break
                    baos.write(buf, 0, r)
                    totalRead += r
                }
                val bytes = baos.toByteArray()
                if (bytes.size < 4) return@use null

                when {
                    // ID3v2 (MP3)
                    bytes[0] == 'I'.code.toByte() && bytes[1] == 'D'.code.toByte() && bytes[2] == '3'.code.toByte() ->
                        extractMp3CoverArt(bytes)
                    // FLAC
                    bytes[0] == 'f'.code.toByte() && bytes[1] == 'L'.code.toByte() && bytes[2] == 'a'.code.toByte() && bytes[3] == 'C'.code.toByte() ->
                        extractFlacCoverArt(bytes)
                    // OGG
                    bytes[0] == 'O'.code.toByte() && bytes[1] == 'g'.code.toByte() && bytes[2] == 'g'.code.toByte() && bytes[3] == 'S'.code.toByte() ->
                        extractOggCoverArt(bytes)
                    // M4A/MP4 (starts with 'ftyp')
                    bytes[4] == 'f'.code.toByte() && bytes[5] == 't'.code.toByte() && bytes[6] == 'y'.code.toByte() && bytes[7] == 'p'.code.toByte() ->
                        extractM4aCoverArt(bytes)
                    // Unknown format — scan for image magic bytes
                    else ->
                        scanForEmbeddedImage(bytes)
                }
            }
        } catch (e: Exception) {
            Log.w("SafPlugin", "Binary cover art extraction failed for $uri: ${e.message}")
            null
        }
    }

    // ── ID3v2 (MP3) cover art extraction ──────────────────────────────────

    private fun extractMp3CoverArt(data: ByteArray): ByteArray? {
        if (data.size < 10) return null

        val version = data[3].toInt() and 0xFF
        // ID3v2 size (synchsafe)
        val tagSize = ((data[6].toInt() and 0x7F) shl 21) or
                      ((data[7].toInt() and 0x7F) shl 14) or
                      ((data[8].toInt() and 0x7F) shl 7) or
                      (data[9].toInt() and 0x7F)

        val limit = minOf(10 + tagSize, data.size, 10 + 3 * 1024 * 1024)
        var i = 10

        while (i < limit - 10) {
            val frameId = String(data, i, 4, Charsets.US_ASCII)

            val frameSize = if (version >= 4) {
                ((data[i+4].toInt() and 0x7F) shl 21) or
                ((data[i+5].toInt() and 0x7F) shl 14) or
                ((data[i+6].toInt() and 0x7F) shl 7) or
                (data[i+7].toInt() and 0x7F)
            } else {
                ((data[i+4].toInt() and 0xFF) shl 24) or
                ((data[i+5].toInt() and 0xFF) shl 16) or
                ((data[i+6].toInt() and 0xFF) shl 8) or
                (data[i+7].toInt() and 0xFF)
            }

            if (frameSize <= 0 || i + 10 + frameSize > limit) break

            if (frameId == "APIC") {
                val result = parseApicFrame(data, i + 10, frameSize)
                if (result != null) return result
            }

            i += 10 + frameSize
        }
        return null
    }

    private fun parseApicFrame(data: ByteArray, offset: Int, size: Int): ByteArray? {
        if (offset + size > data.size || size < 2) return null

        var pos = offset + 1 // skip encoding byte

        // MIME type (null-terminated ASCII)
        var mimeEnd = -1
        for (k in pos until offset + size) {
            if (data[k] == 0.toByte()) { mimeEnd = k; break }
        }
        if (mimeEnd == -1 || mimeEnd >= offset + size) return null
        pos = mimeEnd + 1

        // Picture type (1 byte) — skip
        pos += 1

        // Description (null-terminated, encoding-dependent)
        val encoding = data[offset].toInt() and 0xFF
        if (encoding == 0 || encoding == 3) {
            while (pos < offset + size && data[pos] != 0.toByte()) pos++
            pos++
        } else {
            while (pos + 1 < offset + size && !(data[pos] == 0.toByte() && data[pos+1] == 0.toByte())) pos += 2
            pos += 2
        }

        val dataLen = (offset + size) - pos
        if (dataLen <= 0 || pos + dataLen > data.size) return null
        return data.copyOfRange(pos, pos + dataLen)
    }

    // ── FLAC cover art extraction ─────────────────────────────────────────

    private fun extractFlacCoverArt(data: ByteArray): ByteArray? {
        if (data.size < 4 + 4) return null
        var pos = 4 // skip "fLaC"

        var isLast = false
        while (!isLast && pos + 4 <= data.size) {
            val headerByte = data[pos].toInt() and 0xFF
            isLast = (headerByte and 0x80) != 0
            val blockType = headerByte and 0x7F

            val blockLen = ((data[pos+1].toInt() and 0xFF) shl 16) or
                           ((data[pos+2].toInt() and 0xFF) shl 8) or
                           (data[pos+3].toInt() and 0xFF)
            pos += 4

            if (blockType == 6 && pos + blockLen <= data.size) { // PICTURE
                return parseFlacPictureData(data, pos, blockLen)
            }

            pos += blockLen
        }
        return null
    }

    private fun parseFlacPictureData(data: ByteArray, offset: Int, size: Int): ByteArray? {
        if (offset + size > data.size || size < 32) return null
        var pos = offset

        // Picture type (4 bytes) — skip
        pos += 4

        // MIME type length (4 bytes) + MIME
        val mimeLen = readInt32BE(data, pos)
        pos += 4 + mimeLen

        // Description length (4 bytes) + description
        if (pos + 4 > offset + size) return null
        val descLen = readInt32BE(data, pos)
        pos += 4 + descLen

        // Width (4) + Height (4) + ColorDepth (4) + NumberOfColors (4)
        pos += 16

        // Picture data length (4 bytes)
        if (pos + 4 > offset + size) return null
        val dataLen = readInt32BE(data, pos)
        pos += 4

        if (dataLen <= 0 || pos + dataLen > offset + size) return null
        return data.copyOfRange(pos, pos + dataLen)
    }

    // ── OGG cover art extraction ──────────────────────────────────────────

    private fun extractOggCoverArt(data: ByteArray): ByteArray? {
        // Find Vorbis comment header by scanning for "vorbis" string after "OggS" pages
        // The Vorbis comment header packet starts with:
        //   [1 byte packet type: 0x03 for comment] + "vorbis" (6 bytes) + vendor string + metadata

        val vorbisHeaderSig = byteArrayOf(0x03) + "vorbis".toByteArray(Charsets.US_ASCII)
        val commentStart = findPattern(data, vorbisHeaderSig)
        if (commentStart == -1) return null

        var pos = commentStart + 7 // skip packet type (1) + "vorbis" (6)
        if (pos + 8 > data.size) return null

        // Vendor string (little-endian length-prefixed)
        val vendorLen = readInt32LE(data, pos)
        pos += 4 + vendorLen
        if (pos + 4 > data.size) return null

        // Comment count
        val commentCount = readInt32LE(data, pos)
        pos += 4

        // Scan comments for METADATA_BLOCK_PICTURE
        for (i in 0 until commentCount) {
            if (pos + 4 > data.size) return null
            val commentLen = readInt32LE(data, pos)
            pos += 4
            if (pos + commentLen > data.size) break

            val comment = String(data, pos, commentLen, Charsets.UTF_8)
            val eqIdx = comment.indexOf('=')
            if (eqIdx != -1) {
                val key = comment.substring(0, eqIdx).uppercase()
                if (key == "METADATA_BLOCK_PICTURE") {
                    val value = comment.substring(eqIdx + 1)
                    return decodeMetadataBlockPicture(value)
                }
            }
            pos += commentLen
        }
        return null
    }

    private fun decodeMetadataBlockPicture(base64Value: String): ByteArray? {
        return try {
            val decoded = android.util.Base64.decode(base64Value, android.util.Base64.DEFAULT)
            parseFlacPictureData(decoded, 0, decoded.size)
        } catch (e: Exception) {
            null
        }
    }

    // ── M4A/MP4 cover art extraction ──────────────────────────────────────

    private fun extractM4aCoverArt(data: ByteArray): ByteArray? {
        return scanM4aAtomsForCover(data, 0, data.size)
    }

    private fun scanM4aAtomsForCover(data: ByteArray, start: Int, length: Int): ByteArray? {
        var pos = start
        val end = start + length

        while (pos + 8 <= end) {
            val atomSize = readInt32BE(data, pos)
            val atomType = String(data, pos + 4, 4, Charsets.US_ASCII)

            if (atomSize < 8) break
            val payloadSize = atomSize - 8
            val payloadStart = pos + 8

            when (atomType) {
                "moov", "udta", "meta", "ilst" -> {
                    val actualPayloadStart = if (atomType == "meta") payloadStart + 4 else payloadStart
                    val actualPayloadSize = if (atomType == "meta") payloadSize - 4 else payloadSize
                    val result = scanM4aAtomsForCover(data, actualPayloadStart, actualPayloadSize)
                    if (result != null) return result
                }
                "covr" -> {
                    // Skip atom header in data (8 bytes size + 4 bytes 'data' + 8 bytes flags/version)
                    if (payloadStart + 16 <= end) {
                        val imgDataStart = payloadStart + 16
                        val imgDataLen = payloadSize - 16
                        if (imgDataLen > 0 && imgDataStart + imgDataLen <= data.size) {
                            return data.copyOfRange(imgDataStart, imgDataStart + imgDataLen)
                        }
                    }
                }
            }
            pos += atomSize
        }
        return null
    }

    // ── Generic image scan fallback ───────────────────────────────────────

    private fun scanForEmbeddedImage(data: ByteArray): ByteArray? {
        // Try to find JPEG
        val jpeg = findJpeg(data)
        if (jpeg != null) return jpeg

        // Try to find PNG
        return findPng(data)
    }

    private fun findJpeg(data: ByteArray): ByteArray? {
        var i = 0
        while (i < data.size - 2) {
            if (data[i].toInt() and 0xFF == 0xFF &&
                data[i+1].toInt() and 0xFF == 0xD8 &&
                data[i+2].toInt() and 0xFF == 0xFF) {
                // Found JPEG start marker — scan for end marker (FF D9)
                var j = i + 3
                while (j < data.size - 1) {
                    if (data[j].toInt() and 0xFF == 0xFF && data[j+1].toInt() and 0xFF == 0xD9) {
                        return data.copyOfRange(i, j + 2)
                    }
                    j++
                }
                // If no end marker found but we're past 10KB, return what we have
                // (the data might be truncated but still valid enough)
                if (j - i > 10240) {
                    return data.copyOfRange(i, (j + 2).coerceAtMost(data.size))
                }
            }
            i++
        }
        return null
    }

    private fun findPng(data: ByteArray): ByteArray? {
        val pngSignature = byteArrayOf(
            0x89.toByte(), 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A
        )
        val iendChunk = byteArrayOf(
            0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE.toByte(), 0x42, 0x60, 0x82.toByte()
        )

        var start = findPattern(data, pngSignature)
        if (start == -1) return null

        val end = findPattern(data, iendChunk, start)
        if (end != -1) {
            return data.copyOfRange(start, end + iendChunk.size)
        }
        // Return what we have if no IEND found
        return null
    }

    // ── Binary parsing utilities ──────────────────────────────────────────

    private fun findPattern(data: ByteArray, pattern: ByteArray, startOffset: Int = 0): Int {
        if (pattern.isEmpty() || startOffset >= data.size) return -1
        val max = data.size - pattern.size
        for (i in startOffset..max) {
            var match = true
            for (j in pattern.indices) {
                if (data[i + j] != pattern[j]) {
                    match = false
                    break
                }
            }
            if (match) return i
        }
        return -1
    }

    private fun readInt32BE(data: ByteArray, offset: Int): Int {
        return ((data[offset].toInt() and 0xFF) shl 24) or
               ((data[offset+1].toInt() and 0xFF) shl 16) or
               ((data[offset+2].toInt() and 0xFF) shl 8) or
               (data[offset+3].toInt() and 0xFF)
    }

    private fun readLyrics(fileUriStr: String): String? {
        val uri = Uri.parse(fileUriStr)
        
        // 1. Try sidecar .lrc first
        try {
            val docId = DocumentsContract.getDocumentId(uri)
            val lastDot = docId.lastIndexOf('.')
            if (lastDot != -1) {
                val baseDocId = docId.substring(0, lastDot)
                val treeId = DocumentsContract.getTreeDocumentId(uri)
                val authority = uri.authority
                if (authority != null) {
                    val treeUri = DocumentsContract.buildTreeDocumentUri(authority, treeId)
                    
                    // Try lowercase .lrc
                    var lrcUri = DocumentsContract.buildDocumentUriUsingTree(treeUri, "$baseDocId.lrc")
                    var content = tryReadUri(appContext, lrcUri)
                    
                    // Try uppercase .LRC
                    if (content == null) {
                        lrcUri = DocumentsContract.buildDocumentUriUsingTree(treeUri, "$baseDocId.LRC")
                        content = tryReadUri(appContext, lrcUri)
                    }
                    
                    if (content != null) {
                        return content
                    }
                }
            }
        } catch (e: Exception) {
            // Ignore and fallback to embedded
        }
        
        // 2. Fallback to embedded lyrics
        try {
            val displayName = getDocumentDisplayName(appContext, uri) ?: uri.path ?: ""
            val ext = displayName.substringAfterLast('.', "").lowercase()
            
            appContext.contentResolver.openInputStream(uri)?.use { inputStream ->
                return when (ext) {
                    "mp3" -> extractLyricsFromMp3(inputStream)
                    "flac" -> extractLyricsFromFlac(inputStream)
                    "m4a", "mp4" -> extractLyricsFromM4a(inputStream)
                    else -> null
                }
            }
        } catch (e: Exception) {
            // Ignore
        }
        
        return null
    }

    private fun getDocumentDisplayName(ctx: android.content.Context, uri: Uri): String? {
        val projection = arrayOf(DocumentsContract.Document.COLUMN_DISPLAY_NAME)
        return try {
            ctx.contentResolver.query(uri, projection, null, null, null)?.use { cursor ->
                if (cursor.moveToFirst()) {
                    cursor.getString(0)
                } else null
            }
        } catch (e: Exception) {
            null
        }
    }

    private fun tryReadUri(ctx: android.content.Context, uri: Uri): String? {
        return try {
            ctx.contentResolver.openInputStream(uri)?.use { inputStream ->
                inputStream.bufferedReader(Charsets.UTF_8).use { it.readText() }
            }
        } catch (e: Exception) {
            null
        }
    }

    private fun tryWriteUri(ctx: android.content.Context, uri: Uri, content: String): Boolean {
        return try {
            ctx.contentResolver.openOutputStream(uri, "rwt")?.use { outputStream ->
                outputStream.write(content.toByteArray(Charsets.UTF_8))
                true
            } ?: false
        } catch (e: Exception) {
            false
        }
    }

    private fun saveSidecarLrc(trackUriStr: String, content: String): Boolean {
        val ctx = activity ?: return false
        val uri = Uri.parse(trackUriStr)
        return try {
            val docId = DocumentsContract.getDocumentId(uri)
            val lastDot = docId.lastIndexOf('.')
            if (lastDot == -1) return false
            
            val baseDocId = docId.substring(0, lastDot)
            val treeId = DocumentsContract.getTreeDocumentId(uri)
            val authority = uri.authority ?: return false
            val treeUri = DocumentsContract.buildTreeDocumentUri(authority, treeId)
            
            val lrcDocId = "$baseDocId.lrc"
            val lrcUri = DocumentsContract.buildDocumentUriUsingTree(treeUri, lrcDocId)
            
            // Try to overwrite first
            var written = tryWriteUri(ctx, lrcUri, content)
            
            if (!written) {
                // If overwrite fails (file does not exist), create it
                val lastSlash = docId.lastIndexOf('/')
                val parentDocId = if (lastSlash != -1) {
                    docId.substring(0, lastSlash)
                } else {
                    treeId
                }
                
                val lastSlashInBase = baseDocId.lastIndexOf('/')
                val baseName = if (lastSlashInBase != -1) {
                    baseDocId.substring(lastSlashInBase + 1)
                } else {
                    baseDocId
                }
                
                val parentUri = DocumentsContract.buildDocumentUriUsingTree(treeUri, parentDocId)
                val newLrcUri = DocumentsContract.createDocument(
                    ctx.contentResolver,
                    parentUri,
                    "application/octet-stream",
                    "$baseName.lrc"
                )
                if (newLrcUri != null) {
                    written = tryWriteUri(ctx, newLrcUri, content)
                }
            }
            
            written
        } catch (e: Exception) {
            false
        }
    }

    private fun extractLyricsFromMp3(inputStream: java.io.InputStream): String? {
        val header = ByteArray(10)
        if (inputStream.read(header) != 10) return null
        if (header[0] != 'I'.toByte() || header[1] != 'D'.toByte() || header[2] != '3'.toByte()) {
            return null
        }
        
        val version = header[3].toInt() and 0xFF
        val tagSize = ((header[6].toInt() and 0x7F) shl 21) or
                      ((header[7].toInt() and 0x7F) shl 14) or
                      ((header[8].toInt() and 0x7F) shl 7) or
                      (header[9].toInt() and 0x7F)
                      
        val maxReadSize = minOf(tagSize, 10 * 1024 * 1024)
        val buffer = ByteArray(maxReadSize)
        var read = 0
        while (read < maxReadSize) {
            val r = inputStream.read(buffer, read, maxReadSize - read)
            if (r == -1) break
            read += r
        }
        
        if (read < 10) return null
        
        var i = 0
        while (i < read - 10) {
            if (buffer[i] == 'U'.toByte() && buffer[i+1] == 'S'.toByte() &&
                buffer[i+2] == 'L'.toByte() && buffer[i+3] == 'T'.toByte()) {
                val frameSize = if (version == 4) {
                    ((buffer[i+4].toInt() and 0x7F) shl 21) or
                    ((buffer[i+5].toInt() and 0x7F) shl 14) or
                    ((buffer[i+6].toInt() and 0x7F) shl 7) or
                    (buffer[i+7].toInt() and 0x7F)
                } else {
                    ((buffer[i+4].toInt() and 0xFF) shl 24) or
                    ((buffer[i+5].toInt() and 0xFF) shl 16) or
                    ((buffer[i+6].toInt() and 0xFF) shl 8) or
                    (buffer[i+7].toInt() and 0xFF)
                }
                
                if (frameSize > 0 && i + 10 + frameSize <= read) {
                    val lyrics = parseUsltFrame(buffer, i, frameSize)
                    if (lyrics != null) return lyrics
                }
                i += 10 + frameSize
            } else {
                i++
            }
        }
        return null
    }

    private fun parseUsltFrame(buffer: ByteArray, startIndex: Int, size: Int): String? {
        if (startIndex + 10 + size > buffer.size) return null
        val bodyStart = startIndex + 10
        if (size <= 4) return null
        
        val encoding = buffer[bodyStart].toInt() and 0xFF
        var textStart = bodyStart + 4 // skip encoding (1) + language (3)
        
        if (encoding == 0 || encoding == 3) {
            while (textStart < bodyStart + size && buffer[textStart] != 0.toByte()) {
                textStart++
            }
            textStart++ // skip null byte
        } else {
            while (textStart + 1 < bodyStart + size && !(buffer[textStart] == 0.toByte() && buffer[textStart+1] == 0.toByte())) {
                textStart += 2
            }
            textStart += 2 // skip null bytes
        }
        
        if (textStart >= bodyStart + size) return null
        val textLen = (bodyStart + size) - textStart
        
        return when (encoding) {
            0 -> String(buffer, textStart, textLen, Charsets.ISO_8859_1)
            1 -> String(buffer, textStart, textLen, Charsets.UTF_16)
            2 -> String(buffer, textStart, textLen, Charsets.UTF_16BE)
            3 -> String(buffer, textStart, textLen, Charsets.UTF_8)
            else -> String(buffer, textStart, textLen, Charsets.UTF_8)
        }
    }

    private fun extractLyricsFromFlac(inputStream: java.io.InputStream): String? {
        val header = ByteArray(4)
        if (inputStream.read(header) != 4) return null
        if (header[0] != 'f'.toByte() || header[1] != 'L'.toByte() ||
            header[2] != 'a'.toByte() || header[3] != 'C'.toByte()) {
            return null
        }
        
        var isLast = false
        while (!isLast) {
            val blockHeader = ByteArray(4)
            if (inputStream.read(blockHeader) != 4) break
            
            val headerByte = blockHeader[0].toInt() and 0xFF
            isLast = (headerByte and 0x80) != 0
            val blockType = headerByte and 0x7F
            
            val length = ((blockHeader[1].toInt() and 0xFF) shl 16) or
                         ((blockHeader[2].toInt() and 0xFF) shl 8) or
                         (blockHeader[3].toInt() and 0xFF)
                         
            if (blockType == 4) {
                val buffer = ByteArray(length)
                var read = 0
                while (read < length) {
                    val r = inputStream.read(buffer, read, length - read)
                    if (r == -1) break
                    read += r
                }
                if (read == length) {
                    return parseVorbisComment(buffer)
                }
                break
            } else {
                var skipped: Long = 0
                while (skipped < length) {
                    val s = inputStream.skip(length.toLong() - skipped)
                    if (s <= 0) break
                    skipped += s
                }
            }
        }
        return null
    }

    private fun parseVorbisComment(buffer: ByteArray): String? {
        if (buffer.size < 8) return null
        var offset = 0
        
        val vendorLen = readInt32LE(buffer, offset)
        offset += 4 + vendorLen
        if (offset + 4 > buffer.size) return null
        
        val commentCount = readInt32LE(buffer, offset)
        offset += 4
        
        for (i in 0 until commentCount) {
            if (offset + 4 > buffer.size) break
            val commentLen = readInt32LE(buffer, offset)
            offset += 4
            if (offset + commentLen > buffer.size) break
            
            val commentStr = String(buffer, offset, commentLen, Charsets.UTF_8)
            offset += commentLen
            
            val eq = commentStr.indexOf('=')
            if (eq != -1) {
                val key = commentStr.substring(0, eq).uppercase()
                if (key == "LYRICS" || key == "UNSYNCEDLYRICS") {
                    return commentStr.substring(eq + 1)
                }
            }
        }
        return null
    }

    private fun readInt32LE(buffer: ByteArray, offset: Int): Int {
        return (buffer[offset].toInt() and 0xFF) or
               ((buffer[offset + 1].toInt() and 0xFF) shl 8) or
               ((buffer[offset + 2].toInt() and 0xFF) shl 16) or
               ((buffer[offset + 3].toInt() and 0xFF) shl 24)
    }

    private fun extractLyricsFromM4a(inputStream: java.io.InputStream): String? {
        return scanM4aAtoms(inputStream, -1)
    }

    private fun scanM4aAtoms(inputStream: java.io.InputStream, maxBytes: Long): String? {
        val header = ByteArray(8)
        var bytesRead: Long = 0
        
        while (maxBytes < 0 || bytesRead < maxBytes) {
            val r = inputStream.read(header)
            if (r != 8) break
            bytesRead += r
            
            val size = ((header[0].toInt() and 0xFF) shl 24) or
                       ((header[1].toInt() and 0xFF) shl 16) or
                       ((header[2].toInt() and 0xFF) shl 8) or
                       (header[3].toInt() and 0xFF)
                       
            val type = String(header, 4, 4, Charsets.US_ASCII)
            
            if (size < 8) break
            val payloadSize = size - 8
            
            if (type == "moov" || type == "udta" || type == "meta" || type == "ilst") {
                if (type == "meta") {
                    val dummy = ByteArray(4)
                    if (inputStream.read(dummy) != 4) break
                    bytesRead += 4
                    val lyrics = scanM4aAtoms(inputStream, payloadSize.toLong() - 4)
                    if (lyrics != null) return lyrics
                } else {
                    val lyrics = scanM4aAtoms(inputStream, payloadSize.toLong())
                    if (lyrics != null) return lyrics
                }
            } else if (type == "\u00a9lyr") {
                val dataHeader = ByteArray(8)
                if (inputStream.read(dataHeader) != 8) break
                bytesRead += 8
                
                val dSize = ((dataHeader[0].toInt() and 0xFF) shl 24) or
                            ((dataHeader[1].toInt() and 0xFF) shl 16) or
                            ((dataHeader[2].toInt() and 0xFF) shl 8) or
                            (dataHeader[3].toInt() and 0xFF)
                val dType = String(dataHeader, 4, 4, Charsets.US_ASCII)
                
                if (dType == "data") {
                    val flags = ByteArray(8)
                    if (inputStream.read(flags) != 8) break
                    bytesRead += 8
                    
                    val textLen = dSize - 16
                    if (textLen > 0) {
                        val textBytes = ByteArray(textLen)
                        var read = 0
                        while (read < textLen) {
                            val rd = inputStream.read(textBytes, read, textLen - read)
                            if (rd == -1) break
                            read += rd
                        }
                        return String(textBytes, 0, read, Charsets.UTF_8)
                    }
                }
                break
            } else {
                var skipped: Long = 0
                while (skipped < payloadSize) {
                    val s = inputStream.skip(payloadSize.toLong() - skipped)
                    if (s <= 0) break
                    skipped += s
                }
                bytesRead += payloadSize
            }
        }
        return null
    }

    // ── ActivityAware ─────────────────────────────────────────────────────

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        binding.addActivityResultListener(this)
    }

    override fun onDetachedFromActivityForConfigChanges() { activity = null }
    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
        binding.addActivityResultListener(this)
    }
    override fun onDetachedFromActivity() { activity = null }
}
