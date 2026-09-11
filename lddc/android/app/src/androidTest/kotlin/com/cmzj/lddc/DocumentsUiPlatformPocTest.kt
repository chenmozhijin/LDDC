package com.cmzj.lddc

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.provider.DocumentsContract
import android.provider.OpenableColumns
import android.util.Base64
import android.util.Log
import androidx.test.core.app.ActivityScenario
import androidx.test.core.app.ApplicationProvider
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.By
import androidx.test.uiautomator.Direction
import androidx.test.uiautomator.StaleObjectException
import androidx.test.uiautomator.UiDevice
import androidx.test.uiautomator.UiObject2
import androidx.test.uiautomator.Until
import io.flutter.plugin.common.MethodChannel
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.json.JSONObject
import java.io.File
import java.security.MessageDigest
import java.util.UUID
import java.util.concurrent.atomic.AtomicReference

class DocumentsUiPlatformPocTest {
    companion object {
        private const val APP_PACKAGE = "com.cmzj.lddc"
        private const val NAV_OPEN_LYRICS = "lddc.nav.open_lyrics"
        private const val NAV_LOCAL_MATCH = "lddc.nav.local_match"
        private const val OPEN_SONG_FILE = "lddc.open_lyrics.open_song_file"
        private const val CONVERT_OPEN_LYRICS = "lddc.open_lyrics.convert"
        private const val SAVE_LYRICS_FILE = "lddc.open_lyrics.save_file"
        private const val SAVE_LYRICS_TAG = "lddc.open_lyrics.save_tag"
        private const val PICK_TREE = "lddc.local_match.pick_tree"
        private const val SAVE_TAG_SUCCEEDED = "lddc.open_lyrics.notice.saveTagSucceeded"
        private const val SAVE_TAG_FAILED = "lddc.open_lyrics.notice.saveTagFailed"
        private const val CONVERT_FAILED = "lddc.open_lyrics.notice.convertFailed"
        private const val EMBEDDED_LYRICS = "Hello LDDC"
        private const val FIXTURE_DIRECTORY = "LDDCPlatformTest"
        private const val FIXTURE_PROVIDER_TITLE = "LDDC Platform Fixtures"
        private const val TIMEOUT_MS = 15_000L
        private const val RESOURCE_SETTLE_TIMEOUT_MS = 10_000L
        private const val RESOURCE_SAMPLE_INTERVAL_MS = 100L
        private const val RESOURCE_STABLE_SAMPLE_COUNT = 3
        private const val EVIDENCE_LOG_TAG = "LDDC_NATIVE_EVIDENCE"
        private const val EVIDENCE_LOG_PREFIX = "LDDC_EVIDENCE"
        private const val EVIDENCE_LOG_CHUNK_SIZE = 2_400
        private val DOCUMENTS_UI_PACKAGES =
            setOf("com.google.android.documentsui", "com.android.documentsui")
    }

    private lateinit var device: UiDevice
    private var scenario: ActivityScenario<MainActivity>? = null
    private var seededAudioUri: Uri? = null
    private var seededExportUri: Uri? = null
    private lateinit var seededAudioName: String
    private lateinit var runId: String
    private lateinit var initialPersistedTreeUris: Set<String>
    private val capabilityEvidence = linkedMapOf<String, MutableList<Map<String, Any?>>>()
    private val artifacts = mutableListOf<Map<String, Any?>>()
    private var hostedSystemAnrDetected = false

    @Before
    fun setUp() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        device = UiDevice.getInstance(instrumentation)
        runId =
            InstrumentationRegistry.getArguments().getString("lddcRunId")
                ?: "local-${UUID.randomUUID()}"
        capabilityEvidence.clear()
        artifacts.clear()
        hostedSystemAnrDetected = false
        initialPersistedTreeUris = persistedTreeUris()
        seededAudioName = "lddc-platform-${UUID.randomUUID().toString().take(8)}.mp3"
        val fixtureBytes =
            instrumentation.context.assets.open("audio_sample.mp3").use { input -> input.readBytes() }
        val seedResult =
            callFixtureSeedProvider(
                PlatformFixtureSeedProvider.METHOD_SEED_AUDIO,
                Bundle().apply {
                    putString(PlatformFixtureSeedProvider.EXTRA_RUN_ID, runId)
                    putString(PlatformFixtureSeedProvider.EXTRA_DISPLAY_NAME, seededAudioName)
                    putByteArray(PlatformFixtureSeedProvider.EXTRA_BYTES, fixtureBytes)
                },
            )
        seededAudioUri =
            Uri.parse(
                requireNotNull(seedResult.getString(PlatformFixtureSeedProvider.EXTRA_URI)) {
                    "fixture seed provider 没有返回文档 URI"
                },
            )
        // test APK 在 connectedAndroidTest 启动前才安装，DocumentsUI 进程可能仍持有
        // 安装前的 provider 根缓存。只终止系统 Picker 进程让它下次按 PackageManager
        // 和 roots URI 重建状态，不修改应用数据，也不注入任何选择结果。
        DOCUMENTS_UI_PACKAGES.forEach { packageName ->
            device.executeShellCommand("am force-stop $packageName")
        }
        scenario = ActivityScenario.launch(MainActivity::class.java)
        assertTrue("LDDC 未进入前台", waitForLddcForeground())
    }

    @After
    fun tearDown() {
        try {
            scenario?.close()
        } finally {
            callFixtureSeedProvider(
                PlatformFixtureSeedProvider.METHOD_CLEANUP_RUN,
                Bundle().apply { putString(PlatformFixtureSeedProvider.EXTRA_RUN_ID, runId) },
            )
            seededExportUri?.let { uri ->
                // 场景异常退出时仍尽力删除已经由系统保存器创建的测试文件；主流程
                // 会对相同 helper 的返回值做强断言，这里不能用清理异常覆盖原始失败。
                deleteSavedDocument(uri)
            }
            releaseNewPersistedTreePermissions()
        }
    }

    @Test
    fun semanticsIdentifierCanOpenDocumentsUiAndSelectRealAudio() {
        runReported("android_documentsui_select") {
            verifySafFileDescriptorErrorMappings()
            selectSeededAudio()
            recordCapability(
                "filePicker",
                "documentsui_select_audio",
                mapOf("selectedName" to seededAudioName, "uriScheme" to "content"),
            )
            recordCapability("nativeChannels", "flutter_picker_round_trip")
            recordCapability("media", "saf_fd_taglib_read_embedded_lyrics")

            waitForObjectWithBoundedScroll(By.res(CONVERT_OPEN_LYRICS), "Flutter 未暴露歌词转换动作").click()
            waitForEnabledObject(By.res(SAVE_LYRICS_TAG), "歌词转换后写入歌曲标签按钮仍不可用").click()
            waitForSaveTagOutcome()
            recordCapability("media", "saf_read_write_fd_tag_saved")

            // 音频页会在会话期间持有只读 fd。重建 Activity 可直接验证旧实例的
            // onDestroy 是否把 registry 清零，而不是把合法会话 fd 误判为泄漏。
            scenario?.recreate()
            assertTrue("Activity 重建后 LDDC 未恢复", waitForLddcForeground())
            selectSeededAudio()
            recordCapability("media", "saved_tag_reopened_after_activity_recreation")
            recordSelectedArtifact()

            // 第二次打开留下的会话 fd 也必须在场景结束前由 Activity 生命周期释放。
            scenario?.recreate()
            assertTrue("第二次 Activity 重建后 LDDC 未恢复", waitForLddcForeground())
        }
    }

    @Test
    fun documentsUiCancellationReturnsToSameFlutterAction() {
        runReported("android_documentsui_cancel") {
            openSongPicker()
            device.pressBack()

            assertTrue("取消后没有返回 LDDC", waitForLddcForeground())
            assertNotNull(
                "取消后打开歌曲动作不可再次发现",
                device.wait(Until.findObject(By.res(OPEN_SONG_FILE)), TIMEOUT_MS),
            )
            recordCapability("filePicker", "documentsui_cancel")
            recordCapability("nativeChannels", "flutter_picker_cancel_round_trip")
        }
    }

    @Test
    fun documentsUiSavesLyricsAndReadsBackRealOutput() {
        runReported("android_documentsui_save") {
            selectSeededAudio()
            // 音频标签先以原始文本打开；只有执行生产 Converter 后，保存格式才是
            // LRC。旧测试跳过转换却手工输入 .lrc，制造了 text/plain 与扩展名
            // 冲突，DocumentsUI 正确地追加了 .txt，因而不能代表真实 LRC 导出。
            waitForObjectWithBoundedScroll(
                By.res(CONVERT_OPEN_LYRICS),
                "Flutter 未暴露歌词转换动作",
            ).click()
            val outputName = "lddc-export-${UUID.randomUUID()}.lrc"
            waitForEnabledObject(
                By.res(SAVE_LYRICS_FILE),
                "歌词转换后文件保存按钮仍不可用",
            ).click()
            waitForDocumentsUi()
            val fileNameInput = waitForDocumentsUiFileNameInput()
            fileNameInput.text = outputName
            assertTrue(
                "DocumentsUI 拒绝写入目标文件名，禁止继续保存默认文件名",
                device.wait(
                    Until.hasObject(
                        By.clazz("android.widget.EditText").text(outputName),
                    ),
                    TIMEOUT_MS,
                ),
            )
            waitForDocumentsUiResource(
                listOf("action_menu_save", "button1"),
                "DocumentsUI 没有暴露保存动作",
            ).click()

            assertTrue("保存后没有返回 LDDC", waitForLddcForeground())
            val output = waitForSavedDocumentFromUi(outputName)
            seededExportUri = output.first
            assertTrue("真实 ACTION_CREATE_DOCUMENT 输出没有歌词正文", output.second.toString(Charsets.UTF_8).contains(EMBEDDED_LYRICS))
            recordArtifact(outputName, output.second)
            recordCapability("filePicker", "documentsui_create_document")
            recordCapability("nativeChannels", "flutter_save_text_round_trip")

            // 打开歌曲后仍持有只读 fd；重建 Activity 后再做最终资源快照，证明保存流程
            // 没有用残留媒体句柄掩盖文件导出结果。
            scenario?.recreate()
            assertTrue("保存后的 Activity 重建没有恢复 LDDC", waitForLddcForeground())
            assertTrue(
                "真实 ACTION_CREATE_DOCUMENT 输出未能通过 DocumentsContract 删除",
                deleteSavedDocument(output.first),
            )
            seededExportUri = null
        }
    }

    @Test
    fun documentsUiPersistsAndReleasesTreePermission() {
        runReported("android_documentsui_tree") {
            waitForObject(By.res(NAV_LOCAL_MATCH), "UI Automator 无法发现本地匹配导航").click()
            // 目录入口位于目标页顶部 Header。导航点击后应等待新路由建立语义树；
            // 若立即抓取任意 scrollable，可能误滚动尚未切换完成的旧页面或队列列表。
            waitForObject(By.res(PICK_TREE), "Flutter 未暴露 Android 目录选择动作").click()
            waitForDocumentsUi()

            // Android 11+ 禁止授权 Downloads 等系统根。明确进入 test-only provider
            // 的可写子目录，不能因 Picker 记住了其他位置就授权“当前目录”。
            openFixtureRunDirectoryInDocumentsUi()
            val select = waitForDocumentsUiResource(
                listOf("action_menu_select", "button1"),
                "DocumentsUI 没有暴露目录确认动作",
            )
            assertTrue("当前 DocumentsUI 目录不可授权", select.isEnabled)
            select.click()
            completeTreeSelectionConfirmation()

            val persisted = waitForNewPersistedTreePermission()
            assertTrue("持久目录授权没有读权限", persisted.isReadPermission)
            recordCapability("filePicker", "documentsui_open_document_tree")
            recordCapability("nativeChannels", "pick_tree_and_persist_permission_round_trip")

            releasePersistedPermission(persisted.uri, persisted.isReadPermission, persisted.isWritePermission)
            assertTrue("测试新增的持久目录授权没有释放", persistedTreeUris() == initialPersistedTreeUris)
        }
    }

    @Test
    fun pendingPickerIsReleasedWhenActivityIsDestroyed() {
        runReported("android_documentsui_lifecycle") {
            openSongPicker()
            val pendingBeforeDestroy = activityResourceSnapshot()["pendingPickerCount"]
            assertTrue("DocumentsUI 打开后生产 Activity 没有登记 pending picker", pendingBeforeDestroy == 1)

            // 系统 Picker 仍在前台时销毁被测 Activity，直接覆盖用户切走、系统回收或
            // 配置变更发生在选择过程中的生命周期边界。旧 Activity 必须先完成 pending
            // Future，再释放 fd；新实例不能继承陈旧 busy 状态。
            scenario?.close()
            scenario = null
            recordCapability(
                "lifecycle",
                "pending_picker_activity_destroyed",
                mapOf("pendingPickerCountBeforeDestroy" to pendingBeforeDestroy),
            )

            if (DOCUMENTS_UI_PACKAGES.any { packageName -> device.findObject(By.pkg(packageName)) != null }) {
                device.pressBack()
            }
            scenario = ActivityScenario.launch(MainActivity::class.java)
            assertTrue(
                "Activity 销毁后无法重新启动 LDDC",
                waitForLddcForeground(),
            )
            assertTrue(
                "新 Activity 继承了旧实例的 pending picker",
                activityResourceSnapshot()["pendingPickerCount"] == 0,
            )

            openSongPicker()
            device.pressBack()
            assertTrue(
                "重启后取消 DocumentsUI 没有返回 LDDC",
                waitForLddcForeground(),
            )
            assertTrue(
                "重启后的取消流程没有清空 pending picker",
                activityResourceSnapshot()["pendingPickerCount"] == 0,
            )
            recordCapability("filePicker", "documentsui_cancel_after_activity_restart")
            recordCapability("nativeChannels", "pending_picker_destroyed_and_reopened")
        }
    }

    private fun openSongPicker() {
        waitForObject(By.res(NAV_OPEN_LYRICS), "UI Automator 无法发现 Flutter 主导航").click()
        waitForObject(By.res(OPEN_SONG_FILE), "UI Automator 无法发现打开歌曲按钮").click()
        waitForDocumentsUi()
    }

    private fun verifySafFileDescriptorErrorMappings() {
        val selectedUri = seededAudioUri ?: throw AssertionError("seed 音频 URI 已丢失")
        assertSafFdError(selectedUri, "permission_denied", "未授权的真实 DocumentsProvider URI")

        val grantResult =
            callFixtureSeedProvider(
                PlatformFixtureSeedProvider.METHOD_GRANT_MISSING_AUDIO,
                Bundle().apply { putString(PlatformFixtureSeedProvider.EXTRA_RUN_ID, runId) },
            )
        val missingUri =
            Uri.parse(
                requireNotNull(grantResult.getString(PlatformFixtureSeedProvider.EXTRA_URI)) {
                    "fixture seed provider 没有返回已授权的缺失文档 URI"
                },
            )
        try {
            // test provider 自己授予 URI 后，ContentResolver 会真实进入 provider 的
            // FileNotFoundException，区分“无权限”和“已授权但不存在”两个错误路径。
            assertSafFdError(missingUri, "file_not_found", "不存在的已授权文档")
        } finally {
            callFixtureSeedProvider(
                PlatformFixtureSeedProvider.METHOD_REVOKE_URI,
                Bundle().apply { putString(PlatformFixtureSeedProvider.EXTRA_URI, missingUri.toString()) },
            )
        }
        recordCapability("nativeChannels", "saf_fd_permission_denied")
        recordCapability("nativeChannels", "saf_fd_file_not_found")
    }

    private fun assertSafFdError(
        uri: Uri,
        expectedCode: String,
        description: String,
    ) {
        scenario?.onActivity { activity ->
            val handler =
                SafFileDescriptorChannelHandler(
                    AndroidSafFileDescriptorGateway(activity.contentResolver) { value -> value.lastPathSegment },
                )
            val result = RecordingNativeResult()
            handler.openReadOnly(uri.toString(), result)
            assertEquals("$description 没有映射为 $expectedCode", expectedCode, result.errorCode)
            assertEquals("$description 失败后错误登记了 raw fd", 0, handler.count())
        } ?: throw AssertionError("ActivityScenario 已关闭")
    }

    private fun callFixtureSeedProvider(method: String, extras: Bundle): Bundle {
        val resolver = InstrumentationRegistry.getInstrumentation().targetContext.contentResolver
        val uri = Uri.parse("content://${PlatformFixtureSeedProvider.AUTHORITY}")
        return resolver.call(uri, method, null, extras)
            ?: throw AssertionError("fixture seed provider 调用没有返回结果: $method")
    }

    private fun selectSeededAudio() {
        openSongPicker()
        findSeededAudioInDocumentsUi().click()
        assertTrue("选择文件后没有返回 LDDC", waitForLddcForeground())
        assertTrue(
            "生产 TagLib 没有从 SAF fd 回读匿名内嵌歌词",
            device.wait(Until.hasObject(By.textContains(EMBEDDED_LYRICS)), TIMEOUT_MS),
        )
    }

    private fun findSeededAudioInDocumentsUi(): UiObject2 {
        device.findObject(By.text(seededAudioName))?.let { return it }

        openFixtureRunDirectoryInDocumentsUi()
        return device.wait(
            Until.findObject(By.text(seededAudioName).clazz("android.widget.TextView")),
            TIMEOUT_MS,
        ) ?: throw DocumentsUiFailureException("DocumentsUI 进入测试 provider 后没有返回 seed 音频")
    }

    private fun waitForLddcForeground(): Boolean {
        // Android 15 的无障碍窗口会在系统装饰节点下暴露应用语义树，应用包节点
        // 不再保证位于 depth(0)。固定根深度会把已经 RESUMED、完成首帧的 LDDC
        // 误判为未启动；包名仍由系统提供且不会匹配 DocumentsUI，因此只移除错误
        // 的层级假设，不降低“必须真实返回应用窗口”的前台证据。
        val deadline = System.currentTimeMillis() + TIMEOUT_MS
        var handledSystemAnr = false
        val systemAnrWaitSelector = By.res("android", "aerr_wait")
        while (System.currentTimeMillis() < deadline) {
            val waitButton = device.findObject(systemAnrWaitSelector)
            if (waitButton != null) {
                // Hosted emulator 偶发在冷启动时弹出 Quickstep ANR，系统模态层会
                // 挡住 ActivityScenario 请求启动的 LDDC。必须先处理模态层再判断
                // 应用节点；否则 LDDC 节点即使位于对话框后方也会被误判为可操作。
                // 只允许在 LDDC 节点尚不存在时按系统资源 ID 点一次“等待”。节点
                // 已存在或 ANR 再次出现都可能是 LDDC 自身无响应，必须失败而不能
                // 被测试基础设施吞掉。
                if (handledSystemAnr || device.hasObject(By.pkg(APP_PACKAGE))) {
                    Log.e(EVIDENCE_LOG_TAG, "system ANR remained after LDDC launch request")
                    return false
                }
                waitButton.click()
                handledSystemAnr = true
                device.wait(Until.gone(systemAnrWaitSelector), 2_000)
                device.waitForIdle(100)
                Log.w(EVIDENCE_LOG_TAG, "dismissed pre-launch system ANR with android:id/aerr_wait")
                continue
            }
            if (
                device.currentPackageName == APP_PACKAGE &&
                    device.hasObject(By.pkg(APP_PACKAGE))
            ) {
                return true
            }
            Thread.sleep(250)
        }
        return false
    }

    private fun openFixtureRunDirectoryInDocumentsUi() {
        // ACTION_OPEN_DOCUMENT 与 ACTION_OPEN_DOCUMENT_TREE 都会记住上次目录；已经
        // 位于本次 runId 目录时直接返回，避免无意义地重开 roots 抽屉。
        if (device.findObject(By.text(seededAudioName)) != null) {
            return
        }
        if (device.findObject(By.text(FIXTURE_DIRECTORY)) != null) {
            clickFreshDocumentsUiObject(
                By.clickable(true)
                    .enabled(true)
                    .hasDescendant(By.text(FIXTURE_DIRECTORY)),
            ) {
                "DocumentsUI 没有暴露可进入的运行隔离目录；当前界面=${documentsUiStateSummary()}"
            }
            return
        }

        // DocumentsUI 会记住上一次访问的 Downloads 等位置，test-only provider
        // 因而不一定出现在当前内容区。导航按钮没有 resource-id，content-desc 又会
        // 随系统语言变化；通过稳定 toolbar 资源和按钮控件类型打开 roots 抽屉，
        // 可以避免把坐标或本地化系统文案写进平台门禁。
        if (device.findObject(By.text(FIXTURE_PROVIDER_TITLE)) == null) {
            val toolbar =
                waitForDocumentsUiResource(
                    listOf("toolbar"),
                    "DocumentsUI 没有暴露稳定的 toolbar 资源",
                )
            val rootsButton =
                toolbar.findObject(By.clazz("android.widget.ImageButton").clickable(true))
                    ?: throw DocumentsUiFailureException("DocumentsUI toolbar 没有可点击的 roots 导航按钮")
            rootsButton.click()
            device.waitForIdle(500)
        }

        // 标题由测试 provider 自己控制，不是系统本地化文案。不同 DocumentsUI
        // 版本的标题可能多包一层布局。抽屉动画会让已缓存的 UiObject2 失效，
        // 因此用 UI Automator 原生 hasDescendant 一次查询可点击容器，避免逐层读取
        // parent 触发 StaleObjectException。最终文件仍按随机完整名称选择。
        clickFreshDocumentsUiObject(
            By.clickable(true)
                .enabled(true)
                .hasDescendant(By.text(FIXTURE_PROVIDER_TITLE)),
        ) {
            "DocumentsUI 没有发现可点击的测试文档 provider；当前界面=${documentsUiStateSummary()}"
        }
        clickFreshDocumentsUiObject(
            By.clickable(true)
                .enabled(true)
                .hasDescendant(By.text(FIXTURE_DIRECTORY)),
        ) {
            "DocumentsUI 进入测试 provider 后没有发现运行隔离目录；当前界面=${documentsUiStateSummary()}"
        }
    }

    private fun clickFreshDocumentsUiObject(
        selector: androidx.test.uiautomator.BySelector,
        message: () -> String,
    ) {
        val deadline = System.currentTimeMillis() + TIMEOUT_MS
        var lastStaleObject: StaleObjectException? = null
        while (System.currentTimeMillis() < deadline) {
            val candidate = device.findObject(selector)
            if (candidate != null) {
                try {
                    candidate.click()
                    return
                } catch (error: StaleObjectException) {
                    // DocumentsUI 抽屉动画会替换 accessibility node。旧对象失效后
                    // 必须重新执行 selector，不能缓存对象、改用坐标或重跑整个测试。
                    lastStaleObject = error
                }
            }
            device.waitForIdle(100)
        }
        val failure = DocumentsUiFailureException(message())
        lastStaleObject?.let(failure::initCause)
        throw failure
    }

    private fun waitForDocumentsUi() {
        val deadline = System.currentTimeMillis() + TIMEOUT_MS
        var recoveredSystemAnr = false
        while (System.currentTimeMillis() < deadline) {
            if (detectHostedSystemAnr()) {
                if (recoveredSystemAnr) {
                    // 已按“等待”恢复过一次仍然复发，说明系统模态层无法用恢复动作消除，
                    // 继续点击只会无限延长门禁时间。此时必须按系统 ANR 分类失败，
                    // 交给 runner 在零业务动作时做有界重启，不能假装恢复成功。
                    throw HostedSystemAnrException("DocumentsUI 等待期间系统 ANR 反复出现")
                }
                dismissSystemAnrModal()
                recoveredSystemAnr = true
                continue
            }
            if (device.currentPackageName in DOCUMENTS_UI_PACKAGES) {
                return
            }
            device.waitForIdle(100)
        }
        throw DocumentsUiFailureException("真实 DocumentsUI 没有打开，禁止回退坐标点击")
    }

    private fun documentsUiStateSummary(): String {
        val packageName = device.currentPackageName ?: "unknown"
        val values =
            device.findObjects(By.pkg(packageName))
                .flatMap { node ->
                    // 诊断发生时系统界面可能仍在动画，单个节点失效不应覆盖原始
                    // 断言。这里只跳过 stale 节点，正常 selector 仍严格失败。
                    try {
                        listOfNotNull(node.text, node.contentDescription)
                    } catch (_: StaleObjectException) {
                        emptyList()
                    }
                }
                .map(String::trim)
                .filter(String::isNotEmpty)
                .distinct()
                .take(24)
        return "package=$packageName values=$values"
    }

    private fun returnFromDocumentsUiForResourceSnapshot() {
        val deadline = System.currentTimeMillis() + 5_000
        // hosted emulator 的 Quickstep ANR 属于 DocumentsUI 之上的系统模态层。
        // 该模态层只能按 android:id/aerr_wait 关闭：它在窗口层级里顶替了前台窗口，
        // device.currentPackageName 会返回 android 而不是 DocumentsUI，按返回键也
        // 不会消除对话框。旧实现只按返回键并在包名循环里判断是否退出，导致模态层
        // 一直挡住 Picker 的取消回调，pendingPickerCount 永远停在 1，于是真实原因
        // 被误分类为 resource_cleanup_failure，runner 的零动作重启分支无法触发。
        // 这里不改变原始失败分类，ANR 事实仍由 writeEvidence 单独记录。
        dismissSystemAnrModal()
        while (System.currentTimeMillis() < deadline && device.currentPackageName in DOCUMENTS_UI_PACKAGES) {
            // 失败可能发生在 provider 根、Recent 或搜索页。Back 是系统导航语义，
            // 逐层返回会触发生产 Picker 的取消回调并清空 pending request。
            device.pressBack()
            device.waitForIdle(200)
        }
        // 关闭系统模态层后 Picker 才可能真正退出；窗口切换与取消回调是异步的，
        // 这里只留出固定的短暂观察窗口，不做无界等待。
        repeat(10) {
            if (device.currentPackageName !in DOCUMENTS_UI_PACKAGES) {
                return
            }
            device.waitForIdle(200)
        }
    }

    private fun findDocumentsUiResource(resourceNames: List<String>): UiObject2? {
        for (resourceName in resourceNames) {
            for (packageName in DOCUMENTS_UI_PACKAGES + "android") {
                device.findObject(By.res(packageName, resourceName))?.let { return it }
            }
        }
        return null
    }

    private fun waitForDocumentsUiResource(resourceNames: List<String>, message: String): UiObject2 {
        val deadline = System.currentTimeMillis() + TIMEOUT_MS
        var recoveredSystemAnr = false
        while (System.currentTimeMillis() < deadline) {
            if (detectHostedSystemAnr()) {
                if (recoveredSystemAnr) {
                    // 与 waitForDocumentsUi 同一契约：恢复只允许一次，复发即按系统 ANR
                    // 失败，避免用反复“等待”掩盖真实的系统无响应。
                    throw HostedSystemAnrException("等待 DocumentsUI 资源时系统 ANR 反复出现")
                }
                dismissSystemAnrModal()
                recoveredSystemAnr = true
                continue
            }
            findDocumentsUiResource(resourceNames)?.let { return it }
            device.waitForIdle(100)
        }
        throw DocumentsUiFailureException(message)
    }

    private fun detectHostedSystemAnr(): Boolean {
        val waitButton = device.findObject(By.res("android", "aerr_wait"))
        val closeButton = device.findObject(By.text("Close app"))
        val waitText = device.findObject(By.text("Wait"))
        val quickstepMessage = device.findObject(By.textContains("Quickstep isn't responding"))
        val detected = waitButton != null || closeButton != null || waitText != null || quickstepMessage != null
        if (detected) {
            hostedSystemAnrDetected = true
            Log.e(EVIDENCE_LOG_TAG, "hosted system ANR detected during system UI interaction")
        }
        return detected
    }

    /**
     * 关闭已经出现的宿主系统 ANR 模态层，返回是否真的执行了恢复动作。
     *
     * 系统 ANR 对话框属于 `android` 包，会替换前台窗口并拦截输入。只要它在场，
     * DocumentsUI 的点击与返回键都不会生效。这里只在检测到系统对话框资源
     * `android:id/aerr_wait` 时动作，并且要求 `aerr_close` 不存在：真实 ANR
     * 对话框会同时提供“关闭应用”和“等待”，出现 `aerr_close` 说明无法确定是
     * 哪个进程无响应，保守地不做恢复，让上层按失败处理，避免吞掉被测应用
     * 自身的无响应缺陷。恢复最多由调用方各执行一次，避免把持续无响应伪装成通过。
     */
    private fun dismissSystemAnrModal(): Boolean {
        val waitButton = device.findObject(By.res("android", "aerr_wait")) ?: return false
        if (device.findObject(By.res("android", "aerr_close")) != null) {
            // Android 同时提供“关闭应用/等待”时无法区分宿主应用与系统进程，
            // 保守地不做恢复，让上层按失败处理。
            Log.e(EVIDENCE_LOG_TAG, "system ANR close action present; refusing automated recovery")
            return false
        }
        try {
            waitButton.click()
        } catch (_: StaleObjectException) {
            // 对话框正好在点击瞬间被系统移除属于正常恢复路径，不需要额外重试。
            // 本轮恢复额度已经消耗，上层会用 detectHostedSystemAnr() 重新判定。
        }
        device.wait(Until.gone(By.res("android", "aerr_wait")), 2_000)
        device.waitForIdle(100)
        Log.w(EVIDENCE_LOG_TAG, "dismissed hosted system ANR with android:id/aerr_wait")
        return true
    }

    private fun waitForDocumentsUiFileNameInput(): UiObject2 {
        val deadline = System.currentTimeMillis() + TIMEOUT_MS
        while (System.currentTimeMillis() < deadline) {
            // AOSP/API 35 的输入框与文件列表项都使用 android:id/title，不能只按
            // resource-id 查询，否则会对普通 TextView 执行 ACTION_SET_TEXT 后继续
            // 保存错误名称。部分厂商版本改用 file_name，两者都必须同时限制为
            // EditText，确保命中的确是可编辑文件名控件。
            for (resourceName in listOf("title", "file_name")) {
                for (packageName in DOCUMENTS_UI_PACKAGES + "android") {
                    device.findObject(
                        By.res(packageName, resourceName)
                            .clazz("android.widget.EditText"),
                    )?.let { return it }
                }
            }
            device.waitForIdle(100)
        }
        throw DocumentsUiFailureException("DocumentsUI 没有暴露可编辑的文件名输入框")
    }

    private fun completeTreeSelectionConfirmation() {
        val deadline = System.currentTimeMillis() + TIMEOUT_MS
        while (System.currentTimeMillis() < deadline) {
            if (device.currentPackageName == APP_PACKAGE) {
                return
            }
            // 部分 Android 版本会延迟显示第二层系统确认框；只按系统资源 ID
            // 处理，不依赖本地化按钮名称或屏幕坐标。
            findDocumentsUiResource(listOf("button1"))?.let { confirm ->
                if (confirm.isEnabled) {
                    confirm.click()
                }
            }
            device.waitForIdle(100)
        }
        throw AssertionError("目录授权后没有返回 LDDC")
    }

    private fun waitForObject(selector: androidx.test.uiautomator.BySelector, message: String): UiObject2 {
        return device.wait(Until.findObject(selector), TIMEOUT_MS) ?: throw AssertionError(message)
    }

    private fun waitForSaveTagOutcome() {
        val deadline = System.currentTimeMillis() + TIMEOUT_MS
        while (System.currentTimeMillis() < deadline) {
            device.findObject(By.res(SAVE_TAG_SUCCEEDED))?.let { return }
            device.findObject(By.res(SAVE_TAG_FAILED))?.let { failure ->
                val detail = failure.text?.takeIf(String::isNotBlank) ?: failure.contentDescription
                throw AssertionError("真实 SAF fd 写入歌词标签失败: ${detail ?: "未提供错误详情"}")
            }
            device.waitForIdle(100)
        }
        throw AssertionError("真实 SAF fd 写入歌词标签没有产生成功或失败结果")
    }

    private fun waitForEnabledObject(
        selector: androidx.test.uiautomator.BySelector,
        message: String,
    ): UiObject2 {
        // 紧凑窗口中的 OverflowBar 可能把后续动作放到当前视口之外；先执行
        // 有界滚动，再观察转换完成后的 enabled 状态，不能把不可见误判成禁用。
        waitForObjectWithBoundedScroll(selector, message)
        val deadline = System.currentTimeMillis() + TIMEOUT_MS
        while (System.currentTimeMillis() < deadline) {
            device.findObject(selector)?.let { candidate ->
                if (candidate.isEnabled) {
                    return candidate
                }
            }
            device.findObject(By.res(CONVERT_FAILED))?.let { failure ->
                val detail = failure.text?.takeIf(String::isNotBlank) ?: failure.contentDescription
                throw AssertionError("歌词转换失败: ${detail ?: "未提供错误详情"}")
            }
            device.waitForIdle(100)
        }
        throw AssertionError(message)
    }

    private fun waitForObjectWithBoundedScroll(
        selector: androidx.test.uiautomator.BySelector,
        message: String,
    ): UiObject2 {
        device.findObject(selector)?.let { return it }
        val scrollable = waitForObject(By.scrollable(true), "Flutter 页面没有暴露可滚动语义容器")
        repeat(6) {
            scrollable.scroll(Direction.DOWN, 0.8f)
            device.waitForIdle(250)
            device.findObject(selector)?.let { return it }
        }
        throw AssertionError(message)
    }

    private fun waitForSavedDocumentFromUi(displayName: String): Pair<Uri, ByteArray> {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        val resolver = context.contentResolver
        val deadline = System.currentTimeMillis() + TIMEOUT_MS
        var lastObservedName: String? = null
        while (System.currentTimeMillis() < deadline) {
            val nodes =
                (device.findObjects(By.textContains("content://")) +
                    device.findObjects(By.descContains("content://"))).distinct()
            for (node in nodes) {
                val value =
                    try {
                        listOfNotNull(node.text, node.contentDescription).joinToString(" ")
                    } catch (_: StaleObjectException) {
                        continue
                    }
                val uriText = Regex("""content://[^\s，。；]+""").find(value)?.value ?: continue
                val uri = Uri.parse(uriText.trimEnd(',', ';', ')', ']', '}'))
                val observedName =
                    resolver.query(
                        uri,
                        arrayOf(OpenableColumns.DISPLAY_NAME),
                        null,
                        null,
                        null,
                    )?.use { cursor ->
                        if (!cursor.moveToFirst()) {
                            null
                        } else {
                            cursor.getString(
                                cursor.getColumnIndexOrThrow(OpenableColumns.DISPLAY_NAME),
                            )
                        }
                    }
                lastObservedName = observedName
                if (observedName == displayName) {
                    val bytes = resolver.openInputStream(uri)?.use { input -> input.readBytes() }
                    if (bytes != null) {
                        return uri to bytes
                    }
                }
            }
            Thread.sleep(100)
        }
        throw AssertionError(
            "保存成功界面没有返回可回读的精确目标 URI；expected=$displayName, observed=$lastObservedName",
        )
    }

    private fun deleteSavedDocument(uri: Uri): Boolean {
        val resolver =
            ApplicationProvider.getApplicationContext<android.content.Context>()
                .contentResolver
        return try {
            if (!DocumentsContract.deleteDocument(resolver, uri)) {
                false
            } else {
                // 删除成功后再查询同一授权 URI。provider 返回空游标或抛出文件不存在
                // 都表示资源已释放；仍能读到条目则必须让平台场景失败。
                val stillExists =
                    try {
                        resolver.query(
                            uri,
                            arrayOf(OpenableColumns.DISPLAY_NAME),
                            null,
                            null,
                            null,
                        )?.use { cursor -> cursor.moveToFirst() } == true
                    } catch (_: Exception) {
                        false
                    }
                !stillExists
            }
        } catch (_: Exception) {
            false
        }
    }

    private fun persistedTreeUris(): Set<String> {
        return InstrumentationRegistry.getInstrumentation().targetContext
            .contentResolver
            .persistedUriPermissions
            .map { it.uri.toString() }
            .toSet()
    }

    private fun waitForNewPersistedTreePermission(): android.content.UriPermission {
        val resolver = InstrumentationRegistry.getInstrumentation().targetContext.contentResolver
        val deadline = System.currentTimeMillis() + TIMEOUT_MS
        while (System.currentTimeMillis() < deadline) {
            resolver.persistedUriPermissions.firstOrNull {
                it.uri.toString() !in initialPersistedTreeUris
            }?.let { return it }
            Thread.sleep(100)
        }
        throw AssertionError("应用没有取得新的持久目录授权")
    }

    private fun releasePersistedPermission(uri: Uri, readable: Boolean, writable: Boolean) {
        var flags = 0
        if (readable) flags = flags or Intent.FLAG_GRANT_READ_URI_PERMISSION
        if (writable) flags = flags or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
        if (flags != 0) {
            InstrumentationRegistry.getInstrumentation().targetContext
                .contentResolver
                .releasePersistableUriPermission(uri, flags)
        }
    }

    private fun releaseNewPersistedTreePermissions() {
        val resolver = InstrumentationRegistry.getInstrumentation().targetContext.contentResolver
        for (permission in resolver.persistedUriPermissions.toList()) {
            if (permission.uri.toString() !in initialPersistedTreeUris) {
                releasePersistedPermission(
                    permission.uri,
                    permission.isReadPermission,
                    permission.isWritePermission,
                )
            }
        }
    }

    private fun runReported(
        scenarioName: String,
        action: () -> Unit,
    ) {
        val baseline = activityResourceSnapshot()
        var failure: Throwable? = null
        try {
            action()
        } catch (error: Throwable) {
            failure = error
            returnFromDocumentsUiForResourceSnapshot()
        }
        val final =
            try {
                if (failure == null) {
                    waitForActivityResourcesToReturnToBaseline(baseline)
                } else {
                    activityResourceSnapshot()
                }
            } catch (error: Throwable) {
                failure = failure ?: error
                emptyMap()
            }
        if (final == baseline) {
            recordCapability(
                "resourceCleanup",
                "activity_resources_returned_to_baseline",
                mapOf("openFdCount" to final["openFdCount"], "pendingPickerCount" to final["pendingPickerCount"]),
            )
        } else if (failure == null) {
            failure = AssertionError("Android 资源未回到基线: baseline=$baseline final=$final")
        }
        writeEvidence(
            scenarioName = scenarioName,
            baseline = baseline,
            final = final,
            failure = failure,
        )
        failure?.let { throw it }
    }

    private class HostedSystemAnrException(message: String) : AssertionError(message)

    private class DocumentsUiFailureException(message: String) : AssertionError(message)

    private fun waitForActivityResourcesToReturnToBaseline(
        baseline: Map<String, Int>,
    ): Map<String, Int> {
        val deadline = System.currentTimeMillis() + RESOURCE_SETTLE_TIMEOUT_MS
        var latest = activityResourceSnapshot()
        var stableSamples = 0
        while (System.currentTimeMillis() < deadline) {
            latest = activityResourceSnapshot()
            stableSamples = if (latest == baseline) stableSamples + 1 else 0
            if (stableSamples >= RESOURCE_STABLE_SAMPLE_COUNT) {
                return latest
            }
            // DocumentsUI 返回后，生产 LocalMatch controller 会继续 await 真实
            // SAF 元数据扫描。等待连续样本稳定只消除“Future 尚未完成”的取样竞态；
            // 真正遗漏 closeFd 时计数不会回零，仍会在固定期限后按资源泄漏失败。
            Thread.sleep(RESOURCE_SAMPLE_INTERVAL_MS)
        }
        return latest
    }

    private fun activityResourceSnapshot(): Map<String, Int> {
        val snapshot = AtomicReference<Map<String, Int>>()
        scenario?.onActivity { activity -> snapshot.set(activity.resourceSnapshot()) }
            ?: throw AssertionError("ActivityScenario 已关闭")
        return snapshot.get() ?: throw AssertionError("无法读取 Android 资源快照")
    }

    private fun recordCapability(
        capability: String,
        action: String,
        details: Map<String, Any?> = emptyMap(),
    ) {
        val entry = linkedMapOf<String, Any?>("action" to action).apply { putAll(details) }
        capabilityEvidence.getOrPut(capability) { mutableListOf() }.add(entry)
    }

    private fun recordSelectedArtifact() {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        val uri = seededAudioUri ?: throw AssertionError("MediaStore fixture URI 已丢失")
        val bytes =
            context.contentResolver.openInputStream(uri)?.use { it.readBytes() }
                ?: throw AssertionError("无法回读写入后的 MediaStore fixture")
        recordArtifact(seededAudioName, bytes)
    }

    private fun recordArtifact(name: String, bytes: ByteArray) {
        val sha256 = MessageDigest.getInstance("SHA-256")
            .digest(bytes)
            .joinToString("") { byte -> "%02x".format(byte) }
        artifacts.add(
            mapOf(
                "name" to name,
                "size" to bytes.size,
                "sha256" to sha256,
            ),
        )
    }

    private fun writeEvidence(
        scenarioName: String,
        baseline: Map<String, Int>,
        final: Map<String, Int>,
        failure: Throwable?,
    ) {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        val directory = File(context.cacheDir, "lddc_native_evidence/$runId").apply { mkdirs() }
        val target = File(directory, "$scenarioName.json")
        val temporary = File(directory, "$scenarioName.json.tmp")
        val nativeActionCount =
            capabilityEvidence
                // nativeChannels 中的 SAF 错误映射在打开系统 Picker 前执行，不能
                // 被当作系统 UI 动作。只统计已经形成真实平台能力证据的选择、
                // 媒体和生命周期动作；任一成功动作都会禁止系统 ANR 重试。
                .filterKeys { capability -> capability in setOf("filePicker", "media", "lifecycle") }
                .values
                .sumOf { actions -> actions.size }
        val hostedSystemAnrConfirmed = hostedSystemAnrDetected || failure is HostedSystemAnrException
        val failureCategory =
            when {
                failure == null -> null
                // 真实业务动作已经成功落地时，即使之后出现宿主系统 ANR 也不能重试，
                // 否则会用一次重跑替真实的产品行为作证。此时必须按普通失败分类。
                hostedSystemAnrConfirmed && nativeActionCount > 0 ->
                    if (final != baseline) "resource_cleanup_failure" else "application_failure"
                hostedSystemAnrConfirmed -> "hosted_system_anr"
                // 无系统 ANR 可归因时，资源未回基线仍是最高优先级的确定性失败。
                final != baseline -> "resource_cleanup_failure"
                failure is DocumentsUiFailureException -> "documents_ui_failure"
                else -> "application_failure"
            }
        val payload =
            mapOf(
                "runId" to runId,
                "scenario" to scenarioName,
                "profile" to "platform",
                "platform" to "android",
                "framework" to "uiautomator",
                "steps" to
                    listOf(
                        mapOf(
                            "step" to scenarioName,
                            "success" to (failure == null),
                            "error" to failure?.toString(),
                        ),
                    ),
                "capabilityEvidence" to capabilityEvidence,
                "resources" to
                    mapOf(
                        "baseline" to baseline,
                        "final" to final,
                        "thresholds" to mapOf("openFdCount" to 0, "pendingPickerCount" to 0),
                    ),
                "artifacts" to artifacts,
                "extra" to
                    mapOf(
                        "failureCategory" to
                            failureCategory,
                        "nativeActionCount" to nativeActionCount,
                        // runner 需要独立区分“ANR 挡住了 Picker 清理”与“真的泄漏”：
                        // 系统模态层在场时 Picker 拿不到取消回调，pendingPickerCount
                        // 必然停在 1，这不是产品缺陷，不能用它锁死零动作 ANR 恢复。
                        "resourcesReturnedToBaseline" to (final == baseline),
                    ),
            )
        val jsonObject = JSONObject(payload)
        temporary.writeText(jsonObject.toString(2), Charsets.UTF_8)
        if (target.exists() && !target.delete()) {
            throw AssertionError("无法替换旧 Android evidence")
        }
        if (!temporary.renameTo(target)) {
            throw AssertionError("无法原子写入 Android evidence")
        }

        // connectedDebugAndroidTest 会在 Gradle 任务结束前卸载测试包，应用 cache
        // 随之删除。把同一份 evidence 编码为有界 logcat 分块，runner 才能在卸载后
        // 恢复报告；分块不包含路径、凭据或 fixture 正文。
        val encoded =
            Base64.encodeToString(
                jsonObject.toString().toByteArray(Charsets.UTF_8),
                Base64.NO_WRAP,
            )
        val chunks = encoded.chunked(EVIDENCE_LOG_CHUNK_SIZE)
        chunks.forEachIndexed { index, chunk ->
            Log.i(
                EVIDENCE_LOG_TAG,
                "$EVIDENCE_LOG_PREFIX|$runId|$scenarioName|$index|${chunks.size}|$chunk",
            )
        }
    }
}

private class RecordingNativeResult : MethodChannel.Result {
    var errorCode: String? = null
        private set

    override fun success(result: Any?) = Unit

    override fun error(
        errorCode: String,
        errorMessage: String?,
        errorDetails: Any?,
    ) {
        this.errorCode = errorCode
    }

    override fun notImplemented() = Unit
}
