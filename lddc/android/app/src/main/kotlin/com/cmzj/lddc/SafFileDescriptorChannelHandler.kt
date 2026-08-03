package com.cmzj.lddc

import android.content.ContentResolver
import android.net.Uri
import android.os.ParcelFileDescriptor
import io.flutter.plugin.common.MethodChannel
import java.io.FileNotFoundException

internal data class OpenedSafFileDescriptor(
    val fd: Int,
    val nameHint: String?,
)

/**
 * 隔离 Android ContentResolver 与 MethodChannel 错误映射。
 *
 * MainActivity 只负责把生产 ContentResolver 接入该网关；参数校验、异常类型到稳定错误码的
 * 映射以及 raw fd 所有权都集中在这里。这样 JVM 测试可以注入确定性网关验证错误边界，
 * instrumentation 则继续使用相同生产实现和真实 URI grant，不需要测试 RPC 或反射。
 */
internal interface SafFileDescriptorGateway {
    fun open(uriText: String, mode: String): OpenedSafFileDescriptor?

    fun close(fd: Int)
}

internal class AndroidSafFileDescriptorGateway(
    private val contentResolver: ContentResolver,
    private val displayNameLookup: (Uri) -> String?,
) : SafFileDescriptorGateway {
    override fun open(uriText: String, mode: String): OpenedSafFileDescriptor? {
        val uri = Uri.parse(uriText)
        val descriptor = contentResolver.openFileDescriptor(uri, mode) ?: return null
        val fd = descriptor.detachFd()
        // detach 后 ParcelFileDescriptor 不再拥有底层 fd；close 仍要释放 Java 包装对象。
        descriptor.close()
        return OpenedSafFileDescriptor(
            fd = fd,
            nameHint = displayNameLookup(uri) ?: uri.lastPathSegment,
        )
    }

    override fun close(fd: Int) {
        ParcelFileDescriptor.adoptFd(fd).close()
    }
}

internal class SafFileDescriptorChannelHandler(
    private val gateway: SafFileDescriptorGateway,
) {
    private val ownedFileDescriptors = OwnedFileDescriptorRegistry(gateway::close)

    fun openReadOnly(uriText: String?, result: MethodChannel.Result) {
        open(uriText = uriText, mode = "r", result = result)
    }

    fun openReadWrite(uriText: String?, result: MethodChannel.Result) {
        open(uriText = uriText, mode = "rw", result = result)
    }

    fun close(fdValue: Int?, result: MethodChannel.Result) {
        val fd = SafChannelArguments.validFileDescriptor(fdValue)
        if (fd == null) {
            result.error("invalid_argument", "fd 非法", null)
            return
        }
        // 未登记或重复关闭按幂等成功处理，避免整数被系统复用后误关其他文件。
        ownedFileDescriptors.close(fd)
        result.success(null)
    }

    fun count(): Int = ownedFileDescriptors.count()

    fun closeAll(): Int = ownedFileDescriptors.closeAll()

    private fun open(
        uriText: String?,
        mode: String,
        result: MethodChannel.Result,
    ) {
        val normalizedUri = SafChannelArguments.nonBlank(uriText)
        if (normalizedUri == null) {
            result.error("invalid_argument", "uri 不能为空", null)
            return
        }
        try {
            val descriptor = gateway.open(normalizedUri, mode)
            if (descriptor == null) {
                result.error("open_fd_failed", "无法打开 SAF 文件描述符", null)
                return
            }
            if (!ownedFileDescriptors.register(descriptor.fd)) {
                // 注册冲突时新 fd 尚未交给 Dart，必须在失败前立即归还系统。
                gateway.close(descriptor.fd)
                result.error("fd_registry_conflict", "SAF 文件描述符所有权冲突", null)
                return
            }
            result.success(mapOf("fd" to descriptor.fd, "nameHint" to descriptor.nameHint))
        } catch (error: SecurityException) {
            result.error("permission_denied", "SAF 权限不足: ${error.message}", null)
        } catch (error: FileNotFoundException) {
            result.error("file_not_found", "SAF 文件不存在: ${error.message}", null)
        } catch (error: Exception) {
            result.error("open_fd_failed", "打开 SAF 文件描述符失败: ${error.message}", null)
        }
    }
}
