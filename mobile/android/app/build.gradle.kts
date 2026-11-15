import java.util.Properties

plugins {
    id("com.android.application")
    // Firebase. Reads android/app/google-services.json at build time and bakes
    // the project ids into the APK — which is why that file is not a secret,
    // and why the service-account key, which is, never comes near the app.
    id("com.google.gms.google-services")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing comes from android/key.properties, which is gitignored and
// never checked in. When it is absent — a fresh clone, CI without secrets —
// the release build falls back to the debug key so `flutter build apk` still
// works; it just produces an artifact you cannot publish.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseKey = keystorePropertiesFile.exists()
if (hasReleaseKey) {
    keystoreProperties.load(keystorePropertiesFile.inputStream())
}

android {
    namespace = "so.dacaam.dacaam_pos"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // flutter_local_notifications schedules with java.time, which older
        // Android versions do not have. Desugaring backports it rather than
        // raising minSdk and cutting off the handsets this runs on.
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        // Fixed for the lifetime of the app: the store identifies an install
        // by this string, and changing it after publishing orphans everyone
        // who already has it.
        applicationId = "so.dacaam.dacaam_pos"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKey) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = keystoreProperties["storeFile"]?.let { file(it) }
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName(if (hasReleaseKey) "release" else "debug")
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
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
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
