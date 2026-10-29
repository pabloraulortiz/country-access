import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../dni.dart';
import '../models.dart';
import '../ocr.dart';
import '../photo.dart';
import '../push.dart';

final _db = Supabase.instance.client;

class GuardHome extends StatefulWidget {
  final Profile profile;
  const GuardHome({super.key, required this.profile});
  @override
  State<GuardHome> createState() => _GuardHomeState();
}

class _GuardHomeState extends State<GuardHome> {
  int _tab = 0;
  String _direction = 'in';

  Future<void> _panic() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Botón de pánico'),
        content: const Text('¿Enviar alerta a administración y demás guardias?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('ENVIAR')),
        ],
      ),
    );
    if (ok == true) {
      await _db.from('panic_events').insert({
        'country_id': widget.profile.countryId,
        'guard_id': widget.profile.id,
      });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Alerta enviada')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      _ScanTab(direction: _direction),
      _ManualTab(profile: widget.profile, direction: _direction),
      _PatrolTab(profile: widget.profile),
      const _RecentTab(),
    ];
    return Scaffold(
      appBar: AppBar(
        title: const Text('Garita'),
        actions: [
          SegmentedButton<String>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: 'in', icon: Icon(Icons.login), label: Text('Ing.')),
              ButtonSegment(value: 'out', icon: Icon(Icons.logout), label: Text('Egr.')),
            ],
            selected: {_direction},
            onSelectionChanged: (s) => setState(() => _direction = s.first),
          ),
          IconButton(icon: const Icon(Icons.warning_amber, color: Colors.red), onPressed: _panic),
          IconButton(icon: const Icon(Icons.logout), onPressed: () => Push.signOut()),
        ],
      ),
      body: _ShiftGate(
        child: Column(children: [
          const _ShiftBanner(),
          Expanded(child: pages[_tab]),
        ]),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.qr_code_scanner), label: 'Escanear'),
          NavigationDestination(icon: Icon(Icons.badge_outlined), label: 'Identificar'),
          NavigationDestination(icon: Icon(Icons.directions_walk), label: 'Ronda'),
          NavigationDestination(icon: Icon(Icons.list_alt), label: 'Movimientos'),
        ],
      ),
    );
  }
}

// ---------- Turno obligatorio ----------
class _ShiftGate extends StatefulWidget {
  final Widget child;
  const _ShiftGate({required this.child});
  @override
  State<_ShiftGate> createState() => _ShiftGateState();
}

class _ShiftGateState extends State<_ShiftGate> {
  bool _on = true;
  bool _checked = false;
  Timer? _t;

  Future<void> _check() async {
    try {
      final r = await _db.rpc('guard_on_shift');
      if (mounted) {
        setState(() {
          _on = r == true;
          _checked = true;
        });
      }
    } catch (_) {
      // Sin conexión: el servidor igual valida cada operación.
      if (mounted) setState(() => _checked = true);
    }
  }

  @override
  void initState() {
    super.initState();
    _check();
    _t = Timer.periodic(const Duration(minutes: 2), (_) => _check());
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_checked) return const Center(child: CircularProgressIndicator());
    if (_on) return widget.child;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.lock_clock, size: 72),
          const SizedBox(height: 16),
          Text('Fuera de turno', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          const Text('No tenés un turno asignado en este momento. Consultá con administración.',
              textAlign: TextAlign.center),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () {
              setState(() => _checked = false);
              _check();
            },
            icon: const Icon(Icons.refresh),
            label: const Text('Reintentar'),
          ),
        ]),
      ),
    );
  }
}

// ---------- Turno actual ----------
class _ShiftBanner extends StatefulWidget {
  const _ShiftBanner();
  @override
  State<_ShiftBanner> createState() => _ShiftBannerState();
}

class _ShiftBannerState extends State<_ShiftBanner> {
  late Future<List<Map<String, dynamic>>> _f = _fetch();
  Timer? _t;

  Future<List<Map<String, dynamic>>> _fetch() async {
    final r = await _db.rpc('current_shift_info');
    return (r as List).map((e) => Map<String, dynamic>.from(e)).toList();
  }

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(minutes: 5), (_) => setState(() => _f = _fetch()));
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _f,
      builder: (context, snap) {
        if (!snap.hasData || snap.data!.isEmpty) return const SizedBox();
        final shifts = snap.data!;
        final mine = shifts.any((s) => s['mine'] == true);
        return Container(
          width: double.infinity,
          color: mine ? Colors.green.shade50 : Colors.orange.shade100,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (!mine)
              const Text('⚠ No tenés turno asignado en este momento',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            for (final s in shifts) ...[
              Text('${s['name']} ${s['start']}–${s['end']}',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              if ((s['guards'] as List).isEmpty)
                const Text('sin asignar', style: TextStyle(fontSize: 12))
              else
                Wrap(spacing: 10, children: [
                  for (final g in s['guards'] as List)
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      ProfileAvatar(path: g['photo'], name: g['name'], radius: 12),
                      const SizedBox(width: 4),
                      Text(g['name'], style: const TextStyle(fontSize: 12)),
                    ]),
                ]),
            ],
          ]),
        );
      },
    );
  }
}

// ---------- Escáner QR ----------
class _ScanTab extends StatefulWidget {
  final String direction;
  const _ScanTab({required this.direction});
  @override
  State<_ScanTab> createState() => _ScanTabState();
}

class _ScanTabState extends State<_ScanTab> {
  final _controller = MobileScannerController(detectionSpeed: DetectionSpeed.noDuplicates);
  bool _busy = false;
  Map<String, dynamic>? _result;

  Future<void> _onDetect(BarcodeCapture cap) async {
    if (_busy || cap.barcodes.isEmpty) return;
    final code = cap.barcodes.first.rawValue;
    if (code == null) return;
    setState(() => _busy = true);
    try {
      final res = await _db.rpc('validate_qr', params: {'p_token': code, 'p_direction': widget.direction});
      setState(() => _result = Map<String, dynamic>.from(res));
    } on PostgrestException catch (e) {
      setState(() => _result = {'allowed': false, 'reason': e.message});
    } finally {
      setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_result != null) {
      return _ResultView(result: _result!, onNext: () => setState(() => _result = null));
    }
    return Stack(children: [
      MobileScanner(controller: _controller, onDetect: _onDetect),
      if (_busy) const Center(child: CircularProgressIndicator()),
    ]);
  }
}

String? _normPlate(String s) {
  final p = s.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
  return p.isEmpty ? null : p;
}

// ---------- Identificar por DNI / patente (+ consulta al propietario) ----------
class _ManualTab extends StatefulWidget {
  final Profile profile;
  final String direction;
  const _ManualTab({required this.profile, required this.direction});
  @override
  State<_ManualTab> createState() => _ManualTabState();
}

class _ManualTabState extends State<_ManualTab> {
  final _lotSearch = TextEditingController();
  final _name = TextEditingController();
  final _dni = TextEditingController();
  final _plate = TextEditingController();
  List<Lot> _lotResults = [];
  Lot? _lot;
  String? _requestId;
  Map<String, dynamic>? _result;
  bool _manual = false; // sin autorización previa: consultar al propietario
  bool _busy = false;

  String? _nz(String s) => s.trim().isEmpty ? null : s.trim();

  void _snack(String m) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  void _reset() {
    setState(() {
      _result = null;
      _manual = false;
      _requestId = null;
      _lot = null;
      _lotResults = [];
      _lotSearch.clear();
      _name.clear();
      _dni.clear();
      _plate.clear();
    });
  }

  Future<void> _scanDni() async {
    final d = await Navigator.push<DniData>(
        context, MaterialPageRoute(builder: (_) => const DniScannerScreen()));
    if (d == null) return;
    _dni.text = d.dni;
    if (_name.text.trim().isEmpty && d.fullName.isNotEmpty) _name.text = d.fullName;
    await _search();
  }

  Future<void> _readPlate() async {
    try {
      final p = await readPlateFromCamera();
      if (p == null) {
        _snack('No se detectó una patente, escribila a mano');
        return;
      }
      _plate.text = p;
      await _search();
    } catch (_) {
      _snack('No se pudo leer la patente');
    }
  }

  Future<void> _search() async {
    final dni = _nz(_dni.text);
    final plate = _normPlate(_plate.text);
    if (dni == null && plate == null) {
      _snack('Ingresá DNI o patente');
      return;
    }
    setState(() => _busy = true);
    try {
      final res = await _db.rpc('validate_identity',
          params: {'p_dni': dni, 'p_plate': plate, 'p_direction': widget.direction});
      final r = Map<String, dynamic>.from(res as Map);
      if (r['multiple'] == true) {
        final opts = (r['options'] as List).map((e) => Map<String, dynamic>.from(e)).toList();
        await _pickOption(opts);
      } else if (r['found'] == false) {
        setState(() => _manual = true);
        _snack('Sin autorización vigente: consultá al propietario');
      } else {
        setState(() => _result = r);
      }
    } on PostgrestException catch (e) {
      _snack(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickOption(List<Map<String, dynamic>> opts) async {
    final token = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Elegí la visita'),
        children: opts
            .map((o) => SimpleDialogOption(
                  onPressed: () => Navigator.pop(ctx, o['token'] as String),
                  child: Text('${o['visitor']} · ${o['lot']}'),
                ))
            .toList(),
      ),
    );
    if (token == null) return;
    final res = await _db.rpc('validate_qr', params: {'p_token': token, 'p_direction': widget.direction});
    if (mounted) setState(() => _result = Map<String, dynamic>.from(res as Map));
  }

  Future<void> _searchLots(String q) async {
    if (q.isEmpty) return setState(() => _lotResults = []);
    final rows = await _db
        .from('lots')
        .select('id, code')
        .eq('country_id', widget.profile.countryId)
        .ilike('code', '%$q%')
        .limit(8);
    setState(() => _lotResults = rows.map(Lot.fromMap).toList());
  }

  Future<void> _requestOwner() async {
    if (_lot == null || _name.text.trim().isEmpty) {
      _snack('Elegí lote e ingresá nombre');
      return;
    }
    try {
      final blocked = await _db.rpc('is_blocked',
          params: {'p_dni': _nz(_dni.text), 'p_plate': _normPlate(_plate.text)});
      if (blocked == true) {
        _snack('PERSONA/VEHÍCULO EN LISTA DE BLOQUEO');
        return;
      }
      final debt = await _db.rpc('lot_debt_status', params: {'p_lot': _lot!.id});
      if (debt is Map && debt['debt'] == true) {
        if (debt['block'] == true) {
          _snack('LOTE CON DEUDA: consultar administración');
          return;
        }
        _snack('⚠ Lote con deuda');
      }
      final r = await _db.from('live_requests').insert({
        'country_id': widget.profile.countryId,
        'lot_id': _lot!.id,
        'guard_id': widget.profile.id,
        'visitor_name': _name.text.trim(),
        'dni': _nz(_dni.text),
        'plate': _normPlate(_plate.text),
      }).select('id').single();
      if (mounted) setState(() => _requestId = r['id']);
    } on PostgrestException catch (e) {
      _snack(e.message);
    }
  }

  Future<void> _logManual(String result, String? reason) async {
    try {
      await _db.rpc('log_manual_access', params: {
        'p_lot': _lot!.id,
        'p_name': _name.text.trim(),
        'p_dni': _nz(_dni.text),
        'p_plate': _normPlate(_plate.text),
        'p_direction': widget.direction,
        'p_result': result,
        'p_reason': reason,
      });
      _snack(result == 'allowed' ? 'Movimiento registrado' : 'Denegado registrado');
      _reset();
    } on PostgrestException catch (e) {
      _snack(e.message);
    }
  }

  List<Widget> _manualSection() {
    return [
      const Divider(height: 32),
      Text('Sin autorización: consultar al propietario', style: Theme.of(context).textTheme.titleSmall),
      const SizedBox(height: 12),
      TextField(
        controller: _name,
        textCapitalization: TextCapitalization.words,
        decoration: const InputDecoration(labelText: 'Nombre', border: OutlineInputBorder()),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _lotSearch,
        decoration: InputDecoration(labelText: 'Lote', border: const OutlineInputBorder(), suffixText: _lot?.code),
        onChanged: _searchLots,
      ),
      ..._lotResults.map((l) => ListTile(
            title: Text(l.code),
            onTap: () => setState(() {
              _lot = l;
              _lotResults = [];
              _lotSearch.text = l.code;
            }),
          )),
      const SizedBox(height: 16),
      if (_requestId == null)
        FilledButton.icon(
          icon: const Icon(Icons.notifications_active),
          label: const Text('Consultar al propietario'),
          onPressed: _requestOwner,
        )
      else
        StreamBuilder<List<Map<String, dynamic>>>(
          stream: _db.from('live_requests').stream(primaryKey: ['id']).eq('id', _requestId!),
          builder: (context, snap) {
            final st = (snap.data?.isNotEmpty ?? false) ? snap.data!.first['status'] as String : 'pending';
            if (st == 'pending') {
              return const ListTile(
                  leading: CircularProgressIndicator(), title: Text('Esperando respuesta del propietario…'));
            }
            final ok = st == 'authorized';
            return Card(
              color: ok ? Colors.green.shade100 : Colors.red.shade100,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(children: [
                  Text(ok ? 'AUTORIZADO por el propietario' : 'RECHAZADO por el propietario',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  FilledButton(
                    onPressed: () => _logManual(
                        ok ? 'allowed' : 'denied', ok ? 'Autorizado en vivo' : 'Rechazado por propietario'),
                    child: Text(ok ? 'Registrar movimiento' : 'Registrar rechazo'),
                  ),
                ]),
              ),
            );
          },
        ),
      const SizedBox(height: 8),
      if (_lot != null && _requestId == null)
        OutlinedButton(
          onPressed: () => _logManual('allowed', 'Registro manual'),
          child: const Text('Registrar sin consulta'),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    if (_result != null) return _ResultView(result: _result!, onNext: _reset);
    return ListView(padding: const EdgeInsets.all(16), children: [
      Row(children: [
        Expanded(
          child: TextField(
            controller: _dni,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'DNI', border: OutlineInputBorder()),
          ),
        ),
        const SizedBox(width: 8),
        IconButton.filledTonal(onPressed: _scanDni, icon: const Icon(Icons.badge_outlined), tooltip: 'Escanear DNI'),
      ]),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(
          child: TextField(
            controller: _plate,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(labelText: 'Patente', border: OutlineInputBorder()),
          ),
        ),
        if (!kIsWeb) ...[
          const SizedBox(width: 8),
          IconButton.filledTonal(
              onPressed: _readPlate, icon: const Icon(Icons.photo_camera_outlined), tooltip: 'Leer patente'),
        ],
      ]),
      const SizedBox(height: 16),
      FilledButton.icon(
        onPressed: _busy ? null : _search,
        icon: _busy
            ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.search),
        label: const Text('Buscar autorización'),
      ),
      if (!_manual)
        TextButton(
          onPressed: () => setState(() => _manual = true),
          child: const Text('Cargar a mano / sin autorización'),
        ),
      if (_manual) ..._manualSection(),
    ]);
  }
}

// ---------- Resultado verde / rojo ----------
class _ResultView extends StatelessWidget {
  final Map<String, dynamic> result;
  final VoidCallback onNext;
  const _ResultView({required this.result, required this.onNext});

  @override
  Widget build(BuildContext context) {
    final ok = result['allowed'] == true;
    const w = TextStyle(color: Colors.white);
    return Container(
      color: ok ? Colors.green.shade700 : Colors.red.shade700,
      width: double.infinity,
      height: double.infinity,
      padding: const EdgeInsets.all(24),
      child: Center(
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(ok ? Icons.check_circle : Icons.cancel, color: Colors.white, size: 96),
            const SizedBox(height: 16),
            Text(ok ? 'AUTORIZADO' : 'DENEGADO', style: w.copyWith(fontSize: 32, fontWeight: FontWeight.bold)),
            if (result['reason'] != null)
              Text('${result['reason']}', style: w.copyWith(fontSize: 20), textAlign: TextAlign.center),
            if (result['warning'] != null)
              Text('⚠ ${result['warning']}',
                  style: const TextStyle(color: Colors.yellow, fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            if (result['visitor'] != null) Text('${result['visitor']}', style: w.copyWith(fontSize: 24)),
            if (result['lot'] != null) Text('Lote: ${result['lot']}', style: w.copyWith(fontSize: 20)),
            if (result['plate'] != null) Text('Patente: ${result['plate']}', style: w.copyWith(fontSize: 18)),
            if (result['dni'] != null) Text('DNI: ${result['dni']}', style: w.copyWith(fontSize: 18)),
            const SizedBox(height: 32),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black),
              onPressed: onNext,
              child: const Text('Siguiente'),
            ),
          ]),
        ),
      ),
    );
  }
}

// ---------- Ronda: novedades ----------
class _PatrolTab extends StatefulWidget {
  final Profile profile;
  const _PatrolTab({required this.profile});
  @override
  State<_PatrolTab> createState() => _PatrolTabState();
}

class _PatrolTabState extends State<_PatrolTab> {
  int _rev = 0;
  bool _busy = false;

  void _snack(String m) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final rows = await _db
        .from('patrol_reports')
        .select('created_at, kind, description, lots(code), profiles(full_name)')
        .order('created_at', ascending: false)
        .limit(30);
    return rows;
  }

  Future<void> _save(String kind, {String? description, String? lotId}) async {
    setState(() => _busy = true);
    try {
      await _db.from('patrol_reports').insert({
        'country_id': widget.profile.countryId,
        'guard_id': widget.profile.id,
        'kind': kind,
        'description': description,
        'lot_id': lotId,
      });
      _snack(kind == 'clear' ? 'Ronda registrada: sin novedad' : 'Novedad registrada');
      if (mounted) setState(() => _rev++);
    } on PostgrestException catch (e) {
      _snack(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _incident() async {
    final lots = await _db.from('lots').select('id, code').eq('active', true).order('code');
    if (!mounted) return;
    final desc = TextEditingController();
    String? lotId;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.of(ctx).viewInsets.bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Registrar novedad', style: Theme.of(ctx).textTheme.titleLarge),
          const SizedBox(height: 12),
          TextField(
            controller: desc,
            maxLines: 4,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Qué observaste', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          Autocomplete<Map<String, dynamic>>(
            displayStringForOption: (l) => l['code'] as String,
            optionsBuilder: (v) => v.text.isEmpty
                ? const Iterable<Map<String, dynamic>>.empty()
                : lots.where((l) => (l['code'] as String).toLowerCase().contains(v.text.toLowerCase())).take(6),
            onSelected: (l) => lotId = l['id'] as String,
            fieldViewBuilder: (ctx, c, f, _) => TextField(
              controller: c,
              focusNode: f,
              onChanged: (_) => lotId = null,
              decoration: const InputDecoration(labelText: 'Lote (opcional)', border: OutlineInputBorder()),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Guardar novedad')),
        ]),
      ),
    );
    if (ok != true) return;
    if (desc.text.trim().isEmpty) {
      _snack('Escribí la novedad');
      return;
    }
    await _save('incident', description: desc.text.trim(), lotId: lotId);
  }

  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.all(16), children: [
      FilledButton.icon(
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(64), backgroundColor: Colors.green.shade700),
        onPressed: _busy ? null : () => _save('clear'),
        icon: const Icon(Icons.verified),
        label: const Text('Ronda sin novedad'),
      ),
      const SizedBox(height: 12),
      FilledButton.icon(
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(64), backgroundColor: Colors.orange.shade800),
        onPressed: _busy ? null : _incident,
        icon: const Icon(Icons.report_problem_outlined),
        label: const Text('Registrar novedad'),
      ),
      const SizedBox(height: 20),
      Text('Últimos registros', style: Theme.of(context).textTheme.titleMedium),
      FutureBuilder<List<Map<String, dynamic>>>(
        key: ValueKey(_rev),
        future: _load(),
        builder: (context, snap) {
          if (!snap.hasData) return const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()));
          if (snap.data!.isEmpty) return const Padding(padding: EdgeInsets.all(24), child: Text('Sin registros todavía'));
          return Column(
            children: snap.data!.map((r) {
              final clear = r['kind'] == 'clear';
              final t = DateTime.parse(r['created_at']).toLocal();
              final lot = (r['lots'] as Map?)?['code'];
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(clear ? Icons.verified_outlined : Icons.report_problem_outlined,
                    color: clear ? Colors.green : Colors.orange),
                title: Text(clear ? 'Sin novedad' : '${r['description']}'),
                subtitle: Text('${(r['profiles'] as Map?)?['full_name'] ?? ''} · '
                    '${t.day}/${t.month} ${t.hour}:${t.minute.toString().padLeft(2, '0')}'
                    '${lot != null ? ' · $lot' : ''}'),
              );
            }).toList(),
          );
        },
      ),
    ]);
  }
}

// ---------- Movimientos recientes ----------
class _RecentTab extends StatelessWidget {
  const _RecentTab();
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _db.from('access_logs').stream(primaryKey: ['id']).order('created_at', ascending: false).limit(50),
      builder: (context, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        return ListView(
          children: snap.data!.map((r) {
            final ok = r['result'] == 'allowed';
            final t = DateTime.parse(r['created_at']).toLocal();
            return ListTile(
              leading: Icon(r['direction'] == 'in' ? Icons.login : Icons.logout, color: ok ? Colors.green : Colors.red),
              title: Text('${r['plate'] ?? r['dni'] ?? r['reason'] ?? '—'}'),
              subtitle: Text('${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}  ${ok ? '' : r['reason'] ?? 'denegado'}'),
            );
          }).toList(),
        );
      },
    );
  }
}
