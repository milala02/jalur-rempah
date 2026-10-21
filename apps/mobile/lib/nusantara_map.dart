import 'package:flutter/material.dart';

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

  factory MapPortNode.fromJson(Map<String, dynamic> json) {
    final minLv = (json['min_level_required'] as num?)?.toInt() ?? 1;
    return MapPortNode(
      id: (json['id'] as num?)?.toInt() ?? 1,
      code: (json['code'] as String?) ?? 'banda',
      name: (json['name'] as String?) ?? 'Banda',
      countryCode: (json['country_code'] as String?) ?? 'nusantara',
      countryName:
          (json['country_name'] as String?) ?? 'Kepulauan Nusantara',
      relX: (json['map_x'] as num?)?.toDouble() ?? 0.5,
      relY: (json['map_y'] as num?)?.toDouble() ?? 0.5,
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
  final int tier;

  const MapShipMarker({
    required this.id,
    required this.name,
    required this.status,
    required this.portId,
    required this.destPortId,
    this.tier = 1,
  });
}

const List<MapPortNode> kNusantaraPortNodes = <MapPortNode>[
  MapPortNode(
    id: 4,
    code: 'malaka',
    name: 'Malaka',
    countryCode: 'malaka_sultanate',
    countryName: 'Kesultanan Malaka',
    relX: 0.22,
    relY: 0.34,
    minLevelRequired: 1,
    isLocked: false,
  ),
  MapPortNode(
    id: 6,
    code: 'batavia',
    name: 'Batavia',
    countryCode: 'nusantara',
    countryName: 'Kepulauan Nusantara',
    relX: 0.31,
    relY: 0.70,
    minLevelRequired: 1,
    isLocked: false,
  ),
  MapPortNode(
    id: 3,
    code: 'surabaya',
    name: 'Surabaya',
    countryCode: 'nusantara',
    countryName: 'Kepulauan Nusantara',
    relX: 0.45,
    relY: 0.74,
    minLevelRequired: 1,
    isLocked: false,
  ),
  MapPortNode(
    id: 5,
    code: 'makassar',
    name: 'Makassar',
    countryCode: 'nusantara',
    countryName: 'Kepulauan Nusantara',
    relX: 0.59,
    relY: 0.58,
    minLevelRequired: 1,
    isLocked: false,
  ),
  MapPortNode(
    id: 2,
    code: 'ternate',
    name: 'Ternate',
    countryCode: 'nusantara',
    countryName: 'Kepulauan Nusantara',
    relX: 0.76,
    relY: 0.32,
    minLevelRequired: 1,
    isLocked: false,
  ),
  MapPortNode(
    id: 1,
    code: 'banda',
    name: 'Banda',
    countryCode: 'nusantara',
    countryName: 'Kepulauan Nusantara',
    relX: 0.83,
    relY: 0.64,
    minLevelRequired: 1,
    isLocked: false,
  ),
  // 4 Pelabuhan Internasional Baru (Fase 5 — Progressive Unlocking Levels 4..7)
  MapPortNode(
    id: 7,
    code: 'mekkah',
    name: 'Mekkah',
    countryCode: 'arab',
    countryName: 'Arab',
    relX: 0.11,
    relY: 0.24,
    minLevelRequired: 4,
    isLocked: true,
  ),
  MapPortNode(
    id: 8,
    code: 'sakai',
    name: 'Sakai',
    countryCode: 'jepang',
    countryName: 'Jepang',
    relX: 0.91,
    relY: 0.14,
    minLevelRequired: 5,
    isLocked: true,
  ),
  MapPortNode(
    id: 9,
    code: 'lisbon',
    name: 'Lisbon',
    countryCode: 'eropa',
    countryName: 'Eropa',
    relX: 0.05,
    relY: 0.12,
    minLevelRequired: 6,
    isLocked: true,
  ),
  MapPortNode(
    id: 10,
    code: 'kairo',
    name: 'Kairo',
    countryCode: 'mesir',
    countryName: 'Mesir',
    relX: 0.07,
    relY: 0.38,
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
  // Rute Samudra Internasional (Fase 5)
  <int>[4, 7], // Malaka - Mekkah (Arab)
  <int>[7, 10], // Mekkah - Kairo (Mesir)
  <int>[10, 9], // Kairo - Lisbon (Eropa)
  <int>[2, 8], // Ternate - Sakai (Jepang)
];

class NusantaraMapWidget extends StatelessWidget {
  final String selectedPortCode;
  final List<MapPortNode> ports;
  final List<MapShipMarker> ships;
  final Set<int> eventPortIds;
  final ValueChanged<String>? onSelectPort;
  final ValueChanged<MapPortNode>? onLockedPortTap;

  const NusantaraMapWidget({
    super.key,
    required this.selectedPortCode,
    required this.ships,
    this.ports = kNusantaraPortNodes,
    this.eventPortIds = const <int>{},
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
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final activePorts = ports.isNotEmpty ? ports : kNusantaraPortNodes;

    return SizedBox(
      height: 240,
      width: double.infinity,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final w = constraints.maxWidth;
            final h = constraints.maxHeight;
            return GestureDetector(
              onTapUp: (details) {
                final pos = details.localPosition;
                for (final p in activePorts) {
                  final px = p.relX * w;
                  final py = p.relY * h;
                  if ((pos - Offset(px, py)).distance <= 28) {
                    if (p.isLocked) {
                      if (onLockedPortTap != null) {
                        onLockedPortTap!(p);
                      } else {
                        showLockedPortFeedback(context, p);
                      }
                    } else {
                      onSelectPort?.call(p.code);
                    }
                    break;
                  }
                }
              },
              child: CustomPaint(
                key: const Key('nusantara_map_canvas'),
                painter: NusantaraMapPainter(
                  selectedPortCode: selectedPortCode,
                  ports: activePorts,
                  ships: ships,
                  eventPortIds: eventPortIds,
                  isDark: isDark,
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
  final bool isDark;

  NusantaraMapPainter({
    required this.selectedPortCode,
    required this.ports,
    required this.ships,
    required this.eventPortIds,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Latar Samudra Nusantara & Jalur Internasional
    final seaRect = Offset.zero & size;
    final seaGradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: isDark
          ? const <Color>[Color(0xFF0A192F), Color(0xFF112240), Color(0xFF0F2942)]
          : const <Color>[Color(0xFFD6ECFA), Color(0xFFB8E0F6), Color(0xFFA2D2EE)],
    );
    canvas.drawRect(
      seaRect,
      Paint()..shader = seaGradient.createShader(seaRect),
    );

    // 2. Garis Grid Lintang & Bujur Kartografi
    final gridPaint = Paint()
      ..color = isDark ? const Color(0x16FFFFFF) : const Color(0x16004D40)
      ..strokeWidth = 1.0;
    for (int i = 1; i < 6; i++) {
      final gx = (size.width / 6) * i;
      canvas.drawLine(Offset(gx, 0), Offset(gx, size.height), gridPaint);
    }
    for (int j = 1; j < 4; j++) {
      final gy = (size.height / 4) * j;
      canvas.drawLine(Offset(0, gy), Offset(size.width, gy), gridPaint);
    }

    // 3. Siluet Kepulauan Nusantara & Daratan Internasional
    final islandFill = Paint()
      ..color = isDark ? const Color(0xFF2E473B) : const Color(0xFFC8DFA8)
      ..style = PaintingStyle.fill;
    final islandStroke = Paint()
      ..color = isDark ? const Color(0xFF52796F) : const Color(0xFF6B8E4E)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;

    void drawIslandPolygon(List<Offset> relPoints) {
      final path = Path();
      for (int i = 0; i < relPoints.length; i++) {
        final pt = Offset(
          relPoints[i].dx * size.width,
          relPoints[i].dy * size.height,
        );
        if (i == 0) {
          path.moveTo(pt.dx, pt.dy);
        } else {
          path.lineTo(pt.dx, pt.dy);
        }
      }
      path.close();
      canvas.drawPath(path, islandFill);
      canvas.drawPath(path, islandStroke);
    }

    // Sumatera & Semenanjung Malaka
    drawIslandPolygon(const <Offset>[
      Offset(0.14, 0.28),
      Offset(0.19, 0.31),
      Offset(0.26, 0.50),
      Offset(0.28, 0.62),
      Offset(0.22, 0.65),
      Offset(0.15, 0.42),
    ]);
    // Pulau Jawa
    drawIslandPolygon(const <Offset>[
      Offset(0.28, 0.69),
      Offset(0.49, 0.71),
      Offset(0.51, 0.78),
      Offset(0.29, 0.76),
    ]);
    // Pulau Kalimantan
    drawIslandPolygon(const <Offset>[
      Offset(0.35, 0.28),
      Offset(0.48, 0.24),
      Offset(0.51, 0.48),
      Offset(0.37, 0.50),
      Offset(0.32, 0.38),
    ]);
    // Pulau Sulawesi
    drawIslandPolygon(const <Offset>[
      Offset(0.56, 0.32),
      Offset(0.66, 0.30),
      Offset(0.62, 0.46),
      Offset(0.64, 0.60),
      Offset(0.57, 0.62),
      Offset(0.55, 0.44),
    ]);
    // Kepulauan Maluku (Ternate & Banda) & Papua
    drawIslandPolygon(const <Offset>[
      Offset(0.74, 0.26),
      Offset(0.79, 0.28),
      Offset(0.78, 0.40),
      Offset(0.73, 0.36),
    ]);
    drawIslandPolygon(const <Offset>[
      Offset(0.80, 0.58),
      Offset(0.86, 0.60),
      Offset(0.85, 0.68),
      Offset(0.79, 0.66),
    ]);

    // 4. Jalur Pelayaran Nusantara & Samudra (Sea Routes)
    final portById = <int, MapPortNode>{
      for (final p in ports) p.id: p,
    };

    for (final edge in kNusantaraSeaRoutes) {
      final pA = portById[edge[0]];
      final pB = portById[edge[1]];
      if (pA == null || pB == null) continue;
      final isRouteLocked = pA.isLocked || pB.isLocked;
      final routePaint = Paint()
        ..color = isRouteLocked
            ? (isDark ? const Color(0x449E9E9E) : const Color(0x55757575))
            : (isDark ? const Color(0x6BFBBF24) : const Color(0x6B8B4513))
        ..strokeWidth = isRouteLocked ? 1.2 : 1.8
        ..style = PaintingStyle.stroke;

      final start = Offset(pA.relX * size.width, pA.relY * size.height);
      final end = Offset(pB.relX * size.width, pB.relY * size.height);
      canvas.drawLine(start, end, routePaint);
    }

    // 5. Titik Pelabuhan & Ikon Gembok (🔒) untuk Pelabuhan yang Terkunci (is_locked: true)
    for (final p in ports) {
      final center = Offset(p.relX * size.width, p.relY * size.height);
      final isSelected = p.code == selectedPortCode;
      final hasEvent = eventPortIds.contains(p.id);

      if (hasEvent && !p.isLocked) {
        final alertRingPaint = Paint()
          ..color = const Color(0x59FF5252)
          ..style = PaintingStyle.fill;
        canvas.drawCircle(center, 15, alertRingPaint);
      }

      if (isSelected && !p.isLocked) {
        final glowPaint = Paint()
          ..color = const Color(0x59D97706)
          ..style = PaintingStyle.fill;
        canvas.drawCircle(center, 12, glowPaint);
      }

      // Jika is_locked: true, gambar titik pelabuhan dengan warna abu-abu (Colors.grey)
      final dotPaint = Paint()
        ..color = p.isLocked
            ? Colors.grey
            : hasEvent
                ? Colors.redAccent
                : isSelected
                    ? const Color(0xFFD97706)
                    : (isDark
                        ? const Color(0xFF38BDF8)
                        : const Color(0xFF8B4513));
      canvas.drawCircle(center, isSelected ? 6.5 : 5.5, dotPaint);

      final borderPaint = Paint()
        ..color = p.isLocked ? const Color(0xFFE0E0E0) : Colors.white
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke;
      canvas.drawCircle(center, isSelected ? 6.5 : 5.5, borderPaint);

      // Jika is_locked: true, gambar ikon gembok (🔒) tepat di atas titik pelabuhan
      if (p.isLocked) {
        final lockPainter = TextPainter(
          text: const TextSpan(
            text: '🔒',
            style: TextStyle(fontSize: 11),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        lockPainter.paint(
          canvas,
          Offset(center.dx - lockPainter.width / 2, center.dy - 19),
        );
      }

      final labelText =
          p.isLocked ? '${p.name} (Lv.${p.minLevelRequired})' : p.name;
      final tp = TextPainter(
        text: TextSpan(
          text: labelText,
          style: TextStyle(
            color: p.isLocked
                ? Colors.grey
                : (isDark ? Colors.white : const Color(0xFF2B1810)),
            fontSize: isSelected ? 11.0 : 9.8,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      tp.paint(
        canvas,
        Offset(center.dx - tp.width / 2, center.dy + 6),
      );
    }

    // 6. Ikon Kapal Pemain di atas Peta (Bersandar atau Berlayar di Rute)
    for (int idx = 0; idx < ships.length; idx++) {
      final sh = ships[idx];
      final originNode = portById[sh.portId ?? 1] ?? ports.first;
      final destNode = sh.destPortId != null ? portById[sh.destPortId!] : null;

      Offset shipPos;
      if (sh.status == 'sailing' && destNode != null) {
        shipPos = Offset(
          ((originNode.relX + destNode.relX) / 2) * size.width,
          ((originNode.relY + destNode.relY) / 2) * size.height - 6,
        );
      } else {
        final offsetAngle = (idx * 10.0) - 6.0;
        shipPos = Offset(
          originNode.relX * size.width + offsetAngle,
          originNode.relY * size.height - 12,
        );
      }

      final hullPath = Path()
        ..moveTo(shipPos.dx - 8, shipPos.dy)
        ..lineTo(shipPos.dx + 8, shipPos.dy)
        ..lineTo(shipPos.dx + 5, shipPos.dy + 5)
        ..lineTo(shipPos.dx - 5, shipPos.dy + 5)
        ..close();

      final hullPaint = Paint()
        ..color = sh.status == 'sailing'
            ? const Color(0xFFEA580C)
            : const Color(0xFF16A34A);
      canvas.drawPath(hullPath, hullPaint);

      final sailPath = Path()
        ..moveTo(shipPos.dx, shipPos.dy - 9)
        ..lineTo(shipPos.dx + 6, shipPos.dy - 1)
        ..lineTo(shipPos.dx, shipPos.dy - 1)
        ..close();
      canvas.drawPath(
        sailPath,
        Paint()..color = isDark ? const Color(0xFFFEF3C7) : Colors.white,
      );
    }
  }

  @override
  bool shouldRepaint(covariant NusantaraMapPainter oldDelegate) {
    return oldDelegate.selectedPortCode != selectedPortCode ||
        oldDelegate.isDark != isDark ||
        oldDelegate.ports != ports ||
        oldDelegate.ships != ships ||
        oldDelegate.eventPortIds != eventPortIds;
  }
}
