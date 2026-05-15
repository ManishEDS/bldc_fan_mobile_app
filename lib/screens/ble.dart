import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter/foundation.dart';

class BLEHelper {
  static BluetoothCharacteristic? writeCharacteristic;

  /// Set the writable characteristic after discovery
  static void setWriteCharacteristic(BluetoothCharacteristic characteristic) {
    writeCharacteristic = characteristic;
    if (kDebugMode) {
      print('Writable characteristic set: ${characteristic.uuid}');
    }
  }

  /// Send a single-byte command (e.g. [0x0E]) to the device
  static Future<void> send(List<int> data) async {
    if (writeCharacteristic == null) {
      if (kDebugMode) print('No writable characteristic set!');
      return;
    }
    try {
      await writeCharacteristic!.write(data);
      if (kDebugMode) print('Sent BLE data: $data');
    } catch (e) {
      if (kDebugMode) {
        print('Write with response failed: $e. Trying without response...');
      }
      try {
        await writeCharacteristic!.write(data, withoutResponse: true);
        if (kDebugMode) print('Sent BLE data (no response): $data');
      } catch (e2) {
        if (kDebugMode) print('Write failed: $e2');
      }
    }
  }
}
