// ignore_for_file: library_private_types_in_public_api, use_build_context_synchronously, avoid_print

import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';
import 'ble.dart';
import 'dart:async';
import 'dart:typed_data';

class CameraColorPickerPage extends StatefulWidget {
  const CameraColorPickerPage({super.key});

  @override
  _CameraColorPickerPageState createState() => _CameraColorPickerPageState();
}

class _CameraColorPickerPageState extends State<CameraColorPickerPage>
    with WidgetsBindingObserver {
  CameraController? _controller;
  Future<void>? _initializeControllerFuture;
  Color _pickedColor = Colors.black;
  int _r = 0, _g = 0, _b = 0;
  DateTime _lastPickTime = DateTime.now();
  static const _minPickInterval = Duration(
    milliseconds: 500,
  ); // Throttle captures

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeCamera();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_controller == null || !_controller!.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      _controller?.pausePreview();
    } else if (state == AppLifecycleState.resumed) {
      _controller?.resumePreview();
    }
  }

  Future<void> _initializeCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isNotEmpty) {
        _controller = CameraController(
          cameras[0],
          ResolutionPreset.high,
          enableAudio: false,
        );
        _initializeControllerFuture = _controller!.initialize().then((_) {
          if (mounted) {
            setState(() {});
          }
        });
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('No camera found')));
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error initializing camera: $e')));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _pickColor() async {
    final now = DateTime.now();
    if (now.difference(_lastPickTime) < _minPickInterval) return; // Throttle
    _lastPickTime = now;

    if (_controller == null || !_controller!.value.isInitialized) return;

    try {
      final XFile imageFile = await _controller!.takePicture();
      final Uint8List bytes = await imageFile.readAsBytes();
      final img.Image? image = img.decodeImage(bytes);

      if (image != null) {
        final imageX = (image.width / 2).toInt();
        final imageY = (image.height / 2).toInt();
        final pixel = image.getPixelSafe(imageX, imageY);
        setState(() {
          _r = pixel.r.toInt();
          _g = pixel.g.toInt();
          _b = pixel.b.toInt();
          _pickedColor = Color.fromRGBO(_r, _g, _b, 1.0);
        });

        await _sendRGBToDevice();
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error picking color: $e')));
    }
  }

  Future<void> _sendRGBToDevice() async {
    // Check for black or white (or near)
    if ((_r == 0 && _g == 0 && _b == 0) ||
        (_r == 255 && _g == 255 && _b == 255)) {
      print('Color is black or white, not sending to BLE');
      return;
    }
    if ((_r <= 34 && _g <= 34 && _b <= 34) ||
        (_r >= 221 && _g >= 221 && _b >= 221)) {
      print('Color too dark or too bright, not sending to BLE');
      return;
    }

    // Create RGB data packet in the format: [0xD5, R, G, B, 0x5D]
    final List<int> rgbData = [0xD5, _r, _g, _b, 0x5D];

    // Send using BLEHelper
    await BLEHelper.send(rgbData);
    print('Camera sent RGB: $rgbData');
  }

  Future<void> _navigateToRGBPage() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('rgb_r', _r);
    await prefs.setInt('rgb_g', _g);
    await prefs.setInt('rgb_b', _b);
    print('Saved RGB to SharedPreferences: ($_r, $_g, $_b)'); // Debug print

    Navigator.pop(context, {'r': _r, 'g': _g, 'b': _b});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text(
          'Color Picker',
          style: TextStyle(color: Colors.white),
        ),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: FutureBuilder<void>(
          future: _initializeControllerFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.done) {
              if (_controller != null && _controller!.value.isInitialized) {
                return Column(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: _pickColor,
                        child: AspectRatio(
                          aspectRatio: _controller!.value.aspectRatio,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              CameraPreview(_controller!),
                              CustomPaint(
                                painter: CrosshairPainter(),
                                size: const Size(40, 40),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: _navigateToRGBPage,
                      child: Container(
                        height: 50,
                        color: _pickedColor,
                        child: Center(
                          child: Text(
                            'RGB: ($_r, $_g, $_b)',
                            style: TextStyle(
                              color: _pickedColor.computeLuminance() > 0.5
                                  ? Colors.black
                                  : Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              } else {
                return const Center(
                  child: Text(
                    'Camera not initialized',
                    style: TextStyle(color: Colors.white),
                  ),
                );
              }
            } else {
              return const Center(child: CircularProgressIndicator());
            }
          },
        ),
      ),
    );
  }
}

class CrosshairPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = 2;

    canvas.drawLine(
      Offset(0, size.height / 2),
      Offset(size.width, size.height / 2),
      paint,
    );

    canvas.drawLine(
      Offset(size.width / 2, 0),
      Offset(size.width / 2, size.height),
      paint,
    );

    final circlePaint = Paint()
      ..color = Colors.transparent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawCircle(Offset(size.width / 2, size.height / 2), 10, circlePaint);
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}
