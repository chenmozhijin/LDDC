import java.util.Properties
import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    id("com.android.application")
    // Flutter 新版本使用 Built-in Kotlin，应用层不能再显式应用 KGP，否则后续 Flutter 会拒绝构建。
    // Flutter 插件仍必须在 Android 插件之后应用，确保生成任务能接入原生工程。
    id("dev.flutter.flutter-gradle-plugin")
}

val releaseSigningProperties = Properties()
val releaseSigningPropertiesFile = rootProject.file("key.properties")
if (releaseSigningPropertiesFile.isFile) {
    releaseSigningPropertiesFile.inputStream().use(releaseSigningProperties::load)
}

fun releaseSigningValue(propertyName: String, environmentName: String): String? {
    val environmentValue = providers.environmentVariable(environmentName).orNull
    if (!environmentValue.isNullOrBlank()) {
        return environmentValue
    }
    return releaseSigningProperties.getProperty(propertyName)?.takeIf(String::isNotBlank)
}

val releaseKeystoreFile = releaseSigningValue("storeFile", "LDDC_ANDROID_KEYSTORE_FILE")
val releaseKeystorePassword = releaseSigningValue("storePassword", "LDDC_ANDROID_KEYSTORE_PASSWORD")
val releaseKeyAlias = releaseSigningValue("keyAlias", "LDDC_ANDROID_KEY_ALIAS")
val releaseKeyPassword = releaseSigningValue("keyPassword", "LDDC_ANDROID_KEY_PASSWORD")
val hasReleaseSigning = listOf(
    releaseKeystoreFile,
    releaseKeystorePassword,
    releaseKeyAlias,
    releaseKeyPassword,
).all { !it.isNullOrBlank() }
val allowUnsignedCiRelease =
    providers.environmentVariable("CI").orNull.equals("true", ignoreCase = true) &&
        providers.environmentVariable("LDDC_ALLOW_UNSIGNED_CI_RELEASE").orNull == "1"

android {
    namespace = "com.cmzj.lddc"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlin {
        compilerOptions {
            jvmTarget.set(JvmTarget.JVM_17)
        }
    }

    defaultConfig {
        applicationId = "com.cmzj.lddc"
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        // Android 版本号仍由 pubspec.yaml 的 version 字段统一驱动，避免多处手写后忘记同步。
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (hasReleaseSigning) {
                storeFile = file(releaseKeystoreFile!!)
                storePassword = releaseKeystorePassword
                keyAlias = releaseKeyAlias
                keyPassword = releaseKeyPassword
            }
        }
    }

    buildTypes {
        release {
            // Release 包必须由正式 keystore 签名。缺少签名时不回退 debug 签名，
            // 避免本地验证产物被误当作可分发安装包。
            if (hasReleaseSigning) {
                signingConfig = signingConfigs.getByName("release")
            }
        }
    }

    testOptions {
        execution = "ANDROIDX_TEST_ORCHESTRATOR"
    }

    sourceSets {
        getByName("androidTest").assets.srcDir("../../integration_test/fixtures/media")
    }
}

gradle.taskGraph.whenReady {
    val releasePackagingRequested = allTasks.any { task ->
        task.name.contains("Release") &&
            listOf("assemble", "bundle", "package", "sign", "validateSigning").any(task.name::contains)
    }
    // GitHub CI 需要验证 release APK/AAB 的完整编译链，但这些产物不会上传或发布。
    // 只有 CI=true 且显式开启专用变量时才允许无签名打包，本地仍必须提供正式密钥。
    if (releasePackagingRequested && !hasReleaseSigning && !allowUnsignedCiRelease) {
        throw GradleException(
            "Android release 构建缺少正式签名。请设置 LDDC_ANDROID_KEYSTORE_FILE、" +
                "LDDC_ANDROID_KEYSTORE_PASSWORD、LDDC_ANDROID_KEY_ALIAS、" +
                "LDDC_ANDROID_KEY_PASSWORD，或在 android/key.properties 中提供 " +
                "storeFile/storePassword/keyAlias/keyPassword。"
        )
    }
}

flutter {
    source = "../.."
}

configurations.configureEach {
    if (name == "debugRuntimeClasspath" || name == "debugAndroidTestRuntimeClasspath") {
        // 应用与 AndroidTest 必须解析到同一个固定 runner；Release 不包含该测试依赖。
        resolutionStrategy.force("androidx.test:runner:1.7.0")
    }
}

dependencies {
    testImplementation("junit:junit:4.13.2")
    androidTestImplementation("androidx.test:core:1.7.0")
    androidTestImplementation("androidx.test:runner:1.7.0")
    androidTestImplementation("androidx.test:rules:1.7.0")
    androidTestImplementation("androidx.test.uiautomator:uiautomator:2.4.0")
    androidTestUtil("androidx.test:orchestrator:1.6.1")
}
