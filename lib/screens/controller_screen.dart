// ignore_for_file: avoid_print, use_build_context_synchronously, constant_identifier_names
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_gauges/gauges.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'dart:math';
import 'dart:async';
import 'package:permission_handler/permission_handler.dart';
import '/screens/ble_utility.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class ControllerScreen extends StatefulWidget {
  final String deviceId;
  final String deviceName;
  final String roomName;
  final String macAddress;

  const ControllerScreen({
    super.key,
    required this.deviceId,
    required this.deviceName,
    required this.roomName,
    required this.macAddress,
  });

  @override
  State<ControllerScreen> createState() => _ControllerScreenState();
}

class _ControllerScreenState extends State<ControllerScreen>
    with SingleTickerProviderStateMixin {
  double _fanSpeed = 0.0;
  int _timerValue = 0;
  bool _isFanOn = false;
  bool _isLedOn = false;
  int _fanModeIndex = 0; // 0: Normal, 1: Speed, 2: Turbo
  final List<String> _fanModes = ['Normal', 'Speed', 'Boost'];
  Timer? _timer;
  int _timerRemaining = 0;

  BluetoothDevice? _device;
  BluetoothCharacteristic? _writeCharacteristic;
  BluetoothConnectionState _connectionState =
      BluetoothConnectionState.disconnected;

  // BLE command codes
  static const int FANON = 0x0E;
  static const int FANOFF = 0x06;
  static const int GEAR1 = 0x05;
  static const int GEAR2 = 0x0F;
  static const int GEAR3 = 0x0A;
  static const int GEAR4 = 0x03;
  static const int GEAR5 = 0x02;
  static const int GEAR6 = 0x1A;
  static const int GEAR7 = 0x0C;
  static const int R5M = 0x1F;
  static const int R30M = 0xDD;
  static const int R1H = 0x10;
  static const int R2H = 0x0D;
  static const int R4H = 0x01;
  static const int R6H = 0x09;
  static const int R8H = 0x07;

  @override
  void initState() {
    super.initState();
    _connectToDevice();
    _requestPermissions();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _connectToDevice() async {
    try {
      final device = BluetoothDevice.fromId(widget.deviceId);
      setState(() {
        _device = device;
      });

      BLEUtility.connectedDevice = device;

      // Force enable the device in SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      List<String> savedDevices = prefs.getStringList('saved_devices') ?? [];
      for (int i = 0; i < savedDevices.length; i++) {
        final dev = jsonDecode(savedDevices[i]);
        if (dev['id'] == device.remoteId.toString()) {
          dev['enabled'] = true;
          savedDevices[i] = jsonEncode(dev);
        }
      }
      await prefs.setStringList('saved_devices', savedDevices);

      device.connectionState.listen((state) {
        setState(() {
          _connectionState = state;
        });
        if (state == BluetoothConnectionState.connected) {
          BLEUtility.connectedDevice = device;
        } else {
          BLEUtility.connectedDevice = null;
        }
      });

      if (_connectionState != BluetoothConnectionState.connected) {
        await device.connect(autoConnect: false);
      }

      List<BluetoothService> services = await device.discoverServices();
      _writeCharacteristic = services
          .expand((service) => service.characteristics)
          .firstWhere(
            (c) => c.properties.write,
            orElse: () => throw Exception('No writable characteristic found'),
          );
    } catch (e) {
      print('Bluetooth connection error: $e');
    }
  }

  Future<void> _requestPermissions() async {
    if (Platform.isAndroid) {
      await Permission.bluetoothScan.request();
      await Permission.bluetoothConnect.request();
      await Permission.bluetooth.request();
      await Permission.bluetoothAdvertise.request();
      await Permission.locationWhenInUse.request();
      await Permission.location.request();
    } else if (Platform.isIOS) {
      await Permission.locationWhenInUse.request();
    }
  }

  void _startTimer(int minutes, int code) {
    _timer?.cancel();
    setState(() {
      _timerValue = minutes;
      _timerRemaining = minutes * 60;
    });
    if (minutes > 0) {
      // Send as string code (hex, uppercase, 2 chars)
      BLEUtility.sendDataToDevice(
        code.toRadixString(16).padLeft(2, '0').toUpperCase(),
      );
      _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (_timerRemaining > 0) {
          setState(() {
            _timerRemaining--;
          });
        } else {
          timer.cancel();
          setState(() {
            _timerValue = 0;
            _timerRemaining = 0;
          });
        }
      });
    }
  }

  void _clearTimer() {
    _timer?.cancel();
    setState(() {
      _timerValue = 0;
      _timerRemaining = 0;
    });
  }

  String _formatTimer(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    if (m > 0) {
      return '$m:${s.toString().padLeft(2, '0')}';
    } else {
      return '$s s';
    }
  }

  Widget _buildFanGraphic(ColorScheme colorScheme) {
    return _RotatingFan(
      fanPainter: _FanPainter(
        color: colorScheme.onSurface,
        centerColor: _isLedOn
            ? Colors.yellow
            : colorScheme.surfaceContainerHighest,
      ),
      speedLevel: _isFanOn ? _fanSpeed : 0,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final mediaQuery = MediaQuery.of(context);
    _requestPermissions();

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        backgroundColor: colorScheme.surface,
        elevation: 0,
        title: Text(
          widget.deviceName,
          style: textTheme.titleLarge?.copyWith(
            color: colorScheme.onSurface,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(
              _connectionState == BluetoothConnectionState.connected
                  ? Icons.bluetooth_connected
                  : Icons.bluetooth_disabled,
              color: _connectionState == BluetoothConnectionState.connected
                  ? Colors.blue
                  : colorScheme.error,
              size: 28,
            ),
            onPressed: () {
              showModalBottomSheet(
                context: context,
                builder: (context) => SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _connectionState == BluetoothConnectionState.connected
                              ? Icons.bluetooth_connected
                              : Icons.bluetooth_disabled,
                          color:
                              _connectionState ==
                                  BluetoothConnectionState.connected
                              ? Colors.blue
                              : colorScheme.error,
                          size: 48,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _connectionState == BluetoothConnectionState.connected
                              ? 'Connected'
                              : 'Disconnected',
                          style: textTheme.titleMedium?.copyWith(
                            color:
                                _connectionState ==
                                    BluetoothConnectionState.connected
                                ? Colors.blue
                                : colorScheme.error,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Device: ${widget.deviceName}',
                          style: textTheme.bodyLarge,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Device ID: ${widget.deviceId}',
                          style: textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurface.withOpacity(0.6),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
            tooltip: 'Bluetooth Status',
          ),
        ],
      ),
      body: SafeArea(
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            SingleChildScrollView(
              child: Column(
                children: [
                  Container(
                    width: double.infinity,
                    padding: EdgeInsets.symmetric(
                      vertical: mediaQuery.size.height * 0.03,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.primary.withOpacity(0.1),
                      borderRadius: const BorderRadius.only(
                        bottomLeft: Radius.circular(16),
                        bottomRight: Radius.circular(16),
                      ),
                    ),
                    child: Stack(
                      children: [
                        Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(height: mediaQuery.size.height * 0.02),
                            Center(
                              child: SizedBox(
                                height: mediaQuery.size.height * 0.15,
                                child: _buildFanGraphic(colorScheme),
                              ),
                            ),
                            SizedBox(height: mediaQuery.size.height * 0.02),
                            Text(
                              'Bluetooth is required to control.',
                              style: textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurface.withOpacity(0.7),
                              ),
                            ),
                            SizedBox(height: mediaQuery.size.height * 0.04),
                          ],
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: mediaQuery.size.height * 0.06),
                  // Mode selector
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child: ToggleButtons(
                      borderRadius: BorderRadius.circular(12),
                      isSelected: List.generate(3, (i) => i == _fanModeIndex),
                      onPressed: (index) {
                        setState(() {
                          _fanModeIndex = index;
                          if (_fanModeIndex == 1) {
                            _fanSpeed = 6;
                          } else if (_fanModeIndex == 2) {
                            _fanSpeed = 7;
                          }
                          if (_fanSpeed == 6) {
                            _fanModeIndex = 1;
                          } else if (_fanSpeed == 7) {
                            _fanModeIndex = 2;
                          }
                        });
                        // Send speed command as string hex
                        if (_fanSpeed == 6) {
                          BLEUtility.sendDataToDevice('1A');
                        } else if (_fanSpeed == 7) {
                          BLEUtility.sendDataToDevice('0C');
                        } else {
                          BLEUtility.sendDataToDevice('05');
                        }
                      },
                      selectedColor: colorScheme.onPrimary,
                      fillColor: colorScheme.primary,
                      color: colorScheme.onSurface,
                      children: _fanModes
                          .map(
                            (mode) => Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16.0,
                              ),
                              child: Text(mode),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                  // Speed Dial
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16.0),
                    child: Container(
                      width: mediaQuery.size.width * 0.45,
                      height: mediaQuery.size.width * 0.45,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: colorScheme.surfaceContainerHighest.withOpacity(
                          0.2,
                        ),
                        border: Border.all(
                          color: colorScheme.primary.withOpacity(0.4),
                          width: 4,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: colorScheme.primary.withOpacity(0.08),
                            blurRadius: 12,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: Center(
                        child: SfRadialGauge(
                          axes: <RadialAxis>[
                            RadialAxis(
                              minimum: 1,
                              maximum: 7,
                              interval: 1,
                              showLabels: false,
                              showTicks: false,
                              axisLineStyle: AxisLineStyle(
                                thickness: 0.2,
                                thicknessUnit: GaugeSizeUnit.factor,
                                color: colorScheme.primary.withOpacity(0.15),
                              ),
                              pointers: <GaugePointer>[
                                RangePointer(
                                  value: _fanSpeed,
                                  color: colorScheme.primary,
                                  width: 0.2,
                                  sizeUnit: GaugeSizeUnit.factor,
                                ),
                                MarkerPointer(
                                  value: _fanSpeed,
                                  markerType: MarkerType.circle,
                                  color: colorScheme.primary,
                                  markerHeight: 30,
                                  markerWidth: 30,
                                  enableDragging: true,
                                  onValueChanged: (value) {
                                    final snapped = value
                                        .round()
                                        .clamp(1, 7)
                                        .toDouble();
                                    setState(() {
                                      _fanSpeed = snapped;
                                      if (_fanSpeed == 6) {
                                        _fanModeIndex = 1;
                                      } else if (_fanSpeed == 7) {
                                        _fanModeIndex = 2;
                                      } else if (_fanSpeed < 6) {
                                        _fanModeIndex = 0;
                                      }
                                    });
                                  },
                                  onValueChangeEnd: (value) {
                                    final snapped = value.round().clamp(1, 7);
                                    setState(() {
                                      _fanSpeed = snapped.toDouble();
                                    });
                                    // Send speed command as string hex
                                    switch (snapped) {
                                      case 1:
                                        BLEUtility.sendDataToDevice('05');
                                        break;
                                      case 2:
                                        BLEUtility.sendDataToDevice('0F');
                                        break;
                                      case 3:
                                        BLEUtility.sendDataToDevice('0A');
                                        break;
                                      case 4:
                                        BLEUtility.sendDataToDevice('03');
                                        break;
                                      case 5:
                                        BLEUtility.sendDataToDevice('02');
                                        break;
                                      case 6:
                                        BLEUtility.sendDataToDevice('1A');
                                        break;
                                      case 7:
                                        BLEUtility.sendDataToDevice('0C');
                                        break;
                                    }
                                  },
                                ),
                              ],
                              annotations: <GaugeAnnotation>[
                                GaugeAnnotation(
                                  widget: Text(
                                    '${_fanSpeed.toInt()}',
                                    style: textTheme.displaySmall?.copyWith(
                                      color: colorScheme.onSurface,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  positionFactor: 0.1,
                                  angle: 90,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  // Timer label and buttons
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24.0,
                      vertical: 8,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              'Timer',
                              style: textTheme.titleMedium?.copyWith(
                                color: colorScheme.onSurface,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(width: 12),
                            if (_timerValue > 0)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: colorScheme.primary.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  children: [
                                    Text(
                                      _timerValue < 60
                                          ? '$_timerValue min'
                                          : '${(_timerValue / 60).toStringAsFixed(_timerValue % 60 == 0 ? 0 : 1)} hr',
                                      style: textTheme.bodyMedium?.copyWith(
                                        color: colorScheme.primary,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    if (_timerRemaining > 0) ...[
                                      const SizedBox(width: 8),
                                      Text(
                                        _formatTimer(_timerRemaining),
                                        style: textTheme.bodyMedium?.copyWith(
                                          color: colorScheme.primary,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            if (_timerValue > 0)
                              IconButton(
                                icon: Icon(
                                  Icons.clear,
                                  color: colorScheme.error,
                                ),
                                tooltip: 'Clear Timer',
                                onPressed: _clearTimer,
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              _TimerButton(
                                label: '5m',
                                selected: _timerValue == 5,
                                onTap: () => _startTimer(5, 0x1F),
                                colorScheme: colorScheme,
                                textTheme: textTheme,
                              ),
                              const SizedBox(width: 8),
                              _TimerButton(
                                label: '30m',
                                selected: _timerValue == 30,
                                onTap: () => _startTimer(30, 0xDD),
                                colorScheme: colorScheme,
                                textTheme: textTheme,
                              ),
                              const SizedBox(width: 8),
                              _TimerButton(
                                label: '1h',
                                selected: _timerValue == 60,
                                onTap: () => _startTimer(60, 0x10),
                                colorScheme: colorScheme,
                                textTheme: textTheme,
                              ),
                              const SizedBox(width: 8),
                              _TimerButton(
                                label: '2h',
                                selected: _timerValue == 120,
                                onTap: () => _startTimer(120, 0x0D),
                                colorScheme: colorScheme,
                                textTheme: textTheme,
                              ),
                              const SizedBox(width: 8),
                              _TimerButton(
                                label: '4h',
                                selected: _timerValue == 240,
                                onTap: () => _startTimer(240, 0x01),
                                colorScheme: colorScheme,
                                textTheme: textTheme,
                              ),
                              const SizedBox(width: 8),
                              _TimerButton(
                                label: '6h',
                                selected: _timerValue == 360,
                                onTap: () => _startTimer(360, 0x09),
                                colorScheme: colorScheme,
                                textTheme: textTheme,
                              ),
                              const SizedBox(width: 8),
                              _TimerButton(
                                label: '8h',
                                selected: _timerValue == 480,
                                onTap: () => _startTimer(480, 0x07),
                                colorScheme: colorScheme,
                                textTheme: textTheme,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // Floating Power Button (overlapping container and body)
            Positioned(
              top: mediaQuery.size.height * 0.28,
              left: mediaQuery.size.width / 2 - 64,
              child: GestureDetector(
                child: Container(
                  width: 128,
                  height: 64,
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(32),
                    boxShadow: [
                      BoxShadow(
                        color: colorScheme.primary.withOpacity(0.15),
                        blurRadius: 8,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      // Fan Section
                      Expanded(
                        child: GestureDetector(
                          onTap: () async {
                            final newState = !_isFanOn;
                            setState(() {
                              _isFanOn = newState;
                            });
                            BLEUtility.sendDataToDevice(newState ? '0E' : '06');
                          },
                          child: Container(
                            decoration: BoxDecoration(
                              color: _isFanOn
                                  ? colorScheme.primary
                                  : Colors.transparent,
                              borderRadius: const BorderRadius.only(
                                topLeft: Radius.circular(32),
                                bottomLeft: Radius.circular(32),
                              ),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.air,
                                  color: _isFanOn
                                      ? colorScheme.onPrimary
                                      : colorScheme.onSurface.withOpacity(0.5),
                                  size: 28,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _isFanOn ? "Fan On" : "Fan Off",
                                  style: TextStyle(
                                    color: _isFanOn
                                        ? colorScheme.onPrimary
                                        : colorScheme.onSurface.withOpacity(
                                            0.7,
                                          ),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      // Separator
                      Container(
                        width: 1,
                        height: 40,
                        color: colorScheme.outline.withOpacity(0.3),
                        margin: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      // Light Section
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            setState(() {
                              _isLedOn = !_isLedOn;
                            });
                          },
                          child: Container(
                            decoration: BoxDecoration(
                              color: _isLedOn
                                  ? const Color.fromARGB(255, 255, 235, 59)
                                  : Colors.transparent,
                              borderRadius: const BorderRadius.only(
                                topRight: Radius.circular(32),
                                bottomRight: Radius.circular(32),
                              ),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.lightbulb,
                                  color: _isLedOn
                                      ? colorScheme.onPrimary
                                      : colorScheme.onSurface.withOpacity(0.5),
                                  size: 28,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _isLedOn ? "Light On" : "Light Off",
                                  style: TextStyle(
                                    color: _isLedOn
                                        ? colorScheme.onPrimary
                                        : colorScheme.onSurface.withOpacity(
                                            0.7,
                                          ),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Custom widget for rotating fan, used when fan is powered on.
class _RotatingFan extends StatefulWidget {
  final _FanPainter fanPainter;
  final double speedLevel;
  const _RotatingFan({required this.fanPainter, required this.speedLevel});

  @override
  State<_RotatingFan> createState() => _RotatingFanState();
}

class _RotatingFanState extends State<_RotatingFan>
    with SingleTickerProviderStateMixin {
  late AnimationController _rotController;

  @override
  void initState() {
    super.initState();
    _rotController = AnimationController(
      vsync: this,
      duration: _durationForSpeed(widget.speedLevel),
    );
    if (widget.speedLevel > 0) {
      _rotController.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant _RotatingFan oldWidget) {
    super.didUpdateWidget(oldWidget);
    final newDuration = _durationForSpeed(widget.speedLevel);

    if (_rotController.duration != newDuration) {
      final value = _rotController.value;
      _rotController.duration = newDuration;
      if (widget.speedLevel > 0) {
        _rotController.repeat();
        _rotController.value = value;
      }
    }
    if (widget.speedLevel > 0) {
      if (!_rotController.isAnimating) {
        _rotController.repeat();
      }
    } else {
      _rotController.stop();
    }
  }

  @override
  void dispose() {
    _rotController.dispose();
    super.dispose();
  }

  Duration _durationForSpeed(double speed) {
    final minDuration = 0.4;
    final maxDuration = 2.0;
    double t = ((speed.clamp(1, 7)) - 1) / 6;
    double seconds = maxDuration - (maxDuration - minDuration) * t;
    return Duration(milliseconds: (seconds * 1000).toInt());
  }

  @override
  Widget build(BuildContext context) {
    return RotationTransition(
      turns: _rotController,
      child: CustomPaint(
        painter: widget.fanPainter,
        child: const SizedBox(width: 120, height: 120),
      ),
    );
  }
}

class _FanPainter extends CustomPainter {
  final Color color;
  final Color centerColor;
  _FanPainter({required this.color, required this.centerColor});

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
      path.moveTo(center.dx, center.dy);
      path.cubicTo(
        center.dx + bladeCurve * cos(angle - 0.3),
        center.dy + bladeCurve * sin(angle - 0.3),
        center.dx + bladeWidth * cos(angle - 0.18),
        center.dy + bladeWidth * sin(angle - 0.18),
        center.dx + bladeLength * cos(angle),
        center.dy + bladeLength * sin(angle),
      );
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
    canvas.drawCircle(
      center,
      size.width * 0.13,
      Paint()..color = const Color.fromARGB(255, 238, 235, 59),
    );
    canvas.drawCircle(center, size.width * 0.09, Paint()..color = centerColor);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _TimerButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final ColorScheme colorScheme;
  final TextTheme textTheme;
  const _TimerButton({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.colorScheme,
    required this.textTheme,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? colorScheme.primary
              : colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: textTheme.bodyMedium?.copyWith(
            color: selected ? colorScheme.onPrimary : colorScheme.onSurface,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}
