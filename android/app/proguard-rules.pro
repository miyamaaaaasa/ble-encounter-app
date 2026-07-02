# flutter_local_notifications: GsonのTypeToken型情報がR8で削除されると
# 通知スケジュールが実行時例外になる（開門通知が届かないバグの根本原因）
-keepattributes Signature
-keepattributes *Annotation*
-keepattributes EnclosingMethod
-keepattributes InnerClasses

-keep class com.dexterous.** { *; }
-keep class com.google.gson.** { *; }
-keep class com.google.gson.reflect.TypeToken { *; }
-keep class * extends com.google.gson.reflect.TypeToken
-keep,allowobfuscation class * extends com.google.gson.reflect.TypeToken
