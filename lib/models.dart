import 'package:supabase_flutter/supabase_flutter.dart';

final _db = Supabase.instance.client;

class Profile {
  final String id;
  final String countryId;
  final String role; // admin | guard | owner
  final String fullName;
  Profile({required this.id, required this.countryId, required this.role, required this.fullName});

  static Future<Profile> loadCurrent() async {
    final uid = _db.auth.currentUser!.id;
    final r = await _db.from('profiles').select().eq('id', uid).single();
    return Profile(
      id: r['id'],
      countryId: r['country_id'],
      role: r['role'],
      fullName: r['full_name'],
    );
  }
}

class Lot {
  final String id;
  final String code;
  Lot({required this.id, required this.code});
  factory Lot.fromMap(Map<String, dynamic> m) => Lot(id: m['id'], code: m['code']);
}

class Visit {
  final String id;
  final String lotId;
  final String visitorName;
  final String? dni;
  final String? plate;
  final String type;
  final String status;
  final DateTime validFrom;
  final DateTime validTo;
  final int maxUses;
  final int uses;
  final String qrToken;

  Visit({
    required this.id,
    required this.lotId,
    required this.visitorName,
    this.dni,
    this.plate,
    required this.type,
    required this.status,
    required this.validFrom,
    required this.validTo,
    required this.maxUses,
    required this.uses,
    required this.qrToken,
  });

  factory Visit.fromMap(Map<String, dynamic> m) {
    final v = m['visitors'] as Map<String, dynamic>;
    return Visit(
      id: m['id'],
      lotId: m['lot_id'],
      visitorName: v['full_name'],
      dni: v['dni'],
      plate: v['plate'],
      type: m['type'],
      status: m['status'],
      validFrom: DateTime.parse(m['valid_from']).toLocal(),
      validTo: DateTime.parse(m['valid_to']).toLocal(),
      maxUses: m['max_uses'],
      uses: m['uses'],
      qrToken: m['qr_token'],
    );
  }
}

class LiveRequest {
  final String id;
  final String lotId;
  final String visitorName;
  final String? dni;
  final String? plate;
  final String status;
  final DateTime createdAt;

  LiveRequest({
    required this.id,
    required this.lotId,
    required this.visitorName,
    this.dni,
    this.plate,
    required this.status,
    required this.createdAt,
  });

  factory LiveRequest.fromMap(Map<String, dynamic> m) => LiveRequest(
        id: m['id'],
        lotId: m['lot_id'],
        visitorName: m['visitor_name'],
        dni: m['dni'],
        plate: m['plate'],
        status: m['status'],
        createdAt: DateTime.parse(m['created_at']).toLocal(),
      );
}
