# FFmpegKit usa JNI e reflection: as classes precisam sobreviver ao R8.
-keep class com.arthenica.ffmpegkit.** { *; }
-keep class com.arthenica.smartexception.** { *; }
-dontwarn com.arthenica.**

# Flutter embedding
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.embedding.** { *; }
-dontwarn io.flutter.embedding.**

# androidx.window (vem junto com o Flutter, para telas dobráveis) referencia
# classes de extensão que só existem em aparelhos de alguns fabricantes.
# Elas não estão no classpath de compilação, e sem estas linhas o R8 aborta
# o build de release com "Missing classes detected while running R8".
# A ausência é esperada: o próprio androidx.window checa em tempo de execução
# antes de usá-las.
-dontwarn androidx.window.extensions.**
-dontwarn androidx.window.sidecar.**
