import java.util.Properties
import java.io.FileInputStream
import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    id("com.android.application")
    id("kotlin-android")
    // O plugin do Flutter tem que vir DEPOIS dos plugins de Android e Kotlin.
    id("dev.flutter.flutter-gradle-plugin")
}

// Carrega as credenciais de assinatura de android/key.properties.
// Esse arquivo NÃO vai para o Git (ver .gitignore). Use key.properties.example
// como modelo. Sem ele, o build release cai no keystore de debug e a Play
// Store recusa o envio.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasSigningConfig = keystorePropertiesFile.exists()
if (hasSigningConfig) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    // O applicationId é a identidade permanente do app na Play Store.
    // Depois do primeiro envio ele NUNCA mais pode ser alterado.
    namespace = "br.com.lianeheidemann.videotogif"

    compileSdk = 36

    // O FFmpegKit traz bibliotecas nativas (.so) e precisa do NDK.
    // Esta é a versão que o Flutter 3.47 espera; se a sua instalação tiver
    // outra, a mensagem de erro do build informa qual usar.
    ndkVersion = "28.2.13676358"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // Necessário para APIs de java.time em minSdk < 26.
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        applicationId = "br.com.lianeheidemann.videotogif"

        // ffmpeg_kit_flutter_new exige no mínimo a API 24 (Android 7.0).
        minSdk = 24

        // Regra da Play Store: apps novos e atualizações precisam mirar a
        // API do ano anterior. A partir de 31/08/2026 o mínimo é a API 36.
        targetSdk = 36

        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // Não declaramos `ndk { abiFilters }` aqui de propósito. Ele conflita
        // com `flutter build apk --split-per-abi`, que configura os próprios
        // filtros de ABI, e o Gradle recusa as duas coisas ao mesmo tempo:
        //   Conflicting configuration : '...' in ndk abiFilters cannot be
        //   present when splits abi filters are set
        // Restringir ABI aqui também não traria ganho para a loja: o AAB é
        // dividido por ABI no servidor, então cada usuário baixa só a sua.
    }

    signingConfigs {
        if (hasSigningConfig) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = keystoreProperties["storeFile"]?.let { file(it) }
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasSigningConfig) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }

            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }

    // Reduz o download final: o Play entrega só a ABI do aparelho do usuário.
    bundle {
        abi { enableSplit = true }
        density { enableSplit = true }
        language { enableSplit = false }
    }

    packaging {
        jniLibs {
            useLegacyPackaging = false
        }
    }
}

// A partir do Kotlin 2.2 o bloco `kotlinOptions` dentro de `android` está
// obsoleto; a configuração do alvo da JVM passou para cá.
kotlin {
    compilerOptions {
        jvmTarget.set(JvmTarget.JVM_17)
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
