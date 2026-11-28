import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'camera_qr.dart';

/// Board side: point this device at the QR code on the camera phone's screen.
/// Pops with the camera's addresses, or null when closed.
class CameraQrScanScreen extends StatefulWidget {
  const CameraQrScanScreen({super.key});

  @override
  State<CameraQrScanScreen> createState() => _CameraQrScanScreenState();
}

class _CameraQrScanScreenState extends State<CameraQrScanScreen> {
  final _ctrl = MobileScannerController(formats: const [BarcodeFormat.qrCode]);
  bool _done = false;
  String? _wrong;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_done) return;
    for (final b in capture.barcodes) {
      final hosts = CameraQr.hosts(b.rawValue);
      if (hosts != null) {
        _done = true;
        Navigator.of(context).pop(hosts);
        return;
      }
    }
    if (_wrong == null) setState(() => _wrong = 'Not a camera code — open camera mode on the phone');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(title: const Text('Scan the camera phone\'s QR')),
      body: Stack(
        children: [
          MobileScanner(
            controller: _ctrl,
            onDetect: _onDetect,
            errorBuilder: (context, error, child) => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Camera unavailable: ${error.errorCode.name}.\n'
                  'If board recording is on, it may be holding the camera.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70),
                ),
              ),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 24,
            child: Text(
              _wrong ?? 'On the camera phone: camera mode shows a QR code while the board is not linked.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 15, shadows: [Shadow(blurRadius: 6)]),
            ),
          ),
        ],
      ),
    );
  }
}
