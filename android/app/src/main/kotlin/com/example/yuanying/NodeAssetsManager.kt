package com.example.yuanying

import android.content.Context
import android.content.res.AssetManager
import java.io.File
import java.io.FileOutputStream
import java.io.IOException

/**
 * Android 侧只负责把 APK assets 中的 Node 项目同步到可写目录。
 *
 * Node 运行时由插件中心提供，进程的启动、退出和重启统一由 Dart
 * NodeJSService 管理，与 Windows 端保持一致。
 */
internal object NodeAssetsManager {
    private const val ASSET_ROOT = "nodejs-project"

    @Synchronized
    fun prepareProject(context: Context): Map<String, Any> {
        val projectDir = File(context.applicationContext.filesDir, ASSET_ROOT)
        projectDir.mkdirs()

        copyAssetTree(context.assets, ASSET_ROOT, projectDir)

        val scriptFile = File(projectDir, "dist/main.js")
        check(scriptFile.isFile) {
            "Node.js 资源不完整，缺少 ${scriptFile.absolutePath}"
        }

        return mapOf(
            "projectDir" to projectDir.absolutePath,
            "scriptPath" to scriptFile.absolutePath,
        )
    }

    private fun copyAssetTree(
        assets: AssetManager,
        assetPath: String,
        destDir: File,
    ) {
        destDir.mkdirs()
        val entries = assets.list(assetPath) ?: return

        for (entry in entries) {
            val childAssetPath = "$assetPath/$entry"
            val childDest = File(destDir, entry)
            val children = assets.list(childAssetPath)

            if (children != null && children.isNotEmpty()) {
                copyAssetTree(assets, childAssetPath, childDest)
                continue
            }

            try {
                assets.open(childAssetPath).use { input ->
                    val bytes = input.buffered().readBytes()
                    if (childDest.isFile &&
                        childDest.length() == bytes.size.toLong() &&
                        childDest.readBytes().contentEquals(bytes)
                    ) {
                        return@use
                    }
                    childDest.parentFile?.mkdirs()
                    FileOutputStream(childDest).use { output ->
                        output.write(bytes)
                    }
                }
            } catch (_: IOException) {
                // AssetManager.list() 对空目录返回空数组；open() 失败时按目录处理。
                childDest.mkdirs()
            }
        }
    }
}
