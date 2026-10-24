import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' as math;
import 'package:flutter/material.dart';

import 'nusantara_map.dart';

/// Model Kapten NPC untuk simulasi kehidupan maritim Nusantara di sisi klien (Client-Side).
class NpcCaptain {
  final int id;
  final String name;
  final int startPortId;
  final String color;
  final String personality;
  int currentPortId;
  int destinationPortId;
  double x;
  double y;
  double targetX;
  double targetY;

  NpcCaptain({
    required this.id,
    required this.name,
    required this.startPortId,
    required this.color,
    required this.personality,
    int? currentPortId,
    int? destinationPortId,
    required this.x,
    required this.y,
    double? targetX,
    double? targetY,
  })  : currentPortId = currentPortId ?? startPortId,
        destinationPortId = destinationPortId ?? startPortId,
        targetX = targetX ?? x,
        targetY = targetY ?? y;

  Offset get position => Offset(x, y);

  factory NpcCaptain.fromJson(
    Map<String, dynamic> json, {
    List<MapPortNode> ports = kNusantaraPortNodes,
  }) {
    final int startId = (json['startPortId'] as num?)?.toInt() ??
        (json['start_port_id'] as num?)?.toInt() ??
        1;
    final MapPortNode startPort = ports
            .where((p) => p.id == startId)
            .firstOrNull ??
        ports.first;
    return NpcCaptain(
      id: (json['id'] as num?)?.toInt() ?? 1,
      name: (json['name'] as String?) ?? 'Laksamana Jaya',
      startPortId: startId,
      color: (json['color'] as String?) ?? '#60A5FA',
      personality: (json['personality'] as String?) ?? 'agresif',
      currentPortId: startId,
      destinationPortId: startId,
      x: startPort.mapX,
      y: startPort.mapY,
      targetX: startPort.mapX,
      targetY: startPort.mapY,
    );
  }
}

/// Daftar 20 Kapten NPC Nusantara bawaan (sinkron dengan GET /v1/world/npc-captains).
List<NpcCaptain> buildDefaultNpcCaptains({
  List<MapPortNode> ports = kNusantaraPortNodes,
}) {
  const List<Map<String, dynamic>> rawSpecs = <Map<String, dynamic>>[
    <String, dynamic>{
      'id': 1,
      'name': 'Laksamana Jaya',
      'startPortId': 6,
      'color': '#60A5FA',
      'personality': 'agresif',
    },
    <String, dynamic>{
      'id': 2,
      'name': 'Sultan Babullah',
      'startPortId': 2,
      'color': '#94A3B8',
      'personality': 'agresif',
    },
    <String, dynamic>{
      'id': 3,
      'name': 'Laksamana Malahayati',
      'startPortId': 4,
      'color': '#38BDF8',
      'personality': 'agresif',
    },
    <String, dynamic>{
      'id': 4,
      'name': 'Pangeran Dipati Unus',
      'startPortId': 3,
      'color': '#64748B',
      'personality': 'agresif',
    },
    <String, dynamic>{
      'id': 5,
      'name': 'Sultan Hasanuddin',
      'startPortId': 5,
      'color': '#818CF8',
      'personality': 'agresif',
    },
    <String, dynamic>{
      'id': 6,
      'name': 'Kapitan Pattimura',
      'startPortId': 1,
      'color': '#7DD3FC',
      'personality': 'agresif',
    },
    <String, dynamic>{
      'id': 7,
      'name': 'Karaeng Matoaya',
      'startPortId': 5,
      'color': '#93C5FD',
      'personality': 'konservatif',
    },
    <String, dynamic>{
      'id': 8,
      'name': 'Syahbandar Nyai Gede Pinatih',
      'startPortId': 3,
      'color': '#A5B4FC',
      'personality': 'konservatif',
    },
    <String, dynamic>{
      'id': 9,
      'name': 'Hang Tuah',
      'startPortId': 4,
      'color': '#CBD5E1',
      'personality': 'agresif',
    },
    <String, dynamic>{
      'id': 10,
      'name': 'Sultan Baabullah Muda',
      'startPortId': 2,
      'color': '#67E8F9',
      'personality': 'konservatif',
    },
    <String, dynamic>{
      'id': 11,
      'name': 'Daeng Marewa',
      'startPortId': 5,
      'color': '#94A3B8',
      'personality': 'agresif',
    },
    <String, dynamic>{
      'id': 12,
      'name': 'Ki Juru Martani',
      'startPortId': 6,
      'color': '#64748B',
      'personality': 'konservatif',
    },
    <String, dynamic>{
      'id': 13,
      'name': 'Ratu Kalinyamat',
      'startPortId': 3,
      'color': '#60A5FA',
      'personality': 'agresif',
    },
    <String, dynamic>{
      'id': 14,
      'name': 'Sultan Nuku',
      'startPortId': 2,
      'color': '#38BDF8',
      'personality': 'agresif',
    },
    <String, dynamic>{
      'id': 15,
      'name': 'Orangkaya Banda',
      'startPortId': 1,
      'color': '#93C5FD',
      'personality': 'konservatif',
    },
    <String, dynamic>{
      'id': 16,
      'name': 'Juragan Datuk Bendahara',
      'startPortId': 4,
      'color': '#CBD5E1',
      'personality': 'konservatif',
    },
    <String, dynamic>{
      'id': 17,
      'name': 'Nahkoda La Maddukelleng',
      'startPortId': 5,
      'color': '#7DD3FC',
      'personality': 'agresif',
    },
    <String, dynamic>{
      'id': 18,
      'name': 'Saudagar Jayakarta',
      'startPortId': 6,
      'color': '#818CF8',
      'personality': 'konservatif',
    },
    <String, dynamic>{
      'id': 19,
      'name': 'Panglima Wangkang',
      'startPortId': 3,
      'color': '#64748B',
      'personality': 'konservatif',
    },
    <String, dynamic>{
      'id': 20,
      'name': 'Kapten Raden Patah',
      'startPortId': 1,
      'color': '#94A3B8',
      'personality': 'konservatif',
    },
  ];

  return rawSpecs
      .map((spec) => NpcCaptain.fromJson(spec, ports: ports))
      .toList();
}

/// Engine Simulasi NPC Client-Side (WorldBox Style) yang berjalan seluruhnya di HP (Flutter).
class NpcSimulationEngine extends ChangeNotifier {
  final math.Random _random;
  final bool enableTimerInTest;
  List<MapPortNode> _ports;
  List<NpcCaptain> _captains;
  List<Offset> _npcPositions = <Offset>[];
  Timer? _timer;
  int _elapsedSeconds = 0;
  bool _isPaused = false;
  String _latestNews =
      'Kapten Laksamana Jaya baru saja tiba di Batavia • Sultan Babullah berlayar menuju Malaka';

  NpcSimulationEngine({
    List<NpcCaptain>? captains,
    List<MapPortNode> ports = kNusantaraPortNodes,
    int randomSeed = 42,
    this.enableTimerInTest = false,
  })  : _random = math.Random(randomSeed),
        _ports = ports.isNotEmpty ? ports : kNusantaraPortNodes,
        _captains = captains ?? buildDefaultNpcCaptains(ports: ports) {
    _assignRandomDestinations(initialSpread: true);
    _syncPositions();
  }

  static bool get _isFlutterTest {
    try {
      return const bool.fromEnvironment('FLUTTER_TEST') ||
          Platform.environment.containsKey('FLUTTER_TEST');
    } catch (_) {
      return false;
    }
  }

  List<NpcCaptain> get captains => List<NpcCaptain>.unmodifiable(_captains);

  List<Offset> get npcPositions => List<Offset>.unmodifiable(_npcPositions);

  String get latestNews => _latestNews;

  bool get isPaused => _isPaused;

  bool get isRunning => _timer != null && _timer!.isActive;

  void updateCaptains(
    List<NpcCaptain> newCaptains, {
    List<MapPortNode>? ports,
  }) {
    if (ports != null && ports.isNotEmpty) {
      _ports = ports;
    }
    if (newCaptains.isEmpty) return;
    _captains = newCaptains;
    _assignRandomDestinations(initialSpread: true);
    _syncPositions();
    notifyListeners();
  }

  void updatePorts(List<MapPortNode> ports) {
    if (ports.isEmpty) return;
    _ports = ports;
  }

  /// Memulai simulasi NPC dengan Timer.periodic setiap 2 detik.
  void start() {
    _isPaused = false;
    _timer?.cancel();
    if (_isFlutterTest && !enableTimerInTest) {
      return;
    }
    _timer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (_isPaused) return;
      stepSimulation();
    });
  }

  /// Menjalankan satu langkah simulasi (dipanggil setiap 2 detik oleh Timer.periodic).
  void stepSimulation() {
    _elapsedSeconds += 2;
    if (_elapsedSeconds % 10 == 0) {
      _assignRandomDestinations();
    }
    _moveCaptainsTowardsTargets();
    _syncPositions();
    notifyListeners();
  }

  void _assignRandomDestinations({bool initialSpread = false}) {
    final List<MapPortNode> availablePorts =
        _ports.where((p) => !p.isLocked).toList();
    final List<MapPortNode> candidatePorts =
        availablePorts.isNotEmpty ? availablePorts : _ports;
    if (candidatePorts.isEmpty) return;

    for (int i = 0; i < _captains.length; i++) {
      final NpcCaptain npc = _captains[i];
      final List<MapPortNode> otherPorts =
          candidatePorts.where((p) => p.id != npc.currentPortId).toList();
      final MapPortNode dest = otherPorts.isNotEmpty
          ? otherPorts[_random.nextInt(otherPorts.length)]
          : candidatePorts[_random.nextInt(candidatePorts.length)];

      npc.destinationPortId = dest.id;
      npc.targetX = dest.mapX;
      npc.targetY = dest.mapY;

      if (initialSpread) {
        final double jitterX = ((i % 5) - 2) * 0.0035;
        final double jitterY = ((i ~/ 5) - 2) * 0.0035;
        npc.x = (npc.x + (npc.targetX - npc.x) * 0.25 + jitterX).clamp(0.05, 0.95);
        npc.y = (npc.y + (npc.targetY - npc.y) * 0.25 + jitterY).clamp(0.05, 0.95);
      }
    }
  }

  void _moveCaptainsTowardsTargets() {
    final Map<int, MapPortNode> portById = <int, MapPortNode>{
      for (final p in _ports) p.id: p,
    };

    String? arrivalAnnouncement;
    for (final NpcCaptain npc in _captains) {
      final double dx = npc.targetX - npc.x;
      final double dy = npc.targetY - npc.y;
      final double dist = math.sqrt(dx * dx + dy * dy);
      final double stepFactor =
          npc.personality == 'agresif' ? 0.24 : 0.16;

      if (dist <= 0.004) {
        npc.x = npc.targetX;
        npc.y = npc.targetY;
        if (npc.currentPortId != npc.destinationPortId) {
          npc.currentPortId = npc.destinationPortId;
          final String portName =
              portById[npc.currentPortId]?.name ?? 'Batavia';
          arrivalAnnouncement ??=
              'Kapten ${npc.name} baru saja tiba di $portName';
        }
      } else {
        npc.x += dx * stepFactor;
        npc.y += dy * stepFactor;
      }
    }

    if (arrivalAnnouncement != null) {
      _latestNews = arrivalAnnouncement;
    } else if (_captains.isNotEmpty) {
      final NpcCaptain spot =
          _captains[(_elapsedSeconds ~/ 2) % _captains.length];
      final String destName =
          portById[spot.destinationPortId]?.name ?? 'Batavia';
      _latestNews =
          'Kapten Laksamana Jaya baru saja tiba di Batavia • Kapten ${spot.name} berlayar menuju $destName';
    }
  }

  void _syncPositions() {
    _npcPositions = _captains.map((c) => Offset(c.x, c.y)).toList();
  }

  /// Pause timer NPC saat aplikasi di-background.
  void pause() {
    _isPaused = true;
    _timer?.cancel();
    _timer = null;
  }

  /// Resume timer NPC saat aplikasi kembali ke foreground.
  void resume() {
    if (!_isPaused && isRunning) return;
    start();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _timer = null;
    super.dispose();
  }
}
