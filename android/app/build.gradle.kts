plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    // Put on the classpath only; applied below when Firebase is configured.
    id("com.google.gms.google-services") apply false
}

// Push notifications are optional. Drop the customer's google-services.json
// into android/app/ to enable FCM; without it the app relies on its WebSocket.
if (file("google-services.json").exists()) {
    apply(plugin = "com.google.gms.google-services")
}

android {
    namespace = "com.example.optional_mail_client"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // Change to your own reverse-domain ID before publishing (see docs/CLIENT.md).
        applicationId = "com.example.optional_mail_client"
        // flutter_secure_storage and Firebase Messaging need API 24+.
        minSdk = maxOf(flutter.minSdkVersion, 24)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // Debug keys only so `flutter run --release` works locally. Configure
            // a real signing config before publishing (see docs/CLIENT.md).
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}
