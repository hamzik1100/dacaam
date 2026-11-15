# R8 rules for the release build.
#
# Flutter's own engine classes are kept by the plugin's consumer rules, so this
# file only needs what R8 cannot infer.

# Flutter's deferred-component and Play Core hooks are referenced reflectively
# by the engine. Without these, a minified release build fails to link even
# though the app never uses deferred components.
-dontwarn com.google.android.play.core.**
-keep class io.flutter.embedding.engine.deferredcomponents.** { *; }

# Keep line numbers so a stack trace from a released build can still be read,
# and rename the source file so the original paths are not shipped.
-keepattributes SourceFile,LineNumberTable
-renamesourcefileattribute SourceFile
