import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import '../services/ride_service.dart';

class RideScreen extends StatefulWidget {
  const RideScreen({super.key});

  @override
  State<RideScreen> createState() => _RideScreenState();
}

class _RideScreenState extends State<RideScreen> with TickerProviderStateMixin {
  late AnimationController _glowController;
  late Animation<double> _glowAnimation;
  Timer? _durationTimer;
  Duration _currentDuration = Duration.zero;

  @override
  void initState() {
    super.initState();
    _glowController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    )..repeat(reverse: true);
    
    _glowAnimation = Tween<double>(begin: 0.3, end: 0.8).animate(
      CurvedAnimation(parent: _glowController, curve: Curves.easeInOut),
    );
    
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final rideService = context.read<RideService>();
      if (rideService.isRiding) {
        setState(() {
          _currentDuration = rideService.rideDuration;
        });
      }
    });
  }

  @override
  void dispose() {
    _glowController.dispose();
    _durationTimer?.cancel();
    super.dispose();
  }

  void _stopRide() {
    final rideService = context.read<RideService>();
    rideService.stopRide();
    Navigator.of(context).pop();
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  String _formatDistance(double meters) {
    if (meters < 1000) {
      return '${meters.toStringAsFixed(0)} m';
    }
    return '${(meters / 1000).toStringAsFixed(2)} km';
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
          child: Consumer<RideService>(
            builder: (context, rideService, child) {
              final data = rideService.currentData;
              
              return Column(
                children: [
                  _buildHeader(),
                  const SizedBox(height: 16),
                  _buildSpeedometer(data.speed, data.maxSpeed),
                  const SizedBox(height: 24),
                  _buildStatsRow(data, rideService),
                  const SizedBox(height: 16),
                  _buildRotationIndicators(data),
                  const SizedBox(height: 16),
                  Expanded(child: _buildSpeedChart(rideService)),
                  _buildStopButton(),
                  const SizedBox(height: 20),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFFF4B4B),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFFF4B4B).withOpacity(0.5),
                      blurRadius: 10,
                      spreadRadius: 2,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'RIDE IN PROGRESS',
                style: GoogleFonts.orbitron(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFFFF4B4B),
                  letterSpacing: 2,
                ),
              ),
            ],
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF1D1E33),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white10),
            ),
            child: Row(
              children: [
                const Icon(Icons.timer, color: Color(0xFF00D9FF), size: 18),
                const SizedBox(width: 8),
                Text(
                  _formatDuration(_currentDuration),
                  style: GoogleFonts.orbitron(
                    fontSize: 16,
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSpeedometer(double speed, double maxSpeed) {
    return AnimatedBuilder(
      animation: _glowAnimation,
      builder: (context, child) {
        return Container(
          width: 220,
          height: 220,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                const Color(0xFF1D1E33),
                const Color(0xFF0A0E21).withOpacity(0.8),
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF00D9FF).withOpacity(_glowAnimation.value * 0.3),
                blurRadius: 30,
                spreadRadius: 5,
              ),
              BoxShadow(
                color: const Color(0xFFFF4B4B).withOpacity(_glowAnimation.value * 0.2),
                blurRadius: 40,
                spreadRadius: 10,
              ),
            ],
            border: Border.all(
              color: const Color(0xFF00D9FF).withOpacity(0.3),
              width: 3,
            ),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Speed arc
              CustomPaint(
                size: const Size(200, 200),
                painter: SpeedArcPainter(
                  speed: speed,
                  maxSpeed: 200,
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    speed.toStringAsFixed(0),
                    style: GoogleFonts.orbitron(
                      fontSize: 56,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    'KM/H',
                    style: GoogleFonts.rajdhani(
                      fontSize: 16,
                      color: const Color(0xFF00D9FF),
                      letterSpacing: 4,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF4B4B).withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'MAX ${maxSpeed.toStringAsFixed(0)}',
                      style: GoogleFonts.rajdhani(
                        fontSize: 12,
                        color: const Color(0xFFFF4B4B),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStatsRow(data, RideService rideService) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          Expanded(
            child: _buildStatCard(
              'DISTANCE',
              _formatDistance(data.distance),
              Icons.route,
              const Color(0xFF00D9FF),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _buildStatCard(
              'ACCEL',
              '${data.acceleration.toStringAsFixed(1)} m/s²',
              Icons.speed,
              const Color(0xFFFF4B4B),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _buildStatCard(
              'STOP TIME',
              '${data.estimatedStopTime.toStringAsFixed(1)}s',
              Icons.stop_circle_outlined,
              const Color(0xFFFFAB00),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1D1E33),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 8),
          Text(
            value,
            style: GoogleFonts.orbitron(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: GoogleFonts.rajdhani(
              fontSize: 10,
              color: Colors.white54,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRotationIndicators(data) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF1D1E33),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'ROTATION SENSORS',
              style: GoogleFonts.rajdhani(
                fontSize: 12,
                color: Colors.white54,
                letterSpacing: 2,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildRotationBar('ROLL', data.rotationX, const Color(0xFFFF4B4B)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildRotationBar('PITCH', data.rotationY, const Color(0xFF00D9FF)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildRotationBar('YAW', data.rotationZ, const Color(0xFFFFAB00)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRotationBar(String label, double value, Color color) {
    final normalizedValue = (value.abs() / 5).clamp(0.0, 1.0);
    
    return Column(
      children: [
        Text(
          label,
          style: GoogleFonts.rajdhani(
            fontSize: 10,
            color: Colors.white38,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          height: 6,
          decoration: BoxDecoration(
            color: Colors.white10,
            borderRadius: BorderRadius.circular(3),
          ),
          child: FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: normalizedValue,
            child: Container(
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(3),
                boxShadow: [
                  BoxShadow(
                    color: color.withOpacity(0.5),
                    blurRadius: 6,
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '${value.toStringAsFixed(2)} r/s',
          style: GoogleFonts.orbitron(
            fontSize: 10,
            color: Colors.white70,
          ),
        ),
      ],
    );
  }

  Widget _buildSpeedChart(RideService rideService) {
    final history = rideService.speedHistory;
    
    if (history.length < 2) {
      return Center(
        child: Text(
          'Collecting speed data...',
          style: GoogleFonts.rajdhani(
            fontSize: 14,
            color: Colors.white38,
          ),
        ),
      );
    }

    final spots = history.asMap().entries.map((entry) {
      return FlSpot(entry.key.toDouble(), entry.value.speed);
    }).toList();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF1D1E33),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'SPEED HISTORY',
              style: GoogleFonts.rajdhani(
                fontSize: 12,
                color: Colors.white54,
                letterSpacing: 2,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: LineChart(
                LineChartData(
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: 50,
                    getDrawingHorizontalLine: (value) {
                      return FlLine(
                        color: Colors.white10,
                        strokeWidth: 1,
                      );
                    },
                  ),
                  titlesData: FlTitlesData(
                    show: true,
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    bottomTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        interval: 50,
                        reservedSize: 40,
                        getTitlesWidget: (value, meta) {
                          return Text(
                            value.toInt().toString(),
                            style: GoogleFonts.rajdhani(
                              fontSize: 10,
                              color: Colors.white38,
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  minX: 0,
                  maxX: (history.length - 1).toDouble(),
                  minY: 0,
                  maxY: 200,
                  lineBarsData: [
                    LineChartBarData(
                      spots: spots,
                      isCurved: true,
                      gradient: const LinearGradient(
                        colors: [Color(0xFF00D9FF), Color(0xFFFF4B4B)],
                      ),
                      barWidth: 3,
                      isStrokeCapRound: true,
                      dotData: const FlDotData(show: false),
                      belowBarData: BarAreaData(
                        show: true,
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            const Color(0xFF00D9FF).withOpacity(0.3),
                            const Color(0xFF00D9FF).withOpacity(0.0),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStopButton() {
    return GestureDetector(
      onTap: _stopRide,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 20),
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFFF4B4B), Color(0xFFFF2E2E)],
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFFF4B4B).withOpacity(0.4),
              blurRadius: 20,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.stop, color: Colors.white, size: 24),
            const SizedBox(width: 12),
            Text(
              'STOP RIDE',
              style: GoogleFonts.orbitron(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                letterSpacing: 3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SpeedArcPainter extends CustomPainter {
  final double speed;
  final double maxSpeed;

  SpeedArcPainter({required this.speed, required this.maxSpeed});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 15;
    
    // Background arc
    final bgPaint = Paint()
      ..color = Colors.white10
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round;
    
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      math.pi * 0.75,
      math.pi * 1.5,
      false,
      bgPaint,
    );
    
    // Speed arc
    final speedRatio = (speed / maxSpeed).clamp(0.0, 1.0);
    final gradient = SweepGradient(
      startAngle: math.pi * 0.75,
      endAngle: math.pi * 2.25,
      colors: const [
        Color(0xFF00D9FF),
        Color(0xFFFFAB00),
        Color(0xFFFF4B4B),
      ],
    );
    
    final speedPaint = Paint()
      ..shader = gradient.createShader(Rect.fromCircle(center: center, radius: radius))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round;
    
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      math.pi * 0.75,
      math.pi * 1.5 * speedRatio,
      false,
      speedPaint,
    );
  }

  @override
  bool shouldRepaint(covariant SpeedArcPainter oldDelegate) {
    return oldDelegate.speed != speed;
  }
}


