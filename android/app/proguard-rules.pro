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

# Retaining these two is what keeps release stack traces readable now that most
# of the DEX is obfuscated. AGP bundles the R8 mapping file into the AAB, so
# Play deobfuscates Android vitals on its own, but only if the attributes
# survive to be mapped back.
-keepattributes SourceFile,LineNumberTable
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
-keep class * extends io.grpc.ManagedChannelProvider { *; }
-keep class * extends io.grpc.NameResolverProvider { *; }
-keep class * extends io.grpc.LoadBalancerProvider { *; }
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
