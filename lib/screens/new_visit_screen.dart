import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models.dart';

final _db = Supabase.instance.client;

class NewVisitScreen extends StatefulWidget {
  final Profile profile;
  final List<Lot> lots;
  const NewVisitScreen({super.key, required this.profile, required this.lots});
  @override
  State<NewVisitScreen> createState() => _NewVisitScreenState();
}

class _NewVisitScreenState extends State<NewVisitScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _dni = TextEditingController();
  final _plate = TextEditingController();
  final _notes = TextEditingController();
  late String _lotId = widget.lots.first.id;
  String _type = 'single';
  DateTime _from = DateTime.now();
  DateTime _to = DateTime.now().add(const Duration(hours: 12));
  int _maxUses = 1;
  final Set<int> _weekdays = {};
  bool _frequent = false;
  bool _saving = false;

  Future<DateTime?> _pick(DateTime initial) async {
    final d = await showDatePicker(
        context: context, initialDate: initial, firstDate: DateTime.now().subtract(const Duration(days: 1)), lastDate: DateTime.now().add(const Duration(days: 365)));
    if (d == null || !mounted) return null;
    final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(initial));
    if (t == null) return null;
    return DateTime(d.year, d.month, d.day, t.hour, t.minute);
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    if (_to.isBefore(_from)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('La fecha final es anterior a la inicial')));
      return;
    }
    setState(() => _saving = true);
    try {
      final dni = _dni.text.trim().isEmpty ? null : _dni.text.trim();
      final plate = _plate.text.trim().isEmpty ? null : _plate.text.trim().toUpperCase().replaceAll(' ', '');

      // Reutiliza el visitante si ya existe por DNI
      String? visitorId;
      if (dni != null) {
        final ex = await _db
            .from('visitors')
            .select('id')
            .eq('country_id', widget.profile.countryId)
            .eq('dni', dni)
            .maybeSingle();
        visitorId = ex?['id'];
      }
      visitorId ??= (await _db
          .from('visitors')
          .insert({
            'country_id': widget.profile.countryId,
            'full_name': _name.text.trim(),
            'dni': dni,
            'plate': plate,
            'is_frequent': _frequent,
            'created_by': widget.profile.id,
          })
          .select('id')
          .single())['id'];

      await _db.from('visits').insert({
        'country_id': widget.profile.countryId,
        'lot_id': _lotId,
        'visitor_id': visitorId,
        'created_by': widget.profile.id,
        'type': _type,
        'valid_from': _from.toUtc().toIso8601String(),
        'valid_to': _to.toUtc().toIso8601String(),
        'max_uses': _type == 'single' ? 1 : _maxUses,
        if (_type == 'recurring') 'weekdays': _weekdays.toList()..sort(),
        'notes': _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      });
      if (mounted) Navigator.pop(context);
    } on PostgrestException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final f = DateFormat('dd/MM/yyyy HH:mm');
    return Scaffold(
      appBar: AppBar(title: const Text('Nueva visita')),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          if (widget.lots.length > 1)
            DropdownButtonFormField<String>(
              value: _lotId,
              decoration: const InputDecoration(labelText: 'Lote', border: OutlineInputBorder()),
              items: widget.lots.map((l) => DropdownMenuItem(value: l.id, child: Text(l.code))).toList(),
              onChanged: (v) => setState(() => _lotId = v!),
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
            controller: _dni,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'DNI (opcional)', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _plate,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(labelText: 'Patente (opcional)', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'single', label: Text('Única')),
              ButtonSegment(value: 'range', label: Text('Rango')),
              ButtonSegment(value: 'recurring', label: Text('Recurrente')),
              ButtonSegment(value: 'service', label: Text('Servicio')),
            ],
            selected: {_type},
            onSelectionChanged: (s) => setState(() => _type = s.first),
          ),
          const SizedBox(height: 12),
          ListTile(
            title: const Text('Desde'),
            subtitle: Text(f.format(_from)),
            trailing: const Icon(Icons.edit_calendar),
            onTap: () async {
              final d = await _pick(_from);
              if (d != null) setState(() => _from = d);
            },
          ),
          ListTile(
            title: const Text('Hasta'),
            subtitle: Text(f.format(_to)),
            trailing: const Icon(Icons.edit_calendar),
            onTap: () async {
              final d = await _pick(_to);
              if (d != null) setState(() => _to = d);
            },
          ),
          if (_type != 'single')
            Row(children: [
              const Text('Cantidad de usos'),
              const Spacer(),
              IconButton(icon: const Icon(Icons.remove), onPressed: () => setState(() => _maxUses = (_maxUses - 1).clamp(1, 999))),
              Text('$_maxUses'),
              IconButton(icon: const Icon(Icons.add), onPressed: () => setState(() => _maxUses = (_maxUses + 1).clamp(1, 999))),
            ]),
          if (_type == 'recurring')
            Wrap(
              spacing: 6,
              children: List.generate(7, (i) {
                const names = ['L', 'M', 'X', 'J', 'V', 'S', 'D'];
                final day = i + 1;
                return FilterChip(
                  label: Text(names[i]),
                  selected: _weekdays.contains(day),
                  onSelected: (s) => setState(() => s ? _weekdays.add(day) : _weekdays.remove(day)),
                );
              }),
            ),
          SwitchListTile(
            title: const Text('Invitado frecuente'),
            value: _frequent,
            onChanged: (v) => setState(() => _frequent = v),
          ),
          TextFormField(
            controller: _notes,
            decoration: const InputDecoration(labelText: 'Notas para la guardia', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving ? const CircularProgressIndicator() : const Text('Crear y generar QR'),
          ),
        ]),
      ),
    );
  }
}
