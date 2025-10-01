// controller_screen.dart
// ignore_for_file: avoid_print, use_build_context_synchronously, constant_identifier_names, unused_field,
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import '/screens/ble_utility.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../ble.dart';
import 'fan_control.dart';
import 'light_control.dart';

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

class _ControllerScreenState extends State<ControllerScreen> {
  BluetoothDevice? _device;
  BluetoothCharacteristic? _writeCharacteristic;
  BluetoothConnectionState _connectionState =
      BluetoothConnectionState.disconnected;
  bool _isFanOn = false;
  bool _isLedOn = false;
  bool _isDeviceOn = false;
  int _currentIndex = 0;

  void _updateFanState(bool isOn) {
    setState(() {
      _isFanOn = isOn;
    });
  }

  void _updateLightState(bool isOn) {
    setState(() {
      _isLedOn = isOn;
    });
  }

  void _toggleDevicePower() async {
    setState(() {
      _isDeviceOn = !_isDeviceOn;
      _isFanOn = _isDeviceOn;
      _isLedOn = _isDeviceOn;
    });
    _updateFanState(_isDeviceOn);
    _updateLightState(_isDeviceOn);
    try {
      if (_isDeviceOn) {
        // Fan ON
        await BLEHelper.send([0x0E]); // FANON
        // Light ON (default: yellowAccent RGB(255,235,59), 6500K)
        await BLEHelper.send([0xD5, 255, 235, 59, 0x5D]);
        await BLEHelper.send([0xD6, (6500 >> 8) & 0xFF, 6500 & 0xFF, 0x5D]);
      } else {
        // Fan OFF
        await BLEHelper.send([0x06]); // FANOFF
        // Light OFF
        await BLEHelper.send([0xD5, 0, 0, 0, 0x5D]);
      }
    } catch (e) {
      print('BLE send error: $e');
    }
  }

  @override
  void initState() {
    super.initState();
    _connectToDevice();
    _requestPermissions();
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

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final mediaQuery = MediaQuery.of(context);
    final isLandscape = mediaQuery.orientation == Orientation.landscape;

    return SafeArea(
      child: Scaffold(
        backgroundColor: colorScheme.surface,
        appBar: AppBar(
          backgroundColor: colorScheme.surface,
          elevation: 0,
          title: Text(
            widget.deviceName,
            style: textTheme.titleLarge?.copyWith(
              color: colorScheme.onSurface,
              fontWeight: FontWeight.bold,
              fontSize: mediaQuery.textScaler.scale(20),
            ),
          ),
          centerTitle: true,
          actions: [
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: mediaQuery.size.width * 0.02,
              ),
              child: IconButton(
                icon: Icon(
                  Icons.power_settings_new,
                  color: _isDeviceOn
                      ? Colors.green
                      : colorScheme.onSurface.withValues(alpha: 0.5),
                  size: isLandscape
                      ? mediaQuery.size.width * 0.05
                      : mediaQuery.size.width * 0.07,
                ),
                onPressed: _toggleDevicePower,
                tooltip: _isDeviceOn ? 'Turn Device Off' : 'Turn Device On',
              ),
            ),
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: mediaQuery.size.width * 0.02,
              ),
              child: IconButton(
                icon: Icon(
                  _connectionState == BluetoothConnectionState.connected
                      ? Icons.bluetooth_connected
                      : Icons.bluetooth_disabled,
                  color: _connectionState == BluetoothConnectionState.connected
                      ? Colors.blue
                      : colorScheme.error,
                  size: isLandscape
                      ? mediaQuery.size.width * 0.05
                      : mediaQuery.size.width * 0.07,
                ),
                onPressed: () {
                  showModalBottomSheet(
                    context: context,
                    backgroundColor: colorScheme.surface,
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(20),
                      ),
                    ),
                    builder: (context) => SafeArea(
                      child: Padding(
                        padding: EdgeInsets.all(mediaQuery.size.width * 0.06),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _connectionState ==
                                      BluetoothConnectionState.connected
                                  ? Icons.bluetooth_connected
                                  : Icons.bluetooth_disabled,
                              color:
                                  _connectionState ==
                                      BluetoothConnectionState.connected
                                  ? Colors.blue
                                  : colorScheme.error,
                              size: mediaQuery.size.width * 0.12,
                            ),
                            SizedBox(height: mediaQuery.size.height * 0.02),
                            Text(
                              _connectionState ==
                                      BluetoothConnectionState.connected
                                  ? 'Connected'
                                  : 'Disconnected',
                              style: textTheme.titleMedium?.copyWith(
                                color:
                                    _connectionState ==
                                        BluetoothConnectionState.connected
                                    ? Colors.blue
                                    : colorScheme.error,
                                fontWeight: FontWeight.bold,
                                fontSize: mediaQuery.textScaler.scale(16),
                              ),
                            ),
                            SizedBox(height: mediaQuery.size.height * 0.01),
                            Text(
                              'Device: ${widget.deviceName}',
                              style: textTheme.bodyLarge?.copyWith(
                                fontSize: mediaQuery.textScaler.scale(14),
                              ),
                            ),
                            SizedBox(height: mediaQuery.size.height * 0.01),
                            Text(
                              'Device ID: ${widget.deviceId}',
                              style: textTheme.bodyMedium?.copyWith(
                                color: colorScheme.onSurface.withValues(
                                  alpha: 0.6,
                                ),
                                fontSize: mediaQuery.textScaler.scale(12),
                              ),
                            ),
                            if (_connectionState ==
                                BluetoothConnectionState.connected) ...[
                              SizedBox(height: mediaQuery.size.height * 0.03),
                              ElevatedButton.icon(
                                icon: const Icon(Icons.link_off),
                                label: const Text('Disconnect'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: colorScheme.error,
                                  foregroundColor: colorScheme.onError,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  padding: EdgeInsets.symmetric(
                                    horizontal: mediaQuery.size.width * 0.04,
                                    vertical: mediaQuery.size.height * 0.015,
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
            ),
          ],
        ),
        body: LayoutBuilder(
          builder: (context, constraints) {
            return IndexedStack(
              index: _currentIndex,
              children: [
                FanControlScreen(
                  onFanStateChanged: _updateFanState,
                  constraints: constraints,
                  isDeviceOn: _isDeviceOn,
                ),
                LightControlScreen(
                  onLightStateChanged: _updateLightState,
                  constraints: constraints,
                  isDeviceOn: _isDeviceOn,
                ),
              ],
            );
          },
        ),
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (index) {
            setState(() {
              _currentIndex = index;
            });
          },
          iconSize: isLandscape
              ? mediaQuery.size.width * 0.04
              : mediaQuery.size.width * 0.06,
          selectedFontSize: mediaQuery.textScaler.scale(12),
          unselectedFontSize: mediaQuery.textScaler.scale(10),
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.air), label: 'Fan'),
            BottomNavigationBarItem(
              icon: Icon(Icons.lightbulb),
              label: 'Light',
            ),
          ],
        ),
      ),
    );
  }
}
