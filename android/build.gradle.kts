import java.io.File
import java.io.FileInputStream
import java.net.HttpURLConnection
import java.net.URI
import java.net.URL
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import java.security.MessageDigest
import java.util.Properties
import java.util.UUID
import java.util.zip.ZipFile

group = "com.qusadprod.sing_box"
version = "1.1.0"

// The oldest supported versions (the Flutter 3.29 app template). In an app
// build the app's own, usually newer, Android and Kotlin Gradle plugins are
// used; a newer version here would not resolve with an older Gradle.
buildscript {
    val kotlinVersion = "1.8.22"
    repositories {
        google()
        mavenCentral()
    }

    dependencies {
        classpath("com.android.tools.build:gradle:8.7.0")
        classpath("org.jetbrains.kotlin:kotlin-gradle-plugin:$kotlinVersion")
    }
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

plugins {
    id("com.android.library")
}

// AGP 9 compiles Kotlin itself (built-in Kotlin) and registers the `kotlin`
// extension. Older AGP versions, and AGP 9 with `android.builtInKotlin=false`,
// need the Kotlin Android plugin.
if (extensions.findByName("kotlin") == null) {
    apply(plugin = "org.jetbrains.kotlin.android")
}

// -----------------------------------------------------------------------------
// libbox (sing-box core) resolution
//
// The ~85 MB libbox AAR is not part of the pub package. It is resolved at
// configuration time (see libbox.properties for the lookup order), verified and
// extracted once per machine into
//   <gradleUserHome>/caches/sing_box/libbox/extracted/<sha256-prefix>/
// The extracted `classes.jar` becomes a plain jar dependency and `jni/` a
// jniLibs source directory. Using the extracted parts instead of a local `.aar`
// file dependency keeps the library module buildable as a project dependency
// (`flutter build apk/appbundle`) and as an AAR (`flutter build aar`), and needs
// no task wiring into AGP's native-library merge tasks.
// -----------------------------------------------------------------------------

class LibboxResolver(
    private val pluginDir: File,
    private val rootDir: File,
    private val gradleUserHome: File,
    private val properties: Properties,
    private val aarOverride: String?,
    private val baseUrlOverride: String?,
    private val logger: org.gradle.api.logging.Logger,
) {
    private val version: String = properties.getProperty("version")?.trim()
        ?: throw GradleException("sing_box: `version` missing in android/libbox.properties")
    private val expectedSha256: String = properties.getProperty("sha256")?.trim()?.lowercase()
        ?: throw GradleException("sing_box: `sha256` missing in android/libbox.properties")
    private val cacheRoot = File(gradleUserHome, "caches/sing_box/libbox")

    /** Returns the directory containing `classes.jar` and `jni/<abi>/libbox.so`. */
    fun resolve(): File {
        val explicit = aarOverride?.takeIf { it.isNotBlank() }
        if (explicit != null) {
            val aar = File(explicit).let { if (it.isAbsolute) it else File(rootDir, explicit) }
            if (!aar.isFile) {
                throw GradleException(
                    "sing_box: libbox AAR set via singBox.libboxAar / SING_BOX_LIBBOX_AAR does not exist: $aar",
                )
            }
            logger.info("sing_box: using libbox from $aar")
            return extract(aar, localSha256(aar))
        }
        val bundled = File(pluginDir, "libs/libbox.aar")
        if (bundled.isFile) {
            val sha = localSha256(bundled)
            if (sha != expectedSha256) {
                logger.warn(
                    "sing_box: android/libs/libbox.aar sha256 $sha differs from libbox.properties " +
                        "($expectedSha256, libbox $version); using the local copy anyway",
                )
            }
            return extract(bundled, sha)
        }
        return extract(download(), expectedSha256)
    }

    private fun download(): File {
        val dir = File(cacheRoot, version)
        val target = File(dir, properties.getProperty("fileName", "libbox.aar").replace("{version}", version))
        if (target.isFile && localSha256(target) == expectedSha256) {
            return target
        }
        val base = (baseUrlOverride?.takeIf { it.isNotBlank() } ?: properties.getProperty("baseUrl"))
            ?.replace("{version}", version)?.trimEnd('/')
            ?: throw GradleException("sing_box: `baseUrl` missing in android/libbox.properties")
        val url = "$base/${target.name}"
        dir.mkdirs()
        val part = File(dir, "${target.name}.${UUID.randomUUID()}.part")
        logger.lifecycle("sing_box: downloading libbox $version from $url")
        val sha = try {
            fetch(url, part)
        } catch (e: Exception) {
            part.delete()
            throw GradleException(
                "sing_box: failed to download libbox $version from $url: ${e.message}\n" +
                    "If you are offline or behind a firewall, download the file manually and point the " +
                    "Gradle property `singBox.libboxAar` (or env SING_BOX_LIBBOX_AAR) to it, or set " +
                    "`singBox.libboxBaseUrl` / SING_BOX_LIBBOX_BASE_URL to a mirror.",
                e,
            )
        }
        if (sha != expectedSha256) {
            part.delete()
            throw GradleException(
                "sing_box: sha256 mismatch for libbox $version downloaded from $url\n" +
                    "  expected: $expectedSha256\n  actual:   $sha",
            )
        }
        Files.move(part.toPath(), target.toPath(), StandardCopyOption.REPLACE_EXISTING, StandardCopyOption.ATOMIC_MOVE)
        rememberSha(target, sha)
        return target
    }

    private fun fetch(url: String, destination: File): String {
        var current: URL = URI(url).toURL()
        var redirects = 0
        while (true) {
            val connection = current.openConnection()
            connection.connectTimeout = 30_000
            connection.readTimeout = 120_000
            connection.setRequestProperty("User-Agent", "sing_box-flutter-gradle")
            if (connection is HttpURLConnection) {
                connection.instanceFollowRedirects = false
                val code = connection.responseCode
                if (code in 300..399) {
                    val location = connection.getHeaderField("Location")
                        ?: throw GradleException("HTTP $code without Location header")
                    connection.disconnect()
                    if (++redirects > 10) throw GradleException("too many redirects")
                    current = URL(current, location)
                    continue
                }
                if (code != HttpURLConnection.HTTP_OK) {
                    connection.disconnect()
                    throw GradleException("HTTP $code")
                }
            }
            val digest = MessageDigest.getInstance("SHA-256")
            connection.getInputStream().use { input ->
                destination.outputStream().use { output ->
                    val buffer = ByteArray(1 shl 16)
                    while (true) {
                        val read = input.read(buffer)
                        if (read < 0) break
                        digest.update(buffer, 0, read)
                        output.write(buffer, 0, read)
                    }
                }
            }
            return digest.digest().toHex()
        }
    }

    /** sha256 of a local file, memoized by path, size and mtime to avoid rehashing 85 MB on every build. */
    private fun localSha256(file: File): String {
        val memo = memoFile(file)
        if (memo.isFile) {
            val props = Properties().apply { memo.inputStream().use { load(it) } }
            if (props.getProperty("length") == file.length().toString() &&
                props.getProperty("lastModified") == file.lastModified().toString()
            ) {
                props.getProperty("sha256")?.let { return it }
            }
        }
        val digest = MessageDigest.getInstance("SHA-256")
        FileInputStream(file).use { input ->
            val buffer = ByteArray(1 shl 16)
            while (true) {
                val read = input.read(buffer)
                if (read < 0) break
                digest.update(buffer, 0, read)
            }
        }
        val sha = digest.digest().toHex()
        rememberSha(file, sha)
        return sha
    }

    private fun rememberSha(file: File, sha: String) {
        val memo = memoFile(file)
        memo.parentFile.mkdirs()
        val props = Properties()
        props.setProperty("path", file.canonicalPath)
        props.setProperty("length", file.length().toString())
        props.setProperty("lastModified", file.lastModified().toString())
        props.setProperty("sha256", sha)
        val tmp = File(memo.parentFile, "${memo.name}.${UUID.randomUUID()}.tmp")
        tmp.outputStream().use { props.store(it, null) }
        Files.move(tmp.toPath(), memo.toPath(), StandardCopyOption.REPLACE_EXISTING, StandardCopyOption.ATOMIC_MOVE)
    }

    private fun memoFile(file: File): File {
        val key = MessageDigest.getInstance("SHA-256")
            .digest(file.canonicalPath.toByteArray()).toHex().take(24)
        return File(cacheRoot, "sha-memo/$key.properties")
    }

    private fun extract(aar: File, sha: String): File {
        val dir = File(cacheRoot, "extracted/${sha.take(20)}")
        if (File(dir, ".complete").isFile) return dir
        val tmp = File(cacheRoot, "extracted/${sha.take(20)}.${UUID.randomUUID()}.tmp")
        tmp.mkdirs()
        try {
            var hasJar = false
            var libraries = 0
            ZipFile(aar).use { zip ->
                for (entry in zip.entries()) {
                    if (entry.isDirectory) continue
                    val name = entry.name
                    val keep = name == "classes.jar" || (name.startsWith("jni/") && name.endsWith(".so"))
                    if (!keep || name.contains("..")) continue
                    val out = File(tmp, name)
                    out.parentFile.mkdirs()
                    zip.getInputStream(entry).use { input -> out.outputStream().use { input.copyTo(it) } }
                    if (name == "classes.jar") hasJar = true else libraries++
                }
            }
            if (!hasJar || libraries == 0) {
                throw GradleException("sing_box: $aar is not a libbox AAR (classes.jar or jni/*.so missing)")
            }
            File(tmp, ".complete").writeText("$sha\n${aar.canonicalPath}\n")
            if (!File(dir, ".complete").isFile) {
                dir.deleteRecursively()
                if (!tmp.renameTo(dir) && !File(dir, ".complete").isFile) {
                    throw GradleException("sing_box: cannot move extracted libbox to $dir")
                }
            }
        } finally {
            if (tmp.exists()) tmp.deleteRecursively()
        }
        return dir
    }

    private fun ByteArray.toHex(): String = joinToString("") { "%02x".format(it) }
}

val libboxProperties = Properties().apply {
    file("libbox.properties").inputStream().use { load(it) }
}

val libboxDir: File = LibboxResolver(
    pluginDir = projectDir,
    rootDir = rootProject.projectDir,
    gradleUserHome = gradle.gradleUserHomeDir,
    properties = libboxProperties,
    aarOverride = providers.gradleProperty("singBox.libboxAar").orNull
        ?: providers.environmentVariable("SING_BOX_LIBBOX_AAR").orNull,
    baseUrlOverride = providers.gradleProperty("singBox.libboxBaseUrl").orNull
        ?: providers.environmentVariable("SING_BOX_LIBBOX_BASE_URL").orNull,
    logger = logger,
).resolve()

android {
    namespace = "com.qusadprod.sing_box"

    compileSdk = 35

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    sourceSets {
        getByName("main") {
            java.srcDirs("src/main/kotlin")
            jniLibs.srcDir(File(libboxDir, "jni"))
        }
        getByName("test") {
            java.srcDirs("src/test/kotlin")
        }
    }

    defaultConfig {
        minSdk = 24
        consumerProguardFiles("consumer-rules.pro")
    }

    testOptions {
        unitTests {
            isIncludeAndroidResources = true
            isReturnDefaultValues = true
            all {
                it.useJUnitPlatform()

                it.outputs.upToDateWhen { false }

                it.testLogging {
                    events("passed", "skipped", "failed", "standardOut", "standardError")
                    showStandardStreams = true
                }
            }
        }
    }
}

// Works with built-in Kotlin and with the Kotlin Android plugin (the typed
// `kotlin {}` block exists only with built-in Kotlin).
tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinJvmCompile>().configureEach {
    compilerOptions.jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
}

dependencies {
    implementation(files(File(libboxDir, "classes.jar")))
    // Kept at versions built with Kotlin 1.8 that need neither compileSdk 36
    // nor a recent AGP; apps with newer copies resolve to those.
    implementation("androidx.core:core-ktx:1.13.1")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.7.3")

    testImplementation("org.jetbrains.kotlin:kotlin-test-junit5")
    testImplementation("org.junit.jupiter:junit-jupiter:5.13.4")
    testRuntimeOnly("org.junit.platform:junit-platform-launcher")
}
