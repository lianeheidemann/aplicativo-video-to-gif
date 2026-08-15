import 'dart:io';

import 'package:gal/gal.dart';
import 'package:share_plus/share_plus.dart';

/// Salvar na galeria e compartilhar o GIF pronto.
class OutputService {
  const OutputService();

  static const _albumName = 'Vídeo em GIF';

  /// Salva na galeria do aparelho, pedindo permissão se ainda não tiver.
  ///
  /// Lança [OutputException] com uma mensagem em português quando o usuário
  /// nega o acesso — é o erro que mais aparece na prática.
  Future<void> saveToGallery(File gif) async {
    if (!await Gal.hasAccess()) {
      final granted = await Gal.requestAccess();
      if (!granted) {
        throw OutputException(
          'Sem permissão para salvar na galeria. Você pode liberar em '
          'Ajustes > Apps > Vídeo em GIF > Permissões.',
        );
      }
    }

    try {
      await Gal.putImage(gif.path, album: _albumName);
    } on GalException catch (e) {
      throw OutputException(
        'Não foi possível salvar na galeria: ${e.type.message}',
      );
    }
  }

  Future<void> share(File gif) async {
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(gif.path, mimeType: 'image/gif')],
        text: 'GIF feito com o app Vídeo em GIF',
      ),
    );
  }
}

class OutputException implements Exception {
  OutputException(this.message);

  final String message;

  @override
  String toString() => message;
}
