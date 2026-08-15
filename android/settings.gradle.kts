pluginManagement {
    val flutterSdkPath = run {
        val properties = java.util.Properties()
        file("local.properties").inputStream().use { properties.load(it) }
        val flutterSdkPath = properties.getProperty("flutter.sdk")
        require(flutterSdkPath != null) { "flutter.sdk não está definido em local.properties" }
        flutterSdkPath
    }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

// Pisos de versão exigidos pelo Flutter 3.47. Quem valida é o
// DependencyVersionChecker.kt, dentro do próprio SDK do Flutter — abaixo do
// piso de ERRO o build falha; entre o de erro e o de aviso ele passa
// reclamando. Confira estes números ao atualizar o Flutter:
//
//   | Item     | Aqui    | Erro abaixo de | Avisa abaixo de |
//   |----------|---------|----------------|-----------------|
//   | Gradle   | 8.14.3  | 8.14.0         | 9.1.0           |
//   | AGP      | 8.13.0  | 8.11.1         | 9.0.1           |
//   | Kotlin   | 2.2.20  | 2.2.20         | 2.3.20          |
//   | Java     | 17      | 17             | 17              |
//   | minSdk   | 24      | 23             | 24              |
//
// (Gradle fica em android/gradle/wrapper/gradle-wrapper.properties;
//  Java e minSdk em app/build.gradle.kts.)
plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    // Ficamos na linha 8.x do AGP de propósito: o AGP 9 lê apenas a DSL nova,
    // incompatível com a forma como app/build.gradle.kts está escrito.
    // Migrar para o AGP 9 exigirá reescrever aquele arquivo.
    id("com.android.application") version "8.13.0" apply false
    id("org.jetbrains.kotlin.android") version "2.2.20" apply false
}

include(":app")
