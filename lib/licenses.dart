import 'package:flutter/foundation.dart';

/// Registra o aviso de licença do FFmpeg na tela de licenças do app.
///
/// A LGPL exige três coisas de quem distribui um binário fechado ligado a
/// uma biblioteca LGPL: dizer que a usa, dizer sob qual licença, e apontar
/// onde obter o código-fonte dela. Como o FFmpeg entra aqui como biblioteca
/// dinâmica (.so dentro do APK), o requisito de "permitir a substituição da
/// biblioteca" já está atendido pela própria forma de empacotamento.
///
/// Chame [registerThirdPartyLicenses] no `main()`. O texto aparece em
/// *Sobre → Licenças*, que é onde a revisão da Play Store procura.
void registerThirdPartyLicenses() {
  LicenseRegistry.addLicense(() async* {
    yield const LicenseEntryWithLineBreaks(
      ['FFmpeg'],
      'Este aplicativo usa o FFmpeg (https://ffmpeg.org), licenciado sob a '
      'GNU Lesser General Public License (LGPL) versão 2.1 ou posterior.\n\n'
      'O FFmpeg é usado nesta build SEM nenhum componente sob licença GPL '
      '(x264, x265, xvid e vid.stab não estão incluídos).\n\n'
      'O código-fonte do FFmpeg está disponível em '
      'https://github.com/FFmpeg/FFmpeg e o texto completo da LGPL em '
      'https://www.gnu.org/licenses/old-licenses/lgpl-2.1.html\n\n'
      'As bibliotecas do FFmpeg são distribuídas neste aplicativo como '
      'bibliotecas compartilhadas (.so), sem modificações.',
    );

    yield const LicenseEntryWithLineBreaks(
      ['ffmpeg-kit-flutter-new'],
      'Empacotamento do FFmpeg para Flutter, licenciado sob a GNU Lesser '
      'General Public License (LGPL) versão 3.0.\n\n'
      'Código-fonte: https://github.com/sk3llo/ffmpeg_kit_flutter\n'
      'Texto da licença: https://www.gnu.org/licenses/lgpl-3.0.html',
    );
  });
}
