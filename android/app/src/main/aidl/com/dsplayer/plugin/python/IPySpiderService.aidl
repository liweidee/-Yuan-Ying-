package com.dsplayer.plugin.python;

import android.os.ParcelFileDescriptor;

interface IPySpiderService {
    String ping();
    String loadSource(in ParcelFileDescriptor pfd, String name);
    String call(String key, String method, String env, String argsJson);
    String unloadSource(String key);
    String setFsGuardMode(String mode);
    String callBigFile(String key, String method, String env, String argsJson, in ParcelFileDescriptor pfd);
    String execCode(String file, String code, String workDir, in ParcelFileDescriptor pfd);
}