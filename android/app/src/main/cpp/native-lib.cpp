#include <jni.h>
#include <android/log.h>
#include <cstring>
#include <cstdlib>
#include <cerrno>
#include <string>
#include <unistd.h>
#include "node.h"

#define LOG_TAG "NodeJS-JNI"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO,  LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

extern "C" {

JNIEXPORT jint JNICALL
Java_com_example_yuanying_NodeJSManager_nodeStart(
        JNIEnv* env,
        jobject /* thiz */,
        jobjectArray argsArray,
        jstring projectDirStr) {

    jsize argc = env->GetArrayLength(argsArray);
    LOGI("nodeStart called with %d arguments", argc);
    if (argc == 0) { LOGE("No arguments"); return -1; }

    // ---- 1. 把 Java String[] 拷到连续内存（libuv 要求 argv 内存连续）----
    int total_len = 0;
    for (int i = 0; i < argc; i++) {
        jstring jstr = (jstring) env->GetObjectArrayElement(argsArray, i);
        const char* str = env->GetStringUTFChars(jstr, nullptr);
        total_len += (int) strlen(str) + 1;
        env->ReleaseStringUTFChars(jstr, str);
        env->DeleteLocalRef(jstr);
    }

    char* args_buffer = (char*) calloc(total_len, sizeof(char));
    if (!args_buffer) { LOGE("calloc failed"); return -1; }

    char** argv = (char**) calloc(argc + 1, sizeof(char*));
    char* current = args_buffer;

    for (int i = 0; i < argc; i++) {
        jstring jstr = (jstring) env->GetObjectArrayElement(argsArray, i);
        const char* str = env->GetStringUTFChars(jstr, nullptr);
        strcpy(current, str);
        argv[i] = current;
        current += strlen(str) + 1;
        env->ReleaseStringUTFChars(jstr, str);
        env->DeleteLocalRef(jstr);
    }
    argv[argc] = nullptr;

    // ---- 2. 从 JNI 取 projectDir（不硬编码包名）----
    const char* projDirC = env->GetStringUTFChars(projectDirStr, nullptr);
    if (!projDirC) { free(args_buffer); free(argv); return -1; }
    LOGI("projectDir = %s", projDirC);

    // ---- 3. chdir 到 dist/ ----
    std::string distPath = std::string(projDirC) + "/dist";
    if (chdir(distPath.c_str()) != 0) {
        LOGE("chdir(%s) failed: %s", distPath.c_str(), strerror(errno));
    } else {
        LOGI("chdir ok -> %s", distPath.c_str());
    }

    // ---- 4. 设置 NODE_PATH ----
    setenv("NODE_PATH", projDirC, 1);
    LOGI("NODE_PATH = %s", projDirC);

    // ---- 5. 启动 Node ----
    LOGI("Calling node::Start...");
    int result = node::Start(argc, argv);
    LOGI("node::Start returned: %d", result);

    // ---- 6. 清理 ----
    env->ReleaseStringUTFChars(projectDirStr, projDirC);
    free(args_buffer);
    free(argv);
    return result;
}

} // extern "C"