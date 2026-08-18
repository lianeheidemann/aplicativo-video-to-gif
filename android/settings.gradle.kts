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
//   | Gradle   | 9.3.1   | 8.14.0         | 9.1.0           |
//   | AGP      | 9.1.0   | 8.11.1         | 9.0.1           |
//   | Kotlin   | 2.4.0   | 2.2.20         | 2.3.20          |
//   | Java     | 17      | 17             | 17              |
//   | minSdk   | 24      | 23             | 24              |
//
// (Gradle fica em android/gradle/wrapper/gradle-wrapper.properties;
//  Java e minSdk em app/build.gradle.kts.)
//
// Migrado para o AGP 9 em 2026-08-18. A DSL nova (android.newDsl) e o Kotlin
// embutido (android.builtInKotlin) do AGP 9 ainda não são suportados pelo
// Flutter Gradle Plugin desta versão do Flutter — ele faz cast para o tipo
// antigo do AGP internamente e quebra com esses modos ligados. Por isso
// gradle.properties desliga os dois (android.newDsl=false,
// android.builtInKotlin=false) e app/build.gradle.kts ainda aplica o plugin
// "kotlin-android" explicitamente. O próprio template do "flutter create"
// (Flutter 3.47) faz exatamente a mesma coisa em projetos novos.
plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "9.1.0" apply false
    id("org.jetbrains.kotlin.android") version "2.4.0" apply false
}

include(":app")
