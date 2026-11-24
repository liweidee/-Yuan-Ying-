-dontwarn javax.annotation.Nullable
-dontwarn org.conscrypt.Conscrypt
-dontwarn org.conscrypt.OpenSSLProvider

# ===== Node.js 相关 =====
-keep class io.github.nodejs.** { *; }
-dontwarn io.github.nodejs.**

# ===== DsPlayer JAR 插件桥 =====
# 动态 classes.dex 引用了固定包名和接口签名，不能在发布构建中被 R8 重命名。
-keep class com.dsplayer.ds_player.jar_spider.** { *; }
-keep class com.github.catvod.crawler.** { *; }

# 动态 JAR 通过反射/类名链接这些运行时，R8 无法静态识别引用。
-keep class com.google.gson.** { *; }
-keep class okhttp3.** { *; }
-keep class okio.** { *; }
-keep class kotlin.** { *; }
-dontwarn okhttp3.**
-dontwarn okio.**
-dontwarn org.bouncycastle.**
-dontwarn org.conscrypt.**
-dontwarn org.openjsse.**
