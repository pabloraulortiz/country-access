import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final _db = Supabase.instance.client;

class Photos {
  static const bucket = 'profile-photos';

  /// Pregunta cámara o galería y devuelve la foto elegida (o null si cancela).
  static Future<XFile?> pick(BuildContext context) async {
    final src = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
              leading: const Icon(Icons.photo_camera),
              title: const Text('Cámara'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera)),
          ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Galería'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery)),
        ]),
      ),
    );
    if (src == null) return null;
    return ImagePicker().pickImage(
      source: src,
      maxWidth: 800,
      maxHeight: 800,
      imageQuality: 80,
      preferredCameraDevice: CameraDevice.front,
    );
  }

  /// Sube la foto (la reemplaza si ya existía) y guarda la ruta en el perfil. Solo administradores.
  static Future<String> upload(String userId, XFile file) async {
    final me = await _db.from('profiles').select('country_id').eq('id', _db.auth.currentUser!.id).single();
    final path = '${me['country_id']}/$userId.jpg';
    final bytes = await file.readAsBytes();
    await _db.storage.from(bucket).uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: true),
        );
    await _db.from('profiles').update({'photo_path': path}).eq('id', userId);
    return path;
  }
}

/// Avatar con la foto del perfil (URL firmada) o las iniciales si no tiene.
class ProfileAvatar extends StatefulWidget {
  final String? path;
  final String name;
  final double radius;
  const ProfileAvatar({super.key, required this.path, required this.name, this.radius = 20});
  @override
  State<ProfileAvatar> createState() => _ProfileAvatarState();
}

class _ProfileAvatarState extends State<ProfileAvatar> {
  late Future<String?> _url = _sign();

  Future<String?> _sign() async {
    final p = widget.path;
    if (p == null || p.isEmpty) return null;
    try {
      return await _db.storage.from(Photos.bucket).createSignedUrl(p, 3600);
    } catch (_) {
      return null;
    }
  }

  @override
  void didUpdateWidget(covariant ProfileAvatar old) {
    super.didUpdateWidget(old);
    if (old.path != widget.path) _url = _sign();
  }

  String get _initials {
    final parts = widget.name.trim().split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    return (parts.first[0] + (parts.length > 1 ? parts[1][0] : '')).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: _url,
      builder: (context, snap) {
        final url = snap.data;
        return CircleAvatar(
          radius: widget.radius,
          backgroundImage: url != null ? NetworkImage(url) : null,
          child: url == null ? Text(_initials, style: TextStyle(fontSize: widget.radius * 0.8)) : null,
        );
      },
    );
  }
}
