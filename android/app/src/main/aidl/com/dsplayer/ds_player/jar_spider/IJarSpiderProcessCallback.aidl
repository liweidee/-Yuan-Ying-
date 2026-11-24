package com.dsplayer.ds_player.jar_spider;

oneway interface IJarSpiderProcessCallback {
    void onResult(String requestId, String responseJson);
}
