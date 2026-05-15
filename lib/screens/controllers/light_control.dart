// ignore_for_file: avoid_print, use_build_context_synchronously, constant_identifier_names, unused_field, deprecated_member_use
import 'dart:async';
import 'package:flutter/material.dart';
import '../camera_color_picker.dart';
import '../ble.dart';

class LightControlScreen extends StatefulWidget {
  final Function(bool) onLightStateChanged;
  final BoxConstraints constraints;
  final bool isDeviceOn;

  const LightControlScreen({
    super.key,
    required this.onLightStateChanged,
    required this.constraints,
    required this.isDeviceOn,
  });

  @override
  State<LightControlScreen> createState() => _LightControlScreenState();
}

class _LightControlScreenState extends State<LightControlScreen> {
  final bool _isLedOn = false;
  Color _lightColor = Colors.yellowAccent;
  double _lightCct = 6500.0;
  Timer? _debounceTimer;
  double _red = 255;
  double _green = 235;
  double _blue = 59;
  double _stripPosition = 0.0;

  void _sendLightColor(Color color) {
    List<int> colorBytes = [color.red, color.green, color.blue];
    final packet = <int>[0xD5, ...colorBytes, 0x5D];
    try {
      BLEHelper.send(packet);
      print(
        'Sent color: R=${color.red}, G=${color.green}, B=${color.blue} (Hex: ${packet.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')})',
      );
    } catch (e) {
      print('BLE send error (color): $e');
    }
  }

  Color _cctToColor(double cct) {
    // Interpolate between warm white and cool white
    const warmWhite = Color(0xFFFFD700); // warm
    const coolWhite = Color(0xFFE6F0FA); // cold
    final t = ((cct - 2500) / (6500 - 2500)).clamp(0.0, 1.0);
    return Color.lerp(warmWhite, coolWhite, t) ?? warmWhite;
  }

  void _sendLightCct() {
    final cct = _lightCct.toInt().clamp(2500, 6500);
    final highByte = (cct >> 8) & 0xFF;
    final lowByte = cct & 0xFF;
    final packet = <int>[0xD6, highByte, lowByte, 0x5D];
    try {
      BLEHelper.send(packet);
      print(
        'Sent CCT: ${cct}K (Hex: ${packet.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')})',
      );
      // Update color to match CCT
      final cctColor = _cctToColor(_lightCct);
      setState(() {
        _lightColor = cctColor;
        _red = cctColor.red.toDouble();
        _green = cctColor.green.toDouble();
        _blue = cctColor.blue.toDouble();
        _stripPosition = _calculateStripPosition(cctColor);
      });
      _sendLightColor(cctColor); // Also send RGB for visual sync
    } catch (e) {
      print('BLE send error (CCT): $e');
    }
  }

  Widget _buildCctSlider(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final mediaQuery = MediaQuery.of(context);
    final availableWidth = widget.constraints.maxWidth;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Color Temperature',
          style: textTheme.titleMedium?.copyWith(
            color: colorScheme.onSurface,
            fontWeight: FontWeight.bold,
            fontSize: mediaQuery.textScaler.scale(16),
          ),
        ),
        SizedBox(height: widget.constraints.maxHeight * 0.01),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            SizedBox(
              width: availableWidth * 0.1,
              child: ElevatedButton(
                onPressed: () {
                  setState(() {
                    _lightCct = (_lightCct - 100).clamp(2500.0, 6500.0);
                  });
                  _sendLightCct();
                },
                style: ElevatedButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: Size(availableWidth * 0.1, availableWidth * 0.1),
                  backgroundColor: colorScheme.surfaceContainerHigh,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Icon(Icons.remove, size: availableWidth * 0.05),
              ),
            ),
            Expanded(
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: Colors.transparent,
                  inactiveTrackColor: Colors.transparent,
                  thumbColor: colorScheme.primary,
                  overlayColor: colorScheme.primary.withValues(alpha: 0.2),
                  trackHeight: 8,
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 12,
                  ),
                  trackShape: GradientRectSliderTrackShape(
                    gradient: const LinearGradient(
                      colors: [
                        Color.fromARGB(255, 241, 143, 52), // Warm
                        Color.fromARGB(255, 237, 225, 213), // Daylight
                      ],
                    ),
                    darkenInactive: false,
                  ),
                ),
                child: Slider(
                  value: _lightCct,
                  min: 2500,
                  max: 6500,
                  divisions: 40,
                  label: '${_lightCct.toInt()}K',
                  onChanged: (value) {
                    final newCct = (value / 100).round() * 100.0;
                    setState(() {
                      _lightCct = newCct;
                      // Update color live as slider moves
                      final cctColor = _cctToColor(newCct);
                      _lightColor = cctColor;
                      _red = cctColor.red.toDouble();
                      _green = cctColor.green.toDouble();
                      _blue = cctColor.blue.toDouble();
                      _stripPosition = _calculateStripPosition(cctColor);
                    });
                    print('CCT slider dragging: ${newCct.toInt()}K');
                    _sendLightColor(_cctToColor(newCct)); // Live update RGB
                  },
                  onChangeEnd: (value) {
                    final newCct = (value / 100).round() * 100.0;
                    setState(() {
                      _lightCct = newCct;
                      final cctColor = _cctToColor(newCct);
                      _lightColor = cctColor;
                      _red = cctColor.red.toDouble();
                      _green = cctColor.green.toDouble();
                      _blue = cctColor.blue.toDouble();
                      _stripPosition = _calculateStripPosition(cctColor);
                    });
                    print('CCT slider drag ended: ${newCct.toInt()}K');
                    _sendLightCct(); // This will also update color and send RGB
                  },
                ),
              ),
            ),
            SizedBox(
              width: availableWidth * 0.1,
              child: ElevatedButton(
                onPressed: () {
                  setState(() {
                    _lightCct = (_lightCct + 100).clamp(2500.0, 6500.0);
                  });
                  _sendLightCct();
                },
                style: ElevatedButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: Size(availableWidth * 0.1, availableWidth * 0.1),
                  backgroundColor: colorScheme.surfaceContainerHigh,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Icon(Icons.add, size: availableWidth * 0.05),
              ),
            ),
            Container(
              width: availableWidth * 0.15,
              height: availableWidth * 0.1,
              padding: EdgeInsets.all(availableWidth * 0.02),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              alignment: Alignment.center,
              child: Text(
                '${_lightCct.toInt()}K',
                style: textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  fontSize: mediaQuery.textScaler.scale(12),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildRGBStrip(ColorScheme colorScheme, double width) {
    return GestureDetector(
      onHorizontalDragUpdate: (details) {
        final box = context.findRenderObject() as RenderBox?;
        if (box == null) {
          print('Error: RenderBox is null');
          return;
        }
        final localPosition = box.globalToLocal(details.globalPosition);
        final x = localPosition.dx.clamp(0.0, width);
        final t = x / width;
        final hue = t * 360;
        final color = HSVColor.fromAHSV(1.0, hue, 1.0, 1.0).toColor();
        setState(() {
          _stripPosition = t;
          _lightColor = color;
          _red = color.red.toDouble();
          _green = color.green.toDouble();
          _blue = color.blue.toDouble();
        });
        print('Drag: x=$x, t=$t, hue=$hue, color=$color');
        _debounceTimer?.cancel();
        _debounceTimer = Timer(const Duration(milliseconds: 100), () {
          _sendLightColor(color);
        });
      },
      onHorizontalDragEnd: (_) {
        _debounceTimer?.cancel();
        _sendLightColor(_lightColor);
        print('Drag ended: color=$_lightColor');
      },
      onTapDown: (details) {
        final box = context.findRenderObject() as RenderBox?;
        if (box == null) {
          print('Error: RenderBox is null');
          return;
        }
        final localPosition = box.globalToLocal(details.globalPosition);
        final x = localPosition.dx.clamp(0.0, width);
        final t = x / width;
        final hue = t * 360;
        final color = HSVColor.fromAHSV(1.0, hue, 1.0, 1.0).toColor();
        setState(() {
          _stripPosition = t;
          _lightColor = color;
          _red = color.red.toDouble();
          _green = color.green.toDouble();
          _blue = color.blue.toDouble();
        });
        print('Tap: x=$x, t=$t, hue=$hue, color=$color');
        _sendLightColor(color);
      },
      child: Container(
        height: width * 0.1,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: const LinearGradient(
            colors: [
              Colors.red,
              Colors.yellow,
              Colors.green,
              Colors.cyan,
              Colors.blue,
              Color(0xFFFF00FF),
              Colors.red,
            ],
          ),
          border: Border.all(color: colorScheme.outline, width: 2),
        ),
        child: Align(
          alignment: Alignment(_stripPosition * 2 - 1, 0),
          child: Container(
            width: 8,
            height: width * 0.1,
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: Colors.black, width: 1),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRGBSliders(
    ColorScheme colorScheme,
    TextTheme textTheme,
    double width,
  ) {
    final mediaQuery = MediaQuery.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'RGB Adjustment',
          style: textTheme.titleMedium?.copyWith(
            color: colorScheme.onSurface,
            fontWeight: FontWeight.bold,
            fontSize: mediaQuery.textScaler.scale(16),
          ),
        ),
        SizedBox(height: widget.constraints.maxHeight * 0.01),
        // Red Slider
        Row(
          children: [
            SizedBox(
              width: width * 0.1,
              child: Text(
                'R',
                style: textTheme.bodyLarge?.copyWith(
                  color: Color.fromARGB(
                    255,
                    (Colors.red.red * 255.0).round() & 0xff,
                    0,
                    0,
                  ), // Fix for deprecated 'red'
                  fontWeight: FontWeight.bold,
                  fontSize: mediaQuery.textScaler.scale(14),
                ),
              ),
            ),
            Expanded(
              child: Slider(
                value: _red,
                min: 0,
                max: 255,
                divisions: 255,
                label: _red.round().toString(),
                activeColor: Colors.red,
                onChanged: (value) {
                  setState(() {
                    _red = value;
                    _lightColor = Color.fromRGBO(
                      _red.round(),
                      _green.round(),
                      _blue.round(),
                      1.0,
                    );
                    _stripPosition = _calculateStripPosition(_lightColor);
                  });
                },
                onChangeEnd: (value) {
                  setState(() {
                    _red = value.roundToDouble();
                    _lightColor = Color.fromRGBO(
                      _red.round(),
                      _green.round(),
                      _blue.round(),
                      1.0,
                    );
                    _stripPosition = _calculateStripPosition(_lightColor);
                  });
                  _sendLightColor(_lightColor);
                },
              ),
            ),
            Container(
              width: width * 0.15,
              padding: EdgeInsets.all(width * 0.02),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              alignment: Alignment.center,
              child: Text(
                '${_red.round()}',
                style: textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  fontSize: mediaQuery.textScaler.scale(12),
                ),
              ),
            ),
          ],
        ),
        // Green Slider
        Row(
          children: [
            SizedBox(
              width: width * 0.1,
              child: Text(
                'G',
                style: textTheme.bodyLarge?.copyWith(
                  color: Colors.green,
                  fontWeight: FontWeight.bold,
                  fontSize: mediaQuery.textScaler.scale(14),
                ),
              ),
            ),
            Expanded(
              child: Slider(
                value: _green,
                min: 0,
                max: 255,
                divisions: 255,
                label: _green.round().toString(),
                activeColor: Colors.green,
                onChanged: (value) {
                  setState(() {
                    _green = value;
                    _lightColor = Color.fromRGBO(
                      _red.round(),
                      _green.round(),
                      _blue.round(),
                      1.0,
                    );
                    _stripPosition = _calculateStripPosition(_lightColor);
                  });
                },
                onChangeEnd: (value) {
                  setState(() {
                    _green = value.roundToDouble();
                    _lightColor = Color.fromRGBO(
                      _red.round(),
                      _green.round(),
                      _blue.round(),
                      1.0,
                    );
                    _stripPosition = _calculateStripPosition(_lightColor);
                  });
                  _sendLightColor(_lightColor);
                },
              ),
            ),
            Container(
              width: width * 0.15,
              padding: EdgeInsets.all(width * 0.02),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              alignment: Alignment.center,
              child: Text(
                '${_green.round()}',
                style: textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  fontSize: mediaQuery.textScaler.scale(12),
                ),
              ),
            ),
          ],
        ),
        // Blue Slider
        Row(
          children: [
            SizedBox(
              width: width * 0.1,
              child: Text(
                'B',
                style: textTheme.bodyLarge?.copyWith(
                  color: Colors.blue,
                  fontWeight: FontWeight.bold,
                  fontSize: mediaQuery.textScaler.scale(14),
                ),
              ),
            ),
            Expanded(
              child: Slider(
                value: _blue,
                min: 0,
                max: 255,
                divisions: 255,
                label: _blue.round().toString(),
                activeColor: Colors.blue,
                onChanged: (value) {
                  setState(() {
                    _blue = value;
                    _lightColor = Color.fromRGBO(
                      _red.round(),
                      _green.round(),
                      _blue.round(),
                      1.0,
                    );
                    _stripPosition = _calculateStripPosition(_lightColor);
                  });
                },
                onChangeEnd: (value) {
                  setState(() {
                    _blue = value.roundToDouble();
                    _lightColor = Color.fromRGBO(
                      _red.round(),
                      _green.round(),
                      _blue.round(),
                      1.0,
                    );
                    _stripPosition = _calculateStripPosition(_lightColor);
                  });
                  _sendLightColor(_lightColor);
                },
              ),
            ),
            Container(
              width: width * 0.15,
              padding: EdgeInsets.all(width * 0.02),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              alignment: Alignment.center,
              child: Text(
                '${_blue.round()}',
                style: textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  fontSize: mediaQuery.textScaler.scale(12),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  double _calculateStripPosition(Color color) {
    final hsv = HSVColor.fromColor(color);
    return hsv.hue / 360.0;
  }

  Widget _buildBulbIcon(double size) {
    if (!widget.isDeviceOn) {
      return Icon(
        Icons.lightbulb,
        color: Colors.grey.withValues(alpha: 0.5),
        size: size,
      );
    }

    final isWhiteLike =
        (_red >= 200 && _green >= 200 && _blue >= 150) ||
        _lightColor == Colors.yellowAccent;

    if (isWhiteLike) {
      const warmWhite = Color(0xFFFFD700);
      const coolWhite = Color(0xFFE6F0FA);
      final t = (_lightCct - 2500) / (6500 - 2500);
      final interpolatedColor =
          Color.lerp(warmWhite, coolWhite, t) ?? warmWhite;
      return Icon(Icons.lightbulb, color: interpolatedColor, size: size);
    }

    return Icon(Icons.lightbulb, color: _lightColor, size: size);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final mediaQuery = MediaQuery.of(context);
    final availableHeight = widget.constraints.maxHeight;
    final availableWidth = widget.constraints.maxWidth;

    String hexColor = _lightColor.value
        .toRadixString(16)
        .padLeft(8, '0')
        .substring(2, 8)
        .toUpperCase();

    return SafeArea(
      child: Column(
        children: [
          // Fixed bulb container
          Padding(
            padding: EdgeInsets.symmetric(horizontal: availableWidth * 0.04),
            child: Container(
              width: double.infinity,
              height: widget.constraints.maxWidth * 0.55,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    colorScheme.primary.withValues(alpha: 0.1),
                    colorScheme.primaryContainer.withValues(alpha: 0.1),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(32),
              ),
              child: Center(
                child: FractionallySizedBox(
                  widthFactor: 0.6,
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: _buildBulbIcon(widget.constraints.maxWidth * 0.42),
                  ),
                ),
              ),
            ),
          ),
          // Scrollable controls
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(horizontal: availableWidth * 0.04),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(height: availableHeight * 0.09),
                  AbsorbPointer(
                    absorbing: !widget.isDeviceOn,
                    child: Opacity(
                      opacity: widget.isDeviceOn ? 1.0 : 0.4,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Color',
                            style: textTheme.titleMedium?.copyWith(
                              color: colorScheme.onSurface,
                              fontWeight: FontWeight.bold,
                              fontSize: mediaQuery.textScaler.scale(16),
                            ),
                          ),
                          SizedBox(height: availableHeight * 0.015),
                          Center(
                            child: _buildRGBStrip(
                              colorScheme,
                              availableWidth * 0.9,
                            ),
                          ),
                          SizedBox(height: availableHeight * 0.015),
                          Center(
                            child: Container(
                              width: availableWidth * 0.9,
                              height: availableWidth * 0.1,
                              decoration: BoxDecoration(
                                color: _lightColor,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: colorScheme.outline,
                                  width: 2,
                                ),
                              ),
                              child: Center(
                                child: Text(
                                  '#$hexColor',
                                  style: TextStyle(
                                    color: _lightColor.computeLuminance() > 0.5
                                        ? Colors.black
                                        : Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: mediaQuery.textScaler.scale(14),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          SizedBox(height: availableHeight * 0.02),
                          _buildRGBSliders(
                            colorScheme,
                            textTheme,
                            availableWidth,
                          ),
                          SizedBox(height: availableHeight * 0.02),
                          _buildCctSlider(context),
                          SizedBox(height: availableHeight * 0.02),
                          Center(
                            child: IconButton(
                              icon: Icon(
                                Icons.camera_alt,
                                size: availableWidth * 0.07,
                              ),
                              color: colorScheme.primary,
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
                                  setState(() {
                                    _lightColor = selectedColor;
                                    _red = rr.toDouble();
                                    _green = gg.toDouble();
                                    _blue = bb.toDouble();
                                    _stripPosition = _calculateStripPosition(
                                      selectedColor,
                                    );
                                  });
                                  _sendLightColor(selectedColor);
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(height: availableHeight * 0.05),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class GradientRectSliderTrackShape extends SliderTrackShape {
  final LinearGradient gradient;
  final bool darkenInactive;

  const GradientRectSliderTrackShape({
    required this.gradient,
    this.darkenInactive = true,
  });

  @override
  Rect getPreferredRect({
    required RenderBox parentBox,
    Offset offset = Offset.zero,
    required SliderThemeData sliderTheme,
    bool isEnabled = false,
    bool isDiscrete = false,
  }) {
    final trackHeight = sliderTheme.trackHeight ?? 4;
    final trackLeft = offset.dx;
    final trackTop = offset.dy + (parentBox.size.height - trackHeight) / 2;
    final trackWidth = parentBox.size.width;
    return Rect.fromLTWH(trackLeft, trackTop, trackWidth, trackHeight);
  }

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    Offset? secondaryOffset,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required TextDirection textDirection,
    required Offset thumbCenter,
    bool isDiscrete = false,
    bool isEnabled = false,
  }) {
    if (sliderTheme.trackHeight == null || sliderTheme.trackHeight! <= 0) {
      return;
    }

    final rect = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
      isEnabled: isEnabled,
      isDiscrete: isDiscrete,
    );

    final activePaint = Paint()..shader = gradient.createShader(rect);
    final inactivePaint = Paint()
      ..shader = gradient.createShader(rect)
      ..colorFilter = ColorFilter.mode(
        Colors.black.withValues(alpha: darkenInactive ? 0.5 : 0.0),
        BlendMode.srcOver,
      );

    final activeRect = Rect.fromLTWH(
      rect.left,
      rect.top,
      thumbCenter.dx - rect.left,
      rect.height,
    );
    final inactiveRect = Rect.fromLTWH(
      thumbCenter.dx,
      rect.top,
      rect.right - thumbCenter.dx,
      rect.height,
    );

    context.canvas.drawRect(activeRect, activePaint);
    context.canvas.drawRect(inactiveRect, inactivePaint);
  }
}
