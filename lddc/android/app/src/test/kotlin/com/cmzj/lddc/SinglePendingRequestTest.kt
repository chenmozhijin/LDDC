package com.cmzj.lddc

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class SinglePendingRequestTest {
    @Test
    fun beginRejectsConcurrentRequestAndTakeClearsState() {
        val registry = SinglePendingRequest<String>()

        assertTrue(registry.begin("first"))
        assertFalse(registry.begin("second"))
        assertEquals(1, registry.count())
        assertEquals("first", registry.take())
        assertEquals(0, registry.count())
        assertNull(registry.take())
        assertTrue(registry.begin("third"))
    }
}
