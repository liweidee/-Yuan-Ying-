import com.android.build.gradle.internal.api.ApkVariantOutputImpl
import org.jetbrains.kotlin.konan.properties.Properties

plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
}

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
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // 说明：ABI 限制由 flutter build --split-per-abi 提供，
        // 这里不再添加 ndk.abiFilters，避免与其冲突。

        externalNativeBuild {
            cmake {
                cppFlags.add("-std=c++14")
            }
        }
    }

    packagingOptions.jniLibs.useLegacyPackaging = true

    // ===== 签名配置 =====
    val keyProperties = Properties().also {
        val properties = rootProject.file("key.properties")
        if (properties.exists())
            it.load(properties.inputStream())
    }

    val config = keyProperties.getProperty("storeFile")?.let {
        signingConfigs.create("release") {
            storeFile = file(it)
            storePassword = keyProperties.getProperty("storePassword")
            keyAlias = keyProperties.getProperty("keyAlias")
            keyPassword = keyProperties.getProperty("keyPassword")
            enableV1Signing = true
            enableV2Signing = true
        }
    }

    buildFeatures {
        // 启用 AIDL 编译（PythonPluginBridge 依赖 IPySpiderService）
        aidl = true
        if (project.hasProperty("dev")) {
            resValues = true
        }
    }

    buildTypes {
        all {
            signingConfig = config ?: signingConfigs["debug"]
        }
        release {
            if (project.hasProperty("dev")) {
                applicationIdSuffix = ".dev"
                resValue(
                    type = "string",
                    name = "app_name",
                    value = "Yuanying dev",
                )
            }
        }
        debug {
            applicationIdSuffix = ".debug"
        }
    }

    applicationVariants.all {
        val variant = this
        variant.outputs.forEach { output ->
            (output as ApkVariantOutputImpl).versionCodeOverride = flutter.versionCode
        }
    }

    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
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
    implementation("org.nanohttpd:nanohttpd:2.3.1")
}