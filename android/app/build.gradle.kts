plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.fristproject"
    compileSdk = flutter.compileSdkVersion

    // ✅ FIX 1: Set back to 27 (The plugins require this).
    // Since you deleted the folder in Step 2, this will auto-download a clean copy.
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
        // ✅ FIX 2: Keep Desugaring enabled
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "com.example.fristproject"

        // ✅ FIX 3: Keep Min SDK 23
        minSdk = 23

        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // ✅ FIX 4: Keep the Desugar library
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")
}