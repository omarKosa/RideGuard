import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../services/ride_service.dart';
import 'ride_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);
    
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  void _startRide() async {
    final rideService = context.read<RideService>();

    try {
      await rideService.startRide();

      if (!mounted) return;

      Navigator.of(context).push(
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) => const RideScreen(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.1),
                  end: Offset.zero,
                ).animate(
                  CurvedAnimation(
                    parent: animation,
                    curve: Curves.easeOutCubic,
                  ),
                ),
                child: child,
              ),
            );
          },
          transitionDuration: const Duration(milliseconds: 500),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Could not start ride. Please check permissions and try again.',
            style: GoogleFonts.rajdhani(
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.redAccent.shade200,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF0A0E21),
              Color(0xFF1A1A2E),
              Color(0xFF16213E),
            ],
          ),
        ),
        child: SafeArea(
          child: Stack(
            children: [
              // Background decorative elements
              Positioned(
                top: -100,
                right: -100,
                child: Container(
                  width: 300,
                  height: 300,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        const Color(0xFFFF4B4B).withOpacity(0.1),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                bottom: -150,
                left: -100,
                child: Container(
                  width: 400,
                  height: 400,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        const Color(0xFF00D9FF).withOpacity(0.08),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
              
              // Main content
              Column(
                children: [
                  const SizedBox(height: 60),
                  
                  // Logo and title
                  _buildHeader(),
                  
                  const Spacer(),
                  
                  // Start ride button
                  _buildStartButton(),
                  
                  const Spacer(),
                  
                  // Bottom info
                  _buildBottomInfo(),
                  
                  const SizedBox(height: 40),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      children: [
        // Motorcycle icon
        Container(
          width: 100,
          height: 100,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFFFF4B4B),
                Color(0xFFFF6B6B),
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFFF4B4B).withOpacity(0.4),
                blurRadius: 30,
                spreadRadius: 5,
              ),
            ],
          ),
          child: const Icon(
            Icons.two_wheeler,
            size: 50,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 24),
        
        Text(
          'MOTOTRACK',
          style: GoogleFonts.orbitron(
            fontSize: 36,
            fontWeight: FontWeight.bold,
            color: Colors.white,
            letterSpacing: 8,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Ride Analytics & Safety',
          style: GoogleFonts.rajdhani(
            fontSize: 16,
            color: Colors.white54,
            letterSpacing: 2,
          ),
        ),
      ],
    );
  }

  Widget _buildStartButton() {
    return Column(
      children: [
        AnimatedBuilder(
          animation: _pulseAnimation,
          builder: (context, child) {
            return Transform.scale(
              scale: _pulseAnimation.value,
              child: Container(
                width: 200,
                height: 200,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      const Color(0xFFFF4B4B).withOpacity(0.2),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            );
          },
        ),
        Transform.translate(
          offset: const Offset(0, -200),
          child: GestureDetector(
            onTap: _startRide,
            child: Container(
              width: 180,
              height: 180,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFFFF4B4B),
                    Color(0xFFFF2E2E),
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFFF4B4B).withOpacity(0.5),
                    blurRadius: 40,
                    spreadRadius: 10,
                  ),
                  const BoxShadow(
                    color: Color(0xFF1A1A2E),
                    blurRadius: 20,
                    spreadRadius: -5,
                    offset: Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.power_settings_new,
                    size: 50,
                    color: Colors.white,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'START RIDE',
                    style: GoogleFonts.orbitron(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      letterSpacing: 2,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Transform.translate(
          offset: const Offset(0, -180),
          child: Text(
            'Tap to begin tracking',
            style: GoogleFonts.rajdhani(
              fontSize: 14,
              color: Colors.white38,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBottomInfo() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildInfoItem(Icons.speed, 'Speed'),
          _buildInfoItem(Icons.rotate_right, 'Rotation'),
          _buildInfoItem(Icons.timer, 'Time'),
        ],
      ),
    );
  }

  Widget _buildInfoItem(IconData icon, String label) {
    return Column(
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: const Color(0xFF1D1E33),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Colors.white10,
              width: 1,
            ),
          ),
          child: Icon(
            icon,
            color: const Color(0xFF00D9FF),
            size: 24,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: GoogleFonts.rajdhani(
            fontSize: 12,
            color: Colors.white54,
          ),
        ),
      ],
    );
  }
}

