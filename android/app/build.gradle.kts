import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing: android/key.properties (local) or env vars (CI), never in git.
val keyProps = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}
fun signingValue(name: String, env: String): String? = keyProps.getProperty(name) ?: System.getenv(env)

android {
    namespace = "at.macrobandit.cashbandit"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // needed by flutter_local_notifications
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "at.macrobandit.cashbandit"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            val store = signingValue("storeFile", "CASHBANDIT_KEYSTORE")
            if (store != null) {
                storeFile = file(store)
                storePassword = signingValue("storePassword", "CASHBANDIT_KEYSTORE_PASSWORD")
                keyAlias = signingValue("keyAlias", "CASHBANDIT_KEY_ALIAS")
                keyPassword = signingValue("keyPassword", "CASHBANDIT_KEY_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            // unsigned when no keystore is configured (e.g. F-Droid signs itself)
            val release = signingConfigs.getByName("release")
            signingConfig = if (release.storeFile != null) release else null
        }
    }

    dependenciesInfo {
        // F-Droid: no Google-encrypted dependency metadata blob in the APK
        includeInApk = false
        includeInBundle = false
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
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
    // AppCompat launch theme: local_auth's biometric dialog crashes on Android <= 8 without it
    implementation("androidx.appcompat:appcompat:1.7.1")
}
