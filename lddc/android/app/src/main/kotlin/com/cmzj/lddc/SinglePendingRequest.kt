package com.cmzj.lddc

/**
 * 保存一个尚未收到系统 Activity result 的请求。
 *
 * begin 使用原子检查阻止重入；take 会先清空再把请求交给回调，避免回调过程中
 * 再次发起请求时被旧状态误判为 busy。Activity 销毁时用 take 取出并明确失败，
 * 不让 Dart Future 永久等待。
 */
internal class SinglePendingRequest<T> {
    private var value: T? = null

    @Synchronized
    fun begin(request: T): Boolean {
        if (value != null) {
            return false
        }
        value = request
        return true
    }

    @Synchronized
    fun take(): T? {
        val request = value
        value = null
        return request
    }

    @Synchronized
    fun count(): Int = if (value == null) 0 else 1
}
