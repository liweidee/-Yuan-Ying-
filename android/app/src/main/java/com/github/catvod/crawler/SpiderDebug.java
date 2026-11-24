package com.github.catvod.crawler;

import android.util.Log;

public final class SpiderDebug {
    private static final String TAG = "JarSpider";

    private SpiderDebug() {
    }

    public static void log(String value) {
        if (value == null || value.isEmpty()) {
            return;
        }
        try {
            Log.d(TAG, value);
        } catch (Throwable ignored) {
        }
    }

    public static void log(Throwable error) {
        if (error == null) {
            return;
        }
        try {
            Log.w(TAG, Log.getStackTraceString(error));
        } catch (Throwable ignored) {
        }
    }
}
