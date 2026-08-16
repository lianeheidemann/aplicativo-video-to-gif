<div align="center">

<img width="110" src="assets/icon.png"/>

# Vídeo em GIF

**Conversor de vídeo para GIF em Flutter, com estimativa de peso antes da conversão**

[![CI](https://img.shields.io/github/actions/workflow/status/lianeheidemann/aplicativo-video-to-gif/ci.yml?branch=main&style=flat-square&label=CI&logo=github&logoColor=white&labelColor=372b4d)](https://github.com/lianeheidemann/aplicativo-video-to-gif/actions/workflows/ci.yml)
[![Versão](https://img.shields.io/github/v/release/lianeheidemann/aplicativo-video-to-gif?style=flat-square&label=vers%C3%A3o&labelColor=372b4d&color=7c53c9)](https://github.com/lianeheidemann/aplicativo-video-to-gif/releases)
[![Testes](https://img.shields.io/badge/testes-39-b79cf2?style=flat-square&labelColor=372b4d)](test)
[![Licença](https://img.shields.io/github/license/lianeheidemann/aplicativo-video-to-gif?style=flat-square&label=licen%C3%A7a&labelColor=372b4d&color=d68fe0)](LICENSE)

![Flutter](https://img.shields.io/badge/Flutter-3.44%2B-b79cf2?style=flat-square&logo=flutter&logoColor=white&labelColor=372b4d)
![Dart](https://img.shields.io/badge/Dart-3.12%2B-7c53c9?style=flat-square&logo=dart&logoColor=white&labelColor=372b4d)
![Android](https://img.shields.io/badge/Android-7.0%2B-d68fe0?style=flat-square&logo=android&logoColor=white&labelColor=372b4d)
![FFmpeg](https://img.shields.io/badge/FFmpeg-LGPL-b79cf2?style=flat-square&logo=ffmpeg&logoColor=white&labelColor=372b4d)

</div>

Aplicativo Android que converte vídeos comuns (MP4, MOV, AVI, MKV, WEBM, 3GP)
em GIF, com controle de corte, proporção, velocidade, resolução e quadros por
segundo — e, principalmente, **mostrando quanto o arquivo vai pesar antes de
gastar tempo convertendo**.


<img src="assets/interface.png"/>

<img src="assets/demonstration.gif"/>

> Toda a conversão roda no aparelho, com FFmpeg. O app não tem permissão de
> internet.
>
> **[⬇ Baixar o APK](https://github.com/lianeheidemann/aplicativo-video-to-gif/releases/latest)**
> — instala direto no Android, sem loja.

---

## O problema que ele resolve

Converter vídeo em GIF é lento, e o peso do resultado é imprevisível: o mesmo
ajuste que produz 800 KB num vídeo produz 14 MB em outro, porque depende de
quanto a cena se mexe. O caminho normal é converter, ver que ficou grande,
ajustar e converter de novo — vários minutos por tentativa.

Este app inverte isso:

1. **Estimativa instantânea** enquanto você mexe nos controles, sem converter
   nada. Antes de qualquer medição o número sai de um palpite baseado no
   bitrate do arquivo, e a faixa exibida é larga de propósito (±40% a ±55%).
2. **Botão "Medir"**, que converte dois trechos de até um segundo com as
   mesmas configurações escolhidas e usa o tamanho real deles para calibrar o
   cálculo — a partir daí a faixa exibida passa a ser de ±15%.
3. **Semáforo de destinos**: mostra se o GIF cabe no WhatsApp, no X/Twitter e
   no Discord. Se não couber, um toque ajusta as configurações para caber.

Como isso funciona por dentro está em
[`docs/COMO_A_ESTIMATIVA_FUNCIONA.md`](docs/COMO_A_ESTIMATIVA_FUNCIONA.md).

## Funcionalidades

- **Prévia do vídeo** com play/pause e linha do tempo marcando o trecho
  escolhido
- **Corte de duração** — arraste as pontas do seletor para escolher o trecho
- **Formato da janela** — Original, 1:1, 4:5, 9:16, 16:9 e Personalizado, com
  redimensionamento pelas alças dos quatro cantos direto na prévia e barras
  para reposicionar o recorte
- **Velocidade** — 0,25x (câmera lenta) a 2x
- **Resolução** — de 160 px a 800 px de largura, oferecendo só as opções que
  não ampliam o vídeo original
- **Quadros por segundo** — 5, 8, 10, 12, 15, 20 ou 24
- **Qualidade de cor** — paleta de 64, 128 ou 256 cores, cinco níveis de
  suavização (dither) e três estratégias de paleta
- **Repetição** — GIF em loop infinito ou tocando uma vez só
- **Conversão em duas passagens** (`palettegen` + `paletteuse`), que é o que
  separa um GIF bonito de um GIF "lavado"
- **Progresso com cancelamento**
- **Salvar na galeria e compartilhar**, com a tela final mostrando o quanto a
  previsão errou em relação ao arquivo gerado

## Como rodar

Requer Flutter 3.44+ (Dart 3.12+) e o Android SDK (API 36) com NDK instalados.

```bash
git clone https://github.com/lianeheidemann/aplicativo-video-to-gif.git
cd aplicativo-video-to-gif

flutter pub get
flutter test
flutter run
```

## Estrutura

```
lib/
├── main.dart                       # ponto de entrada
├── licenses.dart                   # aviso de licença do FFmpeg (LGPL)
├── theme.dart                      # tema Material 3 e cores do veredito
├── models/
│   ├── video_info.dart             # metadados lidos pelo FFprobe
│   ├── conversion_settings.dart    # tudo que o usuário controla
│   └── size_estimate.dart          # resultado da estimativa e classificação
├── services/
│   ├── size_estimator.dart         # o modelo de previsão de peso (Dart puro)
│   ├── ffmpeg_service.dart         # leitura, medição e conversão
│   └── output_service.dart         # galeria e compartilhamento
└── ui/
    ├── home_page.dart              # escolha do vídeo
    ├── editor_page.dart            # controles + prévia com recorte
    ├── converting_page.dart        # progresso e cancelamento
    ├── result_page.dart            # GIF pronto, salvar e compartilhar
    └── widgets/
        ├── labeled_section.dart    # card expansível e chips de opção
        └── size_panel.dart         # painel de peso e compatibilidade

test/
├── size_estimator_test.dart        # 29 testes do modelo de estimativa
└── size_panel_test.dart            # 10 testes do painel de peso

docs/                               # estimativa, licenças e privacidade

tool/
└── gerar_icones.py                 # gera o ícone do app e o adaptativo

.github/workflows/
├── ci.yml                          # formatação, análise, testes e APK debug
└── release.yml                     # publica os APKs num Release
```

O `size_estimator.dart` é Dart puro, sem dependência do Flutter nem do
FFmpeg — por isso dá para testá-lo inteiro sem emulador.

## Qualidade

São **39 testes automatizados**: 29 cobrindo o modelo de estimativa
(dimensões de saída, contagem de quadros, monotonicidade, calibração, ajuste
automático para um alvo e classificação) e 10 cobrindo o painel de peso.

O workflow em `.github/workflows/ci.yml` roda, a cada push, `dart format`,
`flutter analyze`, `flutter test` e um build do APK de debug — esse último
serve para pegar erro de Gradle, de fusão de manifesto e de empacotamento das
bibliotecas nativas do FFmpeg.

## Baixar o APK

Cada versão publicada vira um
[Release](https://github.com/lianeheidemann/aplicativo-video-to-gif/releases)
com os APKs prontos para instalar — comece pelo `arm64-v8a`, que serve para
praticamente todo celular Android atual. O `universal` é maior, mas funciona
em qualquer aparelho.

Para gerar uma versão nova:

```bash
git tag v1.0.0
git push origin v1.0.0
```

O workflow `.github/workflows/release.yml` compila, nomeia e publica os
arquivos sozinho (também dá para dispará-lo pela aba Actions).

## Stack

| Camada | Escolha | Por quê |
|---|---|---|
| Interface | Flutter 3.44 (Material 3) | um código só, com visual nativo no Android |
| Conversão | `ffmpeg_kit_flutter_new_min` (FFmpeg LGPL) | variante sem componentes GPL, permite app de código fechado |
| Escolha de arquivo | `file_picker` | usa o seletor do sistema, sem exigir permissão de mídia |
| Prévia | `video_player` | mostra o trecho e a moldura de recorte antes de converter |
| Saída | `gal` + `share_plus` | salvar na galeria e compartilhar |

## Licença

Código do aplicativo: [MIT](LICENSE).
FFmpeg: LGPL-2.1-or-later — atribuição em [`NOTICE`](NOTICE), detalhes e
obrigações em [`docs/LICENCAS.md`](docs/LICENCAS.md).

---

<p align="center">Developed by <strong>Liane Heidemann</strong></p>
