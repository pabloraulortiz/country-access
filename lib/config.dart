/// Se completa de dos formas:
///  - editando los valores por defecto de abajo, o
///  - con --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=... (lo usa el build en la nube).
const _url = String.fromEnvironment('SUPABASE_URL');
const _key = String.fromEnvironment('SUPABASE_ANON_KEY');

class AppConfig {
  static const supabaseUrl = _url == '' ? 'https://TU-PROYECTO.supabase.co' : _url;
  static const supabaseAnonKey = _key == '' ? 'TU_ANON_KEY' : _key;
}
