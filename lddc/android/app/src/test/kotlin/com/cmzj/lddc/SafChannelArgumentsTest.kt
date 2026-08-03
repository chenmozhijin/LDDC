package com.cmzj.lddc

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class SafChannelArgumentsTest {
    @Test
    fun nonBlankRejectsMissingOrWhitespaceOnlyValues() {
        assertNull(SafChannelArguments.nonBlank(null))
        assertNull(SafChannelArguments.nonBlank("  \n"))
        assertEquals("content://audio/1", SafChannelArguments.nonBlank(" content://audio/1 "))
    }

    @Test
    fun fileDescriptorRejectsNegativeValues() {
        assertNull(SafChannelArguments.validFileDescriptor(null))
        assertNull(SafChannelArguments.validFileDescriptor(-1))
        assertEquals(0, SafChannelArguments.validFileDescriptor(0))
    }

    @Test
    fun mimeTypeUsesTextFallbackAndTrimsExplicitValue() {
        assertEquals("text/plain", SafChannelArguments.mimeType(null))
        assertEquals("text/plain", SafChannelArguments.mimeType("  "))
        assertEquals("text/lrc", SafChannelArguments.mimeType(" text/lrc "))
    }
}
