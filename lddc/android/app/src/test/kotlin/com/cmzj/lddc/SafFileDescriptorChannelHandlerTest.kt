package com.cmzj.lddc

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.FileNotFoundException

class SafFileDescriptorChannelHandlerTest {
    @Test
    fun invalidArgumentsAreRejectedBeforeGatewayAccess() {
        val gateway = FakeSafFileDescriptorGateway()
        val handler = SafFileDescriptorChannelHandler(gateway)

        val missingUri = RecordingMethodResult()
        handler.openReadOnly("  ", missingUri)
        assertEquals("invalid_argument", missingUri.errorCode)
        assertTrue(gateway.openCalls.isEmpty())

        val invalidFd = RecordingMethodResult()
        handler.close(-1, invalidFd)
        assertEquals("invalid_argument", invalidFd.errorCode)
        assertTrue(gateway.closedFds.isEmpty())
    }

    @Test
    fun gatewayExceptionsMapToStableMethodChannelErrors() {
        val cases =
            listOf(
                SecurityException("denied") to "permission_denied",
                FileNotFoundException("missing") to "file_not_found",
                IllegalStateException("broken") to "open_fd_failed",
            )
        for ((failure, expectedCode) in cases) {
            val gateway = FakeSafFileDescriptorGateway(openFailure = failure)
            val result = RecordingMethodResult()

            SafFileDescriptorChannelHandler(gateway).openReadWrite(" content://fixture/1 ", result)

            assertEquals(expectedCode, result.errorCode)
            assertEquals(listOf("content://fixture/1" to "rw"), gateway.openCalls)
        }
    }

    @Test
    fun nullDescriptorMapsToOpenFailureWithoutRegisteringOwnership() {
        val gateway = FakeSafFileDescriptorGateway(opened = null)
        val handler = SafFileDescriptorChannelHandler(gateway)
        val result = RecordingMethodResult()

        handler.openReadOnly("content://fixture/empty", result)

        assertEquals("open_fd_failed", result.errorCode)
        assertEquals(0, handler.count())
    }

    @Test
    fun successfulOpenAndIdempotentCloseTrackOnlyOwnedDescriptor() {
        val gateway = FakeSafFileDescriptorGateway(OpenedSafFileDescriptor(17, "fixture.mp3"))
        val handler = SafFileDescriptorChannelHandler(gateway)
        val opened = RecordingMethodResult()

        handler.openReadOnly("content://fixture/audio", opened)

        @Suppress("UNCHECKED_CAST")
        val payload = opened.successValue as Map<String, Any?>
        assertEquals(17, payload["fd"])
        assertEquals("fixture.mp3", payload["nameHint"])
        assertEquals(1, handler.count())

        val unknown = RecordingMethodResult()
        handler.close(18, unknown)
        assertNull(unknown.errorCode)
        assertTrue(gateway.closedFds.isEmpty())

        val closed = RecordingMethodResult()
        handler.close(17, closed)
        handler.close(17, RecordingMethodResult())
        assertEquals(listOf(17), gateway.closedFds)
        assertEquals(0, handler.count())
    }

    @Test
    fun duplicateDescriptorFailsAndClosesUnregisteredResultImmediately() {
        val gateway = FakeSafFileDescriptorGateway(OpenedSafFileDescriptor(7, null))
        val handler = SafFileDescriptorChannelHandler(gateway)
        handler.openReadOnly("content://fixture/first", RecordingMethodResult())
        val duplicate = RecordingMethodResult()

        handler.openReadOnly("content://fixture/second", duplicate)

        assertEquals("fd_registry_conflict", duplicate.errorCode)
        assertEquals(listOf(7), gateway.closedFds)
        assertEquals(1, handler.count())
    }
}

private class FakeSafFileDescriptorGateway(
    private val opened: OpenedSafFileDescriptor? = OpenedSafFileDescriptor(3, null),
    private val openFailure: Exception? = null,
) : SafFileDescriptorGateway {
    val openCalls = mutableListOf<Pair<String, String>>()
    val closedFds = mutableListOf<Int>()

    override fun open(uriText: String, mode: String): OpenedSafFileDescriptor? {
        openCalls.add(uriText to mode)
        openFailure?.let { throw it }
        return opened
    }

    override fun close(fd: Int) {
        closedFds.add(fd)
    }
}
