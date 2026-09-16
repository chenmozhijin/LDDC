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

// CI 专用签名：CI 需要产出"可直接安装"的 APK/AAB 供下载验证，但没有（也不应该有）
// 正式发布密钥。因此由 workflow 在 job 内用 keytool 生成一次性 keystore，并通过这四个
// 环境变量注入；每次运行的签名都不同，产物只能用于安装验证，不能当作发布版。
// 它与正式签名严格分离：正式 keystore 存在时优先使用正式签名；两者都缺失时仍然报错，
// 本地绝不能靠"放行无签名"产出看似可安装的包。
val ciArtifactKeystoreFile = providers.environmentVariable("LDDC_CI_ARTIFACT_KEYSTORE").orNull
val ciArtifactStorePassword = providers.environmentVariable("LDDC_CI_ARTIFACT_STORE_PASSWORD").orNull
val ciArtifactKeyAlias = providers.environmentVariable("LDDC_CI_ARTIFACT_KEY_ALIAS").orNull
val ciArtifactKeyPassword = providers.environmentVariable("LDDC_CI_ARTIFACT_KEY_PASSWORD").orNull
val hasCiArtifactSigning =
    providers.environmentVariable("CI").orNull.equals("true", ignoreCase = true) &&
        listOf(
            ciArtifactKeystoreFile,
            ciArtifactStorePassword,
            ciArtifactKeyAlias,
            ciArtifactKeyPassword,
        ).all { !it.isNullOrBlank() }

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
        // CI 专用签名配置：只在 CI 且四个环境变量齐全时创建，单独命名以便与正式签名
        // 区分；发布流水线永远用不到它。
        if (hasCiArtifactSigning) {
            create("ciArtifact") {
                storeFile = file(ciArtifactKeystoreFile!!)
                storePassword = ciArtifactStorePassword
                keyAlias = ciArtifactKeyAlias
                keyPassword = ciArtifactKeyPassword
            }
        }
    }

    buildTypes {
        release {
            // Release 包必须签名：优先正式 keystore，其次才是 CI 专用一次性签名。
            // 两者都没有时不回退 debug 签名，避免本地验证产物被误当作可分发安装包。
            when {
                hasReleaseSigning -> signingConfig = signingConfigs.getByName("release")
                hasCiArtifactSigning -> signingConfig = signingConfigs.getByName("ciArtifact")
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
    // Release 打包必须带签名：正式 keystore 或 CI 专用一次性签名二选一。
    // 之前允许"CI 无签名打包"的放行开关已删除——它产出的 APK 装不上，
    // 会掩盖真实问题；现在 CI 也必须真的有签名。
    if (releasePackagingRequested && !hasReleaseSigning && !hasCiArtifactSigning) {
        throw GradleException(
            "Android release 构建缺少签名。请设置 LDDC_ANDROID_KEYSTORE_FILE、" +
                "LDDC_ANDROID_KEYSTORE_PASSWORD、LDDC_ANDROID_KEY_ALIAS、" +
                "LDDC_ANDROID_KEY_PASSWORD，或在 android/key.properties 中提供 " +
                "storeFile/storePassword/keyAlias/keyPassword；CI 侧还会注入 " +
                "LDDC_CI_ARTIFACT_* 四个变量用于一次性签名。"
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
