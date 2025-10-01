// ignore_for_file: avoid_print, use_build_context_synchronously, constant_identifier_names, unused_field,
import 'dart:math';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_gauges/gauges.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../ble.dart';

class FanControlScreen extends StatefulWidget {
  final Function(bool) onFanStateChanged;
  final BoxConstraints constraints;
  final bool isDeviceOn;

  const FanControlScreen({
    super.key,
    required this.onFanStateChanged,
    required this.constraints,
    required this.isDeviceOn,
  });

  @override
  State<FanControlScreen> createState() => _FanControlScreenState();
}

class _FanControlScreenState extends State<FanControlScreen> {
  double _fanSpeed = 0.0;
  int _timerValue = 0;
  Timer? _timer;
  int _timerRemaining = 0;

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
    _loadLastFanSpeed();
  }

  @override
  void didUpdateWidget(covariant FanControlScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isDeviceOn && !oldWidget.isDeviceOn) {
      _sendFanSpeed(); // Send last speed when device turns on
    } else if (!widget.isDeviceOn && oldWidget.isDeviceOn) {
      _clearTimer(); // Clear timer when device turns off
    }
  }

  void _startTimer(int minutes, int code) {
    _timer?.cancel();
    setState(() {
      _timerValue = minutes;
      _timerRemaining = minutes * 60;
    });
    if (minutes > 0) {
      try {
        BLEHelper.send([code]);
      } catch (e) {
        print('BLE send error (timer): $e');
      }
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
          widget.onFanStateChanged(false);
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
        centerColor: colorScheme.surfaceContainerHighest,
      ),
      speedLevel: widget.isDeviceOn ? _fanSpeed : 0,
    );
  }

  Future<void> _saveLastFanSpeed(double speed) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('last_fan_speed', speed);
  }

  Future<void> _loadLastFanSpeed() async {
    final prefs = await SharedPreferences.getInstance();
    final lastSpeed = prefs.getDouble('last_fan_speed') ?? 5.0;
    setState(() {
      _fanSpeed = lastSpeed.clamp(1.0, 5.0);
    });
  }

  void _sendFanSpeed() {
    final snapped = _fanSpeed.round().clamp(1, 5);
    try {
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
      }
    } catch (e) {
      print('BLE send error (speed): $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final mediaQuery = MediaQuery.of(context);
    final isLandscape = mediaQuery.orientation == Orientation.landscape;
    final availableHeight = widget.constraints.maxHeight;
    final availableWidth = widget.constraints.maxWidth;

    // Responsive font size helper
    double responsiveFont(double baseSize) {
      // Use width as reference, but never enlarge above baseSize
      double scale = availableWidth / 400.0; // 400 is a typical mobile width
      return min(baseSize, baseSize * scale);
    }

    return SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(availableWidth * 0.04),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: double.infinity,
                padding: EdgeInsets.symmetric(
                  vertical: availableHeight * 0.03,
                  horizontal: availableWidth * 0.04,
                ),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      colorScheme.primary.withValues(alpha: 0.1),
                      colorScheme.primaryContainer.withValues(alpha: 0.1),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: IgnorePointer(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      SizedBox(height: availableHeight * 0.02),
                      Center(
                        child: FractionallySizedBox(
                          widthFactor: isLandscape ? 0.18 : 0.34,
                          child: AspectRatio(
                            aspectRatio: 1,
                            child: _buildFanGraphic(colorScheme),
                          ),
                        ),
                      ),
                      SizedBox(height: availableHeight * 0.02),
                      Text(
                        'Bluetooth is required to control.',
                        style: textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurface.withValues(alpha: 0.7),
                          fontSize: responsiveFont(10),
                        ),
                      ),
                      SizedBox(height: availableHeight * 0.04),
                    ],
                  ),
                ),
              ),
              SizedBox(height: availableHeight * 0.07),
              AbsorbPointer(
                absorbing: !widget.isDeviceOn,
                child: Opacity(
                  opacity: widget.isDeviceOn ? 1.0 : 0.4,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Speed Dial
                      Padding(
                        padding: EdgeInsets.symmetric(
                          vertical: availableHeight * 0.02,
                        ),
                        child: Center(
                          child: Container(
                            width: availableWidth * 0.5,
                            height: availableWidth * 0.5,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: RadialGradient(
                                colors: [
                                  colorScheme.surfaceContainerHighest
                                      .withValues(alpha: 0.2),
                                  colorScheme.surfaceContainer.withValues(
                                    alpha: 0.1,
                                  ),
                                ],
                              ),
                              border: Border.all(
                                color: colorScheme.primary.withValues(
                                  alpha: 0.4,
                                ),
                                width: 4,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: colorScheme.primary.withValues(
                                    alpha: 0.08,
                                  ),
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
                                    maximum: 5,
                                    interval: 1,
                                    showLabels: false,
                                    showTicks: false,
                                    axisLineStyle: AxisLineStyle(
                                      thickness: 0.2,
                                      thicknessUnit: GaugeSizeUnit.factor,
                                      color: colorScheme.primary.withValues(
                                        alpha: 0.15,
                                      ),
                                    ),
                                    pointers: <GaugePointer>[
                                      RangePointer(
                                        value: _fanSpeed.clamp(1.0, 5.0),
                                        color: colorScheme.primary,
                                        width: 0.2,
                                        sizeUnit: GaugeSizeUnit.factor,
                                      ),
                                      MarkerPointer(
                                        value: _fanSpeed.clamp(1.0, 5.0),
                                        markerType: MarkerType.circle,
                                        color: colorScheme.primary,
                                        markerHeight: 40,
                                        markerWidth: 40,
                                        enableDragging: true,
                                        onValueChanged: (value) {
                                          final snapped = value
                                              .round()
                                              .clamp(1, 5)
                                              .toDouble();
                                          setState(() {
                                            _fanSpeed = snapped;
                                          });
                                        },
                                        onValueChangeEnd: (value) {
                                          final snapped = value.round().clamp(
                                            1,
                                            5,
                                          );
                                          setState(() {
                                            _fanSpeed = snapped.toDouble();
                                          });
                                          _saveLastFanSpeed(_fanSpeed);
                                          _sendFanSpeed();
                                        },
                                      ),
                                    ],
                                    annotations: <GaugeAnnotation>[
                                      GaugeAnnotation(
                                        widget: Text(
                                          '${_fanSpeed.toInt()}',
                                          style: textTheme.displaySmall
                                              ?.copyWith(
                                                color: colorScheme.onSurface,
                                                fontWeight: FontWeight.bold,
                                                fontSize: responsiveFont(24),
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
                      // Speed and Boost Buttons
                      Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: availableWidth * 0.04,
                          vertical: availableHeight * 0.01,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: _SpeedBoostButton(
                                label: 'Speed',
                                selected: _fanSpeed == 6.0,
                                onTap: () {
                                  setState(() {
                                    _fanSpeed = 6.0;
                                  });
                                  _saveLastFanSpeed(_fanSpeed);
                                  try {
                                    BLEHelper.send([GEAR6]);
                                  } catch (e) {
                                    print('BLE send error (speed): $e');
                                  }
                                },
                                colorScheme: colorScheme,
                                textTheme: textTheme,
                                height: availableHeight * 0.05,
                                fontSize: responsiveFont(14),
                              ),
                            ),
                            SizedBox(width: availableWidth * 0.04),
                            Expanded(
                              child: _SpeedBoostButton(
                                label: 'Boost',
                                selected: _fanSpeed == 7.0,
                                onTap: () {
                                  setState(() {
                                    _fanSpeed = 7.0;
                                  });
                                  _saveLastFanSpeed(_fanSpeed);
                                  try {
                                    BLEHelper.send([GEAR7]);
                                  } catch (e) {
                                    print('BLE send error (speed): $e');
                                  }
                                },
                                colorScheme: colorScheme,
                                textTheme: textTheme,
                                height: availableHeight * 0.05,
                                fontSize: responsiveFont(14),
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Timer Section
                      Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: availableWidth * 0.06,
                          vertical: availableHeight * 0.01,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.start,
                              children: [
                                Text(
                                  'Timer',
                                  style: textTheme.titleMedium?.copyWith(
                                    color: colorScheme.onSurface,
                                    fontWeight: FontWeight.bold,
                                    fontSize: responsiveFont(16),
                                  ),
                                ),
                                SizedBox(width: availableWidth * 0.03),
                                if (_timerValue > 0 && _timerRemaining > 0)
                                  Container(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: availableWidth * 0.025,
                                      vertical: availableHeight * 0.005,
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
                                        fontSize: responsiveFont(12),
                                      ),
                                    ),
                                  ),
                                if (_timerValue > 0)
                                  IconButton(
                                    icon: Icon(
                                      Icons.clear,
                                      color: colorScheme.error,
                                      size: availableWidth * 0.06,
                                    ),
                                    tooltip: 'Clear Timer',
                                    onPressed: _clearTimer,
                                  ),
                              ],
                            ),
                            SizedBox(height: availableHeight * 0.01),
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  _TimerButton(
                                    label: '5m',
                                    selected: _timerValue == 5,
                                    onTap: () => _startTimer(5, R5M),
                                    colorScheme: colorScheme,
                                    textTheme: textTheme,
                                    width: availableWidth * 0.15,
                                    height: availableHeight * 0.05,
                                    fontSize: responsiveFont(12),
                                  ),
                                  SizedBox(width: availableWidth * 0.02),
                                  _TimerButton(
                                    label: '30m',
                                    selected: _timerValue == 30,
                                    onTap: () => _startTimer(30, R30M),
                                    colorScheme: colorScheme,
                                    textTheme: textTheme,
                                    width: availableWidth * 0.15,
                                    height: availableHeight * 0.05,
                                    fontSize: responsiveFont(12),
                                  ),
                                  SizedBox(width: availableWidth * 0.02),
                                  _TimerButton(
                                    label: '1h',
                                    selected: _timerValue == 60,
                                    onTap: () => _startTimer(60, R1H),
                                    colorScheme: colorScheme,
                                    textTheme: textTheme,
                                    width: availableWidth * 0.15,
                                    height: availableHeight * 0.05,
                                    fontSize: responsiveFont(12),
                                  ),
                                  SizedBox(width: availableWidth * 0.02),
                                  _TimerButton(
                                    label: '2h',
                                    selected: _timerValue == 120,
                                    onTap: () => _startTimer(120, R2H),
                                    colorScheme: colorScheme,
                                    textTheme: textTheme,
                                    width: availableWidth * 0.15,
                                    height: availableHeight * 0.05,
                                    fontSize: responsiveFont(12),
                                  ),
                                  SizedBox(width: availableWidth * 0.02),
                                  _TimerButton(
                                    label: '4h',
                                    selected: _timerValue == 240,
                                    onTap: () => _startTimer(240, R4H),
                                    colorScheme: colorScheme,
                                    textTheme: textTheme,
                                    width: availableWidth * 0.15,
                                    height: availableHeight * 0.05,
                                    fontSize: responsiveFont(12),
                                  ),
                                  SizedBox(width: availableWidth * 0.02),
                                  _TimerButton(
                                    label: '6h',
                                    selected: _timerValue == 360,
                                    onTap: () => _startTimer(360, R6H),
                                    colorScheme: colorScheme,
                                    textTheme: textTheme,
                                    width: availableWidth * 0.15,
                                    height: availableHeight * 0.05,
                                    fontSize: responsiveFont(12),
                                  ),
                                  SizedBox(width: availableWidth * 0.02),
                                  _TimerButton(
                                    label: '8h',
                                    selected: _timerValue == 480,
                                    onTap: () => _startTimer(480, R8H),
                                    colorScheme: colorScheme,
                                    textTheme: textTheme,
                                    width: availableWidth * 0.15,
                                    height: availableHeight * 0.05,
                                    fontSize: responsiveFont(12),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(height: availableHeight * 0.05),
                    ],
                  ),
                ),
              ),
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
        child: const SizedBox(width: 100, height: 100),
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
      Paint()..color = Colors.grey.withValues(alpha: 0.3),
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
  final double width;
  final double height;
  final double fontSize;

  const _TimerButton({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.colorScheme,
    required this.textTheme,
    required this.width,
    required this.height,
    required this.fontSize,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: width,
        height: height,
        padding: EdgeInsets.symmetric(
          horizontal: width * 0.2,
          vertical: height * 0.2,
        ),
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
              : Border.all(color: colorScheme.outline.withValues(alpha: 0.2)),
        ),
        child: Center(
          child: Text(
            label,
            style: textTheme.bodyMedium?.copyWith(
              color: selected ? colorScheme.onPrimary : colorScheme.onSurface,
              fontWeight: FontWeight.bold,
              fontSize: fontSize, // Already passed responsiveFont
            ),
          ),
        ),
      ),
    );
  }
}

class _SpeedBoostButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final ColorScheme colorScheme;
  final TextTheme textTheme;
  final double height;
  final double fontSize;

  const _SpeedBoostButton({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.colorScheme,
    required this.textTheme,
    required this.height,
    required this.fontSize,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: height,
        padding: EdgeInsets.symmetric(
          horizontal: height * 0.4,
          vertical: height * 0.2,
        ),
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
              : Border.all(color: colorScheme.outline.withValues(alpha: 0.2)),
        ),
        child: Center(
          child: Text(
            label,
            style: textTheme.bodyMedium?.copyWith(
              color: selected ? colorScheme.onPrimary : colorScheme.onSurface,
              fontWeight: FontWeight.bold,
              fontSize: fontSize,
            ),
          ),
        ),
      ),
    );
  }
}
