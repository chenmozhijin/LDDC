package com.cmzj.lddc

/**
 * SAF MethodChannel 的纯参数规范化入口。
 *
 * Android UI、ContentResolver 和 fd 所有权仍由 MainActivity 管理；这里只保留
 * 无平台副作用的输入规则，使本地 JVM 测试能够覆盖错误边界，避免 emulator
 * 启动失败时原生通道完全没有测试证据。
 */
internal object SafChannelArguments {
    fun nonBlank(value: String?): String? = value?.trim()?.takeIf(String::isNotEmpty)

    fun validFileDescriptor(value: Int?): Int? = value?.takeIf { it >= 0 }

    fun mimeType(value: String?): String = nonBlank(value) ?: "text/plain"
}
