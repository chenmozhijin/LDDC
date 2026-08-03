package com.cmzj.lddc;

import android.content.Context;
import android.net.Uri;
import android.provider.DocumentsContract;
import android.util.Base64;

import java.io.File;
import java.io.FileNotFoundException;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;
import java.util.regex.Pattern;

/** test APK 两个 provider 共用的有界文件存储，不依赖 Kotlin runtime。 */
final class PlatformFixtureStore {
    static final String DOCUMENT_AUTHORITY = "com.cmzj.lddc.test.platform.documents";
    static final String ROOT_ID = "lddc_platform_fixtures";
    static final String ROOT_DOCUMENT_ID = "root";

    private static final String FILE_DOCUMENT_PREFIX = "fixture:";
    private static final String DIRECTORY_DOCUMENT_PREFIX = "directory:";
    private static final String FIXTURE_DIRECTORY = "platform_documents";
    private static final Pattern SAFE_SEGMENT = Pattern.compile("[A-Za-z0-9._-]+");

    private PlatformFixtureStore() {}

    static Uri seedAudio(
            Context context,
            String runId,
            String displayName,
            byte[] bytes) throws IOException {
        if (bytes.length == 0 || bytes.length > 64 * 1024) {
            throw new IllegalArgumentException("fixture 大小必须在 1 到 64 KiB 之间");
        }
        File runDirectory = new File(root(context), safeSegment(runId));
        if (!runDirectory.mkdirs() && !runDirectory.isDirectory()) {
            throw new IOException("无法创建 Android platform fixture 目录");
        }
        File fixture = new File(runDirectory, safeSegment(displayName));
        Files.write(fixture.toPath(), bytes);
        Uri documentUri = DocumentsContract.buildDocumentUri(
                DOCUMENT_AUTHORITY,
                documentIdFor(relativePath(context, fixture)));
        // connectedAndroidTest 刚安装 test APK 时，DocumentsUI 可能仍缓存安装前的
        // roots。按 DocumentsProvider 契约通知根和文档变化，让下次启动重新查询。
        context.getContentResolver().notifyChange(
                DocumentsContract.buildRootsUri(DOCUMENT_AUTHORITY), null, false);
        context.getContentResolver().notifyChange(documentUri, null, false);
        return documentUri;
    }

    static Uri missingFixtureUri(String runId) {
        String relativePath = safeSegment(runId) + "/missing-fixture.mp3";
        return DocumentsContract.buildDocumentUri(
                DOCUMENT_AUTHORITY,
                documentIdFor(relativePath));
    }

    static void cleanupRun(Context context, String runId) throws IOException {
        File root = root(context).getCanonicalFile();
        File runDirectory = new File(root, safeSegment(runId)).getCanonicalFile();
        ensureInsideRoot(root, runDirectory);
        deleteRecursively(runDirectory);
    }

    static List<File> allFixtures(Context context) {
        List<File> files = new ArrayList<>();
        collectFiles(root(context), files);
        files.sort(Comparator.comparingLong(File::lastModified).reversed());
        return files;
    }

    static List<File> allRunDirectories(Context context) {
        List<File> directories = new ArrayList<>();
        File[] children = root(context).listFiles();
        if (children != null) {
            for (File child : children) {
                if (child.isDirectory()) directories.add(child);
            }
        }
        directories.sort(Comparator.comparingLong(File::lastModified).reversed());
        return directories;
    }

    static List<File> fixturesInDirectory(Context context, File directory) throws FileNotFoundException {
        File required = requireDirectory(context, directoryDocumentId(context, directory));
        List<File> files = new ArrayList<>();
        File[] children = required.listFiles();
        if (children != null) {
            for (File child : children) {
                if (child.isFile()) files.add(child);
            }
        }
        files.sort(Comparator.comparingLong(File::lastModified).reversed());
        return files;
    }

    static File requireFixture(Context context, String documentId) throws FileNotFoundException {
        File fixture = resolveDocument(context, documentId, FILE_DOCUMENT_PREFIX);
        if (!fixture.isFile()) throw new FileNotFoundException("fixture 文件不存在");
        return fixture;
    }

    static File requireDirectory(Context context, String documentId) throws FileNotFoundException {
        File directory = resolveDocument(context, documentId, DIRECTORY_DOCUMENT_PREFIX);
        if (!directory.isDirectory()) throw new FileNotFoundException("fixture 目录不存在");
        return directory;
    }

    static boolean isDirectoryDocumentId(String documentId) {
        return documentId != null && documentId.startsWith(DIRECTORY_DOCUMENT_PREFIX);
    }

    static String documentId(Context context, File fixture) throws FileNotFoundException {
        try {
            return documentIdFor(relativePath(context, fixture));
        } catch (IOException error) {
            FileNotFoundException wrapped = new FileNotFoundException("无法解析 fixture 路径");
            wrapped.initCause(error);
            throw wrapped;
        }
    }

    static String directoryDocumentId(Context context, File directory) throws FileNotFoundException {
        try {
            return documentIdFor(DIRECTORY_DOCUMENT_PREFIX, relativePath(context, directory));
        } catch (IOException error) {
            FileNotFoundException wrapped = new FileNotFoundException("无法解析 fixture 目录");
            wrapped.initCause(error);
            throw wrapped;
        }
    }

    static File createFixture(
            Context context,
            String parentDocumentId,
            String displayName) throws IOException {
        File directory = requireDirectory(context, parentDocumentId);
        File fixture = new File(directory, safeSegment(displayName)).getCanonicalFile();
        ensureInsideRoot(root(context).getCanonicalFile(), fixture);
        if (!fixture.createNewFile()) throw new IOException("fixture 文件已存在");
        return fixture;
    }

    private static File root(Context context) {
        return new File(context.getFilesDir(), FIXTURE_DIRECTORY);
    }

    private static String safeSegment(String value) {
        if (value == null || !SAFE_SEGMENT.matcher(value).matches()) {
            throw new IllegalArgumentException("fixture 路径片段非法");
        }
        return value;
    }

    private static String relativePath(Context context, File file) throws IOException {
        File root = root(context).getCanonicalFile();
        File canonical = file.getCanonicalFile();
        ensureInsideRoot(root, canonical);
        return root.toPath().relativize(canonical.toPath()).toString().replace(File.separatorChar, '/');
    }

    private static String documentIdFor(String relativePath) {
        return documentIdFor(FILE_DOCUMENT_PREFIX, relativePath);
    }

    private static String documentIdFor(String prefix, String relativePath) {
        String encoded = Base64.encodeToString(
                relativePath.getBytes(StandardCharsets.UTF_8),
                Base64.URL_SAFE | Base64.NO_WRAP | Base64.NO_PADDING);
        return prefix + encoded;
    }

    private static File resolveDocument(
            Context context,
            String documentId,
            String prefix) throws FileNotFoundException {
        if (!documentId.startsWith(prefix)) throw new FileNotFoundException("未知 fixture documentId");
        try {
            String encoded = documentId.substring(prefix.length());
            String relativePath = new String(
                    Base64.decode(encoded, Base64.URL_SAFE | Base64.NO_WRAP | Base64.NO_PADDING),
                    StandardCharsets.UTF_8);
            File root = root(context).getCanonicalFile();
            File resolved = new File(root, relativePath).getCanonicalFile();
            ensureInsideRoot(root, resolved);
            return resolved;
        } catch (IllegalArgumentException | IOException error) {
            FileNotFoundException wrapped = new FileNotFoundException("fixture documentId 非法");
            wrapped.initCause(error);
            throw wrapped;
        }
    }

    private static void ensureInsideRoot(File root, File child) throws IOException {
        if (!child.getPath().startsWith(root.getPath() + File.separator)) {
            throw new IOException("fixture 路径越出受控根目录");
        }
    }

    private static void collectFiles(File directory, List<File> output) {
        File[] children = directory.listFiles();
        if (children == null) return;
        for (File child : children) {
            if (child.isDirectory()) {
                collectFiles(child, output);
            } else if (child.isFile()) {
                output.add(child);
            }
        }
    }

    private static void deleteRecursively(File file) throws IOException {
        if (!file.exists()) return;
        if (file.isDirectory()) {
            File[] children = file.listFiles();
            if (children != null) {
                for (File child : children) deleteRecursively(child);
            }
        }
        if (!file.delete()) throw new IOException("无法清理 platform fixture");
    }
}
