package com.cmzj.lddc;

import android.database.Cursor;
import android.database.MatrixCursor;
import android.os.CancellationSignal;
import android.os.ParcelFileDescriptor;
import android.provider.DocumentsContract.Document;
import android.provider.DocumentsContract.Root;
import android.provider.DocumentsProvider;

import java.io.File;
import java.io.FileNotFoundException;
import java.io.IOException;
import java.util.ArrayList;
import java.util.List;

/**
 * 仅供 instrumentation 的真实 DocumentsProvider。
 *
 * DocumentsUI、URI grant、ContentResolver 与 fd 都由 Android 系统实现；该类只把
 * 匿名小文件暴露给系统，避免把测试稳定性绑定到 MediaStore 空根缓存。
 */
public final class PlatformFixtureDocumentsProvider extends DocumentsProvider {
    private static final String[] ROOT_COLUMNS = {
            Root.COLUMN_ROOT_ID,
            Root.COLUMN_FLAGS,
            Root.COLUMN_TITLE,
            Root.COLUMN_DOCUMENT_ID,
            Root.COLUMN_MIME_TYPES,
    };
    private static final String[] DOCUMENT_COLUMNS = {
            Document.COLUMN_DOCUMENT_ID,
            Document.COLUMN_DISPLAY_NAME,
            Document.COLUMN_MIME_TYPE,
            Document.COLUMN_LAST_MODIFIED,
            Document.COLUMN_FLAGS,
            Document.COLUMN_SIZE,
    };

    @Override
    public boolean onCreate() {
        return true;
    }

    @Override
    public Cursor queryRoots(String[] projection) {
        String[] columns = projection == null ? ROOT_COLUMNS : projection;
        MatrixCursor cursor = new MatrixCursor(columns);
        addRow(cursor, columns, new Object[][] {
                {Root.COLUMN_ROOT_ID, PlatformFixtureStore.ROOT_ID},
                {Root.COLUMN_FLAGS, Root.FLAG_LOCAL_ONLY | Root.FLAG_SUPPORTS_RECENTS
                        | Root.FLAG_SUPPORTS_SEARCH | Root.FLAG_SUPPORTS_IS_CHILD},
                {Root.COLUMN_TITLE, "LDDC Platform Fixtures"},
                {Root.COLUMN_DOCUMENT_ID, PlatformFixtureStore.ROOT_DOCUMENT_ID},
                {Root.COLUMN_MIME_TYPES, "*/*"},
        });
        return cursor;
    }

    @Override
    public Cursor queryDocument(String documentId, String[] projection) throws FileNotFoundException {
        String[] columns = projection == null ? DOCUMENT_COLUMNS : projection;
        MatrixCursor cursor = new MatrixCursor(columns);
        if (PlatformFixtureStore.ROOT_DOCUMENT_ID.equals(documentId)) {
            addRootDirectory(cursor, columns);
        } else if (PlatformFixtureStore.isDirectoryDocumentId(documentId)) {
            addRunDirectory(
                    cursor,
                    columns,
                    PlatformFixtureStore.requireDirectory(providerContext(), documentId));
        } else {
            addFile(cursor, columns, PlatformFixtureStore.requireFixture(providerContext(), documentId));
        }
        return cursor;
    }

    @Override
    public Cursor queryChildDocuments(String parentDocumentId, String[] projection, String sortOrder)
            throws FileNotFoundException {
        if (PlatformFixtureStore.ROOT_DOCUMENT_ID.equals(parentDocumentId)) {
            return directoriesCursor(projection, PlatformFixtureStore.allRunDirectories(providerContext()));
        }
        File directory = PlatformFixtureStore.requireDirectory(providerContext(), parentDocumentId);
        return filesCursor(projection, PlatformFixtureStore.fixturesInDirectory(providerContext(), directory));
    }

    @Override
    public Cursor queryRecentDocuments(String rootId, String[] projection) throws FileNotFoundException {
        requireRoot(rootId);
        return filesCursor(projection, PlatformFixtureStore.allFixtures(providerContext()));
    }

    @Override
    public Cursor querySearchDocuments(String rootId, String query, String[] projection)
            throws FileNotFoundException {
        requireRoot(rootId);
        List<File> matches = new ArrayList<>();
        String normalized = query == null ? "" : query.toLowerCase(java.util.Locale.ROOT);
        for (File file : PlatformFixtureStore.allFixtures(providerContext())) {
            if (file.getName().toLowerCase(java.util.Locale.ROOT).contains(normalized)) {
                matches.add(file);
            }
        }
        return filesCursor(projection, matches);
    }

    @Override
    public ParcelFileDescriptor openDocument(
            String documentId,
            String mode,
            CancellationSignal signal) throws FileNotFoundException {
        return ParcelFileDescriptor.open(
                PlatformFixtureStore.requireFixture(providerContext(), documentId),
                ParcelFileDescriptor.parseMode(mode));
    }

    @Override
    public void deleteDocument(String documentId) throws FileNotFoundException {
        File fixture = PlatformFixtureStore.requireFixture(providerContext(), documentId);
        if (!fixture.delete()) throw new FileNotFoundException("无法删除 platform fixture");
    }

    @Override
    public String createDocument(String parentDocumentId, String mimeType, String displayName)
            throws FileNotFoundException {
        try {
            File fixture = PlatformFixtureStore.createFixture(
                    providerContext(), parentDocumentId, displayName);
            return PlatformFixtureStore.documentId(providerContext(), fixture);
        } catch (IOException error) {
            FileNotFoundException wrapped = new FileNotFoundException("无法创建 platform fixture");
            wrapped.initCause(error);
            throw wrapped;
        }
    }

    @Override
    public boolean isChildDocument(String parentDocumentId, String documentId) {
        try {
            if (PlatformFixtureStore.ROOT_DOCUMENT_ID.equals(parentDocumentId)) {
                PlatformFixtureStore.requireDirectory(providerContext(), documentId);
                return true;
            }
            File parent = PlatformFixtureStore.requireDirectory(providerContext(), parentDocumentId);
            File child = PlatformFixtureStore.requireFixture(providerContext(), documentId);
            return child.getParentFile().getCanonicalFile().equals(parent.getCanonicalFile());
        } catch (FileNotFoundException ignored) {
            return false;
        } catch (IOException ignored) {
            return false;
        }
    }

    private Cursor directoriesCursor(String[] projection, List<File> directories)
            throws FileNotFoundException {
        String[] columns = projection == null ? DOCUMENT_COLUMNS : projection;
        MatrixCursor cursor = new MatrixCursor(columns);
        for (File directory : directories) addRunDirectory(cursor, columns, directory);
        return cursor;
    }

    private Cursor filesCursor(String[] projection, List<File> files) throws FileNotFoundException {
        String[] columns = projection == null ? DOCUMENT_COLUMNS : projection;
        MatrixCursor cursor = new MatrixCursor(columns);
        for (File file : files) addFile(cursor, columns, file);
        return cursor;
    }

    private void addRootDirectory(MatrixCursor cursor, String[] columns) {
        addRow(cursor, columns, new Object[][] {
                {Document.COLUMN_DOCUMENT_ID, PlatformFixtureStore.ROOT_DOCUMENT_ID},
                {Document.COLUMN_DISPLAY_NAME, "LDDC Platform Fixtures"},
                {Document.COLUMN_MIME_TYPE, Document.MIME_TYPE_DIR},
                {Document.COLUMN_FLAGS, Document.FLAG_DIR_PREFERS_LAST_MODIFIED},
                {Document.COLUMN_SIZE, 0L},
        });
    }

    private void addRunDirectory(MatrixCursor cursor, String[] columns, File directory)
            throws FileNotFoundException {
        addRow(cursor, columns, new Object[][] {
                {Document.COLUMN_DOCUMENT_ID,
                        PlatformFixtureStore.directoryDocumentId(providerContext(), directory)},
                {Document.COLUMN_DISPLAY_NAME, "LDDCPlatformTest"},
                {Document.COLUMN_MIME_TYPE, Document.MIME_TYPE_DIR},
                {Document.COLUMN_LAST_MODIFIED, directory.lastModified()},
                {Document.COLUMN_FLAGS, Document.FLAG_DIR_SUPPORTS_CREATE
                        | Document.FLAG_DIR_PREFERS_LAST_MODIFIED},
                {Document.COLUMN_SIZE, 0L},
        });
    }

    private void addFile(MatrixCursor cursor, String[] columns, File file) throws FileNotFoundException {
        String mimeType = file.getName().toLowerCase(java.util.Locale.ROOT).endsWith(".lrc")
                ? "application/lrc"
                : "audio/mpeg";
        addRow(cursor, columns, new Object[][] {
                {Document.COLUMN_DOCUMENT_ID, PlatformFixtureStore.documentId(providerContext(), file)},
                {Document.COLUMN_DISPLAY_NAME, file.getName()},
                {Document.COLUMN_MIME_TYPE, mimeType},
                {Document.COLUMN_LAST_MODIFIED, file.lastModified()},
                {Document.COLUMN_FLAGS, Document.FLAG_SUPPORTS_WRITE | Document.FLAG_SUPPORTS_DELETE},
                {Document.COLUMN_SIZE, file.length()},
        });
    }

    private void requireRoot(String rootId) throws FileNotFoundException {
        if (!PlatformFixtureStore.ROOT_ID.equals(rootId)) {
            throw new FileNotFoundException("未知 fixture rootId");
        }
    }

    private android.content.Context providerContext() throws FileNotFoundException {
        android.content.Context context = getContext();
        if (context == null) throw new FileNotFoundException("provider context 不可用");
        return context;
    }

    private static void addRow(MatrixCursor cursor, String[] columns, Object[][] values) {
        MatrixCursor.RowBuilder row = cursor.newRow();
        for (String column : columns) {
            Object value = null;
            for (Object[] entry : values) {
                if (column.equals(entry[0])) {
                    value = entry[1];
                    break;
                }
            }
            row.add(value);
        }
    }
}
