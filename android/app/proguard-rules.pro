# R8 configuration for the release build.
#
# What is deliberately NOT here matters more than what is. This file used to
# open with blanket keeps on io.flutter.**, com.google.firebase.**,
# com.google.android.gms.** and androidx.**, each with `{ *; }`. Between them
# those four package trees are essentially the whole DEX file — this app's own
# Android code is MainActivity plus a generated registrant — so R8 was left with
# nothing it was allowed to rename or delete. Play Console reported
# Optimization, Obfuscation and Shrinking at 11% apiece, and the bundle carried
# 11.85 MB of uncompressed DEX.
#
# None of those keeps were needed:
#
#   * Flutter injects its own rules (flutter_proguard_rules.pro, wired in at
#     flutter_tools/gradle/src/main/kotlin/FlutterPlugin.kt). They are -dontwarn
#     lines plus a conditional keep on FlutterPlugin implementations marked
#     `allowshrinking,allowobfuscation` — Flutter wants R8 to rename those. A
#     stock `flutter create` app ships no proguard-rules.pro at all.
#   * firebase-common, firebase-auth, firebase-firestore, play-services-base and
#     play-services-auth each ship a proguard.txt inside their AAR, which AGP
#     merges automatically. firebase-auth's own rules already keep the
#     reflection-sensitive parts, including all of
#     com.google.android.gms.internal.**.
#   * Every AndroidX artifact ships consumer rules the same way.
#   * android.support.** matched nothing; there is no support library in the
#     dependency tree.
#
# The libraries know what they need kept. Adding a wildcard on top only stops
# R8 working. If a release-only ClassNotFoundException or NoSuchMethodError ever
# turns up, add a keep for that one class with a note on why — do not restore a
# package wildcard.

# Keep line numbers for useful Play Console deobfuscation while allowing R8 to
# discard the original source-file names. The uploaded mapping file is enough
# to recover obfuscated Android stack traces, and avoiding SourceFile metadata
# gives R8 one less item to retain across every class.
-keepattributes LineNumberTable
-renamesourcefileattribute SourceFile

# Moves classes into the unnamed top-level package so the DEX string pool stops
# storing package names. Must be requested explicitly below AGP 9.1, where it
# becomes implicit. Ticks Play Console's "Repackage Classes" row.
-repackageclasses

# gRPC, bundled by cloud_firestore.
#
# The one real gap left by dropping the blanket keeps: unlike every Firebase and
# Play Services artifact, the io.grpc jars ship no consumer rules of their own,
# and gRPC finds its transport, name-resolver and load-balancer implementations
# through ServiceLoader, which R8 cannot always trace. Scoped to the three
# provider hierarchies rather than the whole package, so it costs almost nothing.
#
# Firestore's protobuf wire types (com.google.firestore.v1, com.google.protobuf)
# need nothing here: they were never covered by the old blanket keeps either and
# have always worked, because R8 understands protobuf-lite natively.
#
# Provider classes are instantiated through ServiceLoader, so their no-arg
# constructors must remain. Their other methods implement non-reflective base
# class APIs and can still be optimized, shrunk and renamed safely.
-keep,allowoptimization,allowobfuscation class * extends io.grpc.ManagedChannelProvider {
    <init>();
}
-keep,allowoptimization,allowobfuscation class * extends io.grpc.NameResolverProvider {
    <init>();
}
-keep,allowoptimization,allowobfuscation class * extends io.grpc.LoadBalancerProvider {
    <init>();
}
-dontwarn io.grpc.**

# Play Core (referenced by Flutter's deferred-components support; the library
# itself is not bundled because this app does not use deferred components).
-dontwarn com.google.android.play.core.splitcompat.SplitCompatApplication
-dontwarn com.google.android.play.core.splitinstall.SplitInstallException
-dontwarn com.google.android.play.core.splitinstall.SplitInstallManager
-dontwarn com.google.android.play.core.splitinstall.SplitInstallManagerFactory
-dontwarn com.google.android.play.core.splitinstall.SplitInstallRequest$Builder
-dontwarn com.google.android.play.core.splitinstall.SplitInstallRequest
-dontwarn com.google.android.play.core.splitinstall.SplitInstallSessionState
-dontwarn com.google.android.play.core.splitinstall.SplitInstallStateUpdatedListener
-dontwarn com.google.android.play.core.tasks.OnFailureListener
-dontwarn com.google.android.play.core.tasks.OnSuccessListener
-dontwarn com.google.android.play.core.tasks.Task
