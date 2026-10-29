import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

/// Ingreso con huella: guarda usuario y clave en el almacenamiento cifrado del
/// teléfono y los libera solo tras validar la huella. No disponible en web.
class Bio {
  static final _auth = LocalAuthentication();
  static const _store = FlutterSecureStorage();
  static const _kUser = 'bio_user';
  static const _kPass = 'bio_pass';

  static Future<bool> available() async {
    if (kIsWeb) return false;
    try {
      return await _auth.isDeviceSupported() && (await _auth.getAvailableBiometrics()).isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> hasSaved() async {
    if (kIsWeb) return false;
    try {
      return (await _store.read(key: _kUser)) != null && (await _store.read(key: _kPass)) != null;
    } catch (_) {
      return false;
    }
  }

  static Future<void> save(String user, String pass) async {
    try {
      await _store.write(key: _kUser, value: user);
      await _store.write(key: _kPass, value: pass);
    } catch (_) {}
  }

  static Future<void> clear() async {
    try {
      await _store.delete(key: _kUser);
      await _store.delete(key: _kPass);
    } catch (_) {}
  }

  /// Pide la huella y devuelve (usuario, clave) guardados, o null si cancela o falla.
  static Future<(String, String)?> unlock() async {
    try {
      final ok = await _auth.authenticate(
        localizedReason: 'Ingresá con tu huella',
        options: const AuthenticationOptions(biometricOnly: true, stickyAuth: true),
      );
      if (!ok) return null;
      final u = await _store.read(key: _kUser);
      final p = await _store.read(key: _kPass);
      return (u != null && p != null) ? (u, p) : null;
    } catch (_) {
      return null;
    }
  }
}
