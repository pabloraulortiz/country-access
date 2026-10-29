import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth_util.dart';
import '../biometric.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _user = TextEditingController();
  final _pass = TextEditingController();
  bool _loading = false;
  bool _bioAvailable = false;
  bool _bioSaved = false;
  bool _remember = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initBio();
  }

  Future<void> _initBio() async {
    final avail = await Bio.available();
    final saved = avail && await Bio.hasSaved();
    if (!mounted) return;
    setState(() {
      _bioAvailable = avail;
      _bioSaved = saved;
      _remember = avail && !saved;
    });
    if (saved) _bioLogin(); // pide la huella apenas se abre la pantalla
  }

  Future<void> _signIn(String user, String pass) async {
    await Supabase.instance.client.auth
        .signInWithPassword(email: toAuthEmail(user), password: toAuthPassword(user, pass));
  }

  Future<void> _login() async {
    final user = _user.text.trim();
    final pass = _pass.text;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _signIn(user, pass);
      if (_bioAvailable && _remember) await Bio.save(user, pass);
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _bioLogin() async {
    final cred = await Bio.unlock();
    if (cred == null || !mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _signIn(cred.$1, cred.$2);
    } on AuthException catch (e) {
      // Clave cambiada o usuario dado de baja: olvidar lo guardado.
      await Bio.clear();
      if (mounted) {
        setState(() {
          _bioSaved = false;
          _remember = true;
          _error = '${e.message}. Ingresá con tu usuario y clave.';
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.shield_outlined, size: 64),
                const SizedBox(height: 12),
                Text('Country Access', style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 24),
                TextField(
                  controller: _user,
                  autocorrect: false,
                  textCapitalization: TextCapitalization.none,
                  decoration: const InputDecoration(labelText: 'Usuario', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _pass,
                  obscureText: true,
                  onSubmitted: (_) => _loading ? null : _login(),
                  decoration: const InputDecoration(labelText: 'Contraseña', border: OutlineInputBorder()),
                ),
                if (_bioAvailable && !_bioSaved)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: _remember,
                    onChanged: (v) => setState(() => _remember = v ?? false),
                    title: const Text('Activar ingreso con huella'),
                  ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _loading ? null : _login,
                    child: _loading
                        ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Ingresar'),
                  ),
                ),
                if (_bioSaved) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _loading ? null : _bioLogin,
                      icon: const Icon(Icons.fingerprint),
                      label: const Text('Ingresar con huella'),
                    ),
                  ),
                ],
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
