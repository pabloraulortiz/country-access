import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models.dart';
import '../push.dart';
import 'new_visit_screen.dart';

final _db = Supabase.instance.client;
final _fmt = DateFormat('dd/MM HH:mm');

class OwnerHome extends StatefulWidget {
  final Profile profile;
  const OwnerHome({super.key, required this.profile});
  @override
  State<OwnerHome> createState() => _OwnerHomeState();
}

class _OwnerHomeState extends State<OwnerHome> {
  int _tab = 0;
  List<Lot> _lots = [];

  @override
  void initState() {
    super.initState();
    _loadLots();
  }

  Future<void> _loadLots() async {
    final rows = await _db
        .from('lot_owners')
        .select('lots(id, code)')
        .eq('profile_id', widget.profile.id);
    setState(() => _lots = rows.map((r) => Lot.fromMap(r['lots'])).toList());
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      _LiveRequestsTab(lots: _lots),
      _VisitsTab(lots: _lots),
      _HistoryTab(lots: _lots),
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.profile.fullName),
        actions: [
          IconButton(icon: const Icon(Icons.logout), onPressed: () => Push.signOut()),
        ],
      ),
      body: pages[_tab],
      floatingActionButton: _tab == 1 && _lots.isNotEmpty
          ? FloatingActionButton.extended(
              icon: const Icon(Icons.add),
              label: const Text('Nueva visita'),
              onPressed: () async {
                await Navigator.push(context,
                    MaterialPageRoute(builder: (_) => NewVisitScreen(profile: widget.profile, lots: _lots)));
                setState(() {});
              },
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.notifications_active_outlined), label: 'Portería'),
          NavigationDestination(icon: Icon(Icons.qr_code_2), label: 'Visitas'),
          NavigationDestination(icon: Icon(Icons.history), label: 'Historial'),
        ],
      ),
    );
  }
}

// ---------- Autorizaciones en vivo ----------
class _LiveRequestsTab extends StatelessWidget {
  final List<Lot> lots;
  const _LiveRequestsTab({required this.lots});

  Future<void> _respond(String id, bool ok) async {
    await _db.from('live_requests').update({
      'status': ok ? 'authorized' : 'rejected',
      'responded_by': _db.auth.currentUser!.id,
      'responded_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', id).eq('status', 'pending');
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _db.from('live_requests').stream(primaryKey: ['id']).order('created_at', ascending: false).limit(30),
      builder: (context, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final lotIds = lots.map((l) => l.id).toSet();
        final items = snap.data!
            .map(LiveRequest.fromMap)
            .where((r) => lotIds.contains(r.lotId) && r.status == 'pending')
            .toList();
        if (items.isEmpty) return const Center(child: Text('Sin solicitudes pendientes'));
        return ListView(
          children: items
              .map((r) => Card(
                    margin: const EdgeInsets.all(12),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(r.visitorName, style: Theme.of(context).textTheme.titleLarge),
                        if (r.dni != null) Text('DNI: ${r.dni}'),
                        if (r.plate != null) Text('Patente: ${r.plate}'),
                        Text('Hace ${DateTime.now().difference(r.createdAt).inMinutes} min'),
                        const SizedBox(height: 12),
                        Row(children: [
                          Expanded(
                              child: FilledButton.icon(
                                  onPressed: () => _respond(r.id, true),
                                  icon: const Icon(Icons.check),
                                  label: const Text('Autorizar'))),
                          const SizedBox(width: 12),
                          Expanded(
                              child: OutlinedButton.icon(
                                  onPressed: () => _respond(r.id, false),
                                  icon: const Icon(Icons.close),
                                  label: const Text('Rechazar'))),
                        ]),
                      ]),
                    ),
                  ))
              .toList(),
        );
      },
    );
  }
}

// ---------- Visitas ----------
class _VisitsTab extends StatefulWidget {
  final List<Lot> lots;
  const _VisitsTab({required this.lots});
  @override
  State<_VisitsTab> createState() => _VisitsTabState();
}

class _VisitsTabState extends State<_VisitsTab> {
  Future<List<Visit>> _load() async {
    if (widget.lots.isEmpty) return [];
    final rows = await _db
        .from('visits')
        .select('*, visitors(full_name, dni, plate)')
        .inFilter('lot_id', widget.lots.map((l) => l.id).toList())
        .inFilter('status', ['authorized'])
        .order('created_at', ascending: false)
        .limit(100);
    return rows.map(Visit.fromMap).toList();
  }

  Future<void> _cancel(String id) async {
    await _db.from('visits').update({'status': 'cancelled'}).eq('id', id);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Visit>>(
      future: _load(),
      builder: (context, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final items = snap.data!;
        if (items.isEmpty) return const Center(child: Text('No hay visitas activas'));
        return RefreshIndicator(
          onRefresh: () async => setState(() {}),
          child: ListView(
            children: items
                .map((v) => ListTile(
                      leading: const Icon(Icons.person_outline),
                      title: Text(v.visitorName),
                      subtitle: Text('${_fmt.format(v.validFrom)} → ${_fmt.format(v.validTo)}  ·  ${v.uses}/${v.maxUses} usos'),
                      onTap: () => _showQr(context, v),
                      trailing: IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => _cancel(v.id)),
                    ))
                .toList(),
          ),
        );
      },
    );
  }

  void _showQr(BuildContext context, Visit v) {
    showModalBottomSheet(
      context: context,
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(v.visitorName, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          QrImageView(data: v.qrToken, size: 240),
          const SizedBox(height: 8),
          Text('Válido hasta ${_fmt.format(v.validTo)}'),
          const SizedBox(height: 12),
          FilledButton.icon(
            icon: const Icon(Icons.share),
            label: const Text('Compartir código'),
            onPressed: () => Share.share(
                'Código de acceso para ${v.visitorName}: ${v.qrToken}\nVálido hasta ${_fmt.format(v.validTo)}'),
          ),
        ]),
      ),
    );
  }
}

// ---------- Historial ----------
class _HistoryTab extends StatelessWidget {
  final List<Lot> lots;
  const _HistoryTab({required this.lots});

  @override
  Widget build(BuildContext context) {
    if (lots.isEmpty) return const SizedBox();
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _db
          .from('access_logs')
          .select('created_at, direction, result, reason, dni, plate, visitors(full_name)')
          .inFilter('lot_id', lots.map((l) => l.id).toList())
          .order('created_at', ascending: false)
          .limit(100),
      builder: (context, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        return ListView(
          children: snap.data!.map((r) {
            final ok = r['result'] == 'allowed';
            final name = (r['visitors'] as Map?)?['full_name'] ?? r['reason'] ?? r['dni'] ?? r['plate'] ?? '—';
            return ListTile(
              leading: Icon(r['direction'] == 'in' ? Icons.login : Icons.logout,
                  color: ok ? Colors.green : Colors.red),
              title: Text('$name'),
              subtitle: Text(_fmt.format(DateTime.parse(r['created_at']).toLocal()) +
                  (ok ? '' : '  ·  ${r['reason'] ?? 'denegado'}')),
            );
          }).toList(),
        );
      },
    );
  }
}
