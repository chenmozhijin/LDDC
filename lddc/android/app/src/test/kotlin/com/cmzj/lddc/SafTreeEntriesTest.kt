package com.cmzj.lddc

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class SafTreeEntriesTest {
    @Test
    fun treeRootUriHasNoCurrentDocumentId() {
        // 树根形态必须返回 null，让调用方回退 getTreeDocumentId()。
        assertNull(SafTreeEntries.currentDocumentId(listOf("tree", "primary:Music")))
    }

    @Test
    fun childDocumentUriReturnsChildDocumentId() {
        // 真实 URI 形如 content://…/tree/primary%3AMusic/document/primary%3AMusic%2FAlbum，
        // getPathSegments() 已解码，因此子文档 id 是含 '/' 的完整一段。
        // 这条用例就是本次回归的防线：若退回 getTreeDocumentId()，结果会变成 primary:Music。
        assertEquals(
            "primary:Music/Album",
            SafTreeEntries.currentDocumentId(
                listOf("tree", "primary:Music", "document", "primary:Music/Album"),
            ),
        )
    }

    @Test
    fun childDocumentsUriStillResolvesChildDocumentId() {
        // …/document/<childDocId>/children 形态不会传给 listChildrenPage，即使传入也不能
        // 误判成树根。
        assertEquals(
            "primary:Music/Album",
            SafTreeEntries.currentDocumentId(
                listOf("tree", "primary:Music", "document", "primary:Music/Album", "children"),
            ),
        )
    }

    @Test
    fun blankChildDocumentIdFallsBackToTreeRoot() {
        assertNull(
            SafTreeEntries.currentDocumentId(listOf("tree", "primary:Music", "document", "")),
        )
    }

    @Test
    fun directoryMimeAcceptsStandardAndLegacyValues() {
        assertTrue(SafTreeEntries.isDirectoryMime("vnd.android.document/directory"))
        assertTrue(SafTreeEntries.isDirectoryMime(" resource/folder "))
        assertTrue(SafTreeEntries.isDirectoryMime("INODE/DIRECTORY"))
        assertFalse(SafTreeEntries.isDirectoryMime("audio/mpeg"))
        assertFalse(SafTreeEntries.isDirectoryMime(null))
        assertFalse(SafTreeEntries.isDirectoryMime("  "))
    }

    @Test
    fun nonNegativeValuesPassThroughAndUnknownValuesBecomeNull() {
        assertNull(SafTreeEntries.nonNegativeOrNull(-1))
        assertNull(SafTreeEntries.nonNegativeOrNull(null))
        assertEquals(java.lang.Long.valueOf(0), SafTreeEntries.nonNegativeOrNull(0))
        assertEquals(java.lang.Long.valueOf(4096), SafTreeEntries.nonNegativeOrNull(4096))
    }
}
