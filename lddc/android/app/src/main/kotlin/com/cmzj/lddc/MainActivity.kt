package com.cmzj.lddc

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.DocumentsContract
import android.provider.DocumentsContract.Document
import android.provider.OpenableColumns
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileNotFoundException
import java.io.IOException

class MainActivity : FlutterActivity() {
    companion object {
        private const val SAF_FD_CHANNEL = "lddc/android_saf_fd"
        private const val SAF_TREE_CHANNEL = "lddc/android_saf_tree"
        private const val SAF_CONTENT_CHANNEL = "lddc/android_saf_content"
        private const val SEARCH_FILE_CHANNEL = "lddc/android_search_file"
        private const val DEFAULT_SAF_CONTENT_MAX_BYTES = 1024 * 1024
        // FlutterActivity 当前没有直接暴露 AndroidX Activity Result API。
        // 这里使用固定 requestCode 接收系统回调，避免为了三个文件选择入口额外扩大 AndroidX 依赖面。
        private const val REQUEST_PICK_TREE = 0x4C01
        private const val REQUEST_PICK_AUDIO_FILE = 0x4C02
        private const val REQUEST_SAVE_TEXT_FILE = 0x4C03
    }

    private val pendingPickers = PickerPendingRequestRegistry()
    private lateinit var safFileDescriptors: SafFileDescriptorChannelHandler

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        safFileDescriptors =
            SafFileDescriptorChannelHandler(
                AndroidSafFileDescriptorGateway(contentResolver, ::queryDisplayName),
            )
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SAF_FD_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "openReadOnlyFd" ->
                        safFileDescriptors.openReadOnly(call.argument<String>("uri"), result)
                    "openReadWriteFd" ->
                        safFileDescriptors.openReadWrite(call.argument<String>("uri"), result)
                    "closeFd" -> safFileDescriptors.close(call.argument<Int>("fd"), result)
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SAF_TREE_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "pickTree" -> pickTree(call, result)
                    "persistTreePermission" -> persistTreePermission(call, result)
                    "listPersistedTrees" -> listPersistedTrees(result)
                    "listChildrenPage" -> listChildrenPage(call, result)
                    "writeDocument" -> writeDocument(call, result)
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SAF_CONTENT_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "readBytes" -> readContentBytes(call, result)
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SEARCH_FILE_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "pickAudioFile" -> pickAudioFile(call, result)
                    "saveTextFile" -> saveTextFile(call, result)
                    else -> result.notImplemented()
                }
            }
    }

    private fun pickAudioFile(call: MethodCall, result: MethodChannel.Result) {
        if (!pendingPickers.beginAudio(result)) {
            return
        }
        try {
            val intent =
                Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                    addCategory(Intent.CATEGORY_OPENABLE)
                    type = "audio/*"
                }
            tryApplyInitialUri(intent, call.argument<String>("initialDirectory"))
            startActivityForResult(intent, REQUEST_PICK_AUDIO_FILE)
        } catch (error: Exception) {
            pendingPickers.takeAudio()
            result.error("pick_audio_failed", "打开音频选择器失败: ${error.message}", null)
        }
    }

    private fun saveTextFile(call: MethodCall, result: MethodChannel.Result) {
        val fileName = SafChannelArguments.nonBlank(call.argument<String>("fileName"))
        val bytes = call.argument<ByteArray>("bytes")
        val mimeType = SafChannelArguments.mimeType(call.argument<String>("mimeType"))
        if (fileName == null || bytes == null) {
            result.error("invalid_argument", "fileName/bytes 不能为空", null)
            return
        }
        if (!pendingPickers.beginSave(
                PendingSaveTextFile(result = result, bytes = bytes, fileName = fileName),
            )
        ) {
            return
        }
        try {
            val intent =
                Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                    addCategory(Intent.CATEGORY_OPENABLE)
                    type = mimeType
                    putExtra(Intent.EXTRA_TITLE, fileName)
                }
            tryApplyInitialUri(intent, call.argument<String>("initialDirectory"))
            startActivityForResult(intent, REQUEST_SAVE_TEXT_FILE)
        } catch (error: Exception) {
            pendingPickers.takeSave()
            result.error("write_failed", "打开文件保存器失败: ${error.message}", null)
        }
    }

    private fun pickTree(call: MethodCall, result: MethodChannel.Result) {
        if (!pendingPickers.beginTree(result)) {
            return
        }
        try {
            val intent =
                Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
                    addFlags(
                        Intent.FLAG_GRANT_READ_URI_PERMISSION or
                            Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                            Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION or
                            Intent.FLAG_GRANT_PREFIX_URI_PERMISSION,
                    )
                }
            tryApplyInitialUri(intent, call.argument<String>("initialUri"))
            startActivityForResult(intent, REQUEST_PICK_TREE)
        } catch (error: Exception) {
            pendingPickers.takeTree()
            result.error("pick_tree_failed", "打开目录选择器失败: ${error.message}", null)
        }
    }

    @Suppress("DEPRECATION")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        when (requestCode) {
            REQUEST_PICK_TREE -> handlePickTreeResult(resultCode, data)
            REQUEST_PICK_AUDIO_FILE -> handlePickAudioFileResult(resultCode, data)
            REQUEST_SAVE_TEXT_FILE -> handleSaveTextFileResult(resultCode, data)
            else -> super.onActivityResult(requestCode, resultCode, data)
        }
    }

    override fun onDestroy() {
        // Flutter engine 分离前先结束所有 pending Future，并释放仍归当前 Activity
        // 所有的 raw fd。每个请求都先从注册表取走，再回调错误，回调重入也不会
        // 看见陈旧 busy 状态。
        pendingPickers.completeDestroyedRequests()
        if (::safFileDescriptors.isInitialized) {
            safFileDescriptors.closeAll()
        }
        super.onDestroy()
    }

    internal fun resourceSnapshot(): Map<String, Int> =
        mapOf(
            "openFdCount" to if (::safFileDescriptors.isInitialized) safFileDescriptors.count() else 0,
            "pendingPickerCount" to pendingPickers.count(),
        )

    private fun handlePickTreeResult(resultCode: Int, data: Intent?) {
        val result = pendingPickers.takeTree()
        if (result == null) {
            return
        }
        if (resultCode != Activity.RESULT_OK) {
            result.error("cancelled", "用户取消目录选择", null)
            return
        }
        val uri = data?.data
        if (uri == null) {
            result.error("pick_tree_failed", "未获取到目录 URI", null)
            return
        }
        result.success(
            mapOf(
                "uri" to uri.toString(),
                "displayName" to resolveTreeDisplayName(uri),
            )
        )
    }

    private fun handlePickAudioFileResult(resultCode: Int, data: Intent?) {
        val result = pendingPickers.takeAudio()
        if (result == null) {
            return
        }
        if (resultCode != Activity.RESULT_OK) {
            result.error("cancelled", "用户取消文件选择", null)
            return
        }
        val uri = data?.data
        if (uri == null) {
            result.error("pick_audio_failed", "未获取到音频文件 URI", null)
            return
        }
        result.success(
            mapOf(
                "name" to (queryDisplayName(uri) ?: uri.lastPathSegment ?: "audio"),
                "identifier" to uri.toString(),
            )
        )
    }

    private fun handleSaveTextFileResult(resultCode: Int, data: Intent?) {
        val request = pendingPickers.takeSave()
        if (request == null) {
            return
        }
        val result = request.result
        val bytes = request.bytes
        if (resultCode != Activity.RESULT_OK) {
            result.error("cancelled", "用户取消文件保存", null)
            return
        }
        val uri = data?.data
        if (uri == null) {
            result.error("write_failed", "未获取到保存目标 URI", null)
            return
        }
        try {
            // 单文件导出直接写入用户确认的目标 URI，避免落到缓存副本。
            contentResolver.openOutputStream(uri, "rwt")?.use { output ->
                output.write(bytes)
                output.flush()
            } ?: run {
                result.error("write_failed", "打开输出流失败", null)
                return
            }
            // 这里仍持有本次 ACTION_CREATE_DOCUMENT 的 URI 授权，是查询系统显示名与所在
            // 相对目录最可靠的时刻：把可读信息一起回给 Dart，界面就不必再展示
            // `content://…%2F…` 这类对用户无意义的编码 URI（provider 查不到时用请求时的
            // 建议文件名兜底）。uri 原样保留，读写逻辑不受影响。
            result.success(
                mapOf(
                    "uri" to uri.toString(),
                    "displayName" to (queryDisplayName(uri) ?: request.fileName),
                    "relativePath" to queryRelativePath(uri),
                )
            )
        } catch (error: SecurityException) {
            result.error("permission_denied", "写入文件失败，权限不足: ${error.message}", null)
        } catch (error: FileNotFoundException) {
            result.error("file_not_found", "写入文件失败，目标不存在: ${error.message}", null)
        } catch (error: IOException) {
            result.error("write_failed", "写入文件失败: ${error.message}", null)
        } catch (error: Exception) {
            result.error("write_failed", "写入文件失败: ${error.message}", null)
        }
    }

    private fun persistTreePermission(call: MethodCall, result: MethodChannel.Result) {
        val uriText = call.argument<String>("uri")
        if (uriText.isNullOrBlank()) {
            result.error("invalid_argument", "uri 不能为空", null)
            return
        }
        val uri = Uri.parse(uriText)
        try {
            // 优先申请读写权限，失败后回退只读权限，避免在只读树授权场景直接失败。
            try {
                contentResolver.takePersistableUriPermission(
                    uri,
                    Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION,
                )
            } catch (_: SecurityException) {
                contentResolver.takePersistableUriPermission(
                    uri,
                    Intent.FLAG_GRANT_READ_URI_PERMISSION,
                )
            }
            result.success(null)
        } catch (error: SecurityException) {
            result.error("permission_denied", "持久化目录授权失败: ${error.message}", null)
        } catch (error: Exception) {
            result.error("persist_permission_failed", "持久化目录授权失败: ${error.message}", null)
        }
    }

    private fun listPersistedTrees(result: MethodChannel.Result) {
        try {
            val trees =
                contentResolver.persistedUriPermissions.map { permission ->
                    mapOf(
                        "uri" to permission.uri.toString(),
                        "displayName" to resolveTreeDisplayName(permission.uri),
                        "persistedTimeMs" to permission.persistedTime,
                        "readable" to permission.isReadPermission,
                        "writable" to permission.isWritePermission,
                    )
                }
            result.success(trees)
        } catch (error: Exception) {
            result.error("list_persisted_failed", "获取持久授权目录失败: ${error.message}", null)
        }
    }

    private fun listChildrenPage(call: MethodCall, result: MethodChannel.Result) {
        val uriText = call.argument<String>("uri")
        val offset = call.argument<Int>("offset") ?: 0
        val limit = call.argument<Int>("limit") ?: 128
        if (uriText.isNullOrBlank() || offset < 0 || limit !in 1..512) {
            result.error("invalid_argument", "uri 不能为空，offset/limit 必须在有效范围内", null)
            return
        }
        val treeUri = Uri.parse(uriText)
        try {
            // 传入 uri 可能是树根，也可能是子目录文档。枚举子目录必须用"当前目录"的文档 id：
            // getTreeDocumentId() 对子目录文档 URI 也只会返回树根 id，会让枚举子目录退化成
            // 再枚举一次树根，子目录永远进不去（递归扫描失效，且不产生任何错误）。
            val currentDocumentId =
                SafTreeEntries.currentDocumentId(treeUri.pathSegments)
                    ?: DocumentsContract.getTreeDocumentId(treeUri)
            val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(treeUri, currentDocumentId)
            val children = mutableListOf<Map<String, Any?>>()
            val queryResult = contentResolver.query(
                childrenUri,
                arrayOf(
                    Document.COLUMN_DOCUMENT_ID,
                    Document.COLUMN_DISPLAY_NAME,
                    Document.COLUMN_MIME_TYPE,
                    Document.COLUMN_SIZE,
                    Document.COLUMN_LAST_MODIFIED,
                ),
                null,
                null,
                "${Document.COLUMN_DISPLAY_NAME} ASC",
            )
            if (queryResult == null) {
                // provider 没有返回游标既不是"空目录"也不是异常。当成空目录会让整棵子树
                // 静默消失，因此这里必须显式失败。
                result.error("list_children_failed", "列举目录失败，provider 未返回游标", null)
                return
            }
            queryResult.use { cursor ->
                val documentIdIndex = cursor.getColumnIndex(Document.COLUMN_DOCUMENT_ID)
                val displayNameIndex = cursor.getColumnIndex(Document.COLUMN_DISPLAY_NAME)
                val mimeTypeIndex = cursor.getColumnIndex(Document.COLUMN_MIME_TYPE)
                val sizeIndex = cursor.getColumnIndex(Document.COLUMN_SIZE)
                val lastModifiedIndex = cursor.getColumnIndex(Document.COLUMN_LAST_MODIFIED)
                if (offset > 0 && !cursor.moveToPosition(offset - 1)) {
                    result.success(mapOf("entries" to children, "nextOffset" to null))
                    return
                }
                var scannedRows = 0
                while (scannedRows < limit && cursor.moveToNext()) {
                    scannedRows += 1
                    if (documentIdIndex < 0 || cursor.isNull(documentIdIndex)) {
                        continue
                    }
                    val documentId = cursor.getString(documentIdIndex)
                    val childUri = DocumentsContract.buildDocumentUriUsingTree(treeUri, documentId)
                    val rawDisplayName =
                        if (displayNameIndex >= 0 && !cursor.isNull(displayNameIndex)) {
                            cursor.getString(displayNameIndex)
                        } else {
                            null
                        }
                    // displayName 缺失时回退路径末段：Dart 侧把它当必填字段，传 null/空串会让
                    // 整个目录页（最多 128 项）作废并被记成一次错误。
                    val displayName = SafChannelArguments.nonBlank(rawDisplayName)
                        ?: childUri.lastPathSegment
                        ?: documentId
                    val mimeType =
                        if (mimeTypeIndex >= 0 && !cursor.isNull(mimeTypeIndex)) {
                            cursor.getString(mimeTypeIndex)
                        } else {
                            null
                        }
                    val size =
                        if (sizeIndex >= 0 && !cursor.isNull(sizeIndex)) {
                            cursor.getLong(sizeIndex)
                        } else {
                            null
                        }
                    val lastModified =
                        if (lastModifiedIndex >= 0 && !cursor.isNull(lastModifiedIndex)) {
                            cursor.getLong(lastModifiedIndex)
                        } else {
                            null
                        }
                    // 目录/文件必须是"二选一必真"：两者都为 false 时 Dart 侧会静默跳过整行
                    // （目录还会丢掉整棵子树），而且不产生任何错误。
                    val isDirectory = SafTreeEntries.isDirectoryMime(mimeType)
                    children.add(
                        mapOf(
                            "uri" to childUri.toString(),
                            "displayName" to displayName,
                            "mimeType" to mimeType,
                            "isDirectory" to isDirectory,
                            "isFile" to !isDirectory,
                            // 负数是 provider 的"未知大小/未知时间"约定，转 null 才能通过 Dart
                            // 侧的非负校验，否则整页作废。
                            "sizeBytes" to SafTreeEntries.nonNegativeOrNull(size),
                            "lastModifiedMs" to SafTreeEntries.nonNegativeOrNull(lastModified),
                        )
                    )
                }
                val nextOffset = if (cursor.moveToNext()) offset + scannedRows else null
                result.success(mapOf("entries" to children, "nextOffset" to nextOffset))
                return
            }
        } catch (error: SecurityException) {
            result.error("permission_denied", "列举目录失败，权限不足: ${error.message}", null)
        } catch (error: FileNotFoundException) {
            result.error("file_not_found", "列举目录失败，目录不存在: ${error.message}", null)
        } catch (error: Exception) {
            result.error("list_children_failed", "列举目录失败: ${error.message}", null)
        }
    }

    private fun readContentBytes(call: MethodCall, result: MethodChannel.Result) {
        val uriText = call.argument<String>("uri")
        if (uriText.isNullOrBlank()) {
            result.error("invalid_argument", "uri 不能为空", null)
            return
        }
        val maxBytes = call.argument<Int>("maxBytes") ?: DEFAULT_SAF_CONTENT_MAX_BYTES
        if (maxBytes <= 0) {
            result.error("invalid_argument", "maxBytes 必须大于 0", null)
            return
        }
        try {
            val uri = Uri.parse(uriText)
            val bytes = contentResolver.openInputStream(uri)?.use { input ->
                val output = ByteArrayOutputStream()
                val buffer = ByteArray(8192)
                var total = 0
                while (true) {
                    val read = input.read(buffer)
                    if (read < 0) {
                        break
                    }
                    total += read
                    if (total > maxBytes) {
                        result.error("file_too_large", "读取文件超过上限: $maxBytes bytes", null)
                        return
                    }
                    output.write(buffer, 0, read)
                }
                output.toByteArray()
            }
            if (bytes == null) {
                result.error("read_failed", "读取文件失败，输入流为空", null)
                return
            }
            result.success(bytes)
        } catch (error: SecurityException) {
            result.error("permission_denied", "读取文件失败，权限不足: ${error.message}", null)
        } catch (error: FileNotFoundException) {
            result.error("file_not_found", "读取文件失败，文件不存在: ${error.message}", null)
        } catch (error: Exception) {
            result.error("read_failed", "读取文件失败: ${error.message}", null)
        }
    }

    private fun writeDocument(call: MethodCall, result: MethodChannel.Result) {
        val treeUriText = call.argument<String>("treeUri")
        val displayName = call.argument<String>("displayName")
        val mimeType = call.argument<String>("mimeType")
        val bytes = call.argument<ByteArray>("bytes")
        // Dart 侧只传"相对授权树的目录名"，这里不接受任何外部 document id，
        // 因此写回永远落在用户授权的子树内。
        val rawSegments = call.argument<List<Any?>>("directorySegments")
        if (treeUriText.isNullOrBlank() || displayName.isNullOrBlank() || mimeType.isNullOrBlank() || bytes == null) {
            result.error("invalid_argument", "treeUri/displayName/mimeType/bytes 不能为空", null)
            return
        }
        val directorySegments =
            SafTreeEntries.normalizeSegments(rawSegments?.map { it?.toString() ?: "" })
        if (directorySegments == null) {
            result.error("invalid_argument", "directorySegments 含非法目录段", null)
            return
        }

        val treeUri = Uri.parse(treeUriText)
        var targetUri: Uri? = null
        var createdNewDocument = false
        try {
            // 目标目录由相对段逐级定位（缺失则创建）。song/mirror/specify 三种保存模式
            // 都收敛到这一个入口，不再隐式写树根。
            val parentDocumentId =
                resolveDirectoryDocumentId(
                    treeUri = treeUri,
                    rootDocumentId = DocumentsContract.getTreeDocumentId(treeUri),
                    segments = directorySegments,
                )
            val parentDocumentUri =
                DocumentsContract.buildDocumentUriUsingTree(treeUri, parentDocumentId)
            targetUri =
                findChildDocumentUri(
                    treeUri = treeUri,
                    parentDocumentId = parentDocumentId,
                    displayName = displayName,
                    expectDirectory = false,
                )
            if (targetUri == null) {
                targetUri =
                    DocumentsContract.createDocument(
                        contentResolver,
                        parentDocumentUri,
                        mimeType,
                        displayName,
                    )
                createdNewDocument = targetUri != null
            }
            val resolvedUri = targetUri
            if (resolvedUri == null) {
                result.error("write_failed", "创建目标文件失败", null)
                return
            }

            // 歌词保存必须由原生侧一次完成“定位/创建/写入”，避免拆分调用在
            // 创建成功、写入失败时留下半成品文件。
            contentResolver.openOutputStream(resolvedUri, "rwt")?.use { output ->
                output.write(bytes)
                output.flush()
            } ?: run {
                if (createdNewDocument) {
                    deleteDocumentQuietly(resolvedUri)
                }
                result.error("write_failed", "打开输出流失败", null)
                return
            }

            result.success(
                mapOf(
                    "uri" to resolvedUri.toString(),
                    "displayName" to (queryDisplayName(resolvedUri) ?: displayName),
                )
            )
        } catch (error: SecurityException) {
            targetUri?.takeIf { createdNewDocument }?.let(::deleteDocumentQuietly)
            result.error("permission_denied", "写入文件失败，权限不足: ${error.message}", null)
        } catch (error: FileNotFoundException) {
            targetUri?.takeIf { createdNewDocument }?.let(::deleteDocumentQuietly)
            result.error("file_not_found", "写入文件失败，目标不存在: ${error.message}", null)
        } catch (error: IOException) {
            targetUri?.takeIf { createdNewDocument }?.let(::deleteDocumentQuietly)
            result.error("write_failed", "写入文件失败: ${error.message}", null)
        } catch (error: Exception) {
            targetUri?.takeIf { createdNewDocument }?.let(::deleteDocumentQuietly)
            result.error("write_failed", "写入文件失败: ${error.message}", null)
        }
    }

    private fun resolveTreeDisplayName(treeUri: Uri): String? {
        return try {
            val documentUri =
                DocumentsContract.buildDocumentUriUsingTree(
                    treeUri,
                    DocumentsContract.getTreeDocumentId(treeUri),
                )
            queryDisplayName(documentUri)
        } catch (_: Exception) {
            treeUri.lastPathSegment
        }
    }

    private fun queryDisplayName(uri: Uri): String? {
        return try {
            contentResolver.query(
                uri,
                arrayOf(OpenableColumns.DISPLAY_NAME),
                null,
                null,
                null,
            )?.use { cursor ->
                if (!cursor.moveToFirst()) {
                    return@use null
                }
                val index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (index >= 0 && !cursor.isNull(index)) {
                    return@use cursor.getString(index)
                }
                null
            }
                ?: contentResolver.query(
                    uri,
                    arrayOf(Document.COLUMN_DISPLAY_NAME),
                    null,
                    null,
                    null,
                )?.use { cursor ->
                    if (!cursor.moveToFirst()) {
                        return@use null
                    }
                    val index = cursor.getColumnIndex(Document.COLUMN_DISPLAY_NAME)
                    if (index >= 0 && !cursor.isNull(index)) {
                        cursor.getString(index)
                    } else {
                        null
                    }
                }
        } catch (_: Exception) {
            null
        }
    }

    /**
     * 文档在所属存储根内的相对目录，例如 `Documents/Lyrics`（不含文件名）。
     *
     * `COLUMN_RELATIVE_PATH` 是 API 26+ 的约定，且并非所有 provider 都返回
     * （Downloads、MediaDocuments 常为 null）：拿不到时返回 null，由展示层退化为
     * 只显示文件名，而不是回落到编码 URI。
     */
    private fun queryRelativePath(uri: Uri): String? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return null
        }
        return try {
            contentResolver.query(
                uri,
                arrayOf(Document.COLUMN_RELATIVE_PATH),
                null,
                null,
                null,
            )?.use { cursor ->
                if (!cursor.moveToFirst()) {
                    return@use null
                }
                val index = cursor.getColumnIndex(Document.COLUMN_RELATIVE_PATH)
                if (index >= 0 && !cursor.isNull(index)) {
                    cursor.getString(index)?.trim()?.takeIf { it.isNotEmpty() }
                } else {
                    null
                }
            }
        } catch (_: Exception) {
            null
        }
    }

    private fun tryApplyInitialUri(intent: Intent, initialDirectory: String?) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O || initialDirectory.isNullOrBlank()) {
            return
        }
        val initialUri =
            when {
                initialDirectory.startsWith("content://") ||
                    initialDirectory.startsWith("file://") -> Uri.parse(initialDirectory)
                else -> Uri.fromFile(File(initialDirectory))
            }
        intent.putExtra(DocumentsContract.EXTRA_INITIAL_URI, initialUri)
    }

    /**
     * 在指定父目录下按 displayName 查找直接子项。
     *
     * [expectDirectory] 用于区分"定位子目录"（保存模式逐级建目录）与"定位同名文件"
     * （写歌词时要覆盖同名文件）。两者必须分开：命中同名目录时不能当作文件覆盖。
     */
    private fun findChildDocumentUri(
        treeUri: Uri,
        parentDocumentId: String,
        displayName: String,
        expectDirectory: Boolean,
    ): Uri? {
        return try {
            val childrenUri =
                DocumentsContract.buildChildDocumentsUriUsingTree(treeUri, parentDocumentId)
            contentResolver.query(
                childrenUri,
                arrayOf(
                    Document.COLUMN_DOCUMENT_ID,
                    Document.COLUMN_DISPLAY_NAME,
                    Document.COLUMN_MIME_TYPE,
                ),
                null,
                null,
                null,
            )?.use { cursor ->
                val documentIdIndex = cursor.getColumnIndex(Document.COLUMN_DOCUMENT_ID)
                val displayNameIndex = cursor.getColumnIndex(Document.COLUMN_DISPLAY_NAME)
                val mimeTypeIndex = cursor.getColumnIndex(Document.COLUMN_MIME_TYPE)
                while (cursor.moveToNext()) {
                    if (documentIdIndex < 0 || displayNameIndex < 0) {
                        continue
                    }
                    if (cursor.isNull(documentIdIndex) || cursor.isNull(displayNameIndex)) {
                        continue
                    }
                    if (cursor.getString(displayNameIndex) != displayName) {
                        continue
                    }
                    val mimeType =
                        if (mimeTypeIndex >= 0 && !cursor.isNull(mimeTypeIndex)) {
                            cursor.getString(mimeTypeIndex)
                        } else {
                            null
                        }
                    if (SafTreeEntries.isDirectoryMime(mimeType) != expectDirectory) {
                        continue
                    }
                    return DocumentsContract.buildDocumentUriUsingTree(
                        treeUri,
                        cursor.getString(documentIdIndex),
                    )
                }
                null
            }
        } catch (_: Exception) {
            null
        }
    }

    /**
     * 在授权树内逐级定位（必要时创建）目录，返回目标目录的 document id。
     *
     * 每一级都用 treeUri + 当前目录 id 构造 URI，目录名来自 Dart 侧已校验的相对段，
     * 因此不会越出用户授权的子树。
     */
    private fun resolveDirectoryDocumentId(
        treeUri: Uri,
        rootDocumentId: String,
        segments: List<String>,
    ): String {
        var currentDocumentId = rootDocumentId
        for (segment in segments) {
            val existing =
                findChildDocumentUri(
                    treeUri = treeUri,
                    parentDocumentId = currentDocumentId,
                    displayName = segment,
                    expectDirectory = true,
                )
            if (existing != null) {
                currentDocumentId = DocumentsContract.getDocumentId(existing)
                continue
            }
            val parentUri = DocumentsContract.buildDocumentUriUsingTree(treeUri, currentDocumentId)
            val created =
                DocumentsContract.createDocument(
                    contentResolver,
                    parentUri,
                    Document.MIME_TYPE_DIR,
                    segment,
                ) ?: throw IOException("创建目录失败: $segment")
            currentDocumentId = DocumentsContract.getDocumentId(created)
        }
        return currentDocumentId
    }

    private fun deleteDocumentQuietly(uri: Uri) {
        try {
            DocumentsContract.deleteDocument(contentResolver, uri)
        } catch (_: Exception) {
            // 清理半成品是 best-effort：主错误必须保留给 Dart，不能被删除失败覆盖。
        }
    }
}
