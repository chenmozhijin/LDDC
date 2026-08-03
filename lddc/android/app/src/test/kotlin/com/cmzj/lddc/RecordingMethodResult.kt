package com.cmzj.lddc

import io.flutter.plugin.common.MethodChannel

internal class RecordingMethodResult(
    private val throwOnError: Boolean = false,
) : MethodChannel.Result {
    var successValue: Any? = null
        private set
    var errorCode: String? = null
        private set
    var errorMessage: String? = null
        private set
    var errorDetails: Any? = null
        private set
    var notImplementedCount: Int = 0
        private set

    override fun success(result: Any?) {
        successValue = result
    }

    override fun error(
        errorCode: String,
        errorMessage: String?,
        errorDetails: Any?,
    ) {
        this.errorCode = errorCode
        this.errorMessage = errorMessage
        this.errorDetails = errorDetails
        if (throwOnError) {
            error("受控 Flutter 回调异常")
        }
    }

    override fun notImplemented() {
        notImplementedCount += 1
    }
}
