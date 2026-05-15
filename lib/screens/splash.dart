import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'home_page.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'scanning.dart'; // Import your scanning screen

class SplashScreen extends StatefulWidget {
  final VoidCallback toggleTheme;
  final bool isDarkMode;

  const SplashScreen({
    super.key,
    required this.toggleTheme,
    required this.isDarkMode,
  });

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat();

    _navigateAfterDelay();
  }

  Future<void> _navigateAfterDelay() async {
    await Future.delayed(const Duration(milliseconds: 2500));
    final prefs = await SharedPreferences.getInstance();
    final isFirstLaunch = prefs.getBool('isFirstLaunch') ?? true;

    if (isFirstLaunch) {
      await prefs.setBool('isFirstLaunch', false);
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => BLEScanScreen(isDarkMode: widget.isDarkMode),
          ),
        );
      }
    } else {
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => MyHomePage(
              title: 'BLDC Fan',
              toggleTheme: widget.toggleTheme,
              isDarkMode: widget.isDarkMode,
            ),
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: Center(
        child: Stack(
          alignment: Alignment.center,
          children: [
            RotationTransition(
              turns: _controller,
              child: SizedBox(
                width: 120,
                height: 120,
                child: CustomPaint(
                  painter: _FanPainter(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
            ),
            // Air blowing effect (animated lines)
            Positioned(right: 0, child: _BlowingAir()),
          ],
        ),
      ),
    );
  }
}

class _BlowingAir extends StatefulWidget {
  @override
  State<_BlowingAir> createState() => _BlowingAirState();
}

class _BlowingAirState extends State<_BlowingAir>
    with SingleTickerProviderStateMixin {
  late AnimationController _airController;

  @override
  void initState() {
    super.initState();
    _airController = AnimationController(
      duration: const Duration(seconds: 1),
      vsync: this,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _airController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _airController,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _airLine(),
          SizedBox(height: 8),
          _airLine(width: 40),
          SizedBox(height: 8),
          _airLine(width: 30),
        ],
      ),
    );
  }

  Widget _airLine({double width = 50}) {
    return Container(
      width: width,
      height: 6,
      decoration: BoxDecoration(
        color: Colors.blueAccent.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(3),
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
      final angle = i * 2 * 3.14159 / 3;
      final path = Path();
      // Start at center, move out a bit to create a gap
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
