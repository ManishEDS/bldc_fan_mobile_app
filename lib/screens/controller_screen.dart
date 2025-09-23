// ignore_for_file: avoid_print, use_build_context_synchronously, constant_identifier_names, unused_field, deprecated_member_use
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
import 'ble.dart';
import 'package:flutter_circle_color_picker/flutter_circle_color_picker.dart';
import 'camera_color_picker.dart';

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
  int _fanModeIndex = 0;
  final List<String> _fanModes = ['Normal', 'Speed', 'Boost'];
  Timer? _timer;
  int _timerRemaining = 0;
  Timer? _debounceTimer;

  BluetoothDevice? _device;
  BluetoothCharacteristic? _writeCharacteristic;
  BluetoothConnectionState _connectionState =
      BluetoothConnectionState.disconnected;

  Color _lightColor = Colors.yellowAccent;
  double _lightCct = 6500.0;

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
    _debounceTimer?.cancel();
    super.dispose();
  }

  Future<void> _connectToDevice() async {
    try {
      final device = BluetoothDevice.fromId(widget.deviceId);
      setState(() {
        _device = device;
      });

      BLEUtility.connectedDevice = device;

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
      for (final service in services) {
        print('Service: ${service.uuid}');
        for (final c in service.characteristics) {
          print('Characteristic: ${c.uuid} props: ${c.properties}');
        }
      }
      _writeCharacteristic = services
          .expand((service) => service.characteristics)
          .firstWhere(
            (c) =>
                c.uuid.toString().toLowerCase() ==
                    'd973f2e1-b19e-11e2-9e96-0800200c9a66' ||
                c.uuid.toString().toLowerCase() ==
                    'd973f2e2-b19e-11e2-9e96-0800200c9a66',
            orElse: () =>
                throw Exception('No correct writable characteristic found'),
          );
      BLEHelper.setWriteCharacteristic(_writeCharacteristic!);
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
      BLEHelper.send([code]);
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
            ? _lightColor
            : colorScheme.surfaceContainerHighest,
      ),
      speedLevel: _isFanOn ? _fanSpeed : 0,
    );
  }

  Future<void> _saveLastFanSpeed(double speed) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('last_fan_speed', speed);
  }

  Future<double> _getLastFanSpeed() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble('last_fan_speed') ?? 5.0;
  }

  void _sendLightColor(Color color) {
    List<int> colorBytes = [color.red, color.green, color.blue];
    final packet = <int>[0xD5, ...colorBytes, 0x5D];
    BLEHelper.send(packet);
    print(
      'Sent color: R=${color.red}, G=${color.green}, B=${color.blue} (Hex: ${packet.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')})',
    );
  }

  void _sendLightCct() {
    final cct = _lightCct.toInt().clamp(2500, 6500);
    final highByte = (cct >> 8) & 0xFF;
    final lowByte = cct & 0xFF;
    final packet = <int>[0xD6, highByte, lowByte, 0x5D];
    BLEHelper.send(packet);
    print(
      'Sent CCT: ${cct}K (Hex: ${packet.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')})',
    );
  }

  void _showLightSettings() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (BuildContext context, StateSetter setModalState) {
          Color localColor = _lightColor;
          double localCct = _lightCct;
          final controller = CircleColorPickerController(
            initialColor: localColor,
          );
          String hexColor = localColor.value
              .toRadixString(16)
              .padLeft(8, '0')
              .substring(2, 8)
              .toUpperCase();

          return Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(20),
              ),
            ),
            child: SafeArea(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.75,
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 16.0),
                          child: Text(
                            'Light Color & Temperature',
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurface,
                                ),
                          ),
                        ),
                      ),
                      // Color Section
                      Text(
                        'Color',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 12),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final dialogWidth = constraints.maxWidth.clamp(
                            200.0,
                            300.0,
                          );
                          final ringSize = dialogWidth * 0.8;
                          return Center(
                            child: CircleColorPicker(
                              controller: controller,
                              onChanged: (color) {
                                print(
                                  'Color picker dragging: R=${color.red}, G=${color.green}, B=${color.blue}',
                                );
                                setModalState(() {
                                  localColor = color;
                                  hexColor = color.value
                                      .toRadixString(16)
                                      .padLeft(8, '0')
                                      .substring(2, 8)
                                      .toUpperCase();
                                });
                                setState(() {
                                  _lightColor = color;
                                });
                                _debounceTimer?.cancel();
                                _debounceTimer = Timer(
                                  const Duration(milliseconds: 100),
                                  () {
                                    _sendLightColor(color);
                                  },
                                );
                              },
                              onEnded: (color) {
                                print(
                                  'Color picker ended: R=${color.red}, G=${color.green}, B=${color.blue}',
                                );
                                setModalState(() {
                                  localColor = color;
                                  hexColor = color.value
                                      .toRadixString(16)
                                      .padLeft(8, '0')
                                      .substring(2, 8)
                                      .toUpperCase();
                                });
                                setState(() {
                                  _lightColor = color;
                                });
                                _sendLightColor(color);
                              },
                              size: Size(ringSize, ringSize),
                              strokeWidth: 4,
                              thumbSize: 20,
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        height: 40,
                        decoration: BoxDecoration(
                          color: localColor,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Theme.of(context).colorScheme.outline,
                            width: 2,
                          ),
                        ),
                        child: Center(
                          child: Text(
                            '#$hexColor',
                            style: TextStyle(
                              color: localColor.computeLuminance() > 0.5
                                  ? Colors.black
                                  : Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ),
                      const Divider(height: 24),
                      // CCT Section
                      Text(
                        'Color Temperature',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 12),
                      _buildCctRow(
                        localCct,
                        (value) {
                          setModalState(() {
                            localCct = value;
                          });
                          setState(() {
                            _lightCct = value;
                          });
                          _debounceTimer?.cancel();
                          _debounceTimer = Timer(
                            const Duration(milliseconds: 100),
                            () {
                              _sendLightCct();
                            },
                          );
                        },
                        context,
                        setModalState,
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _buildPresetButton(2500, localCct, (val) {
                            setModalState(() {
                              localCct = val.toDouble();
                            });
                            setState(() {
                              _lightCct = val.toDouble();
                            });
                            _sendLightCct();
                          }, context),
                          _buildPresetButton(3200, localCct, (val) {
                            setModalState(() {
                              localCct = val.toDouble();
                            });
                            setState(() {
                              _lightCct = val.toDouble();
                            });
                            _sendLightCct();
                          }, context),
                          _buildPresetButton(5600, localCct, (val) {
                            setModalState(() {
                              localCct = val.toDouble();
                            });
                            setState(() {
                              _lightCct = val.toDouble();
                            });
                            _sendLightCct();
                          }, context),
                          _buildPresetButton(6500, localCct, (val) {
                            setModalState(() {
                              localCct = val.toDouble();
                            });
                            setState(() {
                              _lightCct = val.toDouble();
                            });
                            _sendLightCct();
                          }, context),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.camera_alt),
                            color: Theme.of(context).colorScheme.primary,
                            tooltip: 'Pick Color from Camera',
                            onPressed: () async {
                              final result = await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) =>
                                      const CameraColorPickerPage(),
                                ),
                              );
                              if (result != null &&
                                  result is Map<String, int>) {
                                final rr = result['r'] ?? 0;
                                final gg = result['g'] ?? 0;
                                final bb = result['b'] ?? 0;
                                final selectedColor = Color.fromRGBO(
                                  rr,
                                  gg,
                                  bb,
                                  1.0,
                                );
                                setModalState(() {
                                  localColor = selectedColor;
                                  hexColor = selectedColor.value
                                      .toRadixString(16)
                                      .padLeft(8, '0')
                                      .substring(2, 8)
                                      .toUpperCase();
                                  controller.color = selectedColor;
                                });
                                setState(() {
                                  _lightColor = selectedColor;
                                });
                                _sendLightColor(selectedColor);
                              }
                            },
                          ),
                          Row(
                            children: [
                              TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: Text(
                                  'Cancel',
                                  style: TextStyle(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurface,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              ElevatedButton(
                                onPressed: () {
                                  setState(() {
                                    _lightColor = localColor;
                                    _lightCct = localCct;
                                  });
                                  Navigator.pop(context);
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Theme.of(
                                    context,
                                  ).colorScheme.primary,
                                  foregroundColor: Theme.of(
                                    context,
                                  ).colorScheme.onPrimary,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child: const Text('Apply'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildCctRow(
    double localCct,
    Function(double) onChanged,
    BuildContext context,
    StateSetter setModalState,
  ) {
    final screenHeight = MediaQuery.of(context).size.height;
    final containerHeight = screenHeight < 700 ? 30.0 : 40.0;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        SizedBox(
          width: 40,
          child: ElevatedButton(
            onPressed: () {
              final newValue = (localCct - 100).clamp(2500.0, 6500.0);
              setModalState(() {
                localCct = newValue;
              });
              onChanged(newValue);
            },
            style: ElevatedButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: const Size(40, 40),
              backgroundColor: Theme.of(
                context,
              ).colorScheme.surfaceContainerHigh,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Icon(Icons.remove, size: 20),
          ),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: Theme.of(context).colorScheme.primary,
              inactiveTrackColor: Theme.of(context).colorScheme.outline,
              thumbColor: Theme.of(context).colorScheme.primary,
              overlayColor: Theme.of(
                context,
              ).colorScheme.primary.withOpacity(0.2),
              trackHeight: 8,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 12),
            ),
            child: Slider(
              value: localCct,
              min: 2500,
              max: 6500,
              divisions: 40,
              label: '${localCct.toInt()}K',
              onChanged: (value) {
                final newCct = (value / 100).round() * 100.0;
                setModalState(() {
                  localCct = newCct;
                });
                onChanged(newCct);
                print('CCT slider dragging: ${newCct.toInt()}K');
              },
              onChangeStart: (value) {
                print('CCT slider drag started: ${value.toInt()}K');
              },
              onChangeEnd: (value) {
                final newCct = (value / 100).round() * 100.0;
                print('CCT slider drag ended: ${newCct.toInt()}K');
                setModalState(() {
                  localCct = newCct;
                });
                onChanged(newCct);
                _sendLightCct();
              },
            ),
          ),
        ),
        SizedBox(
          width: 40,
          child: ElevatedButton(
            onPressed: () {
              final newValue = (localCct + 100).clamp(2500.0, 6500.0);
              setModalState(() {
                localCct = newValue;
              });
              onChanged(newValue);
            },
            style: ElevatedButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: const Size(40, 40),
              backgroundColor: Theme.of(
                context,
              ).colorScheme.surfaceContainerHigh,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Icon(Icons.add, size: 20),
          ),
        ),
        Container(
          width: 60,
          height: containerHeight,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          alignment: Alignment.center,
          child: Text(
            '${localCct.toInt()}K',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }

  Widget _buildPresetButton(
    int value,
    double currentCct,
    Function(int) onPressed,
    BuildContext context,
  ) {
    Color buttonColor;
    String label;
    switch (value) {
      case 2500:
        buttonColor = const Color.fromARGB(255, 241, 143, 52);
        label = 'Warm';
        break;
      case 3200:
        buttonColor = const Color.fromARGB(255, 235, 158, 90);
        label = 'Soft';
        break;
      case 5600:
        buttonColor = const Color.fromARGB(255, 242, 195, 151);
        label = 'Cool';
        break;
      case 6500:
        buttonColor = const Color.fromARGB(255, 237, 225, 213);
        label = 'Daylight';
        break;
      default:
        buttonColor = Colors.grey;
        label = '${value}K';
    }
    final isSelected = currentCct.toInt() == value;
    return SizedBox(
      width: 80,
      child: ElevatedButton(
        onPressed: () => onPressed(value),
        style: ElevatedButton.styleFrom(
          backgroundColor: buttonColor,
          foregroundColor: isSelected
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.onSurface,
          minimumSize: const Size(80, 40),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: Text(
          label,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Widget _buildPowerCapsule(ColorScheme colorScheme, TextTheme textTheme) {
    return Container(
      width: 160,
      height: 72,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(36),
        gradient: LinearGradient(
          colors: [
            colorScheme.surfaceContainerHighest,
            colorScheme.surfaceContainer,
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: colorScheme.primary.withOpacity(0.15),
            blurRadius: 15,
            spreadRadius: 2,
            offset: const Offset(0, 6),
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
                if (newState) {
                  final lastSpeed = await _getLastFanSpeed();
                  setState(() {
                    _fanSpeed = lastSpeed;
                  });
                }
                BLEHelper.send([newState ? FANON : FANOFF]);
              },
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: _isFanOn
                        ? [colorScheme.primary, colorScheme.primaryContainer]
                        : [Colors.transparent, Colors.transparent],
                  ),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(36),
                    bottomLeft: Radius.circular(36),
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
                    const SizedBox(height: 4),
                    Text(
                      _isFanOn ? "Fan On" : "Fan Off",
                      style: TextStyle(
                        color: _isFanOn
                            ? colorScheme.onPrimary
                            : colorScheme.onSurface.withOpacity(0.7),
                        fontSize: 12,
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
            height: 48,
            color: colorScheme.outline.withOpacity(0.3),
            margin: const EdgeInsets.symmetric(vertical: 12),
          ),
          // Light Section
          Expanded(
            child: GestureDetector(
              onTap: () async {
                if (_isLedOn) {
                  _showLightSettings();
                } else {
                  setState(() {
                    _isLedOn = true;
                  });
                  _sendLightColor(_lightColor);
                  _sendLightCct();
                }
              },
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: _isLedOn
                        ? [
                            _lightColor.withOpacity(0.8),
                            _lightColor.withOpacity(0.6),
                          ]
                        : [Colors.transparent, Colors.transparent],
                  ),
                  borderRadius: const BorderRadius.only(
                    topRight: Radius.circular(36),
                    bottomRight: Radius.circular(36),
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.lightbulb,
                      color: _isLedOn
                          ? Colors.white
                          : colorScheme.onSurface.withOpacity(0.5),
                      size: 28,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _isLedOn ? "Settings" : "Light Off",
                      style: TextStyle(
                        color: _isLedOn
                            ? Colors.white
                            : colorScheme.onSurface.withOpacity(0.7),
                        fontSize: 12,
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
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final mediaQuery = MediaQuery.of(context);

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
                backgroundColor: colorScheme.surface,
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                ),
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
                        if (_connectionState ==
                            BluetoothConnectionState.connected) ...[
                          const SizedBox(height: 24),
                          ElevatedButton.icon(
                            icon: const Icon(Icons.link_off),
                            label: const Text('Disconnect'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: colorScheme.error,
                              foregroundColor: colorScheme.onError,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            onPressed: () async {
                              try {
                                await _device?.disconnect();
                              } catch (e) {
                                print('Error disconnecting: $e');
                              }
                              if (context.mounted) {
                                Navigator.pop(context);
                                Navigator.pop(context);
                              }
                            },
                          ),
                        ],
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
        child: SingleChildScrollView(
          child: Column(
            children: [
              Container(
                width: double.infinity,
                padding: EdgeInsets.symmetric(
                  vertical: mediaQuery.size.height * 0.03,
                ),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      colorScheme.primary.withOpacity(0.1),
                      colorScheme.primaryContainer.withOpacity(0.1),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(16),
                    bottomRight: Radius.circular(16),
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(height: mediaQuery.size.height * 0.02),
                    Center(
                      child: SizedBox(
                        height:
                            mediaQuery.size.height * 0.12, // Reduced from 0.15
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
              ),
              SizedBox(height: mediaQuery.size.height * 0.02),
              // Power Capsule
              Center(child: _buildPowerCapsule(colorScheme, textTheme)),
              SizedBox(height: mediaQuery.size.height * 0.02),
              // Mode selector
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16.0,
                  vertical: 8.0,
                ),
                child: AbsorbPointer(
                  absorbing: !_isFanOn,
                  child: Opacity(
                    opacity: _isFanOn ? 1.0 : 0.4,
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
                          } else {
                            _fanSpeed = 5;
                          }
                        });
                        if (_fanSpeed == 6) {
                          BLEHelper.send([GEAR6]);
                        } else if (_fanSpeed == 7) {
                          BLEHelper.send([GEAR7]);
                        } else {
                          BLEHelper.send([GEAR5]);
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
                ),
              ),
              // Speed Dial
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16.0),
                child: AbsorbPointer(
                  absorbing: !_isFanOn,
                  child: Opacity(
                    opacity: _isFanOn ? 1.0 : 0.4,
                    child: Container(
                      width: mediaQuery.size.width * 0.45,
                      height: mediaQuery.size.width * 0.45,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            colorScheme.surfaceContainerHighest.withOpacity(
                              0.2,
                            ),
                            colorScheme.surfaceContainer.withOpacity(0.1),
                          ],
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
                                      } else {
                                        _fanModeIndex = 0;
                                      }
                                    });
                                  },
                                  onValueChangeEnd: (value) {
                                    final snapped = value.round().clamp(1, 7);
                                    setState(() {
                                      _fanSpeed = snapped.toDouble();
                                    });
                                    _saveLastFanSpeed(_fanSpeed);
                                    switch (snapped) {
                                      case 1:
                                        BLEHelper.send([GEAR1]);
                                        break;
                                      case 2:
                                        BLEHelper.send([GEAR2]);
                                        break;
                                      case 3:
                                        BLEHelper.send([GEAR3]);
                                        break;
                                      case 4:
                                        BLEHelper.send([GEAR4]);
                                        break;
                                      case 5:
                                        BLEHelper.send([GEAR5]);
                                        break;
                                      case 6:
                                        BLEHelper.send([GEAR6]);
                                        break;
                                      case 7:
                                        BLEHelper.send([GEAR7]);
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
                ),
              ),
              // Timer Section
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24.0,
                  vertical: 8,
                ),
                child: AbsorbPointer(
                  absorbing: !_isFanOn,
                  child: Opacity(
                    opacity: _isFanOn ? 1.0 : 0.4,
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
                            if (_timerValue > 0 && _timerRemaining > 0)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      colorScheme.primary,
                                      colorScheme.primaryContainer,
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  _formatTimer(_timerRemaining),
                                  style: textTheme.bodyMedium?.copyWith(
                                    color: colorScheme.onPrimary,
                                    fontWeight: FontWeight.bold,
                                  ),
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
                                onTap: () => _startTimer(5, R5M),
                                colorScheme: colorScheme,
                                textTheme: textTheme,
                              ),
                              const SizedBox(width: 8),
                              _TimerButton(
                                label: '30m',
                                selected: _timerValue == 30,
                                onTap: () => _startTimer(30, R30M),
                                colorScheme: colorScheme,
                                textTheme: textTheme,
                              ),
                              const SizedBox(width: 8),
                              _TimerButton(
                                label: '1h',
                                selected: _timerValue == 60,
                                onTap: () => _startTimer(60, R1H),
                                colorScheme: colorScheme,
                                textTheme: textTheme,
                              ),
                              const SizedBox(width: 8),
                              _TimerButton(
                                label: '2h',
                                selected: _timerValue == 120,
                                onTap: () => _startTimer(120, R2H),
                                colorScheme: colorScheme,
                                textTheme: textTheme,
                              ),
                              const SizedBox(width: 8),
                              _TimerButton(
                                label: '4h',
                                selected: _timerValue == 240,
                                onTap: () => _startTimer(240, R4H),
                                colorScheme: colorScheme,
                                textTheme: textTheme,
                              ),
                              const SizedBox(width: 8),
                              _TimerButton(
                                label: '6h',
                                selected: _timerValue == 360,
                                onTap: () => _startTimer(360, R6H),
                                colorScheme: colorScheme,
                                textTheme: textTheme,
                              ),
                              const SizedBox(width: 8),
                              _TimerButton(
                                label: '8h',
                                selected: _timerValue == 480,
                                onTap: () => _startTimer(480, R8H),
                                colorScheme: colorScheme,
                                textTheme: textTheme,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              SizedBox(height: mediaQuery.size.height * 0.08),
            ],
          ),
        ),
      ),
    );
  }
}

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
        child: const SizedBox(width: 100, height: 100), // Reduced from 120x120
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
      Paint()..color = Colors.grey.withOpacity(0.3),
    );
    canvas.drawCircle(center, size.width * 0.09, Paint()..color = centerColor);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
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
          gradient: selected
              ? LinearGradient(
                  colors: [colorScheme.primary, colorScheme.primaryContainer],
                )
              : null,
          color: selected ? null : colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
          border: selected
              ? null
              : Border.all(color: colorScheme.outline.withOpacity(0.2)),
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
