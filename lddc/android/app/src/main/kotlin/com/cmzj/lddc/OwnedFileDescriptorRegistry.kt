package com.cmzj.lddc

/**
 * 只管理由当前 Activity 从 ParcelFileDescriptor 分离出来的 raw fd。
 *
 * Linux/Android 会复用已经关闭的整数 fd。若直接对 Dart 传回的任意整数调用
 * adoptFd，第二次 close 可能误关后来复用同一整数的其他文件。注册表先移除所有权，
 * 再执行真正关闭，因此重复 close 是安全幂等操作，未知 fd 也绝不会触碰系统资源。
 */
internal class OwnedFileDescriptorRegistry(
    private val closeOwnedDescriptor: (Int) -> Unit,
) {
    private val owned = linkedSetOf<Int>()

    @Synchronized
    fun register(fd: Int): Boolean {
        if (fd < 0) {
            return false
        }
        return owned.add(fd)
    }

    fun close(fd: Int): Boolean {
        val shouldClose = synchronized(this) { owned.remove(fd) }
        if (!shouldClose) {
            return false
        }
        try {
            closeOwnedDescriptor(fd)
        } catch (_: Exception) {
            // 所有权已经从注册表移除。即使底层 close 抛错，也不能把同一整数重新
            // 放回集合，否则系统复用 fd 后再次关闭会伤及无关文件。
        }
        return true
    }

    fun closeAll(): Int {
        val descriptors = synchronized(this) {
            val snapshot = owned.toList()
            owned.clear()
            snapshot
        }
        for (fd in descriptors) {
            try {
                closeOwnedDescriptor(fd)
            } catch (_: Exception) {
                // Activity 销毁时必须继续清理剩余 fd，不能因单个异常提前中断。
            }
        }
        return descriptors.size
    }

    @Synchronized
    fun count(): Int = owned.size
}
