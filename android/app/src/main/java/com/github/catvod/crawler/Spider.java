package com.github.catvod.crawler;

import android.content.Context;

import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * Host-side CatVod spider contract required by dynamic DsPlayer JAR sources.
 *
 * Keep this package and every public method signature identical to DsPlayer.
 */
public abstract class Spider {
    public String siteKey;

    public String action(String value) {
        return null;
    }

    public String categoryContent(
            String tid,
            String page,
            boolean quick,
            HashMap<String, String> extend
    ) {
        return "";
    }

    public String detailContent(List<String> ids) {
        return "";
    }

    public String homeContent(boolean filter) {
        return "";
    }

    public String homeVideoContent() {
        return "";
    }

    public void init(Context context, String extend) {
        init(context);
    }

    public boolean isVideoFormat(String url) {
        return false;
    }

    public String liveContent(String url) {
        return "";
    }

    public boolean manualVideoCheck() {
        return false;
    }

    public String playerContent(
            String flag,
            String id,
            List<String> vipFlags
    ) {
        return "";
    }

    public Object[] proxy(Map<String, String> params) {
        return null;
    }

    public String searchContent(String key, boolean quick) {
        return "";
    }

    public String searchContent(String key, boolean quick, String pg) {
        return "";
    }

    public void init(Context context) {
    }

    public void destroy() {
    }
}
