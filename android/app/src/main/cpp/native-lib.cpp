#include <jni.h>
#include <android/log.h>
#include <string.h>
#include <stdlib.h>

#define LOG_TAG "NodeJS-JNI"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

// 声明 node_start 函数（来自 libnode.so）
extern "C" int node_start(int argc, char* argv[]);

extern "C" JNIEXPORT jint JNICALL
Java_com_example_yuanying_NodeJSManager_nodeStart(
        JNIEnv* env,
        jobject /* this */,
        jobjectArray argsArray) {

    // 获取参数数量
    jsize argc = env->GetArrayLength(argsArray);
    LOGI("nodeStart called with %d arguments", argc);

    // 分配 argv 数组（argc + 1，最后一个为 NULL）
    char** argv = new char*[argc + 1];

    // 转换 Java String 数组为 C 字符串数组
    for (int i = 0; i < argc; i++) {
        jstring jstr = (jstring)env->GetObjectArrayElement(argsArray, i);
        const char* str = env->GetStringUTFChars(jstr, nullptr);
        argv[i] = new char[strlen(str) + 1];
        strcpy(argv[i], str);
        env->ReleaseStringUTFChars(jstr, str);
    }
    argv[argc] = nullptr;

    // 打印参数（调试用）
    for (int i = 0; i < argc; i++) {
        LOGI("argv[%d] = %s", i, argv[i]);
    }

    // 调用 node_start，启动 Node.js 运行时
    int result = node_start(argc, argv);
    LOGI("node_start returned: %d", result);

    // 释放内存
    for (int i = 0; i < argc; i++) {
        delete[] argv[i];
    }
    delete[] argv;

    return result;
}