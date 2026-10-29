// En web se usa el stub (sin ML Kit); en Android/iOS la lectura real.
export 'ocr_stub.dart' if (dart.library.io) 'ocr_mobile.dart';
