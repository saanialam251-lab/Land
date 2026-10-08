import 'package:flutter/material.dart';
import 'ui/theme.dart';
import 'ui/screens/home_screen.dart';
import 'ui/screens/measure_screen.dart';
import 'ui/screens/history_screen.dart';
import 'ui/screens/settings_screen.dart';
import 'ui/widgets/pop.dart';

class MeasureRealityApp extends StatelessWidget {
  const MeasureRealityApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Measure Reality',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      initialRoute: '/',
      onGenerateRoute: (s) {
        switch (s.name) {
          case '/measure':
            return fadeSlide(const MeasureScreen());
          case '/history':
            return fadeSlide(const HistoryScreen());
          case '/settings':
            return fadeSlide(const SettingsScreen());
          default:
            return fadeSlide(const HomeScreen());
        }
      },
    );
  }
}
