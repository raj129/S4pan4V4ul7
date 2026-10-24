plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    id("com.google.firebase.crashlytics")
    // END: FlutterFire Configuration
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val testerKeystorePath = System.getenv("ANDROID_KEYSTORE_PATH")
    ?.takeIf { it.isNotBlank() }

android {
    namespace = "com.system.calculator"
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // flutter_local_notifications needs Java 8+ APIs backported to older
        // Android API levels via desugaring.
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.system.calculator"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // minSdk 23: required for flutter_secure_storage (Android Keystore).
        minSdk = flutter.minSdkVersion
        targetSdk = 35
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        manifestPlaceholders["GOOGLE_MAPS_ANDROID_API_KEY"] =
            System.getenv("GOOGLE_MAPS_ANDROID_API_KEY")
                ?.takeIf { it.isNotBlank() }
                ?: rootProject.file("../.api_keys.json").let { keyFile ->
                    if (!keyFile.isFile) {
                        ""
                    } else {
                        val configuration =
                            groovy.json.JsonSlurper().parse(keyFile) as? Map<*, *>
                                ?: error(".api_keys.json must contain a JSON object.")
                        configuration["GOOGLE_MAPS_ANDROID_API_KEY"] as? String
                            ?: error(
                                ".api_keys.json must define " +
                                    "GOOGLE_MAPS_ANDROID_API_KEY as a string.",
                            )
                    }
                }
    }

    signingConfigs {
        if (testerKeystorePath != null) {
            create("testerRelease") {
                storeFile = file(testerKeystorePath)
                storePassword = System.getenv("ANDROID_KEYSTORE_PASSWORD")
                    ?: error("ANDROID_KEYSTORE_PASSWORD is required for tester signing")
                keyAlias = System.getenv("ANDROID_KEY_ALIAS")
                    ?: error("ANDROID_KEY_ALIAS is required for tester signing")
                keyPassword = System.getenv("ANDROID_KEY_PASSWORD")
                    ?: error("ANDROID_KEY_PASSWORD is required for tester signing")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (testerKeystorePath != null) {
                signingConfigs.getByName("testerRelease")
            } else if (project.hasProperty("allowDebugSigning")) {
                signingConfigs.getByName("debug")
            } else {
                // Debug-signed release builds can be impersonated; fail only
                // when a release task is actually requested.
                if (gradle.startParameter.taskNames.any {
                        it.contains("release", ignoreCase = true)
                    }) {
                    error(
                "Release builds need ANDROID_KEYSTORE_PATH (see README) " +
                            "or allowDebugSigning=true in ~/.gradle/gradle.properties.",
                    )
                }
                signingConfigs.getByName("debug")
            }
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
    testImplementation("junit:junit:4.13.2")
    implementation(platform("com.google.firebase:firebase-bom:34.9.0"))
    implementation("com.google.firebase:firebase-auth")
    implementation("com.google.firebase:firebase-storage")
    implementation("com.google.firebase:firebase-firestore")
    implementation("androidx.work:work-runtime-ktx:2.11.1")
    implementation("androidx.media3:media3-exoplayer:1.11.1")
    implementation("androidx.media3:media3-ui:1.11.1")
    implementation("androidx.media3:media3-transformer:1.11.1")
    implementation("androidx.media3:media3-effect:1.11.1")
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
