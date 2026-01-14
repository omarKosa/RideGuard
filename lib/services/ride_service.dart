import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:geolocator/geolocator.dart';
import '../models/ride_data.dart';

class RideService extends ChangeNotifier {
  RideData _currentData = RideData.initial();
  bool _isRiding = false;
  DateTime? _rideStartTime;
  double _targetSpeed = 100.0; // Default target speed in km/h
  
  // Sensor subscriptions
  StreamSubscription<AccelerometerEvent>? _accelerometerSubscription;
  StreamSubscription<GyroscopeEvent>? _gyroscopeSubscription;
  StreamSubscription<Position>? _positionSubscription;
  
  // Sensor data buffers for smoothing
  final List<double> _accelerationBuffer = [];
  final List<double> _rotationXBuffer = [];
  final List<double> _rotationYBuffer = [];
  final List<double> _rotationZBuffer = [];
  static const int _bufferSize = 10;
  
  // Speed history for charts
  final List<SpeedHistoryPoint> _speedHistory = [];
  
  // Current sensor values
  double _currentAccelX = 0;
  double _currentAccelY = 0;
  double _currentAccelZ = 0;
  double _currentGyroX = 0;
  double _currentGyroY = 0;
  double _currentGyroZ = 0;
  double _currentSpeed = 0;
  double _maxSpeed = 0;
  double _totalDistance = 0;
  Position? _lastPosition;
  
  // Getters
  RideData get currentData => _currentData;
  bool get isRiding => _isRiding;
  DateTime? get rideStartTime => _rideStartTime;
  double get targetSpeed => _targetSpeed;
  List<SpeedHistoryPoint> get speedHistory => List.unmodifiable(_speedHistory);
  Duration get rideDuration => _rideStartTime != null 
      ? DateTime.now().difference(_rideStartTime!) 
      : Duration.zero;

  set targetSpeed(double value) {
    _targetSpeed = value;
    notifyListeners();
  }

  Future<bool> _checkPermissions() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return false;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return false;
      }
    }
    
    if (permission == LocationPermission.deniedForever) {
      return false;
    }
    
    return true;
  }

  Future<void> startRide() async {
    if (_isRiding) return;
    
    final hasPermission = await _checkPermissions();
    if (!hasPermission) {
      // Continue without GPS, use accelerometer-based speed estimation
    }
    
    _isRiding = true;
    _rideStartTime = DateTime.now();
    _maxSpeed = 0;
    _totalDistance = 0;
    _lastPosition = null;
    _speedHistory.clear();
    _currentData = RideData.initial();
    
    _startSensorListening();
    notifyListeners();
  }

  void _startSensorListening() {
    // Accelerometer for acceleration and speed estimation
    _accelerometerSubscription = accelerometerEventStream(
      samplingPeriod: const Duration(milliseconds: 50),
    ).listen((AccelerometerEvent event) {
      _currentAccelX = event.x;
      _currentAccelY = event.y;
      _currentAccelZ = event.z;
      
      // Calculate total acceleration (excluding gravity approximately)
      final totalAccel = sqrt(
        pow(event.x, 2) + pow(event.y, 2) + pow(event.z - 9.8, 2)
      );
      
      _addToBuffer(_accelerationBuffer, totalAccel);
      _updateRideData();
    });
    
    // Gyroscope for rotation/lean detection
    _gyroscopeSubscription = gyroscopeEventStream(
      samplingPeriod: const Duration(milliseconds: 50),
    ).listen((GyroscopeEvent event) {
      _currentGyroX = event.x;
      _currentGyroY = event.y;
      _currentGyroZ = event.z;
      
      _addToBuffer(_rotationXBuffer, event.x);
      _addToBuffer(_rotationYBuffer, event.y);
      _addToBuffer(_rotationZBuffer, event.z);
      _updateRideData();
    });
    
    // GPS for accurate speed
    _startLocationTracking();
  }

  Future<void> _startLocationTracking() async {
    try {
      const LocationSettings locationSettings = LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 5,
      );
      
      _positionSubscription = Geolocator.getPositionStream(
        locationSettings: locationSettings,
      ).listen((Position position) {
        // Speed from GPS in m/s, convert to km/h
        _currentSpeed = position.speed * 3.6;
        if (_currentSpeed < 0) _currentSpeed = 0;
        
        // Update max speed
        if (_currentSpeed > _maxSpeed) {
          _maxSpeed = _currentSpeed;
        }
        
        // Calculate distance
        if (_lastPosition != null) {
          _totalDistance += Geolocator.distanceBetween(
            _lastPosition!.latitude,
            _lastPosition!.longitude,
            position.latitude,
            position.longitude,
          );
        }
        _lastPosition = position;
        
        // Add to speed history
        _speedHistory.add(SpeedHistoryPoint(DateTime.now(), _currentSpeed));
        if (_speedHistory.length > 300) {
          _speedHistory.removeAt(0);
        }
        
        _updateRideData();
      });
    } catch (e) {
      debugPrint('Location tracking error: $e');
    }
  }

  void _addToBuffer(List<double> buffer, double value) {
    buffer.add(value);
    if (buffer.length > _bufferSize) {
      buffer.removeAt(0);
    }
  }

  double _getSmoothedValue(List<double> buffer) {
    if (buffer.isEmpty) return 0;
    return buffer.reduce((a, b) => a + b) / buffer.length;
  }

  void _updateRideData() {
    final smoothedAccel = _getSmoothedValue(_accelerationBuffer);
    final smoothedRotX = _getSmoothedValue(_rotationXBuffer);
    final smoothedRotY = _getSmoothedValue(_rotationYBuffer);
    final smoothedRotZ = _getSmoothedValue(_rotationZBuffer);
    
    // Calculate estimated stop time
    // Using physics: v = v0 + at, when v = 0, t = v0/a
    // Assuming average deceleration of 7 m/s² for motorcycle braking
    const avgDeceleration = 7.0; // m/s²
    final speedMs = _currentSpeed / 3.6; // Convert km/h to m/s
    final estimatedStopTime = speedMs / avgDeceleration;
    
    // Calculate time to reach target speed
    // Using current acceleration trend
    double timeToTarget = 0;
    if (_currentSpeed < _targetSpeed && smoothedAccel > 0.5) {
      final speedDiff = (_targetSpeed - _currentSpeed) / 3.6; // m/s
      timeToTarget = speedDiff / smoothedAccel;
      if (timeToTarget.isInfinite || timeToTarget.isNaN || timeToTarget > 999) {
        timeToTarget = 0;
      }
    }
    
    _currentData = RideData(
      speed: _currentSpeed,
      acceleration: smoothedAccel,
      rotationX: smoothedRotX,
      rotationY: smoothedRotY,
      rotationZ: smoothedRotZ,
      maxSpeed: _maxSpeed,
      estimatedStopTime: estimatedStopTime,
      timeToTarget: timeToTarget,
      timestamp: DateTime.now(),
      distance: _totalDistance,
    );
    
    notifyListeners();
  }

  void stopRide() {
    _isRiding = false;
    
    _accelerometerSubscription?.cancel();
    _gyroscopeSubscription?.cancel();
    _positionSubscription?.cancel();
    
    _accelerometerSubscription = null;
    _gyroscopeSubscription = null;
    _positionSubscription = null;
    
    _accelerationBuffer.clear();
    _rotationXBuffer.clear();
    _rotationYBuffer.clear();
    _rotationZBuffer.clear();
    
    notifyListeners();
  }

  @override
  void dispose() {
    stopRide();
    super.dispose();
  }
}

