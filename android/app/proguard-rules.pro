-dontwarn javax.annotation.Nullable
-dontwarn org.conscrypt.Conscrypt
-dontwarn org.conscrypt.OpenSSLProvider

# ===== Node.js 相关 =====
-keep class io.github.nodejs.** { *; }
-dontwarn io.github.nodejs.**