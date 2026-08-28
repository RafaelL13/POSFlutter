import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

val releaseRequested = gradle.startParameter.taskNames.any {
    it.contains("release", ignoreCase = true)
}

val signingProperties = Properties()
val signingPropertiesFile = rootProject.file("key.properties")

if (signingPropertiesFile.exists()) {
    signingPropertiesFile.inputStream().use {
        signingProperties.load(it)
    }
}

fun signingValue(
    propertyName: String,
    environmentName: String,
): String? {
    val fromEnvironment =
        System.getenv(environmentName)?.trim()?.takeIf { it.isNotEmpty() }

    if (fromEnvironment != null) {
        return fromEnvironment
    }

    return signingProperties
        .getProperty(propertyName)
        ?.trim()
        ?.takeIf { it.isNotEmpty() }
}

val releaseStoreFile =
    signingValue("storeFile", "POSFLUTTER_RELEASE_STORE_FILE")

val releaseStorePassword =
    signingValue(
        "storePassword",
        "POSFLUTTER_RELEASE_STORE_PASSWORD",
    )

val releaseKeyAlias =
    signingValue("keyAlias", "POSFLUTTER_RELEASE_KEY_ALIAS")

val releaseKeyPassword =
    signingValue(
        "keyPassword",
        "POSFLUTTER_RELEASE_KEY_PASSWORD",
    )

val missingReleaseSigningValues = buildList {
    if (releaseStoreFile == null) {
        add(
            "storeFile / " +
                "POSFLUTTER_RELEASE_STORE_FILE",
        )
    }

    if (releaseStorePassword == null) {
        add(
            "storePassword / " +
                "POSFLUTTER_RELEASE_STORE_PASSWORD",
        )
    }

    if (releaseKeyAlias == null) {
        add(
            "keyAlias / " +
                "POSFLUTTER_RELEASE_KEY_ALIAS",
        )
    }

    if (releaseKeyPassword == null) {
        add(
            "keyPassword / " +
                "POSFLUTTER_RELEASE_KEY_PASSWORD",
        )
    }
}

if (
    releaseRequested &&
    missingReleaseSigningValues.isNotEmpty()
) {
    throw GradleException(
        "Android release signing is not configured. " +
            "Missing: " +
            missingReleaseSigningValues.joinToString(", ") +
            ". Configure android/key.properties or the " +
            "POSFLUTTER_RELEASE_* environment variables. " +
            "Release builds must never fall back to debug signing.",
    )
}

android {
    namespace = "com.posflutter.pos_app"
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    signingConfigs {
        if (missingReleaseSigningValues.isEmpty()) {
            create("release") {
                storeFile = file(requireNotNull(releaseStoreFile))
                storePassword = requireNotNull(releaseStorePassword)
                keyAlias = requireNotNull(releaseKeyAlias)
                keyPassword = requireNotNull(releaseKeyPassword)
            }
        }
    }

    defaultConfig {
        applicationId = "com.posflutter.pos_app"
        minSdk = 24
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            signingConfigs.findByName("release")?.let {
                signingConfig = it
            }

            if (
                releaseRequested &&
                signingConfig == null
            ) {
                throw GradleException(
                    "Release signing configuration is required.",
                )
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget =
            org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
