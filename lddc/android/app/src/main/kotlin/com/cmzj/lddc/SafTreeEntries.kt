package com.cmzj.lddc

/**
 * SAF 目录树 URI 与目录行的纯规则入口。
 *
 * 只放无平台副作用的判定，使本地 JVM 测试能够覆盖原生通道最关键的边界；
 * ContentResolver 调用仍集中在 MainActivity。
 */
internal object SafTreeEntries {
    // 平台把 PATH_TREE/PATH_DOCUMENT 声明为 private，这里只能以字面量表达；
    // 对应 DocumentsContract.getDocumentId() 的 tree/<treeDocId>/document/<childDocId> 分支。
    private const val PATH_TREE = "tree"
    private const val PATH_DOCUMENT = "document"

    // 同为字面量的 Document.MIME_TYPE_DIR 标准值，保持本对象不依赖 Android API。
    private const val MIME_TYPE_DIRECTORY = "vnd.android.document/directory"

    // 旧式目录类型。部分第三方 DocumentsProvider 仍在返回这些值，不兼容时目录会被判成
    // 文件，Dart 侧按扩展名过滤后整棵子树永远不会被遍历，而且不产生任何错误。
    private val LEGACY_DIRECTORY_MIME_TYPES = setOf(
        "resource/folder",
        "inode/directory",
        "application/x-directory",
    )

    /**
     * 取出本次请求真正要枚举的目录文档 id。
     *
     * 传入 URI 有两种形态：
     * - `content://<authority>/tree/<treeDocId>`：只需枚举树根，返回 null，由调用方回退
     *   [android.provider.DocumentsContract.getTreeDocumentId]；
     * - `content://<authority>/tree/<treeDocId>/document/<childDocId>`：返回 `<childDocId>`。
     *
     * 不能用 `getTreeDocumentId()` 去枚举子目录：平台实现只是取 `paths.get(1)`，对第二种
     * 形态同样返回树根 id，于是"枚举子目录"退化成"再枚举一次树根"，递归扫描永远进不了
     * 子目录（表现为只扫到所选目录的直接音频，0 条命中且无任何报错）。
     */
    fun currentDocumentId(segments: List<String>): String? {
        val isChildDocument = segments.size >= 4 &&
            segments[0] == PATH_TREE &&
            segments[2] == PATH_DOCUMENT
        if (!isChildDocument) {
            return null
        }
        return segments[3].takeIf(String::isNotEmpty)
    }

    /** 目录判定同时接受标准与旧式目录 MIME。 */
    fun isDirectoryMime(mimeType: String?): Boolean {
        val normalized = mimeType?.trim()?.lowercase()
        if (normalized.isNullOrEmpty()) {
            return false
        }
        return normalized == MIME_TYPE_DIRECTORY ||
            LEGACY_DIRECTORY_MIME_TYPES.contains(normalized)
    }

    /**
     * provider 用负数表示"未知大小/未知时间"。必须转成 null：Dart 侧把非负当作端口契约，
     * 负数会让整个目录页（最多 128 项）作废并被记成一次错误。
     */
    fun nonNegativeOrNull(value: Long?): Long? = value?.takeIf { it >= 0 }
}
