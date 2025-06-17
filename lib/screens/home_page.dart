import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'controller_screen.dart';
import 'scanning.dart';

class MyHomePage extends StatefulWidget {
  const MyHomePage({
    super.key,
    required this.title,
    required this.toggleTheme,
    required this.isDarkMode,
  });

  final String title;
  final VoidCallback toggleTheme;
  final bool isDarkMode;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  final Map<String, String> _deviceRooms = {};
  final Map<String, String> _deviceNames = {};
  final Map<String, String> _deviceMacs = {};
  late SharedPreferences _prefs;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadDevices();
  }

  Future<void> _loadDevices() async {
    setState(() => _isLoading = true);
    _prefs = await SharedPreferences.getInstance();
    _deviceRooms.clear();
    _deviceNames.clear();
    _deviceMacs.clear();
    final keys = _prefs.getKeys();
    for (var key in keys) {
      if (key.startsWith('device_') && !key.startsWith('device_name_')) {
        final deviceId = key.replaceFirst('device_', '');
        _deviceRooms[deviceId] = _prefs.getString(key) ?? 'Default';
        _deviceNames[deviceId] =
            _prefs.getString('device_name_$deviceId') ?? 'Unknown Device';
        final mac = _prefs.getString('device_mac_$deviceId') ?? '';
        _deviceMacs[deviceId] = mac;
      }
    }
    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: colorScheme.primary,
        automaticallyImplyLeading:
            false, // <-- Add this line to remove the back arrow
        title: Text(
          'BLDC FAN',
          style: textTheme.titleLarge?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) {
              if (value == 'test') {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ControllerScreen(
                      deviceId: _deviceRooms.keys.isNotEmpty
                          ? _deviceRooms.keys.first
                          : 'test-id',
                      deviceName: _deviceNames.isNotEmpty
                          ? _deviceNames[_deviceRooms.keys.first] ??
                                'Test Device'
                          : 'Test Device',
                      roomName: _deviceRooms.isNotEmpty
                          ? _deviceRooms[_deviceRooms.keys.first] ?? 'Default'
                          : 'Default',
                      macAddress: _deviceMacs.isNotEmpty
                          ? _deviceMacs[_deviceRooms.keys.first] ?? ''
                          : '',
                    ),
                  ),
                );
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'test', child: Text('Test')),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  Expanded(
                    child: _deviceRooms.isEmpty
                        ? Center(
                            child: Text(
                              'No fans added yet',
                              style: textTheme.titleMedium?.copyWith(
                                color: colorScheme.onSurface.withValues(
                                  alpha: 0.7,
                                ),
                              ),
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.all(16.0),
                            itemCount: _deviceRooms.length,
                            itemBuilder: (context, index) {
                              final deviceId = _deviceRooms.keys.elementAt(
                                index,
                              );
                              final deviceName =
                                  _deviceNames[deviceId] ?? 'Unknown Device';
                              final roomName =
                                  _deviceRooms[deviceId] ?? 'Default';
                              final macAddress = _deviceMacs[deviceId] ?? '';

                              return Padding(
                                padding: const EdgeInsets.only(bottom: 16.0),
                                child: GestureDetector(
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => ControllerScreen(
                                          deviceId: deviceId,
                                          deviceName: deviceName,
                                          roomName: roomName,
                                          macAddress: macAddress,
                                        ),
                                      ),
                                    );
                                  },
                                  onLongPress: () =>
                                      _showDeviceOptionsDialog(deviceId),
                                  child: Card(
                                    elevation: 3,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.all(16.0),
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Icon(
                                                Icons.air,
                                                size: 40,
                                                color: colorScheme.primary,
                                              ),
                                              const SizedBox(width: 16),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      deviceName,
                                                      style: textTheme
                                                          .titleMedium
                                                          ?.copyWith(
                                                            fontWeight:
                                                                FontWeight.bold,
                                                            color: colorScheme
                                                                .onSurface,
                                                          ),
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                    ),
                                                    const SizedBox(height: 2),
                                                    Row(
                                                      children: [
                                                        Icon(
                                                          Icons.meeting_room,
                                                          size: 16,
                                                          color: colorScheme
                                                              .secondary,
                                                        ),
                                                        const SizedBox(
                                                          width: 4,
                                                        ),
                                                        Flexible(
                                                          child: Text(
                                                            roomName,
                                                            style: textTheme
                                                                .bodySmall
                                                                ?.copyWith(
                                                                  color: colorScheme
                                                                      .secondary,
                                                                ),
                                                            overflow:
                                                                TextOverflow
                                                                    .ellipsis,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 10),
                                          Row(
                                            children: [
                                              Icon(
                                                Icons.confirmation_number,
                                                size: 14,
                                                color: colorScheme.outline,
                                              ),
                                              const SizedBox(width: 4),
                                              Flexible(
                                                child: Text(
                                                  deviceId,
                                                  style: textTheme.bodySmall
                                                      ?.copyWith(
                                                        color: colorScheme
                                                            .onSurface
                                                            .withValues(
                                                              alpha: 0.6,
                                                            ),
                                                      ),
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ],
                                          ),
                                          if (macAddress.isNotEmpty) ...[
                                            const SizedBox(height: 4),
                                            Row(
                                              children: [
                                                Icon(
                                                  Icons.bluetooth,
                                                  size: 14,
                                                  color: colorScheme.outline,
                                                ),
                                                const SizedBox(width: 4),
                                                Flexible(
                                                  child: Text(
                                                    macAddress,
                                                    style: textTheme.bodySmall
                                                        ?.copyWith(
                                                          color: colorScheme
                                                              .onSurface
                                                              .withValues(
                                                                alpha: 0.5,
                                                              ),
                                                        ),
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) =>
                                BLEScanScreen(isDarkMode: widget.isDarkMode),
                          ),
                        );
                        _loadDevices();
                      },
                      icon: const Icon(Icons.add, color: Colors.white),
                      label: const Text(
                        'Add Fans',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 50),
                        backgroundColor: colorScheme.secondary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 2,
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  void _showDeviceOptionsDialog(String deviceId) {
    final deviceName = _deviceNames[deviceId] ?? 'Unknown Device';
    final roomName = _deviceRooms[deviceId] ?? 'Default';

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Device Options'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Card(
                margin: const EdgeInsets.symmetric(vertical: 4),
                child: ListTile(
                  leading: const Icon(Icons.edit),
                  title: const Text('Edit Device Name'),
                  onTap: () {
                    Navigator.pop(context);
                    _editDeviceName(deviceId, deviceName);
                  },
                ),
              ),
              Card(
                margin: const EdgeInsets.symmetric(vertical: 4),
                child: ListTile(
                  leading: const Icon(Icons.room),
                  title: const Text('Edit Room Name'),
                  onTap: () {
                    Navigator.pop(context);
                    _editRoomName(deviceId, roomName);
                  },
                ),
              ),
              Card(
                margin: const EdgeInsets.symmetric(vertical: 4),
                color: Colors.red.withValues(alpha: 0.08),
                child: ListTile(
                  leading: const Icon(Icons.delete, color: Colors.red),
                  title: const Text(
                    'Delete Device',
                    style: TextStyle(color: Colors.red),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _deleteDevice(deviceId);
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _editDeviceName(String deviceId, String currentName) async {
    final newName = await _showInputDialog('Edit Device Name', currentName);
    if (newName != null && newName.trim().isNotEmpty) {
      setState(() {
        _deviceNames[deviceId] = newName.trim();
        _prefs.setString('device_name_$deviceId', newName.trim());
      });
    }
  }

  void _editRoomName(String deviceId, String currentRoom) async {
    final newRoom = await _showInputDialog('Edit Room Name', currentRoom);
    if (newRoom != null && newRoom.trim().isNotEmpty) {
      setState(() {
        _deviceRooms[deviceId] = newRoom.trim();
        _prefs.setString('device_$deviceId', newRoom.trim());
      });
    }
  }

  void _deleteDevice(String deviceId) {
    setState(() {
      _deviceRooms.remove(deviceId);
      _deviceNames.remove(deviceId);
      _deviceMacs.remove(deviceId);
      _prefs.remove('device_$deviceId');
      _prefs.remove('device_name_$deviceId');
      _prefs.remove('device_mac_$deviceId');
    });
  }

  Future<String?> _showInputDialog(String title, String currentValue) {
    final controller = TextEditingController(text: currentValue);
    return showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(title),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(border: OutlineInputBorder()),
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, controller.text),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }
}
