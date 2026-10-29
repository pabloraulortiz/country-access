import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config.dart';
import 'models.dart';
import 'push.dart';
import 'screens/login_screen.dart';
import 'screens/owner_home.dart';
import 'screens/guard_home.dart';
import 'screens/admin_home.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(url: AppConfig.supabaseUrl, anonKey: AppConfig.supabaseAnonKey);
  await Push.init();
  runApp(const CountryApp());
}

final supabase = Supabase.instance.client;

class CountryApp extends StatelessWidget {
  const CountryApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Country Access',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: const Color(0xFF1B5E20), useMaterial3: true),
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: supabase.auth.onAuthStateChange,
      builder: (context, _) {
        if (supabase.auth.currentSession == null) return const LoginScreen();
        return FutureBuilder<Profile>(
          future: Profile.loadCurrent().then((p) {
            Push.register();
            return p;
          }),
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Scaffold(body: Center(child: CircularProgressIndicator()));
            }
            if (snap.hasError || !snap.hasData) {
              return Scaffold(
                body: Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Text('No se pudo cargar el perfil'),
                    TextButton(onPressed: () => Push.signOut(), child: const Text('Salir')),
                  ]),
                ),
              );
            }
            final p = snap.data!;
            switch (p.role) {
              case 'guard':
                return GuardHome(profile: p);
              case 'admin':
                return AdminHome(profile: p);
              default:
                return OwnerHome(profile: p);
            }
          },
        );
      },
    );
  }
}
