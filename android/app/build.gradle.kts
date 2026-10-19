plugins {
    id("com.android.application")
    id("kotlin-android")
    // Google services Gradle plugin, processes google-services.json for Firebase
    id("com.google.gms.google-services")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.learnx.learnx"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.learnx.learnx"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Firebase Bill of Materials: pins compatible Firebase library versions so
    // any native Firebase dependencies declared here stay on compatible
    // versions. Auth, Firestore, and Functions are provided natively by the
    // FlutterFire Dart plugins (firebase_auth / cloud_firestore /
    // cloud_functions), so they are not declared here.
    implementation(platform("com.google.firebase:firebase-bom:35.0.2"))

    // Add native-only Firebase products here as needed, e.g.:
    //   implementation("com.google.firebase:firebase-analytics")
    // (firebase-analytics 24.x requires a newer Kotlin Gradle plugin than this
    // project currently uses, so it is intentionally left out.)
}

