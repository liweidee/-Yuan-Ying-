import com.android.build.gradle.internal.api.ApkVariantOutputImpl
import org.jetbrains.kotlin.konan.properties.Properties
import java.io.File

plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
}

val releaseBuildRequested = gradle.startParameter.taskNames.any {
    it.lowercase().contains("release")
}
val keyProperties = Properties().also {
    val properties = rootProject.file("key.properties")
    if (properties.exists()) {
        properties.inputStream().use { stream -> it.load(stream) }
    }
}

fun signingValue(environmentName: String, propertyName: String): String? {
    return System.getenv(environmentName)?.trim()?.takeIf { it.isNotEmpty() }
        ?: keyProperties.getProperty(propertyName)?.trim()?.takeIf { it.isNotEmpty() }
}

val releaseSigningValues = mapOf(
    "storeFile" to signingValue("ANDROID_KEYSTORE_FILE", "storeFile"),
    "storePassword" to signingValue("ANDROID_KEYSTORE_PASSWORD", "storePassword"),
    "keyAlias" to signingValue("ANDROID_KEY_ALIAS", "keyAlias"),
    "keyPassword" to signingValue("ANDROID_KEY_PASSWORD", "keyPassword"),
)
val hasPartialSigningConfig =
    releaseSigningValues.values.any { it != null } &&
        releaseSigningValues.values.any { it == null }
val hasCompleteSigningConfig =
    releaseSigningValues.values.all { it != null }
if (hasPartialSigningConfig && releaseBuildRequested) {
    throw GradleException(
        "Android 固定签名配置不完整，请同时提供 ANDROID_KEYSTORE_FILE、" +
            "ANDROID_KEYSTORE_PASSWORD、ANDROID_KEY_ALIAS、ANDROID_KEY_PASSWORD，" +
            "或在 android/key.properties 中填写 storeFile/storePassword/keyAlias/keyPassword。",
    )
}

fun resolveKeystoreFile(path: String): File {
    val absolute = File(path)
    if (absolute.isAbsolute) return absolute
    val appRelative = project.file(path)
    return if (appRelative.exists()) appRelative else rootProject.file(path)
}

val resolvedVersionCode =
    System.getenv("YUANYING_VERSION_CODE")?.toIntOrNull() ?: flutter.versionCode
val resolvedVersionName =
    System.getenv("YUANYING_VERSION_NAME")?.trim()?.takeIf { it.isNotEmpty() }
        ?: flutter.versionName

android {
    namespace = "com.example.yuanying"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    lint {
        // 禁用 "ExpiredTargetSdkVersion" 检查
        disable += "ExpiredTargetSdkVersion"
        // 如果仍有报错，可以同时禁用它对应的新版检查ID
        // disable += "ExpiringTargetSdkVersion"
    }

    defaultConfig {
        applicationId = "com.example.yuanying"
        minSdk = flutter.minSdkVersion
         // 绕过 Android 10+ 的 W^X 限制，允许从 files/ 执行 proot 二进制
        targetSdk = 28
        versionCode = resolvedVersionCode
        versionName = resolvedVersionName

        // 说明：ABI 限制由 flutter build --split-per-abi 提供，
        // 这里不再添加 ndk.abiFilters，避免与其冲突。
    }

    packagingOptions.jniLibs.useLegacyPackaging = true

    buildFeatures {
        // 启用 AIDL 编译（PythonPluginBridge 依赖 IPySpiderService）
        aidl = true
        if (project.hasProperty("dev")) {
            resValues = true
        }
    }

    signingConfigs {
        if (hasCompleteSigningConfig) {
            create("release") {
                storeFile = resolveKeystoreFile(releaseSigningValues.getValue("storeFile")!!)
                storePassword = releaseSigningValues.getValue("storePassword")
                keyAlias = releaseSigningValues.getValue("keyAlias")
                keyPassword = releaseSigningValues.getValue("keyPassword")
                enableV1Signing = true
                enableV2Signing = true
                enableV3Signing = true
            }
        }
    }

    buildTypes {
        debug {
            signingConfig = signingConfigs.getByName("debug")
            applicationIdSuffix = ".debug"
        }
        release {
            if (!hasCompleteSigningConfig && releaseBuildRequested) {
                throw GradleException(
                    "Release APK 必须使用固定签名。请配置 ANDROID_KEYSTORE_FILE、" +
                        "ANDROID_KEYSTORE_PASSWORD、ANDROID_KEY_ALIAS、ANDROID_KEY_PASSWORD，" +
                        "不要回退到 debug 签名。",
                )
            }
            if (hasCompleteSigningConfig) {
                signingConfig = signingConfigs.getByName("release")
            }

            if (project.hasProperty("dev")) {
                applicationIdSuffix = ".dev"
                resValue(
                    type = "string",
                    name = "app_name",
                    value = "Yuanying dev",
                )
            }
        }
    }

    applicationVariants.all {
        val variant = this
        variant.outputs.forEach { output ->
            (output as ApkVariantOutputImpl).versionCodeOverride = resolvedVersionCode
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    // TVBox/CatVod JAR 源的宿主运行时依赖，与 DsPlayer 保持一致。
    implementation("com.google.code.gson:gson:2.10.1")
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    implementation("com.squareup.okio:okio:3.6.0")
}
