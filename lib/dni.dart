import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class DniData {
  final String dni;
  final String? apellido;
  final String? nombre;
  DniData(this.dni, {this.apellido, this.nombre});
  String get fullName => [nombre, apellido].where((s) => s != null && s.isNotEmpty).join(' ');
}

String _title(String s) => s
    .toLowerCase()
    .split(' ')
    .where((w) => w.isNotEmpty)
    .map((w) => w[0].toUpperCase() + w.substring(1))
    .join(' ');

/// El DNI argentino trae un PDF417 con campos separados por "@":
/// trámite@APELLIDO@NOMBRE@SEXO@NÚMERO@EJEMPLAR@NACIMIENTO@EMISIÓN@...
/// Se busca el patrón SEXO (M/F/X) seguido de 7-8 dígitos; los dos campos anteriores son apellido y nombre.
DniData? parseDni(String raw) {
  final parts = raw.split('@').map((s) => s.trim()).toList();
  for (var i = 2; i + 1 < parts.length; i++) {
    if (RegExp(r'^[MFX]$').hasMatch(parts[i]) && RegExp(r'^\d{7,8}$').hasMatch(parts[i + 1])) {
      return DniData(parts[i + 1], apellido: _title(parts[i - 2]), nombre: _title(parts[i - 1]));
    }
  }
  return null;
}

/// Pantalla que lee el código de barras del DNI y devuelve un [DniData].
class DniScannerScreen extends StatefulWidget {
  const DniScannerScreen({super.key});
  @override
  State<DniScannerScreen> createState() => _DniScannerScreenState();
}

class _DniScannerScreenState extends State<DniScannerScreen> {
  final _c = MobileScannerController(
    formats: const [BarcodeFormat.pdf417],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  bool _done = false;
  String? _msg;

  void _onDetect(BarcodeCapture cap) {
    if (_done) return;
    for (final b in cap.barcodes) {
      final raw = b.rawValue;
      if (raw == null) continue;
      final d = parseDni(raw);
      if (d != null) {
        _done = true;
        Navigator.pop(context, d);
        return;
      }
      setState(() => _msg = 'Ese código no es un DNI reconocible. Cargalo a mano.');
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Escanear DNI (código de atrás)')),
      body: Stack(children: [
        MobileScanner(controller: _c, onDetect: _onDetect),
        if (_msg != null)
          Positioned(
            left: 16,
            right: 16,
            bottom: 24,
            child: Card(child: Padding(padding: const EdgeInsets.all(12), child: Text(_msg!))),
          ),
      ]),
    );
  }
}
