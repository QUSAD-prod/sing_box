# sing_box consumer R8/ProGuard rules.
#
# libbox is a gomobile binding: the native library resolves Java classes,
# fields and methods by name over JNI, so neither the generated bindings nor
# the Java classes implementing libbox interfaces may be renamed or removed.
-keep class go.** { *; }
-keep class io.nekohasekai.libbox.** { *; }
-keep class * implements io.nekohasekai.libbox.** { *; }
-keep class * implements go.Seq$Proxy { *; }
-dontwarn go.**
-dontwarn io.nekohasekai.libbox.**

# Components referenced from the merged AndroidManifest.xml are kept by AAPT;
# keep the in-process plugin entry points explicitly as well.
-keep class com.qusadprod.sing_box.SingBoxPlugin { *; }
