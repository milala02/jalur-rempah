import 'dart:io' show Platform;
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'theme_controller.dart';

/// Mengembalikan path gambar aset peta dunia sesuai pilihan `MapStyle`.
String getMapImagePath(MapStyle style) {
  switch (style) {
    case MapStyle.vintageColor:
      return 'assets/map_vintage_color.png';
    case MapStyle.vintageSepia:
      return 'assets/map_vintage_sepia.png';
    case MapStyle.modern:
      return 'assets/map_modern.png';
  }
}

/// Menentukan `FilterQuality` gambar peta berdasarkan pengaturan `GraphicsQuality`.
FilterQuality getMapFilterQuality(GraphicsQuality quality) {
  switch (quality) {
    case GraphicsQuality.ultra:
    case GraphicsQuality.high:
      return FilterQuality.high;
    case GraphicsQuality.medium:
    case GraphicsQuality.low:
      return FilterQuality.low;
  }
}

/// Rute Pelayaran Legendaris (Jalur Rempah & Jalur Sutra Laut)
const Map<String, List<String>> kLegendarySeaRoutes = <String, List<String>>{
  'jalur_rempah': <String>[
    'banda',
    'batavia',
    'malaka',
    'calicut',
    'mekkah',
    'lisbon',
  ],
  'jalur_sutra_laut': <String>[
    'canton',
    'malaka',
    'calicut',
    'kairo',
  ],
};

class MapPortNode {
  final int id;
  final String code;
  final String name;
  final String countryCode;
  final String countryName;
  final double relX;
  final double relY;
  final int minLevelRequired;
  final bool isLocked;

  const MapPortNode({
    required this.id,
    required this.code,
    required this.name,
    required this.relX,
    required this.relY,
    this.countryCode = 'nusantara',
    this.countryName = 'Kepulauan Nusantara',
    this.minLevelRequired = 1,
    this.isLocked = false,
  });

  /// Alias koordinat X Equirectangular (0.0 - 1.0) sesuai kontrak API `map_x`.
  double get mapX => relX;

  /// Alias koordinat Y Equirectangular (0.0 - 1.0) sesuai kontrak API `map_y`.
  double get mapY => relY;

  factory MapPortNode.fromJson(Map<String, dynamic> json) {
    final minLv = (json['min_level_required'] as num?)?.toInt() ?? 1;
    return MapPortNode(
      id: (json['id'] as num?)?.toInt() ?? 1,
      code: (json['code'] as String?) ?? 'banda',
      name: (json['name'] as String?) ?? 'Banda',
      countryCode: (json['country_code'] as String?) ?? 'nusantara',
      countryName:
          (json['country_name'] as String?) ?? 'Kepulauan Nusantara',
      relX: (json['map_x'] as num?)?.toDouble() ??
          (json['rel_x'] as num?)?.toDouble() ??
          0.5,
      relY: (json['map_y'] as num?)?.toDouble() ??
          (json['rel_y'] as num?)?.toDouble() ??
          0.5,
      minLevelRequired: minLv,
      isLocked: (json['is_locked'] as bool?) ?? (minLv > 1),
    );
  }

  MapPortNode copyWithPlayerLevel(int playerLevel) {
    return MapPortNode(
      id: id,
      code: code,
      name: name,
      countryCode: countryCode,
      countryName: countryName,
      relX: relX,
      relY: relY,
      minLevelRequired: minLevelRequired,
      isLocked: minLevelRequired > playerLevel,
    );
  }
}

class MapShipMarker {
  final int id;
  final String name;
  final String status;
  final int? portId;
  final int? destPortId;
  final int? departTick;
  final int? arriveTick;
  final int tier;

  const MapShipMarker({
    required this.id,
    required this.name,
    required this.status,
    int? portId,
    int? currentPortId,
    int? destPortId,
    int? destinationPortId,
    this.departTick,
    this.arriveTick,
    this.tier = 1,
  })  : portId = portId ?? currentPortId,
        destPortId = destPortId ?? destinationPortId;

  /// ID pelabuhan asal/saat ini (`current_port_id`).
  int? get currentPortId => portId;

  /// ID pelabuhan tujuan (`destination_port_id`).
  int? get destinationPortId => destPortId;

  factory MapShipMarker.fromJson(Map<String, dynamic> json) {
    return MapShipMarker(
      id: (json['id'] as num?)?.toInt() ?? 1,
      name: (json['name'] as String?) ?? 'Kapal Perintis',
      status: (json['status'] as String?) ?? 'docked',
      currentPortId: (json['current_port_id'] as num?)?.toInt() ??
          (json['port_id'] as num?)?.toInt(),
      destinationPortId: (json['destination_port_id'] as num?)?.toInt() ??
          (json['dest_port'] as num?)?.toInt() ??
          (json['dest_port_id'] as num?)?.toInt(),
      departTick: (json['depart_tick'] as num?)?.toInt(),
      arriveTick: (json['arrive_tick'] as num?)?.toInt(),
      tier: (json['tier'] as num?)?.toInt() ?? 1,
    );
  }
}

/// Koordinat Pelabuhan Presisi Proyeksi Equirectangular (0.0 - 1.0)
const List<MapPortNode> kNusantaraPortNodes = <MapPortNode>[
  MapPortNode(
    id: 4,
    code: 'malaka',
    name: 'Malaka',
    countryCode: 'malaka_sultanate',
    countryName: 'Kesultanan Malaka',
    relX: 0.7840,
    relY: 0.4878,
    minLevelRequired: 1,
    isLocked: false,
  ),
  MapPortNode(
    id: 6,
    code: 'batavia',
    name: 'Batavia',
    countryCode: 'nusantara',
    countryName: 'Kepulauan Nusantara',
    relX: 0.7967,
    relY: 0.5343,
    minLevelRequired: 1,
    isLocked: false,
  ),
  MapPortNode(
    id: 3,
    code: 'surabaya',
    name: 'Surabaya',
    countryCode: 'nusantara',
    countryName: 'Kepulauan Nusantara',
    relX: 0.8132,
    relY: 0.5403,
    minLevelRequired: 1,
    isLocked: false,
  ),
  MapPortNode(
    id: 5,
    code: 'makassar',
    name: 'Makassar',
    countryCode: 'nusantara',
    countryName: 'Kepulauan Nusantara',
    relX: 0.8318,
    relY: 0.5286,
    minLevelRequired: 1,
    isLocked: false,
  ),
  MapPortNode(
    id: 2,
    code: 'ternate',
    name: 'Ternate',
    countryCode: 'nusantara',
    countryName: 'Kepulauan Nusantara',
    relX: 0.8538,
    relY: 0.4956,
    minLevelRequired: 1,
    isLocked: false,
  ),
  MapPortNode(
    id: 1,
    code: 'banda',
    name: 'Banda',
    countryCode: 'nusantara',
    countryName: 'Kepulauan Nusantara',
    relX: 0.8608,
    relY: 0.5251,
    minLevelRequired: 1,
    isLocked: false,
  ),
  MapPortNode(
    id: 11,
    code: 'calicut',
    name: 'Calicut',
    countryCode: 'india',
    countryName: 'India (Pantai Malabar)',
    relX: 0.7105,
    relY: 0.4375,
    minLevelRequired: 2,
    isLocked: true,
  ),
  MapPortNode(
    id: 12,
    code: 'canton',
    name: 'Canton',
    countryCode: 'tiongkok',
    countryName: 'Tiongkok (Jalur Sutra Laut)',
    relX: 0.8146,
    relY: 0.3715,
    minLevelRequired: 3,
    isLocked: true,
  ),
  MapPortNode(
    id: 7,
    code: 'mekkah',
    name: 'Mekkah',
    countryCode: 'arab',
    countryName: 'Arab',
    relX: 0.6106,
    relY: 0.3810,
    minLevelRequired: 4,
    isLocked: true,
  ),
  MapPortNode(
    id: 8,
    code: 'sakai',
    name: 'Sakai',
    countryCode: 'jepang',
    countryName: 'Jepang',
    relX: 0.8763,
    relY: 0.3079,
    minLevelRequired: 5,
    isLocked: true,
  ),
  MapPortNode(
    id: 9,
    code: 'lisbon',
    name: 'Lisbon',
    countryCode: 'eropa',
    countryName: 'Eropa',
    relX: 0.4746,
    relY: 0.2849,
    minLevelRequired: 6,
    isLocked: true,
  ),
  MapPortNode(
    id: 10,
    code: 'kairo',
    name: 'Kairo',
    countryCode: 'mesir',
    countryName: 'Mesir',
    relX: 0.5868,
    relY: 0.3331,
    minLevelRequired: 7,
    isLocked: true,
  ),
];

const List<List<int>> kNusantaraSeaRoutes = <List<int>>[
  <int>[4, 6], // Malaka - Batavia
  <int>[6, 3], // Batavia - Surabaya
  <int>[6, 5], // Batavia - Makassar
  <int>[3, 5], // Surabaya - Makassar
  <int>[5, 2], // Makassar - Ternate
  <int>[5, 1], // Makassar - Banda
  <int>[2, 1], // Ternate - Banda
  // Rute Samudra Internasional
  <int>[4, 11], // Malaka - Calicut
  <int>[11, 7], // Calicut - Mekkah
  <int>[7, 10], // Mekkah - Kairo
  <int>[10, 9], // Kairo - Lisbon
  <int>[4, 12], // Malaka - Canton
  <int>[12, 8], // Canton - Sakai
  <int>[2, 8], // Ternate - Sakai
];

/// CustomPainter untuk menggambar 3 lapis animasi ombak laut yang bergeser secara horizontal.
class OceanWavesPainter extends CustomPainter {
  final double animationValue;
  final GraphicsQuality graphicsQuality;

  OceanWavesPainter({
    required this.animationValue,
    this.graphicsQuality = GraphicsQuality.high,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final int waveLayers = graphicsQuality == GraphicsQuality.medium ? 2 : 3;
    final double phase = animationValue * 2 * math.pi;

    for (int layer = 0; layer < waveLayers; layer++) {
      final Paint wavePaint = Paint()
        ..isAntiAlias = true
        // ignore: deprecated_member_use
        ..color = Colors.blue.withOpacity(0.30 - (layer * 0.06))
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6 - (layer * 0.25)
        ..strokeCap = StrokeCap.round;

      final Path wavePath = Path();
      final double baseY = size.height * (0.28 + layer * 0.24);
      final double amplitude = 4.5 + (layer * 1.8);
      final double wavelength = size.width / (3.0 + layer);
      final double layerPhase = phase + (layer * 1.35);

      for (double x = 0; x <= size.width; x += 8.0) {
        final double y = baseY +
            math.sin((x / wavelength) * 2 * math.pi + layerPhase) * amplitude +
            math.cos((x / (wavelength * 0.6)) * math.pi - layerPhase) *
                (amplitude * 0.35);
        if (x == 0) {
          wavePath.moveTo(x, y);
        } else {
          wavePath.lineTo(x, y);
        }
      }

      canvas.drawPath(wavePath, wavePaint);
    }
  }

  @override
  bool shouldRepaint(covariant OceanWavesPainter oldDelegate) {
    return oldDelegate.animationValue != animationValue ||
        oldDelegate.graphicsQuality != graphicsQuality;
  }
}

class NusantaraMapWidget extends StatefulWidget {
  final String selectedPortCode;
  final List<MapPortNode> ports;
  final List<MapShipMarker> ships;
  final Set<int> eventPortIds;
  final int currentTick;
  final double height;
  final ValueChanged<String>? onSelectPort;
  final ValueChanged<MapPortNode>? onLockedPortTap;

  const NusantaraMapWidget({
    super.key,
    required this.selectedPortCode,
    required this.ships,
    this.ports = kNusantaraPortNodes,
    this.eventPortIds = const <int>{},
    this.currentTick = 100,
    this.height = 260,
    this.onSelectPort,
    this.onLockedPortTap,
  });

  static void showLockedPortFeedback(BuildContext context, MapPortNode port) {
    final msg =
        'Pelabuhan ${port.name} terkunci. Butuh Level ${port.minLevelRequired} untuk membuka.';
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          key: Key('locked_port_snackbar_${port.code}'),
          content: Text('🔒 $msg'),
        ),
      );
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        key: const Key('locked_port_dialog'),
        title: Text('🔒 Pelabuhan ${port.name} Terkunci'),
        content: Text(msg),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Mengerti'),
          ),
        ],
      ),
    );
  }

  @override
  State<NusantaraMapWidget> createState() => _NusantaraMapWidgetState();
}

class _NusantaraMapWidgetState extends State<NusantaraMapWidget>
    with TickerProviderStateMixin {
  late final AnimationController _tickController;
  late final AnimationController _wavesController;
  late double _fromTick;
  late double _toTick;
  Offset _parallaxOffset = Offset.zero;

  static bool get _isFlutterTest {
    try {
      return const bool.fromEnvironment('FLUTTER_TEST') ||
          Platform.environment.containsKey('FLUTTER_TEST');
    } catch (_) {
      return false;
    }
  }

  @override
  void initState() {
    super.initState();
    _fromTick = widget.currentTick.toDouble();
    _toTick = widget.currentTick.toDouble();
    _tickController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );
    _wavesController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 7),
    );
    if (!_isFlutterTest) {
      _wavesController.repeat();
    } else {
      _wavesController.value = 0.35;
    }
  }

  @override
  void didUpdateWidget(covariant NusantaraMapWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentTick != widget.currentTick) {
      _fromTick = _currentAnimatedTick;
      _toTick = widget.currentTick.toDouble();
      _tickController.forward(from: 0.0);
    }
  }

  double get _currentAnimatedTick {
    if (!_tickController.isAnimating) {
      return _toTick;
    }
    final t = Curves.easeOutCubic.transform(_tickController.value);
    return _fromTick + (_toTick - _fromTick) * t;
  }

  @override
  void dispose() {
    _tickController.dispose();
    _wavesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    ThemeController? themeController;
    try {
      themeController = Provider.of<ThemeController>(context);
    } catch (_) {
      themeController = null;
    }
    final mapStyle = themeController?.mapStyle ?? MapStyle.vintageColor;
    final graphicsQuality =
        themeController?.graphicsQuality ?? GraphicsQuality.high;
    final mapImagePath = getMapImagePath(mapStyle);
    final filterQuality = getMapFilterQuality(graphicsQuality);
    final isUltra = graphicsQuality == GraphicsQuality.ultra;
    final isLow = graphicsQuality == GraphicsQuality.low;

    if (isLow && _wavesController.isAnimating) {
      _wavesController.stop();
    } else if (!isLow && !_wavesController.isAnimating && !_isFlutterTest) {
      _wavesController.repeat();
    }

    final activePorts =
        widget.ports.isNotEmpty ? widget.ports : kNusantaraPortNodes;
    final bool isNight = widget.currentTick > 500;

    return Container(
      height: widget.height,
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFF3E2723),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFFFFD700),
          width: 2.0,
        ),
        boxShadow: <BoxShadow>[
          const BoxShadow(
            color: Color(0xBB000000),
            blurRadius: 12,
            offset: Offset(0, 6),
          ),
          if (isUltra)
            const BoxShadow(
              color: Color(0x55FFD700),
              blurRadius: 18,
              spreadRadius: 1,
            ),
        ],
      ),
      padding: const EdgeInsets.all(4),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final w = constraints.maxWidth;
            final h = constraints.maxHeight;
            return InteractiveViewer(
              minScale: 1.0,
              maxScale: 5.0,
              onInteractionUpdate: (details) {
                if (isUltra) {
                  setState(() {
                    _parallaxOffset = Offset(
                      (_parallaxOffset.dx + details.focalPointDelta.dx * 0.15)
                          .clamp(-14.0, 14.0),
                      (_parallaxOffset.dy + details.focalPointDelta.dy * 0.15)
                          .clamp(-10.0, 10.0),
                    );
                  });
                }
              },
              child: SizedBox(
                width: w,
                height: h,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // 1. Latar Belakang Gambar Peta dengan FilterQuality Adaptif & Efek Parallax (Ultra)
                    Transform.translate(
                      offset: isUltra ? _parallaxOffset : Offset.zero,
                      child: Image.asset(
                        mapImagePath,
                        key: Key('map_background_image_${mapStyle.name}'),
                        fit: BoxFit.cover,
                        filterQuality: filterQuality,
                        width: w,
                        height: h,
                        errorBuilder: (ctx, err, stack) {
                          return DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: mapStyle == MapStyle.vintageSepia
                                    ? const <Color>[
                                        Color(0xFF3E2723),
                                        Color(0xFF4E342E),
                                        Color(0xFF281815),
                                      ]
                                    : mapStyle == MapStyle.modern
                                        ? const <Color>[
                                            Color(0xFF0D47A1),
                                            Color(0xFF1565C0),
                                            Color(0xFF0A2E6E),
                                          ]
                                        : const <Color>[
                                            Color(0xFF061026),
                                            Color(0xFF0B1B3D),
                                            Color(0xFF132C5C),
                                          ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    // 2. Layer Animasi Ombak Laut (OceanWavesPainter):
                    //    Tepat di atas map_bg, di bawah ikon pelabuhan & kapal. Dimatikan jika Low.
                    if (!isLow)
                      IgnorePointer(
                        child: AnimatedBuilder(
                          animation: _wavesController,
                          builder: (context, _) {
                            return CustomPaint(
                              key: const Key('ocean_waves_canvas'),
                              size: Size(w, h),
                              painter: OceanWavesPainter(
                                animationValue: _wavesController.value,
                                graphicsQuality: graphicsQuality,
                              ),
                            );
                          },
                        ),
                      ),
                    // 3. Overlay Atmosfer Dinamis (Day/Night Cycle) saat malam (currentTick > 500)
                    if (isNight)
                      IgnorePointer(
                        child: Container(
                          key: const Key('map_night_overlay'),
                          // ignore: deprecated_member_use
                          color: Colors.black.withOpacity(0.4),
                        ),
                      ),
                    // 4. Layer Rute Legendaris, Pelabuhan, dan Kapal Pemain
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapUp: (details) {
                        final pos = details.localPosition;
                        MapPortNode? tappedPort;
                        double minDistance = 28.0;
                        for (final p in activePorts) {
                          final px = p.mapX * w;
                          final py = p.mapY * h;
                          final dist = (pos - Offset(px, py)).distance;
                          if (dist <= minDistance) {
                            minDistance = dist;
                            tappedPort = p;
                          }
                        }
                        if (tappedPort != null) {
                          if (tappedPort.isLocked) {
                            if (widget.onLockedPortTap != null) {
                              widget.onLockedPortTap!(tappedPort);
                            } else {
                              NusantaraMapWidget.showLockedPortFeedback(
                                context,
                                tappedPort,
                              );
                            }
                          } else {
                            widget.onSelectPort?.call(tappedPort.code);
                          }
                        }
                      },
                      child: AnimatedBuilder(
                        animation: _tickController,
                        builder: (context, _) {
                          return CustomPaint(
                            key: const Key('nusantara_map_canvas'),
                            size: Size(w, h),
                            painter: NusantaraMapPainter(
                              selectedPortCode: widget.selectedPortCode,
                              ports: activePorts,
                              ships: widget.ships,
                              eventPortIds: widget.eventPortIds,
                              currentTick: _currentAnimatedTick,
                              mapStyle: mapStyle,
                              graphicsQuality: graphicsQuality,
                              isNight: isNight,
                              isDark: isDark,
                            ),
                          );
                        },
                      ),
                    ),
                    // 5. Indikator Waktu (Matahari / Bulan) di Pojok Peta
                    Positioned(
                      top: 8,
                      right: 8,
                      child: IgnorePointer(
                        child: Container(
                          key: const Key('map_day_night_badge'),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xCC1E120E),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: isNight
                                  ? const Color(0xFF93C5FD)
                                  : const Color(0xFFFFD700),
                              width: 1.1,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                isNight
                                    ? Icons.nightlight_round
                                    : Icons.wb_sunny_rounded,
                                size: 14,
                                color: isNight
                                    ? const Color(0xFF93C5FD)
                                    : const Color(0xFFFFD700),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                isNight ? 'Malam' : 'Siang',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.bold,
                                  color: isNight
                                      ? const Color(0xFFDBEAFE)
                                      : const Color(0xFFF5DEB3),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class NusantaraMapPainter extends CustomPainter {
  final String selectedPortCode;
  final List<MapPortNode> ports;
  final List<MapShipMarker> ships;
  final Set<int> eventPortIds;
  final double currentTick;
  final MapStyle mapStyle;
  final GraphicsQuality graphicsQuality;
  final bool isNight;
  final bool isDark;

  NusantaraMapPainter({
    required this.selectedPortCode,
    required this.ports,
    required this.ships,
    required this.eventPortIds,
    this.currentTick = 100.0,
    this.mapStyle = MapStyle.vintageColor,
    this.graphicsQuality = GraphicsQuality.high,
    this.isNight = false,
    required this.isDark,
  });

  /// Menggambar garis rute putus-putus (dashed line) di antara dua koordinat pelabuhan.
  void _drawDashedRouteLine(
    Canvas canvas,
    Offset start,
    Offset end,
    Paint paint, {
    double dashWidth = 5.5,
    double dashSpace = 3.5,
  }) {
    final dx = end.dx - start.dx;
    final dy = end.dy - start.dy;
    final distance = math.sqrt(dx * dx + dy * dy);
    if (distance <= 0.0) return;
    final ux = dx / distance;
    final uy = dy / distance;

    double currentDist = 0.0;
    while (currentDist < distance) {
      final nextDist = math.min(currentDist + dashWidth, distance);
      canvas.drawLine(
        Offset(start.dx + ux * currentDist, start.dy + uy * currentDist),
        Offset(start.dx + ux * nextDist, start.dy + uy * nextDist),
        paint,
      );
      currentDist += dashWidth + dashSpace;
    }
  }

  /// Menggambar Jalur Pelayaran Legendaris (`jalur_rempah` & `jalur_sutra_laut`)
  /// secara berurutan menggunakan garis putus-putus berwarna emas transparan.
  void _drawLegendaryRoutes(
    Canvas canvas,
    Size size,
    Map<String, MapPortNode> portByCode,
  ) {
    final glowPaint = Paint()
      ..isAntiAlias = true
      ..color = const Color(0x38FFD700)
      ..strokeWidth = 3.6
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final rempahDashPaint = Paint()
      ..isAntiAlias = true
      ..color = const Color(0xBBFFD700)
      ..strokeWidth = 1.9
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final sutraDashPaint = Paint()
      ..isAntiAlias = true
      ..color = const Color(0x99FFE082)
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    kLegendarySeaRoutes.forEach((routeCode, portSequence) {
      final isRempah = routeCode == 'jalur_rempah';
      final dashPaint = isRempah ? rempahDashPaint : sutraDashPaint;

      for (int i = 0; i < portSequence.length - 1; i++) {
        final fromPort = portByCode[portSequence[i]];
        final toPort = portByCode[portSequence[i + 1]];
        if (fromPort == null || toPort == null) continue;

        final start = Offset(
          fromPort.mapX * size.width,
          fromPort.mapY * size.height,
        );
        final end = Offset(
          toPort.mapX * size.width,
          toPort.mapY * size.height,
        );

        canvas.drawLine(start, end, glowPaint);
        _drawDashedRouteLine(
          canvas,
          start,
          end,
          dashPaint,
          dashWidth: isRempah ? 6.0 : 4.5,
          dashSpace: 3.5,
        );
      }
    });
  }

  @override
  void paint(Canvas canvas, Size size) {
    final seaRect = Offset.zero & size;
    final bool isUltra = graphicsQuality == GraphicsQuality.ultra;

    // 1. Vignette halus di atas gambar peta agar titik pelabuhan & jalur emas tampak menyala
    final vignetteGradient = RadialGradient(
      center: Alignment.center,
      radius: 0.98,
      colors: const <Color>[
        Color(0x10000000),
        Color(0x55040A18),
      ],
      stops: const <double>[0.55, 1.0],
    );
    canvas.drawRect(
      seaRect,
      Paint()
        ..isAntiAlias = true
        ..shader = vignetteGradient.createShader(seaRect),
    );

    // 2. Indeks Pelabuhan berdasarkan kode dan ID
    final portById = <int, MapPortNode>{
      for (final p in kNusantaraPortNodes) p.id: p,
      for (final p in ports) p.id: p,
    };
    final portByCode = <String, MapPortNode>{
      for (final p in kNusantaraPortNodes) p.code: p,
      for (final p in ports) p.code: p,
    };

    // 3. Gambar Garis Rute Legendaris (`jalur_rempah` & `jalur_sutra_laut`)
    _drawLegendaryRoutes(canvas, size, portByCode);

    // 4. Gambar Rute Lokal Kepulauan Nusantara
    for (final edge in kNusantaraSeaRoutes) {
      final pA = portById[edge[0]];
      final pB = portById[edge[1]];
      if (pA == null || pB == null) continue;
      final isRouteLocked = pA.isLocked || pB.isLocked;

      final start = Offset(pA.mapX * size.width, pA.mapY * size.height);
      final end = Offset(pB.mapX * size.width, pB.mapY * size.height);

      final routePaint = Paint()
        ..isAntiAlias = true
        ..color = isRouteLocked
            ? const Color(0x44D7BA89)
            : const Color(0x88FFD700)
        ..strokeWidth = isRouteLocked ? 1.0 : 1.4
        ..style = PaintingStyle.stroke;

      _drawDashedRouteLine(
        canvas,
        start,
        end,
        routePaint,
        dashWidth: 4.5,
        dashSpace: 3.5,
      );
    }

    // 5. Titik Pelabuhan & Ikon Gembok (🔒) pada Koordinat Presisi Equirectangular
    final displayPorts = portByCode.values.toList();
    for (final p in displayPorts) {
      final center = Offset(p.mapX * size.width, p.mapY * size.height);
      final isSelected = p.code == selectedPortCode;
      final hasEvent = eventPortIds.contains(p.id);

      if (hasEvent && !p.isLocked) {
        final alertRingPaint = Paint()
          ..isAntiAlias = true
          ..color = const Color(0x66EF4444)
          ..style = PaintingStyle.fill;
        canvas.drawCircle(center, 14, alertRingPaint);
      }

      if (isSelected && !p.isLocked) {
        final glowPaint = Paint()
          ..isAntiAlias = true
          ..color = const Color(0x66FFD700)
          ..style = PaintingStyle.fill;
        canvas.drawCircle(center, 12, glowPaint);
        final outerRingPaint = Paint()
          ..isAntiAlias = true
          ..color = const Color(0xFFFFD700)
          ..strokeWidth = 1.4
          ..style = PaintingStyle.stroke;
        canvas.drawCircle(center, 8.5, outerRingPaint);
      }

      final dotPaint = Paint()
        ..isAntiAlias = true
        ..color = p.isLocked
            ? const Color(0xFF78716C)
            : hasEvent
                ? const Color(0xFFEF4444)
                : isSelected
                    ? const Color(0xFFFFD700)
                    : const Color(0xFFF5DEB3);
      canvas.drawCircle(center, isSelected ? 5.8 : 4.5, dotPaint);

      final borderPaint = Paint()
        ..isAntiAlias = true
        ..color = p.isLocked
            ? const Color(0xFFBDBDBD)
            : const Color(0xFF3E2723)
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke;
      canvas.drawCircle(center, isSelected ? 5.8 : 4.5, borderPaint);

      if (p.isLocked) {
        final lockPainter = TextPainter(
          text: const TextSpan(
            text: '🔒',
            style: TextStyle(fontSize: 9.5),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        lockPainter.paint(
          canvas,
          Offset(center.dx - lockPainter.width / 2, center.dy - 16),
        );
      }

      final labelText =
          p.isLocked ? '${p.name} (Lv.${p.minLevelRequired})' : p.name;
      final tp = TextPainter(
        text: TextSpan(
          text: labelText,
          style: TextStyle(
            color: p.isLocked
                ? const Color(0xFFD6CEC2)
                : (isSelected
                    ? const Color(0xFFFFD700)
                    : const Color(0xFFF5DEB3)),
            fontSize: isSelected ? 10.2 : 8.6,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
            shadows: const <Shadow>[
              Shadow(
                color: Color(0xEE000000),
                blurRadius: 3,
                offset: Offset(1, 1),
              ),
            ],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      final labelRect = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(center.dx, center.dy + 10),
          width: tp.width + 6,
          height: tp.height + 2,
        ),
        const Radius.circular(3.5),
      );
      canvas.drawRRect(
        labelRect,
        Paint()
          ..isAntiAlias = true
          ..color = const Color(0xAA1E120E),
      );

      tp.paint(
        canvas,
        Offset(center.dx - tp.width / 2, center.dy + 10 - tp.height / 2),
      );
    }

    // 6. Logika Pergerakan Kapal (Interpolasi Linear Menggunakan map_x & map_y Asli API)
    for (int idx = 0; idx < ships.length; idx++) {
      final sh = ships[idx];
      final originPortId = sh.currentPortId ?? sh.portId ?? 1;
      final originNode = portById[originPortId] ?? displayPorts.first;
      final targetPortId = sh.destinationPortId ?? sh.destPortId;
      final destNode = targetPortId != null ? portById[targetPortId] : null;

      final double startX = originNode.mapX * size.width;
      final double startY = originNode.mapY * size.height;

      double currentX = startX;
      double currentY = startY;
      double rotationAngle = 0.0;
      bool isSailing = false;

      if (sh.status == 'sailing' && destNode != null) {
        isSailing = true;
        final double endX = destNode.mapX * size.width;
        final double endY = destNode.mapY * size.height;

        double progress = 0.5;
        final int? depTick = sh.departTick;
        final int? arrTick = sh.arriveTick;

        if (depTick != null && arrTick != null && arrTick > depTick) {
          progress = ((currentTick - depTick) / (arrTick - depTick))
              .clamp(0.0, 1.0);
        } else if (arrTick != null) {
          final estDepart = arrTick - 10;
          progress = ((currentTick - estDepart) / 10.0).clamp(0.0, 1.0);
        }

        currentX = startX + (endX - startX) * progress;
        currentY = startY + (endY - startY) * progress;
        rotationAngle = math.atan2(endY - startY, endX - startX);

        final wakePaint = Paint()
          ..isAntiAlias = true
          ..color = isNight
              ? const Color(0x7793C5FD)
              : const Color(0xCCFFD700)
          ..strokeWidth = 2.0
          ..style = PaintingStyle.stroke;
        canvas.drawLine(
          Offset(startX, startY),
          Offset(currentX, currentY),
          wakePaint,
        );
      } else {
        final double multiShipOffset = idx == 0 ? 0.0 : ((idx * 8.0) - 4.0);
        currentX = startX + multiShipOffset;
        currentY = startY;
      }

      final shipOffset = Offset(currentX, currentY);

      // Efek Glow (cahaya) ekstra pada ikon kapal jika kualitas grafis di-set Ultra
      if (isUltra) {
        canvas.drawCircle(
          shipOffset,
          17.0,
          Paint()
            ..isAntiAlias = true
            ..color = const Color(0x66FFD700)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7.0),
        );
      }

      canvas.drawCircle(
        shipOffset,
        10.0,
        Paint()
          ..isAntiAlias = true
          ..color = isNight
              ? const Color(0x3394A3B8)
              : (isSailing
                  ? const Color(0x55FFD700)
                  : const Color(0x4434D399)),
      );
      canvas.drawCircle(
        shipOffset,
        10.0,
        Paint()
          ..isAntiAlias = true
          ..color = isNight
              ? const Color(0x8894A3B8)
              : const Color(0xCCFFD700)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.1,
      );

      canvas.save();
      canvas.translate(currentX, currentY);
      if (isSailing) {
        if (rotationAngle.abs() > math.pi / 2) {
          canvas.rotate(rotationAngle - math.pi);
          canvas.scale(-1.0, 1.0);
        } else {
          canvas.rotate(rotationAngle);
        }
      }

      final shipEmojiPainter = TextPainter(
        text: TextSpan(
          text: '⛵',
          style: TextStyle(
            fontSize: 15,
            color: isNight ? const Color(0xB3CBD5E1) : null,
            shadows: <Shadow>[
              const Shadow(
                color: Colors.black,
                blurRadius: 4,
                offset: Offset(0, 1),
              ),
              if (isUltra)
                const Shadow(
                  color: Color(0xFFFFD700),
                  blurRadius: 10,
                ),
            ],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      shipEmojiPainter.paint(
        canvas,
        Offset(-shipEmojiPainter.width / 2, -shipEmojiPainter.height / 2),
      );
      canvas.restore();
    }

    // 7. Bingkai Peta Dalam Beraksen Emas Tipis
    final innerFramePaint = Paint()
      ..isAntiAlias = true
      ..color = const Color(0x77FFD700)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;
    canvas.drawRect(
      Rect.fromLTWH(3, 3, size.width - 6, size.height - 6),
      innerFramePaint,
    );
  }

  @override
  bool shouldRepaint(covariant NusantaraMapPainter oldDelegate) {
    return oldDelegate.selectedPortCode != selectedPortCode ||
        oldDelegate.isDark != isDark ||
        oldDelegate.isNight != isNight ||
        oldDelegate.mapStyle != mapStyle ||
        oldDelegate.graphicsQuality != graphicsQuality ||
        oldDelegate.currentTick != currentTick ||
        oldDelegate.ports != ports ||
        oldDelegate.ships != ships ||
        oldDelegate.eventPortIds != eventPortIds;
  }
}