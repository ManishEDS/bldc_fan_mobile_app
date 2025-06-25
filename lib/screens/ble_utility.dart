import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter/material.dart';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart'; // For Platform.isAndroid and Platform.isIOS

class BLEUtility {
  // Global BluetoothDevice variable
  static BluetoothDevice? connectedDevice;
  static StreamSubscription<BluetoothConnectionState>? connectionSubscription;
  static double cct = 2500;
  static double intensity = 50;
  static double H = 0;
  static double S = 0;
  static double R = 0;
  static double G = 0;
  static double B = 0;
  static int mode = 1;
  static var fxMode = 1;
  static bool currentDeviceEnabled = true;
  static Map<String, ValueNotifier<bool>> deviceStatusNotifiers = {};

  // List of all icons with serial numbers
  static final List<Map<String, dynamic>> modesInfo = [
    {'icon': Icons.sync, 'serial': 1, 'modeIntensity': 1},
    {'icon': Icons.auto_awesome, 'serial': 2, 'modeIntensity': 1},
    {'icon': Icons.light_mode, 'serial': 3, 'modeIntensity': 1},
    {'icon': Icons.flash_on, 'serial': 4, 'modeIntensity': 1},
    {'icon': Icons.emoji_objects, 'serial': 5, 'modeIntensity': 1},
    {'icon': Icons.desktop_windows, 'serial': 6, 'modeIntensity': 1},
    {'icon': Icons.cake, 'serial': 7, 'modeIntensity': 1},
    {'icon': Icons.local_fire_department, 'serial': 8, 'modeIntensity': 1},
    {'icon': Icons.hotel_class, 'serial': 9, 'modeIntensity': 1},
    {'icon': Icons.drive_eta, 'serial': 10, 'modeIntensity': 1},
    {'icon': Icons.wb_twilight, 'serial': 11, 'modeIntensity': 1},
    {'icon': Icons.airport_shuttle, 'serial': 12, 'modeIntensity': 1},
    {'icon': Icons.music_note, 'serial': 13, 'modeIntensity': 1},
    {'icon': Icons.sos, 'serial': 14, 'modeIntensity': 1},
  ];

  // Method to check if a device is connected
  static bool get isConnected => connectedDevice != null;
  static List<Map<String, dynamic>> savedDevices = [];

  static Map<String, double> brightnessValues = {};
  static Map<String, double> cctValues = {};
  static Map<String, double> hueValues = {};
  static Map<String, double> saturationValues = {};

  // Method to connect to a BLE device
  static Future<void> connectToDevice(BuildContext context) async {
    if (connectedDevice == null) {
      return;
    }
    // Show connecting message
    // ScaffoldMessenger.of(context).showSnackBar(
    //   SnackBar(content: Text('Connecting to device...')),
    // );

    //BLEUtility.showDisconnectedDialog(context, 'Connecting to device...');

    try {
      if (Platform.isIOS) {
        await connectedDevice!.connect(
          timeout: const Duration(seconds: 10),
          autoConnect: false,
        );
      } else if (Platform.isAndroid) {
        await connectedDevice!.connect(
          timeout: const Duration(seconds: 10),
          autoConnect: true,
        );
      }

      if (kDebugMode) {
        print('Connected to device: ${connectedDevice!.remoteId}');
      }
      monitorConnection(connectedDevice!); // Start monitoring connection state
    } catch (e) {
      if (kDebugMode) {
        print('Error connecting to device: $e');
      }
    }
  }

  static Future<void> disconnectDeviceById(String deviceId) async {
    try {
      List<BluetoothDevice> devs = FlutterBluePlus.connectedDevices;
      for (var d in devs) {
        if (d.remoteId.toString() == deviceId) d.disconnect();
      }
    } catch (e) {}
  }

  // Method to attempt reconnection every second for 2 minutes
  // static Future<void> attemptReconnect() async {
  //   const reconnectAttempts = 120; // 2 minutes of attempts (120 seconds)
  //   for (int attempt = 1; attempt <= reconnectAttempts; attempt++) {
  //     print('Reconnect attempt $attempt...');
  //     try {
  //       await connectToDevice(context);
  //       if (connectedDevice != null) {
  //         print('Reconnected successfully on attempt $attempt.');
  //         return; // Successfully reconnected, exit the loop
  //       }
  //     } catch (e) {
  //       print('Reconnect attempt $attempt failed: $e');
  //     }

  //     // Retry delay of 1 second before the next attempt
  //     await Future.delayed(Duration(seconds: 1)); // Adjust delay to 1 second
  //   }
  //   print('Failed to reconnect after $reconnectAttempts attempts.');
  // }

  // Method to monitor connection state
  static void monitorConnection(BluetoothDevice device) {
    connectionSubscription
        ?.cancel(); // Cancel any previous connection subscription
    connectionSubscription = device.connectionState.listen((state) {
      if (state == BluetoothConnectionState.connected) {
        connectedDevice = device;
        if (kDebugMode) {
          print('Device connected');
        }
      } else {
        connectedDevice = null;
        if (kDebugMode) {
          print('Device disconnected, attempting to reconnect...');
        }
        //attemptReconnect(); // Trigger reconnection if device is disconnected
      }
    });
  }

  // Method to stop monitoring connection (optional)
  static void stopMonitoringConnection() {
    connectionSubscription?.cancel();
  }

  // Method to send data to the connected BLE device
  static Future<void> sendDataToDevice(List<int> messageBytes) async {
    if (connectedDevice == null) {
      if (kDebugMode) print('No device is connected.');
      return;
    }

    try {
      List<BluetoothService> services = await connectedDevice!
          .discoverServices();
      if (services.isNotEmpty) {
        BluetoothService targetService = services[0];
        List<BluetoothCharacteristic> characteristics =
            targetService.characteristics;

        // Find the first writable characteristic
        BluetoothCharacteristic? targetCharacteristic;
        for (final c in characteristics) {
          if (c.properties.write) {
            targetCharacteristic = c;
            break;
          }
        }
        if (targetCharacteristic == null) {
          if (kDebugMode) print('No writable characteristic found');
          return;
        }

        // Try both write types
        try {
          await targetCharacteristic.write(messageBytes);
          if (kDebugMode) print('Sent message on Android: $messageBytes');
        } catch (e) {
          if (kDebugMode)
            print('Write with response failed: $e. Trying without response...');
          try {
            await targetCharacteristic.write(
              messageBytes,
              withoutResponse: true,
            );
            if (kDebugMode)
              print('Sent message on Android (no response): $messageBytes');
          } catch (e2) {
            if (kDebugMode) print('Write without response also failed: $e2');
          }
        }
      }
    } catch (e) {
      if (kDebugMode) print('Error sending data to device: $e');
    }
  }

  /// Helper method to check if the device is enabled
  static Future<bool> checkDeviceEnabledStatus() async {
    //SharedPreferences prefs = await SharedPreferences.getInstance();
    List<Map<String, dynamic>> savedDevices = await getSavedDevices();

    // Get the current device ID
    String currentDeviceId = connectedDevice!.remoteId.toString();

    // Find the device in the saved devices list
    for (Map<String, dynamic> device in savedDevices) {
      String deviceId = device['id'];
      bool enabled = device['enabled'];

      // Check if the device ID matches and return the 'enabled' status
      if (deviceId == currentDeviceId) {
        return enabled;
      }
    }

    // If the device is not found, consider it as disabled or return false
    return false;
  }

  // Optional method to disconnect from the device
  static Future<void> disconnectDevice() async {
    if (connectedDevice != null) {
      await connectedDevice!.disconnect();
      if (kDebugMode) {
        print('Disconnected from device: ${connectedDevice!.remoteId}');
      }
      connectedDevice = null; // Reset the connected device
    } else {
      if (kDebugMode) {
        print('No device is connected to disconnect.');
      }
    }
  }

  static Future<void> showDisconnectedDialog(
    BuildContext context,
    String message,
  ) async {
    showDialog(
      context: context,
      barrierDismissible: false, // Prevent manual dismissal
      builder: (BuildContext context) {
        // Return the dialog widget
        return AlertDialog(
          backgroundColor: Colors.black,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.bluetooth, color: Colors.blue, size: 30),
              const SizedBox(height: 10),
              Text(
                message,
                style: const TextStyle(color: Colors.white, fontSize: 16),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        );
      },
    );

    // Automatically dismiss the dialog after 2 seconds
    await Future.delayed(const Duration(seconds: 2));
    if (Navigator.canPop(context)) {
      Navigator.pop(context);
    }
  }

  static Future<void> saveDevice(BluetoothDevice device) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    List<String> savedDevices = prefs.getStringList('saved_devices') ?? [];

    // Define the device information with an 'enabled' parameter
    Map<String, dynamic> deviceInfo = {
      'id': device.remoteId.toString(),
      'name': device.platformName,
      'enabled': true, // Default value is true
    };

    // Convert the device information to a JSON string
    String deviceJson = jsonEncode(deviceInfo);

    // Ensure the device is not already saved
    bool alreadySaved = savedDevices.any((entry) {
      Map<String, dynamic> existingDevice = jsonDecode(entry);
      return existingDevice['id'] == device.remoteId.toString();
    });

    if (!alreadySaved) {
      savedDevices.add(deviceJson);
      await prefs.setStringList('saved_devices', savedDevices);
    }
  }

  static Future<List<Map<String, dynamic>>> getSavedDevices() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    List<String> savedDevices = prefs.getStringList('saved_devices') ?? [];

    return savedDevices.map((deviceJson) {
      return jsonDecode(deviceJson) as Map<String, dynamic>;
    }).toList();
  }
}
