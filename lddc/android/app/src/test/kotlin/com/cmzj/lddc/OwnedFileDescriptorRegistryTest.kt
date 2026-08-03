package com.cmzj.lddc

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class OwnedFileDescriptorRegistryTest {
    @Test
    fun closeOnlyTouchesRegisteredDescriptorAndIsIdempotent() {
        val closed = mutableListOf<Int>()
        val registry = OwnedFileDescriptorRegistry(closed::add)

        assertTrue(registry.register(7))
        assertFalse(registry.register(7))
        assertFalse(registry.close(8))
        assertTrue(registry.close(7))
        assertFalse(registry.close(7))
        assertEquals(listOf(7), closed)
        assertEquals(0, registry.count())
    }

    @Test
    fun closeAllContinuesAfterCloserFailureAndClearsOwnershipFirst() {
        val attempted = mutableListOf<Int>()
        val registry =
            OwnedFileDescriptorRegistry { fd ->
                attempted.add(fd)
                if (fd == 3) {
                    error("controlled close failure")
                }
            }
        assertTrue(registry.register(3))
        assertTrue(registry.register(4))

        assertEquals(2, registry.closeAll())
        assertEquals(listOf(3, 4), attempted)
        assertEquals(0, registry.count())
        assertFalse(registry.close(3))
    }

    @Test
    fun negativeDescriptorIsNeverRegistered() {
        val registry = OwnedFileDescriptorRegistry { error("不能调用") }

        assertFalse(registry.register(-1))
        assertEquals(0, registry.count())
    }
}
