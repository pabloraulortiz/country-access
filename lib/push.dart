import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

@pragma('vm:entry-point')
Future<void> _bgHandler(RemoteMessage m) async {
  await Firebase.initializeApp();
}

/// Push con FCM. Si Firebase no está configurado (falta google-services.json /
/// GoogleService-Info.plist) la app funciona igual, sin notificaciones.
class Push {
  static bool _ready = false;
  static bool _listening = false;
  static final _local = FlutterLocalNotificationsPlugin();
  static const _channel = AndroidNotificationChannel(
    'access_alerts',
    'Alertas de acceso',
    description: 'Visitas, autorizaciones y alertas de pánico',
    importance: Importance.max,
  );

  static Future<void> init() async {
    try {
      await Firebase.initializeApp();
      FirebaseMessaging.onBackgroundMessage(_bgHandler);
      await _local.initialize(const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(),
      ));
      await _local
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(_channel);
      await FirebaseMessaging.instance
          .setForegroundNotificationPresentationOptions(alert: true, badge: true, sound: true);
      FirebaseMessaging.onMessage.listen(_onForeground);
      _ready = true;
    } catch (_) {
      _ready = false;
    }
  }

  static void _onForeground(RemoteMessage m) {
    final n = m.notification;
    if (n == null || defaultTargetPlatform != TargetPlatform.android) return; // iOS ya la muestra el sistema
    _local.show(
      m.hashCode,
      n.title,
      n.body,
      NotificationDetails(
        android: AndroidNotificationDetails(_channel.id, _channel.name,
            channelDescription: _channel.description, importance: Importance.max, priority: Priority.high),
      ),
    );
  }

  /// Llamar después de iniciar sesión.
  static Future<void> register() async {
    if (!_ready) return;
    try {
      final fm = FirebaseMessaging.instance;
      final s = await fm.requestPermission(alert: true, badge: true, sound: true);
      if (s.authorizationStatus == AuthorizationStatus.denied) return;
      final t = await fm.getToken();
      if (t != null) await _save(t);
      if (!_listening) {
        _listening = true;
        fm.onTokenRefresh.listen(_save);
      }
    } catch (_) {}
  }

  static Future<void> _save(String? token) async {
    final db = Supabase.instance.client;
    final u = db.auth.currentUser;
    if (u == null) return;
    await db.from('profiles').update({'fcm_token': token}).eq('id', u.id);
  }

  /// Cerrar sesión limpiando el token para no recibir avisos del usuario anterior.
  static Future<void> signOut() async {
    try {
      await _save(null);
      if (_ready) await FirebaseMessaging.instance.deleteToken();
    } catch (_) {}
    await Supabase.instance.client.auth.signOut();
  }
}
