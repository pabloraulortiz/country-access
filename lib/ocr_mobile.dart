import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';

/// Saca una foto con la cámara y busca una patente argentina en el texto.
/// Devuelve null si cancela o no encuentra ninguna. La guardia siempre puede corregirla a mano.
Future<String?> readPlateFromCamera() async {
  final f = await ImagePicker().pickImage(source: ImageSource.camera, maxWidth: 1600, imageQuality: 90);
  if (f == null) return null;
  final rec = TextRecognizer(script: TextRecognitionScript.latin);
  try {
    final r = await rec.processImage(InputImage.fromFilePath(f.path));
    return findPlate(r.text);
  } finally {
    rec.close();
  }
}

/// Formatos: AB123CD (Mercosur), ABC123 (anterior), A123BCD (moto Mercosur), 123ABC (moto anterior).
String? findPlate(String text) {
  final patterns = [
    RegExp(r'[A-Z]{2}\d{3}[A-Z]{2}'),
    RegExp(r'[A-Z]{3}\d{3}'),
    RegExp(r'[A-Z]\d{3}[A-Z]{3}'),
    RegExp(r'\d{3}[A-Z]{3}'),
  ];
  final lines = text.toUpperCase().split('\n').map((l) => l.replaceAll(RegExp(r'[^A-Z0-9]'), '')).toList();
  for (final p in patterns) {
    for (final l in lines) {
      final m = p.firstMatch(l);
      if (m != null) return m.group(0);
    }
  }
  // Por si la patente quedó partida en dos líneas
  final all = lines.join();
  for (final p in patterns) {
    final m = p.firstMatch(all);
    if (m != null) return m.group(0);
  }
  return null;
}
