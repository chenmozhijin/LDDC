package com.cmzj.lddc;

import android.content.ContentProvider;
import android.content.ContentValues;
import android.database.Cursor;
import android.content.Intent;
import android.net.Uri;
import android.os.Bundle;

import java.io.IOException;

/** 只负责当前 runId 的 seed/cleanup，不提供 query 或 openFile。 */
public final class PlatformFixtureSeedProvider extends ContentProvider {
    public static final String AUTHORITY = "com.cmzj.lddc.test.platform.seed";
    public static final String METHOD_SEED_AUDIO = "seedAudio";
    public static final String METHOD_CLEANUP_RUN = "cleanupRun";
    public static final String METHOD_GRANT_MISSING_AUDIO = "grantMissingAudio";
    public static final String METHOD_REVOKE_URI = "revokeUri";
    public static final String EXTRA_RUN_ID = "runId";
    public static final String EXTRA_DISPLAY_NAME = "displayName";
    public static final String EXTRA_BYTES = "bytes";
    public static final String EXTRA_URI = "uri";
    private static final String TARGET_APP_PACKAGE = "com.cmzj.lddc";

    @Override
    public boolean onCreate() {
        return true;
    }

    @Override
    public Bundle call(String method, String arg, Bundle extras) {
        if (getContext() == null) throw new IllegalStateException("seed provider context 不可用");
        try {
            if (METHOD_SEED_AUDIO.equals(method)) {
                if (extras == null) throw new IllegalArgumentException("seedAudio 缺少参数");
                String runId = requireText(extras.getString(EXTRA_RUN_ID), EXTRA_RUN_ID);
                String displayName = requireText(extras.getString(EXTRA_DISPLAY_NAME), EXTRA_DISPLAY_NAME);
                byte[] bytes = extras.getByteArray(EXTRA_BYTES);
                if (bytes == null) throw new IllegalArgumentException("seedAudio 缺少 bytes");
                Bundle result = new Bundle();
                result.putString(
                        EXTRA_URI,
                        PlatformFixtureStore.seedAudio(getContext(), runId, displayName, bytes).toString());
                return result;
            }
            if (METHOD_CLEANUP_RUN.equals(method)) {
                String runId = requireText(
                        extras == null ? null : extras.getString(EXTRA_RUN_ID),
                        EXTRA_RUN_ID);
                PlatformFixtureStore.cleanupRun(getContext(), runId);
                return new Bundle();
            }
            if (METHOD_GRANT_MISSING_AUDIO.equals(method)) {
                String runId = requireText(
                        extras == null ? null : extras.getString(EXTRA_RUN_ID),
                        EXTRA_RUN_ID);
                Uri uri = PlatformFixtureStore.missingFixtureUri(runId);
                // grant 必须由拥有 DocumentsProvider 的 test APK UID 发出。目标应用随后
                // 仍通过真实 ContentResolver 和 provider 校验，不注入任何返回值。
                getContext().grantUriPermission(
                        TARGET_APP_PACKAGE,
                        uri,
                        Intent.FLAG_GRANT_READ_URI_PERMISSION);
                Bundle result = new Bundle();
                result.putString(EXTRA_URI, uri.toString());
                return result;
            }
            if (METHOD_REVOKE_URI.equals(method)) {
                String uriText = requireText(
                        extras == null ? null : extras.getString(EXTRA_URI),
                        EXTRA_URI);
                getContext().revokeUriPermission(
                        Uri.parse(uriText),
                        Intent.FLAG_GRANT_READ_URI_PERMISSION
                                | Intent.FLAG_GRANT_WRITE_URI_PERMISSION);
                return new Bundle();
            }
            return super.call(method, arg, extras);
        } catch (IOException error) {
            throw new IllegalStateException("fixture 存储操作失败", error);
        }
    }

    private static String requireText(String value, String name) {
        if (value == null || value.isEmpty()) throw new IllegalArgumentException("缺少 " + name);
        return value;
    }

    @Override
    public Cursor query(Uri uri, String[] projection, String selection, String[] selectionArgs, String sortOrder) {
        throw new UnsupportedOperationException("seed provider 不支持 query");
    }

    @Override
    public String getType(Uri uri) {
        return null;
    }

    @Override
    public Uri insert(Uri uri, ContentValues values) {
        throw new UnsupportedOperationException("seed provider 不支持 insert");
    }

    @Override
    public int delete(Uri uri, String selection, String[] selectionArgs) {
        throw new UnsupportedOperationException("seed provider 不支持 delete");
    }

    @Override
    public int update(Uri uri, ContentValues values, String selection, String[] selectionArgs) {
        throw new UnsupportedOperationException("seed provider 不支持 update");
    }
}
