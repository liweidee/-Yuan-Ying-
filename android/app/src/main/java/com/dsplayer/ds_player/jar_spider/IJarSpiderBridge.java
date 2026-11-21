package com.dsplayer.ds_player.jar_spider;

import android.content.Context;

import java.util.List;
import java.util.Map;

/**
 * Contract implemented by the dynamically loaded DsPlayer JAR plugin bridge.
 *
 * The package and method signatures must remain identical to the official
 * plugin so plugins/jar/classes.dex can be loaded without repackaging it.
 */
public interface IJarSpiderBridge {
    Map<String, Object> call(
            String jarPath,
            String siteKey,
            String method,
            List<String> args
    );

    Map<String, Object> createSpider(
            String jarPath,
            String siteKey,
            String api,
            String ext
    );

    void destroyJar(String jarPath);

    void init(Context context, String optDir);

    Map<String, Object> loadJar(String jarPath);

    Map<String, Object> proxy(String jarPath, Map<String, String> params);
}
