package com.cmzj.lddc

import io.flutter.plugin.common.MethodChannel

internal data class PendingSaveTextFile(
    val result: MethodChannel.Result,
    val bytes: ByteArray,
)

/** 统一三个系统 Picker 的单请求状态、busy 错误和 Activity 销毁清理。 */
internal class PickerPendingRequestRegistry {
    private val tree = SinglePendingRequest<MethodChannel.Result>()
    private val audio = SinglePendingRequest<MethodChannel.Result>()
    private val save = SinglePendingRequest<PendingSaveTextFile>()

    fun beginTree(result: MethodChannel.Result): Boolean =
        begin(tree, result, result, "已有目录选择请求未完成")

    fun beginAudio(result: MethodChannel.Result): Boolean =
        begin(audio, result, result, "已有音频选择请求未完成")

    fun beginSave(request: PendingSaveTextFile): Boolean =
        begin(save, request, request.result, "已有文件保存请求未完成")

    fun takeTree(): MethodChannel.Result? = tree.take()

    fun takeAudio(): MethodChannel.Result? = audio.take()

    fun takeSave(): PendingSaveTextFile? = save.take()

    fun count(): Int = tree.count() + audio.count() + save.count()

    fun completeDestroyedRequests() {
        completeDestroyed(takeTree(), "目录选择因 Activity 销毁而终止")
        completeDestroyed(takeAudio(), "文件选择因 Activity 销毁而终止")
        completeDestroyed(takeSave()?.result, "文件保存因 Activity 销毁而终止")
    }

    private fun <T> begin(
        registry: SinglePendingRequest<T>,
        value: T,
        result: MethodChannel.Result,
        busyMessage: String,
    ): Boolean {
        if (registry.begin(value)) {
            return true
        }
        result.error("busy", busyMessage, null)
        return false
    }

    private fun completeDestroyed(
        result: MethodChannel.Result?,
        message: String,
    ) {
        if (result == null) {
            return
        }
        try {
            result.error("activity_destroyed", message, null)
        } catch (_: Exception) {
            // engine 可能已经开始分离。某个回调失败不能阻断其他 pending 请求清理。
        }
    }
}
