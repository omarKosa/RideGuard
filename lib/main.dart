import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'services/ride_service.dart';
import 'screens/home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );
  runApp(const MotorcycleRiderApp());
}

class MotorcycleRiderApp extends StatelessWidget {
  const MotorcycleRiderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => RideService(),
      child: MaterialApp(
        title: 'MotoTrack',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          scaffoldBackgroundColor: const Color(0xFF0A0E21),
          colorScheme: const ColorScheme.dark(
            primary: Color(0xFFFF4B4B),
            secondary: Color(0xFF00D9FF),
            surface: Color(0xFF1D1E33),
            background: Color(0xFF0A0E21),
          ),
          textTheme: GoogleFonts.rajdhaniTextTheme(
            ThemeData.dark().textTheme,
          ),
        ),
        home: const HomeScreen(),
      ),
    );
  }
}

