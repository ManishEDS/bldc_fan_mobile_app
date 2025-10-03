import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bldcfan/main.dart';
import 'package:bldcfan/screens/splash.dart';
import 'package:bldcfan/screens/home_page.dart'; // Add this import for MyHomePage

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues(
      {'isFirstLaunch': false},
    ); // Mock to simulate non-first launch, navigate to home instead of BLE scan
  });

  testWidgets('Splash screen renders correctly', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const MyApp());

    // Verify the splash screen renders without errors.
    expect(find.byType(SplashScreen), findsOneWidget);
    expect(find.byType(Scaffold), findsOneWidget);
    expect(
      find.byType(RotationTransition),
      findsWidgets,
    ); // Allows for 1+ (matches the observed 2)
    expect(
      find.byType(CustomPaint),
      findsWidgets,
    ); // Allows for 1+ if there are multiples

    // Advance time to fire the navigation timer.
    await tester.pump(const Duration(seconds: 3));

    // Wait for all async operations (SharedPreferences, navigation) to settle.
    await tester.pumpAndSettle();

    // Verify navigation to MyHomePage (non-first launch).
    expect(find.byType(MyHomePage), findsOneWidget);

    // Verify no counter text exists (confirms it's not the default demo).
    expect(find.text('0'), findsNothing);
  });
}
