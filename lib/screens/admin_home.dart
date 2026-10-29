import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../models.dart';
import '../photo.dart';
import '../push.dart';

final _db = Supabase.instance.client;

void _snack(BuildContext c, String m) =>
    ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(m)));

Future<Map<String, dynamic>> _callUsers(Map<String, dynamic> body) async {
  try {
    final r = await _db.functions.invoke('admin-users', body: body);
    return Map<String, dynamic>.from(r.data as Map);
  } on FunctionException catch (e) {
    final d = e.details;
    throw Exception(d is Map && d['error'] != null ? d['error'] : 'Error del servidor');
  }
}

class AdminHome extends StatefulWidget {
  final Profile profile;
  const AdminHome({super.key, required this.profile});
  @override
  State<AdminHome> createState() => _AdminHomeState();
}

class _AdminHomeState extends State<AdminHome> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [
      _LotsTab(profile: widget.profile),
      _UsersTab(profile: widget.profile),
      const _DebtTab(),
      const _ShiftsTab(),
      const _LogsTab(),
    ];
    return Scaffold(
      appBar: AppBar(
        title: const Text('Administración'),
        actions: [
          IconButton(
            tooltip: 'Lista de bloqueo',
            icon: const Icon(Icons.block),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => Scaffold(
                  appBar: AppBar(title: const Text('Lista de bloqueo')),
                  body: _BlocklistTab(profile: widget.profile),
                ),
              ),
            ),
          ),
          IconButton(icon: const Icon(Icons.logout), onPressed: () => Push.signOut()),
        ],
      ),
      body: Column(children: [
        StreamBuilder<List<Map<String, dynamic>>>(
          stream: _db.from('panic_events').stream(primaryKey: ['id']).order('created_at', ascending: false).limit(1),
          builder: (context, snap) {
            if (!snap.hasData || snap.data!.isEmpty) return const SizedBox();
            final t = DateTime.parse(snap.data!.first['created_at']).toLocal();
            if (DateTime.now().difference(t).inMinutes > 10) return const SizedBox();
            return Container(
              color: Colors.red,
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              child: const Text('⚠ ALERTA DE PÁNICO DE GUARDIA',
                  textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            );
          },
        ),
        Expanded(child: pages[_tab]),
      ]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_work_outlined), label: 'Lotes'),
          NavigationDestination(icon: Icon(Icons.people_outline), label: 'Usuarios'),
          NavigationDestination(icon: Icon(Icons.request_quote_outlined), label: 'Morosidad'),
          NavigationDestination(icon: Icon(Icons.schedule), label: 'Turnos'),
          NavigationDestination(icon: Icon(Icons.history), label: 'Bitácora'),
        ],
      ),
    );
  }
}

// =================== LOTES ===================
class _LotsTab extends StatefulWidget {
  final Profile profile;
  const _LotsTab({required this.profile});
  @override
  State<_LotsTab> createState() => _LotsTabState();
}

class _LotsTabState extends State<_LotsTab> {
  bool _blockOnDebt = false;
  bool _debtOnly = false;
  String _q = '';

  @override
  void initState() {
    super.initState();
    _loadSetting();
  }

  Future<void> _loadSetting() async {
    final r = await _db.from('countries').select('block_on_debt').eq('id', widget.profile.countryId).single();
    if (mounted) setState(() => _blockOnDebt = r['block_on_debt'] == true);
  }

  Future<List<Map<String, dynamic>>> _load() async {
    var q = _db.from('lots').select('id, code, external_ref, debt_blocked, active');
    final rows = await q.order('code');
    return rows.where((l) {
      if (_debtOnly && l['debt_blocked'] != true) return false;
      if (_q.isNotEmpty && !(l['code'] as String).toLowerCase().contains(_q.toLowerCase())) return false;
      return true;
    }).toList();
  }

  Future<void> _edit([Map<String, dynamic>? lot]) async {
    final code = TextEditingController(text: lot?['code'] ?? '');
    final ref = TextEditingController(text: lot?['external_ref'] ?? '');
    bool active = lot?['active'] != false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setS) => AlertDialog(
          title: Text(lot == null ? 'Nuevo lote' : 'Editar lote'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: code, decoration: const InputDecoration(labelText: 'Código (ej. Mz 12 Lote 5)')),
              TextField(controller: ref, decoration: const InputDecoration(labelText: 'Ref. sistema administrativo (opcional)')),
              SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Activo'), value: active, onChanged: (v) => setS(() => active = v)),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Guardar')),
          ],
        ),
      ),
    );
    if (ok != true || code.text.trim().isEmpty) return;
    final data = {
      'code': code.text.trim(),
      'external_ref': ref.text.trim().isEmpty ? null : ref.text.trim(),
      'active': active,
    };
    try {
      if (lot == null) {
        await _db.from('lots').insert({...data, 'country_id': widget.profile.countryId});
      } else {
        await _db.from('lots').update(data).eq('id', lot['id']);
      }
      setState(() {});
    } on PostgrestException catch (e) {
      if (mounted) _snack(context, e.code == '23505' ? 'Ya existe un lote con ese código' : e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton(onPressed: () => _edit(), child: const Icon(Icons.add)),
      body: Column(children: [
        SwitchListTile(
          title: const Text('Bloquear ingreso a lotes con deuda'),
          subtitle: const Text('Desactivado: solo avisa a la guardia'),
          value: _blockOnDebt,
          onChanged: (v) async {
            await _db.from('countries').update({'block_on_debt': v}).eq('id', widget.profile.countryId);
            setState(() => _blockOnDebt = v);
          },
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(children: [
            Expanded(
              child: TextField(
                decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Buscar lote', isDense: true),
                onChanged: (v) => setState(() => _q = v),
              ),
            ),
            const SizedBox(width: 8),
            FilterChip(label: const Text('Con deuda'), selected: _debtOnly, onSelected: (v) => setState(() => _debtOnly = v)),
          ]),
        ),
        Expanded(
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: _load(),
            builder: (context, snap) {
              if (!snap.hasData) return const Center(child: CircularProgressIndicator());
              if (snap.data!.isEmpty) return const Center(child: Text('Sin lotes'));
              return ListView(
                children: snap.data!
                    .map((l) => ListTile(
                          title: Text(l['code']),
                          subtitle: Text([
                            if (l['active'] == false) 'Inactivo',
                            if (l['external_ref'] != null) 'Ref: ${l['external_ref']}',
                          ].join(' · ')),
                          trailing: l['debt_blocked'] == true
                              ? const Chip(label: Text('Deuda'), backgroundColor: Color(0xFFFFCDD2))
                              : null,
                          onTap: () => _edit(l),
                        ))
                    .toList(),
              );
            },
          ),
        ),
      ]),
    );
  }
}

// =================== USUARIOS ===================
class _UsersTab extends StatefulWidget {
  final Profile profile;
  const _UsersTab({required this.profile});
  @override
  State<_UsersTab> createState() => _UsersTabState();
}

class _UsersTabState extends State<_UsersTab> {
  String? _role;
  String _q = '';

  Future<List<Map<String, dynamic>>> _load() async {
    var q = _db.from('profiles').select('id, full_name, role, active, dni, phone, email, photo_path');
    if (_role != null) q = q.eq('role', _role!);
    final rows = await q.order('full_name');
    return rows.where((u) => _q.isEmpty || (u['full_name'] as String).toLowerCase().contains(_q.toLowerCase())).toList();
  }

  static const _roleLabel = {'admin': 'Admin', 'guard': 'Guardia', 'owner': 'Propietario'};

  Future<void> _create() async {
    final created = await Navigator.push<bool>(
        context, MaterialPageRoute(builder: (_) => const _UserFormScreen()));
    if (created == true) setState(() {});
  }

  void _open(Map<String, dynamic> u) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _UserSheet(user: u),
    );
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton(onPressed: _create, child: const Icon(Icons.person_add)),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Buscar usuario', isDense: true),
            onChanged: (v) => setState(() => _q = v),
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(children: [
            ChoiceChip(label: const Text('Todos'), selected: _role == null, onSelected: (_) => setState(() => _role = null)),
            for (final r in _roleLabel.entries) ...[
              const SizedBox(width: 6),
              ChoiceChip(label: Text(r.value), selected: _role == r.key, onSelected: (_) => setState(() => _role = r.key)),
            ],
          ]),
        ),
        Expanded(
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: _load(),
            builder: (context, snap) {
              if (!snap.hasData) return const Center(child: CircularProgressIndicator());
              if (snap.data!.isEmpty) return const Center(child: Text('Sin usuarios'));
              return ListView(
                children: snap.data!
                    .map((u) => ListTile(
                          leading: ProfileAvatar(path: u['photo_path'], name: u['full_name'], radius: 20),
                          title: Text(u['full_name'], style: TextStyle(decoration: u['active'] == false ? TextDecoration.lineThrough : null)),
                          subtitle: Text('${_roleLabel[u['role']]}${u['email'] != null ? ' · ${u['email']}' : ''}'),
                          onTap: () => _open(u),
                        ))
                    .toList(),
              );
            },
          ),
        ),
      ]),
    );
  }
}

// ---- Alta de usuario ----
class _UserFormScreen extends StatefulWidget {
  const _UserFormScreen();
  @override
  State<_UserFormScreen> createState() => _UserFormScreenState();
}

class _UserFormScreenState extends State<_UserFormScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _pass = TextEditingController();
  final _dni = TextEditingController();
  final _phone = TextEditingController();
  String _role = 'owner';
  XFile? _photo;
  Uint8List? _photoBytes;
  Set<String> _lotIds = {};
  bool _saving = false;

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final res = await _callUsers({
        'action': 'create',
        'email': _email.text.trim(),
        'password': _pass.text,
        'full_name': _name.text.trim(),
        'role': _role,
        'dni': _dni.text.trim(),
        'phone': _phone.text.trim(),
        'lot_ids': _lotIds.toList(),
      });
      if (_photo != null) {
        try {
          await Photos.upload(res['id'], _photo!);
        } catch (_) {
          if (mounted) _snack(context, 'Usuario creado, pero no se pudo subir la foto');
        }
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) _snack(context, e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nuevo usuario')),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          Center(
            child: GestureDetector(
              onTap: () async {
                final f = await Photos.pick(context);
                if (f == null) return;
                final b = await f.readAsBytes();
                setState(() {
                  _photo = f;
                  _photoBytes = b;
                });
              },
              child: Stack(alignment: Alignment.bottomRight, children: [
                CircleAvatar(
                  radius: 44,
                  backgroundImage: _photoBytes != null ? MemoryImage(_photoBytes!) : null,
                  child: _photoBytes == null ? const Icon(Icons.person, size: 44) : null,
                ),
                const CircleAvatar(radius: 14, child: Icon(Icons.photo_camera, size: 16)),
              ]),
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _role,
            decoration: const InputDecoration(labelText: 'Rol', border: OutlineInputBorder()),
            items: const [
              DropdownMenuItem(value: 'owner', child: Text('Propietario')),
              DropdownMenuItem(value: 'guard', child: Text('Guardia')),
              DropdownMenuItem(value: 'admin', child: Text('Administrador')),
            ],
            onChanged: (v) => setState(() => _role = v!),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Nombre y apellido', border: OutlineInputBorder()),
            validator: (v) => (v == null || v.trim().length < 3) ? 'Requerido' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'Email (usuario de ingreso)', border: OutlineInputBorder()),
            validator: (v) => (v == null || !v.contains('@')) ? 'Email inválido' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _pass,
            decoration: const InputDecoration(labelText: 'Contraseña inicial (mín. 8)', border: OutlineInputBorder()),
            validator: (v) => (v == null || v.length < 8) ? 'Mínimo 8 caracteres' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(controller: _dni, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'DNI', border: OutlineInputBorder())),
          const SizedBox(height: 12),
          TextFormField(controller: _phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Teléfono', border: OutlineInputBorder())),
          if (_role == 'owner') ...[
            const SizedBox(height: 12),
            ListTile(
              shape: RoundedRectangleBorder(side: const BorderSide(color: Colors.grey), borderRadius: BorderRadius.circular(4)),
              title: const Text('Lotes'),
              subtitle: Text(_lotIds.isEmpty ? 'Ninguno seleccionado' : '${_lotIds.length} seleccionado(s)'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                final r = await _pickLots(context, _lotIds);
                if (r != null) setState(() => _lotIds = r);
              },
            ),
          ],
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Crear usuario'),
          ),
        ]),
      ),
    );
  }
}

// ---- Selector de lotes (multi) ----
Future<Set<String>?> _pickLots(BuildContext context, Set<String> initial) async {
  final lots = await _db.from('lots').select('id, code').eq('active', true).order('code');
  if (!context.mounted) return null;
  final sel = {...initial};
  String q = '';
  return showDialog<Set<String>>(
    context: context,
    builder: (_) => StatefulBuilder(
      builder: (context, setS) {
        final shown = lots.where((l) => q.isEmpty || (l['code'] as String).toLowerCase().contains(q.toLowerCase())).toList();
        return AlertDialog(
          title: const Text('Seleccionar lotes'),
          content: SizedBox(
            width: double.maxFinite,
            height: 400,
            child: Column(children: [
              TextField(decoration: const InputDecoration(prefixIcon: Icon(Icons.search), isDense: true), onChanged: (v) => setS(() => q = v)),
              Expanded(
                child: ListView(
                  children: shown
                      .map((l) => CheckboxListTile(
                            dense: true,
                            title: Text(l['code']),
                            value: sel.contains(l['id']),
                            onChanged: (v) => setS(() => v == true ? sel.add(l['id']) : sel.remove(l['id'])),
                          ))
                      .toList(),
                ),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(context, sel), child: const Text('Aceptar')),
          ],
        );
      },
    ),
  );
}

// ---- Detalle / edición de usuario ----
class _UserSheet extends StatefulWidget {
  final Map<String, dynamic> user;
  const _UserSheet({required this.user});
  @override
  State<_UserSheet> createState() => _UserSheetState();
}

class _UserSheetState extends State<_UserSheet> {
  late bool _active = widget.user['active'] != false;
  late String? _photoPath = widget.user['photo_path'];
  int _rev = 0;
  Set<String>? _lotIds;
  List<String> _lotCodes = [];

  bool get _isOwner => widget.user['role'] == 'owner';

  @override
  void initState() {
    super.initState();
    if (_isOwner) _loadLots();
  }

  Future<void> _loadLots() async {
    final rows = await _db.from('lot_owners').select('lot_id, lots(code)').eq('profile_id', widget.user['id']);
    setState(() {
      _lotIds = rows.map((r) => r['lot_id'] as String).toSet();
      _lotCodes = rows.map((r) => (r['lots'] as Map)['code'] as String).toList()..sort();
    });
  }

  Future<void> _editLots() async {
    final r = await _pickLots(context, _lotIds ?? {});
    if (r == null) return;
    final uid = widget.user['id'];
    await _db.from('lot_owners').delete().eq('profile_id', uid);
    if (r.isNotEmpty) {
      await _db.from('lot_owners').insert(r.map((l) => {'lot_id': l, 'profile_id': uid}).toList());
    }
    await _loadLots();
  }

  Future<void> _changePhoto() async {
    final f = await Photos.pick(context);
    if (f == null) return;
    try {
      final p = await Photos.upload(widget.user['id'], f);
      setState(() {
        _photoPath = p;
        _rev++;
      });
    } catch (_) {
      if (mounted) _snack(context, 'No se pudo subir la foto');
    }
  }

  Future<void> _password() async {
    final c = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Nueva contraseña'),
        content: TextField(controller: c, decoration: const InputDecoration(labelText: 'Mínimo 8 caracteres')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Cambiar')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _callUsers({'action': 'set_password', 'user_id': widget.user['id'], 'password': c.text});
      if (mounted) _snack(context, 'Contraseña actualizada');
    } catch (e) {
      if (mounted) _snack(context, e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _toggle(bool v) async {
    try {
      await _callUsers({'action': 'set_active', 'user_id': widget.user['id'], 'active': v});
      setState(() => _active = v);
    } catch (e) {
      if (mounted) _snack(context, e.toString().replaceFirst('Exception: ', ''));
    }
  }

  @override
  Widget build(BuildContext context) {
    final u = widget.user;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          GestureDetector(
            onTap: _changePhoto,
            child: Stack(alignment: Alignment.bottomRight, children: [
              ProfileAvatar(key: ValueKey(_rev), path: _photoPath, name: u['full_name'], radius: 36),
              const CircleAvatar(radius: 12, child: Icon(Icons.photo_camera, size: 14)),
            ]),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(u['full_name'], style: Theme.of(context).textTheme.titleLarge)),
        ]),
        if (u['email'] != null) Text(u['email']),
        if (u['dni'] != null && (u['dni'] as String).isNotEmpty) Text('DNI: ${u['dni']}'),
        if (u['phone'] != null && (u['phone'] as String).isNotEmpty) Text('Tel: ${u['phone']}'),
        const SizedBox(height: 8),
        if (_isOwner)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Lotes'),
            subtitle: Text(_lotIds == null ? 'Cargando…' : (_lotCodes.isEmpty ? 'Ninguno' : _lotCodes.join(', '))),
            trailing: const Icon(Icons.edit),
            onTap: _lotIds == null ? null : _editLots,
          ),
        SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Activo'), value: _active, onChanged: _toggle),
        OutlinedButton.icon(onPressed: _password, icon: const Icon(Icons.lock_reset), label: const Text('Cambiar contraseña')),
      ]),
    );
  }
}

// =================== MOROSIDAD DEL MES ===================
class _DebtTab extends StatefulWidget {
  const _DebtTab();
  @override
  State<_DebtTab> createState() => _DebtTabState();
}

class _DebtTabState extends State<_DebtTab> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  String _q = '';
  bool _onlyDebt = false;

  static const _meses = ['Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio', 'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre'];
  String get _period => '${_month.year.toString().padLeft(4, '0')}-${_month.month.toString().padLeft(2, '0')}-01';

  Future<List<Map<String, dynamic>>> _load() async {
    final lots = await _db.from('lots').select('id, code').eq('active', true).order('code');
    final debts = await _db.from('lot_debts').select('lot_id, paid').eq('period', _period);
    final map = {for (final d in debts) d['lot_id'] as String: d['paid'] as bool};
    return lots
        .map((l) => {...l, 'owes': map.containsKey(l['id']) && map[l['id']] == false})
        .where((l) =>
            (_q.isEmpty || (l['code'] as String).toLowerCase().contains(_q.toLowerCase())) &&
            (!_onlyDebt || l['owes'] == true))
        .toList();
  }

  Future<void> _set(String lotId, bool owes) async {
    await _db.from('lot_debts').upsert({
      'lot_id': lotId,
      'period': _period,
      'paid': !owes,
      'updated_by': _db.auth.currentUser!.id,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
    setState(() {});
  }

  Future<void> _bulk() async {
    final c = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Morosos ${_meses[_month.month - 1]} ${_month.year}'),
        content: TextField(
          controller: c,
          maxLines: 8,
          decoration: const InputDecoration(
              hintText: 'Un código de lote por línea (código o ref. del sistema)', border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Marcar')),
        ],
      ),
    );
    if (ok != true) return;
    final codes = c.text.split(RegExp(r'[\n;,]')).map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    if (codes.isEmpty) return;
    try {
      final r = await _db.rpc('mark_debts_bulk', params: {'p_period': _period, 'p_codes': codes});
      final missing = List<String>.from(r['missing'] ?? []);
      if (!mounted) return;
      _snack(context, 'Marcados: ${r['marked']}${missing.isEmpty ? '' : ' · No encontrados: ${missing.join(', ')}'}');
      setState(() {});
    } on PostgrestException catch (e) {
      if (mounted) _snack(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
          onPressed: _bulk, icon: const Icon(Icons.playlist_add), label: const Text('Cargar lista')),
      body: Column(children: [
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          IconButton(
              icon: const Icon(Icons.chevron_left),
              onPressed: () => setState(() => _month = DateTime(_month.year, _month.month - 1))),
          Text('${_meses[_month.month - 1]} ${_month.year}', style: Theme.of(context).textTheme.titleMedium),
          IconButton(
              icon: const Icon(Icons.chevron_right),
              onPressed: () => setState(() => _month = DateTime(_month.year, _month.month + 1))),
        ]),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(children: [
            Expanded(
              child: TextField(
                decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Buscar lote', isDense: true),
                onChanged: (v) => setState(() => _q = v),
              ),
            ),
            const SizedBox(width: 8),
            FilterChip(label: const Text('Morosos'), selected: _onlyDebt, onSelected: (v) => setState(() => _onlyDebt = v)),
          ]),
        ),
        Expanded(
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: _load(),
            builder: (context, snap) {
              if (!snap.hasData) return const Center(child: CircularProgressIndicator());
              final items = snap.data!;
              return Column(children: [
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text('${items.where((l) => l['owes'] == true).length} moroso(s) en el mes'),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.only(bottom: 80),
                    children: items
                        .map((l) => SwitchListTile(
                              dense: true,
                              title: Text(l['code']),
                              subtitle: Text(l['owes'] == true ? 'Debe' : 'Al día'),
                              value: l['owes'] == true,
                              onChanged: (v) => _set(l['id'], v),
                            ))
                        .toList(),
                  ),
                ),
              ]);
            },
          ),
        ),
      ]),
    );
  }
}

// =================== TURNOS ===================
class _ShiftsTab extends StatefulWidget {
  const _ShiftsTab();
  @override
  State<_ShiftsTab> createState() => _ShiftsTabState();
}

class _ShiftsTabState extends State<_ShiftsTab> {
  DateTime _day = DateTime.now();
  final _df = DateFormat('yyyy-MM-dd');
  static const _dias = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];

  String get _d => _df.format(_day);
  bool _enforce = true;
  String? _countryId;

  @override
  void initState() {
    super.initState();
    _loadSetting();
  }

  Future<void> _loadSetting() async {
    try {
      final r = await _db.from('countries').select('id, enforce_shift').single();
      if (mounted) {
        setState(() {
          _countryId = r['id'];
          _enforce = r['enforce_shift'] == true;
        });
      }
    } catch (_) {}
  }

  Future<void> _setEnforce(bool v) async {
    if (_countryId == null) return;
    await _db.from('countries').update({'enforce_shift': v}).eq('id', _countryId!);
    setState(() => _enforce = v);
  }

  Future<Map<String, List<Map<String, dynamic>>>> _load() async {
    final shifts = await _db.from('shifts').select().order('start_time');
    final asg = await _db
        .from('shift_assignments')
        .select('id, shift_id, guard_id, profiles(full_name, photo_path)')
        .eq('shift_date', _d);
    final guards = await _db
        .from('profiles')
        .select('id, full_name, photo_path')
        .eq('role', 'guard')
        .eq('active', true)
        .order('full_name');
    return {'shifts': shifts, 'asg': asg, 'guards': guards};
  }

  Future<void> _add(String shiftId, List<Map<String, dynamic>> guards, Set<String> taken) async {
    final avail = guards.where((g) => !taken.contains(g['id'])).toList();
    if (avail.isEmpty) {
      _snack(context, 'No hay más guardias disponibles');
      return;
    }
    final id = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Agregar guardia'),
        children: avail
            .map((g) => SimpleDialogOption(
                  onPressed: () => Navigator.pop(ctx, g['id'] as String),
                  child: Row(children: [
                    ProfileAvatar(path: g['photo_path'], name: g['full_name'], radius: 16),
                    const SizedBox(width: 12),
                    Text(g['full_name']),
                  ]),
                ))
            .toList(),
      ),
    );
    if (id == null) return;
    try {
      await _db.from('shift_assignments').insert({'shift_id': shiftId, 'shift_date': _d, 'guard_id': id});
    } on PostgrestException catch (e) {
      if (mounted) _snack(context, e.code == '23505' ? 'Ya está asignado' : e.message);
    }
    setState(() {});
  }

  Future<void> _remove(String id) async {
    await _db.from('shift_assignments').delete().eq('id', id);
    setState(() {});
  }

  Future<void> _copyPrev() async {
    final prev = _df.format(_day.subtract(const Duration(days: 1)));
    final rows = await _db.from('shift_assignments').select('shift_id, guard_id').eq('shift_date', prev);
    if (rows.isEmpty) {
      if (mounted) _snack(context, 'El día anterior no tiene asignaciones');
      return;
    }
    await _db.from('shift_assignments').upsert(
          rows.map((r) => {...r, 'shift_date': _d}).toList(),
          onConflict: 'shift_id,shift_date,guard_id',
          ignoreDuplicates: true,
        );
    setState(() {});
  }

  Future<void> _repeatWeek() async {
    final rows = await _db.from('shift_assignments').select('shift_id, guard_id').eq('shift_date', _d);
    if (rows.isEmpty) {
      if (mounted) _snack(context, 'Este día no tiene asignaciones');
      return;
    }
    final out = <Map<String, dynamic>>[];
    for (var i = 1; i <= 6; i++) {
      final dd = _df.format(_day.add(Duration(days: i)));
      for (final r in rows) {
        out.add({...r, 'shift_date': dd});
      }
    }
    await _db.from('shift_assignments').upsert(out, onConflict: 'shift_id,shift_date,guard_id', ignoreDuplicates: true);
    if (mounted) _snack(context, 'Repetido en los próximos 6 días');
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      SwitchListTile(
        dense: true,
        title: const Text('Exigir turno asignado'),
        subtitle: const Text('La guardia solo opera en su turno (15 min antes a 30 min después)'),
        value: _enforce,
        onChanged: _setEnforce,
      ),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: () => setState(() => _day = _day.subtract(const Duration(days: 1)))),
        TextButton(
          onPressed: () async {
            final d = await showDatePicker(
                context: context,
                initialDate: _day,
                firstDate: DateTime.now().subtract(const Duration(days: 365)),
                lastDate: DateTime.now().add(const Duration(days: 365)));
            if (d != null) setState(() => _day = d);
          },
          child: Text('${_dias[_day.weekday - 1]} ${_day.day}/${_day.month}/${_day.year}'),
        ),
        IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: () => setState(() => _day = _day.add(const Duration(days: 1)))),
        PopupMenuButton<String>(
          onSelected: (v) => v == 'prev' ? _copyPrev() : _repeatWeek(),
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'prev', child: Text('Copiar del día anterior')),
            PopupMenuItem(value: 'week', child: Text('Repetir en los próximos 6 días')),
          ],
        ),
      ]),
      Expanded(
        child: FutureBuilder<Map<String, List<Map<String, dynamic>>>>(
          future: _load(),
          builder: (context, snap) {
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            final shifts = snap.data!['shifts']!;
            final asg = snap.data!['asg']!;
            final guards = snap.data!['guards']!;
            return ListView(
              padding: const EdgeInsets.all(12),
              children: shifts.map((s) {
                final id = s['id'] as String;
                final mine = asg.where((a) => a['shift_id'] == id).toList();
                final req = s['required_guards'] as int;
                final start = (s['start_time'] as String).substring(0, 5);
                final end = (s['end_time'] as String).substring(0, 5);
                final overnight = start.compareTo(end) >= 0;
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Expanded(
                          child: Text('${s['name']}  $start–$end${overnight ? ' (+1 día)' : ''}',
                              style: Theme.of(context).textTheme.titleMedium),
                        ),
                        Chip(
                          label: Text('${mine.length}/$req'),
                          backgroundColor: mine.length >= req ? Colors.green.shade100 : Colors.red.shade100,
                        ),
                      ]),
                      const SizedBox(height: 8),
                      Wrap(spacing: 8, runSpacing: 4, children: [
                        for (final a in mine)
                          InputChip(
                            avatar: ProfileAvatar(
                                path: (a['profiles'] as Map)['photo_path'],
                                name: (a['profiles'] as Map)['full_name'],
                                radius: 12),
                            label: Text((a['profiles'] as Map)['full_name']),
                            onDeleted: () => _remove(a['id']),
                          ),
                        ActionChip(
                          avatar: const Icon(Icons.add, size: 18),
                          label: const Text('Agregar'),
                          onPressed: () => _add(id, guards, mine.map((a) => a['guard_id'] as String).toSet()),
                        ),
                      ]),
                    ]),
                  ),
                );
              }).toList(),
            );
          },
        ),
      ),
    ]);
  }
}

// =================== BLOQUEOS ===================
class _BlocklistTab extends StatefulWidget {
  final Profile profile;
  const _BlocklistTab({required this.profile});
  @override
  State<_BlocklistTab> createState() => _BlocklistTabState();
}

class _BlocklistTabState extends State<_BlocklistTab> {
  Future<void> _add() async {
    final dni = TextEditingController();
    final plate = TextEditingController();
    final reason = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Bloquear'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: dni, decoration: const InputDecoration(labelText: 'DNI')),
          TextField(controller: plate, decoration: const InputDecoration(labelText: 'Patente')),
          TextField(controller: reason, decoration: const InputDecoration(labelText: 'Motivo')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Guardar')),
        ],
      ),
    );
    if (ok != true || (dni.text.trim().isEmpty && plate.text.trim().isEmpty)) return;
    await _db.from('blocklist').insert({
      'country_id': widget.profile.countryId,
      'dni': dni.text.trim().isEmpty ? null : dni.text.trim(),
      'plate': plate.text.trim().isEmpty ? null : plate.text.trim().toUpperCase().replaceAll(' ', ''),
      'reason': reason.text.trim(),
      'created_by': widget.profile.id,
    });
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton(onPressed: _add, child: const Icon(Icons.add)),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _db.from('blocklist').select().order('created_at', ascending: false),
        builder: (context, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          return ListView(
            children: snap.data!
                .map((b) => ListTile(
                      title: Text('${b['dni'] ?? ''} ${b['plate'] ?? ''}'.trim()),
                      subtitle: Text('${b['reason'] ?? ''}'),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () async {
                          await _db.from('blocklist').delete().eq('id', b['id']);
                          setState(() {});
                        },
                      ),
                    ))
                .toList(),
          );
        },
      ),
    );
  }
}

// =================== BITÁCORA ===================
class _LogsTab extends StatelessWidget {
  const _LogsTab();
  @override
  Widget build(BuildContext context) {
    return const DefaultTabController(
      length: 2,
      child: Column(children: [
        TabBar(tabs: [Tab(text: 'Accesos'), Tab(text: 'Rondas')]),
        Expanded(child: TabBarView(children: [_AccessLog(), _PatrolLog()])),
      ]),
    );
  }
}

class _PatrolLog extends StatelessWidget {
  const _PatrolLog();
  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _db
          .from('patrol_reports')
          .select('created_at, kind, description, lots(code), profiles(full_name)')
          .order('created_at', ascending: false)
          .limit(200),
      builder: (context, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        if (snap.data!.isEmpty) return const Center(child: Text('Sin rondas registradas'));
        return ListView(
          children: snap.data!.map((r) {
            final clear = r['kind'] == 'clear';
            final t = DateTime.parse(r['created_at']).toLocal();
            final lot = (r['lots'] as Map?)?['code'];
            return ListTile(
              leading: Icon(clear ? Icons.verified_outlined : Icons.report_problem_outlined,
                  color: clear ? Colors.green : Colors.orange),
              title: Text(clear ? 'Ronda sin novedad' : '${r['description']}'),
              subtitle: Text('${(r['profiles'] as Map?)?['full_name'] ?? ''} · '
                  '${t.day}/${t.month} ${t.hour}:${t.minute.toString().padLeft(2, '0')}'
                  '${lot != null ? ' · $lot' : ''}'),
            );
          }).toList(),
        );
      },
    );
  }
}

class _AccessLog extends StatelessWidget {
  const _AccessLog();
  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _db
          .from('access_logs')
          .select('created_at, direction, result, reason, dni, plate, lots(code)')
          .order('created_at', ascending: false)
          .limit(200),
      builder: (context, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        return ListView(
          children: snap.data!.map((r) {
            final ok = r['result'] == 'allowed';
            final t = DateTime.parse(r['created_at']).toLocal();
            return ListTile(
              leading: Icon(r['direction'] == 'in' ? Icons.login : Icons.logout, color: ok ? Colors.green : Colors.red),
              title: Text('${(r['lots'] as Map?)?['code'] ?? '—'}  ·  ${r['plate'] ?? r['dni'] ?? ''}'),
              subtitle: Text('${t.day}/${t.month} ${t.hour}:${t.minute.toString().padLeft(2, '0')}  ${r['reason'] ?? ''}'),
            );
          }).toList(),
        );
      },
    );
  }
}
