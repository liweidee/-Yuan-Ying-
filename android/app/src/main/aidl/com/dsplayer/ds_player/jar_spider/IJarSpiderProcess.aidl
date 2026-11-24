package com.dsplayer.ds_player.jar_spider;

import com.dsplayer.ds_player.jar_spider.IJarSpiderProcessCallback;

oneway interface IJarSpiderProcess {
    void call(
            String requestId,
            String requestJson,
            IJarSpiderProcessCallback callback
    );
    void abort();
}
