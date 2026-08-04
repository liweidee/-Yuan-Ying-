#include <jni.h>
#include <android/log.h>
#include <string.h>
#include <stdlib.h>
#include "node.h"   // nodejs-mobile 的正确入口头文件

#define LOG_TAG "NodeJS-JNI"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

extern "C" {

// JNI 入口：启动 Node.js
JNIEXPORT jint JNICALL
Java_com_example_yuanying_NodeJSManager_nodeStart(
        JNIEnv* env,
        jobject thiz,
        jobjectArray argsArray) {

    jsize argc = env->GetArrayLength(argsArray);
    LOGI("nodeStart called with %d arguments", argc);

    if (argc == 0) {
        LOGE("No arguments provided");
        return -1;
    }

    // ---- 关键：把所有参数复制到一块连续内存中 ----
    // node::Start 内部使用 libuv，要求 argv 指向的内存是连续的
    int total_len = 0;
    for (int i = 0; i < argc; i++) {
        jstring jstr = (jstring)env->GetObjectArrayElement(argsArray, i);
        const char* str = env->GetStringUTFChars(jstr, nullptr);
        total_len += strlen(str) + 1;
        env->ReleaseStringUTFChars(jstr, str);
    }

    char* args_buffer = (char*)calloc(total_len, sizeof(char));
    if (!args_buffer) {
        LOGE("Failed to allocate memory for args");
        return -1;
    }

    char* argv[argc + 1];
    char* current = args_buffer;

    for (int i = 0; i < argc; i++) {
        jstring jstr = (jstring)env->GetObjectArrayElement(argsArray, i);
        const char* str = env->GetStringUTFChars(jstr, nullptr);
        strcpy(current, str);
        argv[i] = current;
        current += strlen(str) + 1;
        env->ReleaseStringUTFChars(jstr, str);
    }
    argv[argc] = nullptr;

    // ---- 调用 nodejs-mobile 的正确入口 ----
    LOGI("Calling node::Start...");
    int result = node::Start(argc, argv);

    free(args_buffer);
    LOGI("node::Start returned: %d", result);
    return result;
}

} // extern "C"