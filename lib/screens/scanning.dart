import 'dart:io';
import 'dart:math';
import 'package:bldcfan/screens/home_page.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:location/location.dart'; // Add this import at the top
import 'package:shared_preferences/shared_preferences.dart';

class BLEScanScreen extends StatefulWidget {
  final bool isDarkMode;
  const BLEScanScreen({super.key, required this.isDarkMode});

  @override
  State<BLEScanScreen> createState() => _BLEScanScreenState();
}

class _BLEScanScreenState extends State<BLEScanScreen> {
  List<ScanResult> scanResults = [];
  bool isScanning = false;
  final Map<String, String> deviceRooms = {};
  int _searchTapCount = 0; // Add this line
  // Add this line
  late SharedPreferences _prefs;

  @override
  void initState() {
    super.initState();
    _initSharedPreferences().then((_) async {
      await _requestPermissions(); // Request permissions before initializing Bluetooth
      _initBluetooth();
    });
  }

  Future<void> _initSharedPreferences() async {
    _prefs = await SharedPreferences.getInstance();
    final keys = _prefs.getKeys();
    for (var key in keys) {
      if (key.startsWith('device_')) {
        deviceRooms[key.replaceFirst('device_', '')] =
            _prefs.getString(key) ?? 'Default';
      }
    }
  }

  Future<void> _saveDeviceRoom(String deviceId, String room) async {
    setState(() {
      deviceRooms[deviceId] = room;
    });
    await _prefs.setString('device_$deviceId', room);

    // Save the device name for display on the home page
    final deviceName = scanResults
        .firstWhere((result) => result.device.remoteId.toString() == deviceId)
        .device
        .platformName;
    await _prefs.setString('device_name_$deviceId', deviceName);
  }

  Future<void> _initBluetooth() async {
    if (await FlutterBluePlus.isSupported == false) {
      return;
    }

    if (!kIsWeb && Platform.isAndroid) {
      await _requestPermissions();
    }

    FlutterBluePlus.adapterState.listen((state) {
      if (state == BluetoothAdapterState.on) {
        _startScan();
      } else {
        setState(() => isScanning = false);
      }
    });

    if (await FlutterBluePlus.adapterState.first == BluetoothAdapterState.on) {
      _startScan();
    } else if (!kIsWeb && Platform.isAndroid) {
      await FlutterBluePlus.turnOn();
    }
  }

  Future<void> _requestPermissions() async {
    if (Platform.isAndroid) {
      // Android 12+ permissions
      await Permission.bluetoothScan.request();
      await Permission.bluetoothConnect.request();
      await Permission.bluetooth.request();
      await Permission.bluetoothAdvertise.request();

      // Location permissions (required for BLE scanning on Android <12 and recommended for all)
      await Permission.locationWhenInUse.request();
      await Permission.location.request();
    } else if (Platform.isIOS) {
      // iOS location permission for BLE
      await Permission.locationWhenInUse.request();
    }
  }

  void _startScan() async {
    if (Platform.isAndroid) {
      // Check location permission
      if (await Permission.bluetoothScan.isDenied ||
          await Permission.bluetoothConnect.isDenied ||
          await Permission.locationWhenInUse.isDenied) {
        await _requestPermissions();
        if (await Permission.bluetoothScan.isDenied) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Bluetooth scan permission required!'),
              ),
            );
          }
          return;
        }
      }

      // Check if location is enabled (Android only)
      Location location = Location();
      bool serviceEnabled = await location.serviceEnabled();
      if (!serviceEnabled) {
        serviceEnabled = await location.requestService();
        if (!serviceEnabled) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Location service is required for BLE scanning. Please enable location.',
                ),
              ),
            );
          }
          return;
        }
      }
    }

    setState(() {
      scanResults.clear();
      isScanning = true;
    });

    var subscription = FlutterBluePlus.onScanResults.listen((results) {
      if (results.isNotEmpty) {
        setState(() {
          for (var result in results) {
            if (!scanResults.any(
              (r) => r.device.remoteId == result.device.remoteId,
            )) {
              scanResults.add(result);
            }
          }
        });
      }
    });

    FlutterBluePlus.cancelWhenScanComplete(subscription);
    FlutterBluePlus.startScan(timeout: const Duration(seconds: 15));

    FlutterBluePlus.isScanning.where((val) => val == false).first.then((_) {
      if (mounted) setState(() => isScanning = false);
    });
  }

  Future<void> _connectToDevice(BluetoothDevice device) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return Center(
          child: SizedBox(width: 100, height: 100, child: _RotatingFan()),
        );
      },
    );

    try {
      // Connect to device
      await device.connect(
        //timeout: const Duration(seconds: 10),
        autoConnect: false,
      );

      // Discover services

      // Show room assignment dialog
      await _showRoomAssignmentDialog(device);

      // Save the connected device MAC address
      await _prefs.setString('last_connected_mac', device.remoteId.toString());

      // Navigate to controller screen (MyHomePage)
      if (mounted) {
        Navigator.pop(context); // Dismiss loading dialog
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => MyHomePage(
              title: 'BLDC Fan',
              toggleTheme: () {}, // Provide your toggleTheme callback if needed
              isDarkMode: widget.isDarkMode,
            ),
          ),
        );
      }
    } catch (e) {
      // ignore: use_build_context_synchronously
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Connection failed: ${e.toString()}')),
      );
      // ignore: use_build_context_synchronously
      Navigator.pop(context); // Dismiss loading dialog on error
    }
  }

  Future<void> _showRoomAssignmentDialog(BluetoothDevice device) async {
    String selectedRoom = '';
    final TextEditingController roomController = TextEditingController();

    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Assign ${device.platformName} to Room'),
          content: TextField(
            controller: roomController,
            decoration: const InputDecoration(
              labelText: 'Enter room name',
              hintText: 'e.g. Living Room',
            ),
            onChanged: (value) => selectedRoom = value,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                final roomToSave = (selectedRoom.trim().isEmpty)
                    ? 'Default'
                    : selectedRoom.trim();
                await _saveDeviceRoom(device.remoteId.toString(), roomToSave);
                // ignore: use_build_context_synchronously
                if (mounted) Navigator.pop(context);
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Filter devices whose name contains 'simpex' or 'ventum' (case-insensitive)
    final filteredResults = scanResults.where((result) {
      final name = result.device.platformName.toLowerCase();
      return name.contains('ventum') || name.contains('simpex');
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Searching for Fans'),
        backgroundColor: theme.colorScheme.primary,
      ),
      body: filteredResults.isEmpty
          ? Center(
              child: isScanning
                  ? Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(width: 80, height: 80, child: _RotatingFan()),
                        const SizedBox(height: 16),
                        const Text(
                          'Searching for fans...',
                          style: TextStyle(fontSize: 18),
                        ),
                      ],
                    )
                  : const Text(
                      'No fans found.\nTap the search button to try again.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 16),
                    ),
            )
          : ListView.builder(
              itemCount: filteredResults.length,
              itemBuilder: (context, index) {
                final result = filteredResults[index];
                final deviceName = result.device.platformName.isEmpty
                    ? 'Unknown Device'
                    : result.device.platformName;
                final roomName = deviceRooms[result.device.remoteId.toString()];

                return Card(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  color: theme.colorScheme.surface,
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Device Info
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                deviceName,
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: theme.colorScheme.onSurface,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                result.device.remoteId.toString(),
                                style: TextStyle(
                                  color: theme.colorScheme.onSurface.withValues(
                                    alpha: 0.6,
                                  ),
                                ),
                              ),
                              if (roomName != null)
                                Text(
                                  'Room: $roomName',
                                  style: TextStyle(
                                    color: theme.colorScheme.secondary,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        // Connect Button
                        ElevatedButton(
                          onPressed: () => _connectToDevice(result.device),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: theme.colorScheme.primary,
                          ),
                          child: const Text(
                            'Connect',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: isScanning
            ? null
            : () {
                _searchTapCount++;
                if (_searchTapCount >= 10) {
                  setState(() {});
                }
                _startScan();
              },
        backgroundColor: theme.colorScheme.secondary,
        child: const Icon(Icons.search, color: Colors.white),
      ),
    );
  }

  @override
  void dispose() {
    if (isScanning) FlutterBluePlus.stopScan();
    super.dispose();
  }
}

class _RotatingFan extends StatefulWidget {
  @override
  State<_RotatingFan> createState() => _RotatingFanState();
}

class _RotatingFanState extends State<_RotatingFan>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RotationTransition(
      turns: _controller,
      child: CustomPaint(
        painter: _FanPainter(color: Theme.of(context).colorScheme.primary),
        child: const SizedBox(width: 80, height: 80),
      ),
    );
  }
}

class _FanPainter extends CustomPainter {
  final Color color;
  _FanPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final bladeLength = size.width * 0.45;
    final bladeWidth = size.width * 0.10;
    final bladeCurve = size.width * 0.18;

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    for (int i = 0; i < 3; i++) {
      final angle = i * 2 * pi / 3;
      final path = Path();
      // Start at center to create a gap
      path.moveTo(center.dx, center.dy);
      // Draw one side of the blade with a curve
      path.cubicTo(
        center.dx + bladeCurve * cos(angle - 0.3),
        center.dy + bladeCurve * sin(angle - 0.3),
        center.dx + bladeWidth * cos(angle - 0.18),
        center.dy + bladeWidth * sin(angle - 0.18),
        center.dx + bladeLength * cos(angle),
        center.dy + bladeLength * sin(angle),
      );
      // Draw the other side of the blade with a curve back to center
      path.cubicTo(
        center.dx + bladeWidth * cos(angle + 0.18),
        center.dy + bladeWidth * sin(angle + 0.18),
        center.dx + bladeCurve * cos(angle + 0.3),
        center.dy + bladeCurve * sin(angle + 0.3),
        center.dx,
        center.dy,
      );
      path.close();
      canvas.drawPath(path, paint);
    }

    // Draw center circle
    canvas.drawCircle(center, size.width * 0.13, Paint()..color = Colors.white);
    canvas.drawCircle(center, size.width * 0.09, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
