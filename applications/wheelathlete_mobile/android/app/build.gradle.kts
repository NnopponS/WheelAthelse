plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

val releaseKeystorePath = System.getenv("WHEELATHLETE_KEYSTORE_PATH")
val releaseStorePassword = System.getenv("WHEELATHLETE_KEYSTORE_PASSWORD")
val releaseKeyAlias = System.getenv("WHEELATHLETE_KEY_ALIAS")
val releaseKeyPassword = System.getenv("WHEELATHLETE_KEY_PASSWORD")
val hasReleaseSigning = listOf(
    releaseKeystorePath,
    releaseStorePassword,
    releaseKeyAlias,
    releaseKeyPassword,
).all { !it.isNullOrBlank() }

android {
    namespace = "com.wheelathlete.wheelathlete"
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
        applicationId = "com.wheelathlete.wheelathlete"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("wheelAthleteRelease") {
                storeFile = file(releaseKeystorePath!!)
                storePassword = releaseStorePassword
                keyAlias = releaseKeyAlias
                keyPassword = releaseKeyPassword
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseSigning) {
                signingConfigs.getByName("wheelAthleteRelease")
            } else {
                // Local research builds remain installable for testing. GitHub
                // release jobs fail before this fallback unless persistent
                // release-signing secrets are supplied.
                signingConfigs.getByName("debug")
            }
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

if (!hasReleaseSigning) {
    logger.warn(
        "WheelAthlete Android release signing secrets are not configured; " +
            "this local release build will use the debug key and is not suitable " +
            "for the public auto-update channel.",
    )
}

flutter {
    source = "../.."
}
