package com.cmzj.lddc

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class PickerPendingRequestRegistryTest {
    @Test
    fun eachPickerRejectsOnlyConcurrentRequestWithBusyError() {
        val registry = PickerPendingRequestRegistry()
        val firstTree = RecordingMethodResult()
        val secondTree = RecordingMethodResult()
        assertTrue(registry.beginTree(firstTree))
        assertFalse(registry.beginTree(secondTree))
        assertEquals("busy", secondTree.errorCode)
        assertEquals("已有目录选择请求未完成", secondTree.errorMessage)
        assertEquals(firstTree, registry.takeTree())

        val firstAudio = RecordingMethodResult()
        val secondAudio = RecordingMethodResult()
        assertTrue(registry.beginAudio(firstAudio))
        assertFalse(registry.beginAudio(secondAudio))
        assertEquals("busy", secondAudio.errorCode)
        assertEquals("已有音频选择请求未完成", secondAudio.errorMessage)
        assertEquals(firstAudio, registry.takeAudio())

        val firstSaveResult = RecordingMethodResult()
        val firstSave = PendingSaveTextFile(firstSaveResult, byteArrayOf(1))
        val secondSaveResult = RecordingMethodResult()
        assertTrue(registry.beginSave(firstSave))
        assertFalse(registry.beginSave(PendingSaveTextFile(secondSaveResult, byteArrayOf(2))))
        assertEquals("busy", secondSaveResult.errorCode)
        assertEquals("已有文件保存请求未完成", secondSaveResult.errorMessage)
        assertEquals(firstSave, registry.takeSave())
        assertEquals(0, registry.count())
    }

    @Test
    fun activityDestroyCompletesAllRequestsAndClearsRegistry() {
        val registry = PickerPendingRequestRegistry()
        val tree = RecordingMethodResult()
        val audio = RecordingMethodResult()
        val save = RecordingMethodResult()
        registry.beginTree(tree)
        registry.beginAudio(audio)
        registry.beginSave(PendingSaveTextFile(save, byteArrayOf()))

        registry.completeDestroyedRequests()

        assertEquals("activity_destroyed", tree.errorCode)
        assertEquals("activity_destroyed", audio.errorCode)
        assertEquals("activity_destroyed", save.errorCode)
        assertEquals(0, registry.count())
        assertNull(registry.takeTree())
        assertNull(registry.takeAudio())
        assertNull(registry.takeSave())
    }

    @Test
    fun callbackFailureDoesNotPreventRemainingRequestsFromBeingReleased() {
        val registry = PickerPendingRequestRegistry()
        val throwingTree = RecordingMethodResult(throwOnError = true)
        val audio = RecordingMethodResult()
        val save = RecordingMethodResult()
        registry.beginTree(throwingTree)
        registry.beginAudio(audio)
        registry.beginSave(PendingSaveTextFile(save, byteArrayOf()))

        registry.completeDestroyedRequests()

        assertEquals("activity_destroyed", throwingTree.errorCode)
        assertEquals("activity_destroyed", audio.errorCode)
        assertEquals("activity_destroyed", save.errorCode)
        assertEquals(0, registry.count())
    }
}
