/// Supabase Auth exige email y una clave de 6+ caracteres. La app permite
/// usuario libre (sin @) y claves de 2+ caracteres, convirtiéndolos por debajo:
///  - usuario "jcolazo"  -> email interno "jcolazo@acceso.app"
///  - clave "ab"         -> "ab" + sufijo fijo (para llegar al mínimo de Supabase)
/// Un email real (con @ y otro dominio, ej. el admin inicial) se usa tal cual.
const authDomain = '@acceso.app';
const _pad = '#Acc3so!26';

bool isUsername(String s) => !s.contains('@') || s.toLowerCase().endsWith(authDomain);

String toAuthEmail(String input) {
  final s = input.trim();
  return s.contains('@') ? s : '${s.toLowerCase()}$authDomain';
}

String toAuthPassword(String userOrEmail, String pass) => isUsername(userOrEmail.trim()) ? '$pass$_pad' : pass;

/// Para mostrar: sin el dominio interno.
String displayUser(String? email) {
  final e = email ?? '';
  return e.toLowerCase().endsWith(authDomain) ? e.substring(0, e.length - authDomain.length) : e;
}
