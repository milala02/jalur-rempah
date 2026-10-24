import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'audio_manager.dart';
import 'catalog_models.dart';
import 'npc_engine.dart';
import 'nusantara_map.dart';
import 'syntax_highlight_controller.dart';
import 'theme_controller.dart';

export 'audio_manager.dart';
export 'catalog_models.dart';
export 'npc_engine.dart';
export 'nusantara_map.dart';
export 'syntax_highlight_controller.dart';
export 'theme_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final themeController = ThemeController();
  await themeController.loadPreferences();
  runApp(
    JalurRempahApp(
      themeController: themeController,
    ),
  );
}

// ============================================================================
// 0. Komponen UI Kustom Bertema "Vintage Maritim / Peta Kuno / Papan Kayu"
// ============================================================================

final NumberFormat _kCoinNumberFormat = NumberFormat.decimalPattern('id_ID');

String formatMaritimeCoins(int amount) => _kCoinNumberFormat.format(amount);

/// Kartu bergaya papan pengumuman kayu gelap (#3E2723), border emas tipis (#FFD700),
/// dan bayangan kedalaman (drop shadow).
class MaritimeWoodCard extends StatelessWidget {
  final Widget child;
  final Color? color;
  final EdgeInsetsGeometry? margin;
  final EdgeInsetsGeometry? padding;
  final Color? borderColor;
  final double borderRadius;

  const MaritimeWoodCard({
    super.key,
    required this.child,
    this.color,
    this.margin,
    this.padding,
    this.borderColor,
    this.borderRadius = 12.0,
  });

  @override
  Widget build(BuildContext context) {
    final bool isCustomAlert = color != null;
    final Color effectiveBgTop = isCustomAlert
        ? Color.lerp(color!, MaritimePalette.darkWoodBrown, 0.72)!
        : MaritimePalette.darkWoodBrown;
    final Color effectiveBgBottom = isCustomAlert
        ? Color.lerp(color!, MaritimePalette.carvedMahogany, 0.82)!
        : MaritimePalette.carvedMahogany;

    return Container(
      margin: margin ?? const EdgeInsets.symmetric(vertical: 6.0),
      padding: padding,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            effectiveBgTop,
            MaritimePalette.weatheredTeak,
            effectiveBgBottom,
          ],
          stops: const <double>[0.0, 0.48, 1.0],
        ),
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(
          color: borderColor ?? const Color(0xBBFFD700),
          width: 1.25,
        ),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0xAA000000),
            blurRadius: 8,
            spreadRadius: 0.5,
            offset: Offset(0, 4),
          ),
          BoxShadow(
            color: Color(0x24FFD700),
            blurRadius: 2,
            offset: Offset(0, -1),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(borderRadius),
        child: child,
      ),
    ).animate().slideY(
          begin: 0.5,
          end: 0,
          duration: 320.ms,
          curve: Curves.easeOutCubic,
        );
  }
}

/// Widget Marquee (teks berjalan) sederhana untuk Ticker Berita Dunia di bawah AppBar Tab Pasar.
class WorldNewsMarquee extends StatefulWidget {
  final String text;

  const WorldNewsMarquee({
    super.key,
    required this.text,
  });

  @override
  State<WorldNewsMarquee> createState() => _WorldNewsMarqueeState();
}

class _WorldNewsMarqueeState extends State<WorldNewsMarquee>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

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
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 14),
    );
    if (!_isFlutterTest) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        key: const Key('world_news_marquee'),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(
          color: const Color(0xFF281815),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0x88FFD700), width: 1.0),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.campaign_outlined,
              size: 14,
              color: MaritimePalette.gold,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: ClipRect(
                child: AnimatedBuilder(
                  animation: _controller,
                  builder: (context, child) {
                    final double dx = _isFlutterTest
                        ? 0.0
                        : (0.25 - (_controller.value * 0.5)) * 120.0;
                    return Transform.translate(
                      offset: Offset(dx, 0),
                      child: child,
                    );
                  },
                  child: Text(
                    widget.text,
                    key: const Key('world_news_marquee_text'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: MaritimePalette.parchment,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Penghitung koin animasi dengan TweenAnimationBuilder agar angka berjalan naik/turun.
class AnimatedCoinCounter extends StatelessWidget {
  final int coins;
  final TextStyle? style;
  final String prefix;
  final String suffix;

  const AnimatedCoinCounter({
    super.key,
    required this.coins,
    this.style,
    this.prefix = '💰 ',
    this.suffix = '',
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: coins.toDouble()),
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeOutCubic,
      builder: (context, animatedValue, _) {
        final displayInt = animatedValue.round();
        return Text(
          '$prefix${formatMaritimeCoins(displayInt)}$suffix',
          style: style ??
              MaritimePalette.cinzel(
                color: MaritimePalette.gold,
                fontSize: 13.5,
                fontWeight: FontWeight.bold,
              ),
        );
      },
    );
  }
}

/// Transisi layar kustom bergaya video game (kombinasi FadeTransition & SlideTransition dari bawah ke atas).
class GamePageRoute<T> extends PageRouteBuilder<T> {
  final Widget page;

  GamePageRoute({required this.page, super.settings})
      : super(
          transitionDuration: const Duration(milliseconds: 350),
          reverseTransitionDuration: const Duration(milliseconds: 280),
          pageBuilder: (context, animation, secondaryAnimation) => page,
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            final curved = CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
            );
            final slideAnimation = Tween<Offset>(
              begin: const Offset(0.0, 0.18),
              end: Offset.zero,
            ).animate(curved);
            return FadeTransition(
              opacity: curved,
              child: SlideTransition(
                position: slideAnimation,
                child: child,
              ),
            );
          },
        );
}

/// Teks hadiah melayang (+150 emas) atau kerusakan pertempuran (-35 HP merah bergetar) dengan flutter_animate.
class FloatingRewardText extends StatelessWidget {
  final String text;
  final bool isDamage;

  const FloatingRewardText({
    super.key,
    required this.text,
    this.isDamage = false,
  });

  @override
  Widget build(BuildContext context) {
    final badge = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isDamage ? const Color(0xDD7F1D1D) : const Color(0xDD281815),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDamage ? const Color(0xFFF87171) : MaritimePalette.gold,
          width: 1.3,
        ),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Colors.black87,
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            isDamage ? '💥 ' : '✨ ',
            style: const TextStyle(fontSize: 11.5),
          ),
          Text(
            text,
            style: MaritimePalette.cinzel(
              color: isDamage
                  ? const Color(0xFFFCA5A5)
                  : MaritimePalette.gold,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );

    if (isDamage) {
      return badge
          .animate()
          .shake(duration: 450.ms, hz: 6)
          .slideY(begin: 0.15, end: -0.2, duration: 500.ms);
    }
    return badge
        .animate()
        .scale(
          begin: const Offset(0.85, 0.85),
          end: const Offset(1.0, 1.0),
          duration: 280.ms,
        )
        .slideY(begin: 0.3, end: -0.4, duration: 550.ms)
        .fadeOut(delay: 900.ms, duration: 400.ms);
  }
}

/// Indikator loading bergaya kemudi kapal yang berputar menggunakan flutter_animate().rotate().
class GameLoadingIndicator extends StatelessWidget {
  final double size;
  final String? label;

  const GameLoadingIndicator({
    super.key,
    this.size = 28.0,
    this.label,
  });

  @override
  Widget build(BuildContext context) {
    final wheel = Icon(
      Icons.settings,
      size: size,
      color: MaritimePalette.gold,
    ).animate().rotate(
          duration: 900.ms,
          begin: 0.0,
          end: 1.0,
          curve: Curves.easeInOut,
        );
    if (label == null) {
      return wheel;
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        wheel,
        const SizedBox(height: 8),
        Text(
          label!,
          style: MaritimePalette.cinzel(
            color: MaritimePalette.gold,
            fontSize: 13,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}

/// Bar navigasi bawah bergaya papan kayu kapal dengan ikon emas (#FFD700) saat aktif.
class WoodenBottomNavBar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  const WoodenBottomNavBar({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  static const List<_WoodenNavItemSpec> _items = <_WoodenNavItemSpec>[
    _WoodenNavItemSpec(
      key: Key('nav_market'),
      icon: Icons.anchor,
      activeEmoji: '⚓',
      label: 'Pasar',
    ),
    _WoodenNavItemSpec(
      key: Key('nav_bursa'),
      icon: Icons.balance,
      activeEmoji: '💰',
      label: 'Bursa',
    ),
    _WoodenNavItemSpec(
      key: Key('nav_rules'),
      icon: Icons.auto_stories_outlined,
      activeEmoji: '📜',
      label: 'Aturan',
    ),
    _WoodenNavItemSpec(
      key: Key('nav_ship'),
      icon: Icons.sailing,
      activeEmoji: '⛵',
      label: 'Kapal & Log',
    ),
    _WoodenNavItemSpec(
      key: Key('nav_leaderboard'),
      icon: Icons.emoji_events_outlined,
      activeEmoji: '👑',
      label: 'Peringkat',
    ),
    _WoodenNavItemSpec(
      key: Key('nav_guild'),
      icon: Icons.shield_outlined,
      activeEmoji: '🛡️',
      label: 'Aliansi',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('game_hud_bottom_nav_bar'),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            Color(0xFF2C1B10),
            Color(0xFF1A0F08),
          ],
        ),
        border: Border(
          top: BorderSide(
            color: Color(0xFFFFD700),
            width: 1.5,
          ),
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Color(0xDD000000),
            blurRadius: 12,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: List<Widget>.generate(_items.length, (idx) {
              final item = _items[idx];
              final isSelected = idx == selectedIndex;
              return Expanded(
                child: InkWell(
                  key: item.key,
                  borderRadius: BorderRadius.circular(10),
                  onTap: () {
                    HapticFeedback.lightImpact();
                    AudioManager().playSfx('click');
                    onDestinationSelected(idx);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(
                      vertical: 6,
                      horizontal: 2,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? const Color(0x28FFD700)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                      border: isSelected
                          ? Border.all(
                              color: const Color(0x99FFD700),
                              width: 1.0,
                            )
                          : null,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          item.icon,
                          size: 22,
                          color: isSelected
                              ? const Color(0xFFFFD700)
                              : const Color(0xFF8E8E93),
                          shadows: isSelected
                              ? const <Shadow>[
                                  Shadow(
                                    color: Color(0xAAFFD700),
                                    blurRadius: 6,
                                  ),
                                ]
                              : null,
                        )
                            .animate(target: isSelected ? 1.0 : 0.0)
                            .scale(
                              begin: const Offset(1.0, 1.0),
                              end: const Offset(1.2, 1.2),
                              duration: 220.ms,
                              curve: Curves.easeOutBack,
                            ),
                        const SizedBox(height: 4),
                        Text(
                          item.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: isSelected
                              ? MaritimePalette.cinzel(
                                  color: const Color(0xFFFFD700),
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.bold,
                                )
                              : MaritimePalette.crimsonText(
                                  color: const Color(0xFF8E8E93),
                                  fontSize: 11.0,
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

class _WoodenNavItemSpec {
  final Key key;
  final IconData icon;
  final String activeEmoji;
  final String label;

  const _WoodenNavItemSpec({
    required this.key,
    required this.icon,
    required this.activeEmoji,
    required this.label,
  });
}

// ============================================================================
// 1. Model Data Kontrak API (docs/08-API-CONTRACT.md — MVP, Phase 2, & v0.5)
// ============================================================================

class PortModel {
  final int id;
  final String code;
  final String name;
  final int treasury;

  const PortModel({
    required this.id,
    required this.code,
    required this.name,
    required this.treasury,
  });

  factory PortModel.fromJson(Map<String, dynamic> json) {
    return PortModel(
      id: (json['id'] as num?)?.toInt() ?? 0,
      code: (json['code'] as String?) ?? '',
      name: (json['name'] as String?) ?? '',
      treasury: (json['treasury'] as num?)?.toInt() ?? 0,
    );
  }
}

class MarketItemModel {
  final String commodity;
  final int stock;
  final int target;
  final int price;

  const MarketItemModel({
    required this.commodity,
    required this.stock,
    required this.target,
    required this.price,
  });

  factory MarketItemModel.fromJson(Map<String, dynamic> json) {
    return MarketItemModel(
      commodity: (json['commodity'] as String?) ?? '',
      stock: (json['stock'] as num?)?.toInt() ?? 0,
      target: (json['target'] as num?)?.toInt() ?? 400,
      price: (json['price'] as num?)?.toInt() ?? 1,
    );
  }
}

class PricePointModel {
  final int tickNo;
  final int price;
  final int stock;

  const PricePointModel({
    required this.tickNo,
    required this.price,
    required this.stock,
  });

  factory PricePointModel.fromJson(Map<String, dynamic> json) {
    return PricePointModel(
      tickNo: (json['tick_no'] as num?)?.toInt() ?? 0,
      price: (json['price'] as num?)?.toInt() ?? 0,
      stock: (json['stock'] as num?)?.toInt() ?? 0,
    );
  }
}

class CargoItemModel {
  final String commodity;
  final int qty;

  const CargoItemModel({required this.commodity, required this.qty});

  factory CargoItemModel.fromJson(Map<String, dynamic> json) {
    return CargoItemModel(
      commodity: (json['commodity'] as String?) ?? '',
      qty: (json['qty'] as num?)?.toInt() ?? 0,
    );
  }
}

class ShipModel {
  final int id;
  final String name;
  final int capacity;
  final String status;
  final int? portId;
  final int? destPort;
  final int? departTick;
  final int? arriveTick;
  final int etaTicks;
  final int tier;
  final String shipType;
  final String shipClass;
  final double speedMultiplier;
  final int attackPower;
  final int defensePower;
  final int maxDefensePower;
  final List<CargoItemModel> cargo;

  const ShipModel({
    required this.id,
    required this.name,
    required this.capacity,
    required this.status,
    required this.portId,
    required this.destPort,
    this.departTick,
    required this.arriveTick,
    required this.etaTicks,
    required this.cargo,
    this.tier = 1,
    this.shipType = 'perahu_layar',
    this.shipClass = 'Tingkat I — Perintis Pantai',
    this.speedMultiplier = 1.0,
    this.attackPower = 0,
    this.defensePower = 100,
    this.maxDefensePower = 100,
  });

  int? get currentPortId => portId;
  int? get destinationPortId => destPort;

  ShipModel copyWith({
    int? attackPower,
    int? defensePower,
    int? maxDefensePower,
    String? status,
  }) {
    return ShipModel(
      id: id,
      name: name,
      capacity: capacity,
      status: status ?? this.status,
      portId: portId,
      destPort: destPort,
      departTick: departTick,
      arriveTick: arriveTick,
      etaTicks: etaTicks,
      cargo: cargo,
      tier: tier,
      shipType: shipType,
      shipClass: shipClass,
      speedMultiplier: speedMultiplier,
      attackPower: attackPower ?? this.attackPower,
      defensePower: defensePower ?? this.defensePower,
      maxDefensePower: maxDefensePower ?? this.maxDefensePower,
    );
  }

  factory ShipModel.fromJson(Map<String, dynamic> json) {
    final rawCargo = (json['cargo'] as List<dynamic>?) ?? const <dynamic>[];
    final cap = (json['capacity'] as num?)?.toInt() ?? 35;
    final inferredTier = kShipTiersCatalog
            .where((t) => t.capacity == cap)
            .firstOrNull ??
        kShipTiersCatalog.first;
    return ShipModel(
      id: (json['id'] as num?)?.toInt() ?? 1,
      name: (json['name'] as String?) ?? 'Kapal Perintis',
      capacity: cap,
      status: (json['status'] as String?) ?? 'docked',
      portId: (json['current_port_id'] as num?)?.toInt() ??
          (json['port_id'] as num?)?.toInt(),
      destPort: (json['destination_port_id'] as num?)?.toInt() ??
          (json['dest_port'] as num?)?.toInt(),
      departTick: (json['depart_tick'] as num?)?.toInt(),
      arriveTick: (json['arrive_tick'] as num?)?.toInt(),
      etaTicks: (json['eta_ticks'] as num?)?.toInt() ?? 0,
      tier: (json['tier'] as num?)?.toInt() ?? inferredTier.tier,
      shipType: (json['ship_type'] as String?) ?? inferredTier.code,
      shipClass: (json['ship_class'] as String?) ?? inferredTier.shipClass,
      speedMultiplier: (json['speed_multiplier'] as num?)?.toDouble() ??
          inferredTier.speedMultiplier,
      attackPower: (json['attack_power'] as num?)?.toInt() ?? 0,
      defensePower:
          (json['defense_power'] as num?)?.toInt() ?? inferredTier.hullHp,
      maxDefensePower: (json['max_defense_power'] as num?)?.toInt() ??
          inferredTier.hullHp,
      cargo: rawCargo
          .map((e) => CargoItemModel.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

class RuleTemplateModel {
  final String id;
  final String title;
  final String description;
  final String source;

  const RuleTemplateModel({
    required this.id,
    required this.title,
    required this.description,
    required this.source,
  });

  factory RuleTemplateModel.fromJson(Map<String, dynamic> json) {
    return RuleTemplateModel(
      id: (json['id'] as String?) ?? '',
      title: (json['title'] as String?) ?? '',
      description: (json['description'] as String?) ?? '',
      source: (json['source'] as String?) ?? '',
    );
  }
}

class RuleValidationErrorModel {
  final int line;
  final int column;
  final String code;
  final String message;

  const RuleValidationErrorModel({
    required this.line,
    required this.column,
    required this.code,
    required this.message,
  });

  factory RuleValidationErrorModel.fromJson(Map<String, dynamic> json) {
    return RuleValidationErrorModel(
      line: (json['line'] as num?)?.toInt() ?? 1,
      column: (json['column'] as num?)?.toInt() ?? 1,
      code: (json['code'] as String?) ?? 'ERROR',
      message: (json['message'] as String?) ?? '',
    );
  }
}

class ActionLogItemModel {
  final int id;
  final int tickNo;
  final String ruleName;
  final String action;
  final String result;
  final String detail;

  const ActionLogItemModel({
    required this.id,
    required this.tickNo,
    required this.ruleName,
    required this.action,
    required this.result,
    required this.detail,
  });

  factory ActionLogItemModel.fromJson(Map<String, dynamic> json) {
    return ActionLogItemModel(
      id: (json['id'] as num?)?.toInt() ?? 0,
      tickNo: (json['tick_no'] as num?)?.toInt() ?? 0,
      ruleName: (json['rule_name'] as String?) ?? '-',
      action: (json['action'] as String?) ?? '-',
      result: (json['result'] as String?) ?? '-',
      detail: (json['detail'] as String?) ?? '',
    );
  }
}

class LeaderboardItemModel {
  final int rank;
  final String displayName;
  final int netWorth;
  final String title;

  const LeaderboardItemModel({
    required this.rank,
    required this.displayName,
    required this.netWorth,
    this.title = 'Juragan',
  });

  factory LeaderboardItemModel.fromJson(Map<String, dynamic> json) {
    final nw = (json['net_worth'] as num?)?.toInt() ?? 0;
    final rawTitle = json['title'] as String?;
    return LeaderboardItemModel(
      rank: (json['rank'] as num?)?.toInt() ?? 0,
      displayName: (json['display_name'] as String?) ?? '',
      netWorth: nw,
      title: (rawTitle != null && rawTitle.isNotEmpty)
          ? rawTitle
          : computeRankTitleForNetWorth(nw),
    );
  }
}

String computeRankTitleForNetWorth(int netWorth) {
  if (netWorth < 1000) return 'Awak Baru';
  if (netWorth <= 10000) return 'Juragan';
  if (netWorth <= 100000) return 'Nahkoda';
  return 'Sultan Rempah';
}

int computePlayerLevelForNetWorth(int netWorth) {
  if (netWorth < 5000) return 1;
  if (netWorth <= 20000) return 2;
  if (netWorth <= 50000) return 3;
  if (netWorth <= 150000) return 4;
  if (netWorth <= 500000) return 5;
  if (netWorth <= 1000000) return 6;
  return 7;
}

int computeXpToNextLevelForNetWorth(int netWorth) {
  final nw = netWorth < 0 ? 0 : netWorth;
  if (nw < 5000) return 5000 - nw;
  if (nw <= 20000) return 20001 - nw;
  if (nw <= 50000) return 50001 - nw;
  if (nw <= 150000) return 150001 - nw;
  if (nw <= 500000) return 500001 - nw;
  if (nw <= 1000000) return 1000001 - nw;
  return 0;
}

double computeLevelProgressFraction(int level, int netWorth) {
  if (level >= 7) return 1.0;
  const thresholds = <int>[0, 5000, 20001, 50001, 150001, 500001, 1000001];
  final idx = (level - 1).clamp(0, 5);
  final minW = thresholds[idx];
  final maxW = thresholds[idx + 1];
  final span = (maxW - minW) <= 0 ? 1 : (maxW - minW);
  return ((netWorth - minW) / span).clamp(0.05, 1.0);
}

class SandboxResultModel {
  final int ticks;
  final int finalCoinsDelta;
  final int trades;
  final String disclaimer;

  const SandboxResultModel({
    required this.ticks,
    required this.finalCoinsDelta,
    required this.trades,
    required this.disclaimer,
  });

  factory SandboxResultModel.fromJson(Map<String, dynamic> json) {
    return SandboxResultModel(
      ticks: (json['ticks'] as num?)?.toInt() ?? 0,
      finalCoinsDelta: (json['final_coins_delta'] as num?)?.toInt() ?? 0,
      trades: (json['trades'] as num?)?.toInt() ?? 0,
      disclaimer: (json['disclaimer'] as String?) ?? '',
    );
  }
}

class GuildModel {
  final int id;
  final String code;
  final String name;
  final int memberCount;

  const GuildModel({
    required this.id,
    required this.code,
    required this.name,
    required this.memberCount,
  });

  factory GuildModel.fromJson(Map<String, dynamic> json) {
    return GuildModel(
      id: (json['id'] as num?)?.toInt() ?? 0,
      code: (json['code'] as String?) ?? '',
      name: (json['name'] as String?) ?? '',
      memberCount: (json['member_count'] as num?)?.toInt() ?? 1,
    );
  }
}

class TradeContractModel {
  final int id;
  final String creatorName;
  final String portCode;
  final String commodityCode;
  final int qty;
  final int rewardCoins;
  final String status;
  final String description;

  const TradeContractModel({
    required this.id,
    this.creatorName = 'Gubernur Batavia',
    required this.portCode,
    required this.commodityCode,
    required this.qty,
    required this.rewardCoins,
    required this.status,
    this.description = '',
  });

  String get displayTitle {
    if (description.trim().isNotEmpty) return description.trim();
    final comTitle = commodityCode.isNotEmpty
        ? '${commodityCode[0].toUpperCase()}${commodityCode.substring(1)}'
        : 'Rempah';
    return '$creatorName minta $qty $comTitle → $rewardCoins koin';
  }

  factory TradeContractModel.fromJson(Map<String, dynamic> json) {
    final creator = (json['issuer_name'] as String?) ??
        (json['creator_name'] as String?) ??
        'Syahbandar Nusantara';
    final portCode = (json['port_code'] as String?) ?? 'banda';
    final comCode = (json['commodity_code'] as String?) ?? 'pala';
    final qty = (json['qty'] as num?)?.toInt() ?? 1;
    final rw = (json['reward_coins'] as num?)?.toInt() ?? 100;
    final desc = (json['description'] as String?) ?? '';
    return TradeContractModel(
      id: (json['id'] as num?)?.toInt() ?? 0,
      creatorName: creator,
      portCode: portCode,
      commodityCode: comCode,
      qty: qty,
      rewardCoins: rw,
      status: (json['status'] as String?) ?? 'open',
      description: desc,
    );
  }
}

const List<TradeContractModel> kDefaultTradeContracts = <TradeContractModel>[
  TradeContractModel(
    id: 101,
    creatorName: 'Gubernur Batavia',
    portCode: 'batavia',
    commodityCode: 'garam',
    qty: 50,
    rewardCoins: 2000,
    status: 'open',
    description: 'Gubernur Batavia minta 50 Garam → 2000 koin',
  ),
  TradeContractModel(
    id: 102,
    creatorName: 'Sultan Malaka',
    portCode: 'malaka',
    commodityCode: 'kain',
    qty: 30,
    rewardCoins: 1800,
    status: 'open',
    description: 'Sultan Malaka minta 30 Kain → 1800 koin',
  ),
  TradeContractModel(
    id: 103,
    creatorName: 'Syahbandar Banda',
    portCode: 'banda',
    commodityCode: 'pala',
    qty: 25,
    rewardCoins: 2200,
    status: 'open',
    description: 'Syahbandar Banda minta 25 Pala → 2200 koin',
  ),
  TradeContractModel(
    id: 104,
    creatorName: 'Sultan Ternate',
    portCode: 'ternate',
    commodityCode: 'cengkeh',
    qty: 20,
    rewardCoins: 2100,
    status: 'open',
    description: 'Sultan Ternate minta 20 Cengkeh → 2100 koin',
  ),
  TradeContractModel(
    id: 105,
    creatorName: 'Adipati Surabaya',
    portCode: 'surabaya',
    commodityCode: 'garam',
    qty: 40,
    rewardCoins: 1600,
    status: 'open',
    description: 'Adipati Surabaya minta 40 Garam → 1600 koin',
  ),
];

class DailyRewardStatusModel {
  final bool claimedToday;
  final int currentStreak;
  final int nextStreak;
  final int nextRewardCoins;
  final List<int> rewardsSchedule;

  const DailyRewardStatusModel({
    required this.claimedToday,
    required this.currentStreak,
    required this.nextStreak,
    required this.nextRewardCoins,
    this.rewardsSchedule = const <int>[100, 200, 300, 500, 700, 1000, 2000],
  });

  factory DailyRewardStatusModel.fromJson(Map<String, dynamic> json) {
    final claimed = (json['claimed_today'] as bool?) ??
        (json['has_claimed_today'] as bool?) ??
        false;
    final cur = (json['current_streak'] as num?)?.toInt() ?? 0;
    final nxt = (json['next_streak'] as num?)?.toInt() ?? ((cur % 7) + 1);
    final nxtCoins = (json['next_reward_coins'] as num?)?.toInt() ?? 100;
    final rawSched = (json['rewards_schedule'] as List<dynamic>?)
        ?.map((e) => (e as num).toInt())
        .toList();
    return DailyRewardStatusModel(
      claimedToday: claimed,
      currentStreak: cur,
      nextStreak: nxt,
      nextRewardCoins: nxtCoins,
      rewardsSchedule: (rawSched != null && rawSched.length == 7)
          ? rawSched
          : const <int>[100, 200, 300, 500, 700, 1000, 2000],
    );
  }
}

class AchievementItemModel {
  final String code;
  final String title;
  final String description;
  final String iconEmoji;
  final String requirementType;
  final int requirementValue;
  final int rewardCoins;
  final bool isUnlocked;
  final String? unlockedAt;

  const AchievementItemModel({
    required this.code,
    required this.title,
    required this.description,
    required this.iconEmoji,
    required this.requirementType,
    required this.requirementValue,
    required this.rewardCoins,
    required this.isUnlocked,
    this.unlockedAt,
  });

  factory AchievementItemModel.fromJson(Map<String, dynamic> json) {
    return AchievementItemModel(
      code: (json['code'] as String?) ?? '',
      title: (json['title'] as String?) ?? '',
      description: (json['description'] as String?) ?? '',
      iconEmoji: (json['icon_emoji'] as String?) ?? '🏅',
      requirementType: (json['requirement_type'] as String?) ?? '',
      requirementValue: (json['requirement_value'] as num?)?.toInt() ?? 1,
      rewardCoins: (json['reward_coins'] as num?)?.toInt() ?? 500,
      isUnlocked: (json['is_unlocked'] as bool?) ?? false,
      unlockedAt: json['unlocked_at'] as String?,
    );
  }
}

const List<AchievementItemModel> kDefaultAchievements = <AchievementItemModel>[
  AchievementItemModel(
    code: 'pelaut_pertama',
    title: 'Pelaut Pertama',
    description: 'Beli 1 kapal tambahan di galangan kapal.',
    iconEmoji: '⛵',
    requirementType: 'buy_ships',
    requirementValue: 1,
    rewardCoins: 500,
    isUnlocked: true,
  ),
  AchievementItemModel(
    code: 'saudagar',
    title: 'Saudagar',
    description: 'Jual total 100 unit komoditas di pasar Nusantara.',
    iconEmoji: '⚖️',
    requirementType: 'sell_units',
    requirementValue: 100,
    rewardCoins: 1000,
    isUnlocked: false,
  ),
  AchievementItemModel(
    code: 'juragan',
    title: 'Juragan',
    description: 'Kumpulkan saldo 10.000 koin di kas nakhoda.',
    iconEmoji: '💰',
    requirementType: 'coins',
    requirementValue: 10000,
    rewardCoins: 500,
    isUnlocked: false,
  ),
  AchievementItemModel(
    code: 'sultan',
    title: 'Sultan',
    description: 'Kumpulkan saldo 1.000.000 koin di kas nakhoda.',
    iconEmoji: '👑',
    requirementType: 'coins',
    requirementValue: 1000000,
    rewardCoins: 10000,
    isUnlocked: false,
  ),
  AchievementItemModel(
    code: 'penjelajah',
    title: 'Penjelajah',
    description: 'Kunjungi minimal 5 pelabuhan berbeda di Nusantara.',
    iconEmoji: '🧭',
    requirementType: 'visit_ports',
    requirementValue: 5,
    rewardCoins: 1500,
    isUnlocked: false,
  ),
  AchievementItemModel(
    code: 'pemburu_bajak_laut',
    title: 'Pemburu Bajak Laut',
    description: 'Menangkan 5 pertempuran laut melawan perompak.',
    iconEmoji: '⚔️',
    requirementType: 'win_battles',
    requirementValue: 5,
    rewardCoins: 1000,
    isUnlocked: false,
  ),
  AchievementItemModel(
    code: 'nahkoda_berpengalaman',
    title: 'Nahkoda Berpengalaman',
    description: 'Capai Level 5 sebagai kapten armada.',
    iconEmoji: '🎖️',
    requirementType: 'level',
    requirementValue: 5,
    rewardCoins: 2000,
    isUnlocked: false,
  ),
  AchievementItemModel(
    code: 'programmer_handal',
    title: 'Programmer Handal',
    description: 'Simpan minimal 10 aturan otomasi DSL.',
    iconEmoji: '📜',
    requirementType: 'save_dsl',
    requirementValue: 10,
    rewardCoins: 1500,
    isUnlocked: false,
  ),
  AchievementItemModel(
    code: 'kolektor',
    title: 'Kolektor Armada',
    description: 'Miliki 5 kapal sekaligus dalam armadamu.',
    iconEmoji: '🚢',
    requirementType: 'own_ships',
    requirementValue: 5,
    rewardCoins: 3000,
    isUnlocked: false,
  ),
  AchievementItemModel(
    code: 'kaya_raya',
    title: 'Kaya Raya',
    description: 'Capai total kekayaan bersih (Net Worth) 100.000 koin.',
    iconEmoji: '💎',
    requirementType: 'net_worth',
    requirementValue: 100000,
    rewardCoins: 5000,
    isUnlocked: false,
  ),
  AchievementItemModel(
    code: 'raja_rempah',
    title: 'Raja Rempah',
    description: 'Capai total kekayaan bersih (Net Worth) 1.000.000 koin.',
    iconEmoji: '🏆',
    requirementType: 'net_worth',
    requirementValue: 1000000,
    rewardCoins: 20000,
    isUnlocked: false,
  ),
  AchievementItemModel(
    code: 'diplomat',
    title: 'Diplomat Nusantara',
    description: 'Bergabung atau dirikan sebuah Serikat Dagang (Aliansi).',
    iconEmoji: '🤝',
    requirementType: 'join_guild',
    requirementValue: 1,
    rewardCoins: 500,
    isUnlocked: false,
  ),
  AchievementItemModel(
    code: 'filantropi',
    title: 'Filantropi Serikat',
    description: 'Donasikan total 10.000 koin ke kas aliansi.',
    iconEmoji: '🏛️',
    requirementType: 'donate_guild',
    requirementValue: 10000,
    rewardCoins: 1000,
    isUnlocked: false,
  ),
  AchievementItemModel(
    code: 'penakluk_boss',
    title: 'Penakluk Armada VOC',
    description: 'Kalahkan World Boss bersama aliansi atau armadamu.',
    iconEmoji: '🐉',
    requirementType: 'defeat_boss',
    requirementValue: 1,
    rewardCoins: 5000,
    isUnlocked: false,
  ),
  AchievementItemModel(
    code: 'veteran',
    title: 'Veteran Samudra',
    description: 'Bermain dan klaim hadiah harian selama 7 hari.',
    iconEmoji: '🌟',
    requirementType: 'play_days',
    requirementValue: 7,
    rewardCoins: 1000,
    isUnlocked: false,
  ),
];

// ============================================================================
// 2. Abstraksi Klien API & Penyimpanan Token Aman
// ============================================================================

abstract class TokenVault {
  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  });
  Future<String?> readAccessToken();
  Future<String?> readRefreshToken();
  Future<void> clear();
}

class SecureTokenVault implements TokenVault {
  final FlutterSecureStorage _storage;
  String? _cachedAccessToken;

  SecureTokenVault({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static const String _keyAccessToken = 'jwt_access_token';
  static const String _keyRefreshToken = 'jwt_refresh_token';

  @override
  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    _cachedAccessToken = accessToken;
    await _storage.write(key: _keyAccessToken, value: accessToken);
    await _storage.write(key: _keyRefreshToken, value: refreshToken);
  }

  @override
  Future<String?> readAccessToken() async {
    if (_cachedAccessToken != null) {
      return _cachedAccessToken;
    }
    _cachedAccessToken = await _storage.read(key: _keyAccessToken);
    return _cachedAccessToken;
  }

  @override
  Future<String?> readRefreshToken() async {
    return _storage.read(key: _keyRefreshToken);
  }

  @override
  Future<void> clear() async {
    _cachedAccessToken = null;
    await _storage.delete(key: _keyAccessToken);
    await _storage.delete(key: _keyRefreshToken);
  }
}

class InMemorySecureTokenVault implements TokenVault {
  String? _accessToken;
  String? _refreshToken;

  @override
  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    _accessToken = accessToken;
    _refreshToken = refreshToken;
  }

  @override
  Future<String?> readAccessToken() async => _accessToken;

  @override
  Future<String?> readRefreshToken() async => _refreshToken;

  @override
  Future<void> clear() async {
    _accessToken = null;
    _refreshToken = null;
  }
}

abstract class JalurRempahApiClient {
  int latestServerTick = 100;

  Future<Map<String, dynamic>> login(String email, String password);
  Future<Map<String, dynamic>> register(
    String email,
    String password,
    String displayName,
  );
  Future<Map<String, dynamic>> getProfile();
  Future<List<PortModel>> getPorts();
  Future<List<MarketItemModel>> getMarket(String portCode);
  Future<List<PricePointModel>> getPriceHistory(
    String portCode,
    String commodity,
  );
  Future<ShipModel> getPrimaryShip();
  Future<Map<String, dynamic>> getShipRules(int shipId);
  Future<List<RuleTemplateModel>> getRuleTemplates();
  Future<List<RuleValidationErrorModel>> validateRules(String source);
  Future<int> saveShipRules(int shipId, int baseVersion, String source);
  Future<SandboxResultModel> simulateRules(
    int shipId,
    String source,
    int ticks,
  );
  Future<List<ActionLogItemModel>> getShipLogs(int shipId);
  Future<List<LeaderboardItemModel>> getLeaderboard();
  Future<void> logout(String refreshToken) async {}

  Future<void> deleteAccount() async {}

  Future<void> changePassword({
    required String oldPassword,
    required String newPassword,
  }) async {}

  Future<DailyRewardStatusModel> getDailyRewardStatus() async {
    return const DailyRewardStatusModel(
      claimedToday: true,
      currentStreak: 3,
      nextStreak: 4,
      nextRewardCoins: 500,
    );
  }

  Future<Map<String, dynamic>> claimDailyReward() async {
    return <String, dynamic>{
      'ok': true,
      'day_streak': 4,
      'coins_awarded': 2000,
      'bonus_ship_awarded': false,
    };
  }

  Future<List<AchievementItemModel>> getAchievements() async {
    return kDefaultAchievements;
  }

  Future<List<TradeContractModel>> getTradeContracts() async {
    return kDefaultTradeContracts;
  }

  Future<Map<String, dynamic>> fulfillTradeContract(
    int contractId, {
    required int shipId,
  }) async {
    return <String, dynamic>{
      'id': contractId,
      'status': 'fulfilled',
      'reward_coins': 2000,
    };
  }

  Future<List<dynamic>> getLedger({String? cursor}) async {
    return <dynamic>[
      <String, dynamic>{
        'id': 3,
        'tick_no': 42,
        'delta': 120,
        'reason': 'Misi Harian',
        'created_at': '2026-10-23T10:00:00Z',
      },
      <String, dynamic>{
        'id': 2,
        'tick_no': 35,
        'delta': -500,
        'reason': 'Beli Kapal',
        'created_at': '2026-10-23T09:30:00Z',
      },
      <String, dynamic>{
        'id': 1,
        'tick_no': 1,
        'delta': 1000,
        'reason': 'starter',
        'created_at': '2026-10-23T08:00:00Z',
      },
    ];
  }

  Future<Map<String, dynamic>> getIntel(
    String portCode,
    String commodityCode,
  ) async {
    return <String, dynamic>{
      'tick_no': latestServerTick,
      'port_code': portCode,
      'commodity_code': commodityCode,
      'items': <Map<String, dynamic>>[
        <String, dynamic>{
          'port_id': 1,
          'port_code': 'banda',
          'port_name': 'Banda',
          'commodity_code': commodityCode,
          'price': 70,
          'stock': 400,
          'tick_seen': latestServerTick,
          'age_ticks': 0,
        },
        <String, dynamic>{
          'port_id': 6,
          'port_code': 'batavia',
          'port_name': 'Batavia',
          'commodity_code': commodityCode,
          'price': 95,
          'stock': 280,
          'tick_seen': latestServerTick - 2,
          'age_ticks': 2,
        },
        <String, dynamic>{
          'port_id': 13,
          'port_code': 'lisbon',
          'port_name': 'Lisbon',
          'commodity_code': commodityCode,
          'price': 150,
          'stock': 160,
          'tick_seen': latestServerTick - 5,
          'age_ticks': 5,
        },
      ],
    };
  }

  // Fase 9: Autentikasi Google (POST /v1/auth/google)
  Future<Map<String, dynamic>> loginWithGoogle({String idToken = ''}) async {
    return <String, dynamic>{
      'access_token': 'google-jwt-token',
      'refresh_token': 'google-refresh-token',
      'is_new_player': false,
    };
  }

  // Ekstensi v0.5 (Fase 3 & Fase 4) dengan default fallback agar backward-compatible
  Future<LegalDocumentModel> getLegalDocuments() async {
    return const LegalDocumentModel(
      tosVersion: 'v1.0',
      termsOfService:
          'Syarat & Ketentuan (ToS) & EULA Jalur Rempah v1.0: Dilarang melakukan eksploitasi bug, automasi di luar Bahasa Aturan resmi, manipulasi pasar terkoordinasi (wash trading), dan Real Money Trading (RMT).',
      privacyPolicyUupdp:
          'Kebijakan Privasi (Kepatuhan UU No. 27 Tahun 2022 tentang Pelindungan Data Pribadi / UU PDP): Kami hanya menyimpan email, hash sandi scrypt, dan log simulasi kapal. Anda berhak menghapus & menganonimkan akun kapan saja melalui fitur Hapus Akun di menu profil.',
      codeOfConduct:
          'Hukum In-Game (Code of Conduct): Transaksi P2P wajib berada pada rentang 50%-200% harga pasar. Pelanggaran dikenai Shadowban hingga Permanent Ban.',
    );
  }

  Future<List<MapPortNode>> getWorldPorts() async {
    return kNusantaraPortNodes;
  }

  Future<List<NpcCaptain>> getNpcCaptains() async {
    return buildDefaultNpcCaptains();
  }

  Future<List<CommodityCatalogItemModel>> getWorldCommodities() async {
    return kExtendedCommoditiesCatalog;
  }

  Future<List<WorldEventItemModel>> getWorldEvents() async {
    return const <WorldEventItemModel>[
      WorldEventItemModel(
        tickNo: 100,
        season: 'muson_barat',
        eventCode: 'WABAH_HAMA',
        title: 'Wabah Hama',
        description: 'Wabah Hama di Banda! Harga Pala naik.',
        portId: 1,
        commodityId: 1,
        activeUntilTick: 125,
        isActive: true,
      ),
    ];
  }

  Future<List<P2pOrderItemModel>> getP2pOrders() async {
    return const <P2pOrderItemModel>[
      P2pOrderItemModel(
        id: 1,
        orderType: 'auction',
        sellerId: 2,
        sellerName: 'Saudagar_Maluku',
        portId: 1,
        portCode: 'banda',
        commodityId: 1,
        commodityCode: 'pala',
        qty: 5,
        unitPrice: 75,
        totalPrice: 375,
        marketPriceAtCreation: 70,
        status: 'open',
        expiresTick: 1440,
      ),
    ];
  }

  Future<P2pOrderItemModel> createP2pOrder({
    required String orderType,
    required int shipId,
    required int commodityId,
    required int qty,
    required int unitPrice,
    int? targetPlayerId,
  }) async {
    final com = kExtendedCommoditiesCatalog
            .where((c) => c.id == commodityId)
            .firstOrNull ??
        kExtendedCommoditiesCatalog.first;
    return P2pOrderItemModel(
      id: DateTime.now().millisecondsSinceEpoch % 100000,
      orderType: orderType,
      sellerId: 1,
      sellerName: 'Anda',
      targetPlayerId: targetPlayerId,
      portId: 1,
      portCode: 'banda',
      commodityId: commodityId,
      commodityCode: com.code,
      qty: qty,
      unitPrice: unitPrice,
      totalPrice: qty * unitPrice,
      marketPriceAtCreation: com.basePrice,
      status: 'open',
      expiresTick: 1440,
    );
  }

  Future<void> acceptP2pOrder(int orderId, int shipId) async {}

  Future<void> cancelP2pOrder(int orderId) async {}

  Future<String> compileBlocks(Map<String, dynamic> blockJson) async {
    final cond = blockJson['condition'] as Map<String, dynamic>? ?? {};
    final act = blockJson['action'] as Map<String, dynamic>? ?? {};
    final cFunc = (cond['func'] ?? 'di').toString();
    final cArgs = ((cond['args'] as List<dynamic>?) ?? const <dynamic>[])
        .map((e) => e.toString())
        .join(', ');
    final aFunc = (act['func'] ?? 'beli').toString();
    final aArgs = ((act['args'] as List<dynamic>?) ?? const <dynamic>[])
        .map((e) => e.toString())
        .join(', ');
    return 'jika $cFunc($cArgs) maka $aFunc($aArgs)';
  }

  Future<List<ShipModel>> getShips() async {
    final primary = await getPrimaryShip();
    return <ShipModel>[primary];
  }

  Future<ShipModel> buyShip({
    required String name,
    required int portId,
    required ShipTierSpecModel tierSpec,
  }) async {
    return ShipModel(
      id: DateTime.now().millisecondsSinceEpoch % 10000,
      name: name,
      capacity: tierSpec.capacity,
      status: 'docked',
      portId: portId,
      destPort: null,
      arriveTick: null,
      etaTicks: 0,
      tier: tierSpec.tier,
      shipType: tierSpec.code,
      shipClass: tierSpec.shipClass,
      speedMultiplier: tierSpec.speedMultiplier,
      attackPower: 0,
      defensePower: tierSpec.hullHp,
      maxDefensePower: tierSpec.hullHp,
      cargo: const <CargoItemModel>[],
    );
  }

  Future<Map<String, dynamic>> repairShip(int shipId) async {
    return <String, dynamic>{
      'ship_id': shipId,
      'defense_power': 100,
      'max_defense_power': 100,
      'restored_hp': 35,
      'repair_cost': 70,
    };
  }

  Future<Map<String, dynamic>> equipWeapon({
    required int shipId,
    required String weapon,
    int qty = 1,
  }) async {
    final bonus = (weapon == 'meriam' ? 35 : 15) * qty;
    return <String, dynamic>{
      'ship_id': shipId,
      'weapon': weapon,
      'equipped_qty': qty,
      'attack_power_added': bonus,
      'attack_power': bonus,
      'defense_power': 100,
      'cost': weapon == 'meriam' ? 250 * qty : 120 * qty,
    };
  }

  Future<List<DailyQuestItemModel>> getQuests() async {
    return kDefaultDailyQuests;
  }

  Future<Map<String, dynamic>> claimQuest(int questId) async {
    return <String, dynamic>{
      'id': questId,
      'quest_id': questId,
      'is_claimed': true,
      'reward_coins': 200,
      'reward_xp': 250,
    };
  }

  Future<int> advanceTutorial() async {
    return 1;
  }

  Future<List<GuildSummaryModel>> getGuilds({String query = ''}) async {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return kDefaultGuildDirectory;
    return kDefaultGuildDirectory
        .where((g) =>
            g.name.toLowerCase().contains(q) ||
            g.code.toLowerCase().contains(q))
        .toList();
  }

  Future<GuildDetailModel> getGuildDetail(int guildId) async {
    final found = kDefaultGuildDirectory
            .where((g) => g.id == guildId)
            .firstOrNull ??
        kDefaultGuildDirectory.first;
    return GuildDetailModel(
      id: found.id,
      code: found.code,
      name: found.name,
      description: found.description,
      leaderId: 1,
      leaderName: found.leaderName,
      treasuryCoins: found.treasuryCoins,
      totalGuildWealth: found.treasuryCoins + 8500,
      worldBoss: GuildWorldBossModel(
        isActive: found.treasuryCoins > 10000,
        name: 'Bajak Laut Armada Besar',
        hp: 500,
        maxHp: 500,
        portId: 1,
      ),
      members: <GuildMemberModel>[
        GuildMemberModel(
          playerId: 1,
          displayName: found.leaderName,
          role: 'leader',
          level: 3,
          coins: 5000,
          netWorth: 8500,
        ),
        const GuildMemberModel(
          playerId: 2,
          displayName: 'Nahkoda_Satu',
          role: 'member',
          level: 2,
          coins: 2500,
          netWorth: 4000,
        ),
      ],
    );
  }

  Future<GuildDetailModel> createGuild({
    required String name,
    String? code,
    String description = '',
  }) async {
    final safeCode = (code != null && code.trim().isNotEmpty)
        ? code.trim().toLowerCase()
        : name
            .toLowerCase()
            .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
            .replaceAll(RegExp(r'^_+|_+$'), '');
    return GuildDetailModel(
      id: 99,
      code: safeCode.isEmpty ? 'aliansi_baru' : safeCode,
      name: name,
      description: description,
      leaderId: 1,
      leaderName: 'Nahkoda_Satu',
      treasuryCoins: 5000,
      totalGuildWealth: 11350,
      worldBoss: const GuildWorldBossModel(
        isActive: false,
        name: 'Bajak Laut Armada Besar',
        hp: 0,
        maxHp: 500,
        portId: 1,
      ),
      members: const <GuildMemberModel>[
        GuildMemberModel(
          playerId: 1,
          displayName: 'Nahkoda_Satu',
          role: 'leader',
          level: 2,
          coins: 5000,
          netWorth: 6350,
        ),
      ],
    );
  }

  Future<GuildDetailModel> joinGuild(int guildId) async {
    return getGuildDetail(guildId);
  }

  Future<void> leaveGuild(int guildId) async {}

  Future<Map<String, dynamic>> donateToGuild(int amount) async {
    return <String, dynamic>{
      'donated_amount': amount,
      'treasury_coins': 5000 + amount,
      'boss_active': (5000 + amount) > 10000,
    };
  }

  Future<Map<String, dynamic>> attackGuildWorldBoss(
    int guildId, {
    int? shipId,
  }) async {
    return <String, dynamic>{
      'guild_id': guildId,
      'boss_name': 'Bajak Laut Armada Besar',
      'damage_dealt': 60,
      'boss_hp_after': 440,
      'boss_max_hp': 500,
      'boss_active': true,
      'defeated': false,
    };
  }

  Future<Map<String, dynamic>> getCombatLogsAndNotifications() async {
    return <String, dynamic>{
      'notifications': <Map<String, dynamic>>[
        <String, dynamic>{
          'type': 'NAVAL_COMBAT',
          'severity': 'danger',
          'title': 'Serangan Bajak Laut Selat Malaka!',
          'message':
              'Bajak Laut menyerang kapal Anda! -35 HP, 4 Pala dirampas.',
          'tick_no': 41,
          'ship_id': 1,
        },
      ],
      'combat_logs': <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 1,
          'tick_no': 41,
          'ship_id': 1,
          'pirate_name': 'Bajak Laut Selat Malaka',
          'damage': 35,
          'is_pirate': true,
          'outcome': 'pirate_victory',
          'ship_attack_power': 0,
          'ship_defense_before': 100,
          'ship_defense_after': 65,
          'looted_commodity_code': 'pala',
          'looted_qty': 4,
          'bounty_coins': 0,
          'detail':
              'Bajak Laut menyerang kapal Anda! -35 HP, 4 Pala dirampas.',
        },
      ],
    };
  }
}

class HttpJalurRempahApiClient extends JalurRempahApiClient {
  final String baseUrl;
  final TokenVault tokenVault;
  final VoidCallback? onForceLogout;
  final HttpClient _http = HttpClient();

  HttpJalurRempahApiClient({
    required this.baseUrl,
    required this.tokenVault,
    this.onForceLogout,
  });

  Future<Map<String, dynamic>> _rawPost(
    String path,
    Map<String, dynamic> body,
  ) async {
    final uri = Uri.parse('$baseUrl$path');
    final req = await _http.openUrl('POST', uri);
    req.headers.set('content-type', 'application/json; charset=utf-8');
    req.headers.set('x-client-version', '0.5.0');
    req.write(jsonEncode(body));
    final resp = await req.close();
    final text = await resp.transform(utf8.decoder).join();
    final dynamic rawDecoded =
        text.isNotEmpty ? jsonDecode(text) : <String, dynamic>{};
    final Map<String, dynamic> decoded = rawDecoded is Map<String, dynamic>
        ? rawDecoded
        : rawDecoded is List<dynamic>
            ? <String, dynamic>{'items': rawDecoded}
            : <String, dynamic>{};
    if (resp.statusCode >= 400) {
      final errObj = decoded['error'] as Map<String, dynamic>?;
      throw Exception(
        errObj?['message']?.toString() ??
            'Permintaan gagal (${resp.statusCode})',
      );
    }
    return decoded;
  }

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    bool isRetry = false,
  }) async {
    final uri = Uri.parse('$baseUrl$path');
    final req = await _http.openUrl(method, uri);
    req.headers.set('content-type', 'application/json; charset=utf-8');
    req.headers.set('x-client-version', '0.5.0');
    final token = await tokenVault.readAccessToken();
    if (token != null && token.isNotEmpty) {
      req.headers.set('authorization', 'Bearer $token');
    }
    if (body != null) {
      req.write(jsonEncode(body));
    }
    final resp = await req.close();
    final text = await resp.transform(utf8.decoder).join();
    final dynamic rawDecoded =
        text.isNotEmpty ? jsonDecode(text) : <String, dynamic>{};
    final Map<String, dynamic> decoded = rawDecoded is Map<String, dynamic>
        ? rawDecoded
        : rawDecoded is List<dynamic>
            ? <String, dynamic>{'items': rawDecoded}
            : <String, dynamic>{};
    final headerTick = int.tryParse(resp.headers.value('x-tick') ?? '');
    final bodyTick = (decoded['current_tick'] as num?)?.toInt() ??
        (decoded['tick_no'] as num?)?.toInt();
    if (bodyTick != null && bodyTick > 0) {
      latestServerTick = bodyTick;
    } else if (headerTick != null && headerTick > 0) {
      latestServerTick = headerTick;
    }

    // Auto-refresh token saat menerima 401 Unauthorized
    if (resp.statusCode == 401 &&
        !isRetry &&
        path != '/v1/auth/refresh' &&
        path != '/v1/auth/login' &&
        path != '/v1/auth/register' &&
        path != '/v1/auth/google') {
      final refreshToken = await tokenVault.readRefreshToken();
      if (refreshToken != null && refreshToken.isNotEmpty) {
        try {
          final refreshRes = await _rawPost(
            '/v1/auth/refresh',
            {'refresh_token': refreshToken},
          );
          final newAccess = refreshRes['access_token'] as String?;
          final newRefresh = refreshRes['refresh_token'] as String?;
          if (newAccess != null && newAccess.isNotEmpty) {
            await tokenVault.saveTokens(
              accessToken: newAccess,
              refreshToken: (newRefresh != null && newRefresh.isNotEmpty)
                  ? newRefresh
                  : refreshToken,
            );
            return await _request(method, path, body: body, isRetry: true);
          } else {
            await tokenVault.clear();
            onForceLogout?.call();
          }
        } catch (e) {
          await tokenVault.clear();
          onForceLogout?.call();
        }
      } else {
        await tokenVault.clear();
        onForceLogout?.call();
      }
    }

    if (resp.statusCode >= 400) {
      final errObj = decoded['error'] as Map<String, dynamic>?;
      throw Exception(
        errObj?['message']?.toString() ??
            'Permintaan gagal (${resp.statusCode})',
      );
    }
    return decoded;
  }

  @override
  Future<void> logout(String refreshToken) async {
    try {
      await _request(
        'POST',
        '/v1/auth/logout',
        body: {'refresh_token': refreshToken},
      );
    } catch (_) {}
  }

  @override
  Future<Map<String, dynamic>> login(String email, String password) async {
    final res = await _request(
      'POST',
      '/v1/auth/login',
      body: {'email': email, 'password': password},
    );
    await tokenVault.saveTokens(
      accessToken: (res['access_token'] as String?) ?? '',
      refreshToken: (res['refresh_token'] as String?) ?? '',
    );
    return res;
  }

  @override
  Future<Map<String, dynamic>> register(
    String email,
    String password,
    String displayName,
  ) async {
    final res = await _request(
      'POST',
      '/v1/auth/register',
      body: {
        'email': email,
        'password': password,
        'display_name': displayName,
        'tos_accepted': true,
      },
    );
    await tokenVault.saveTokens(
      accessToken: (res['access_token'] as String?) ?? '',
      refreshToken: (res['refresh_token'] as String?) ?? '',
    );
    return res;
  }

  @override
  Future<Map<String, dynamic>> loginWithGoogle({String idToken = ''}) async {
    final effectiveToken = idToken.trim();
    if (effectiveToken.isEmpty) {
      throw Exception('idToken Google kosong');
    }
    final res = await _request(
      'POST',
      '/v1/auth/google',
      body: <String, dynamic>{'id_token': effectiveToken},
    );
    await tokenVault.saveTokens(
      accessToken: (res['access_token'] as String?) ?? '',
      refreshToken: (res['refresh_token'] as String?) ?? '',
    );
    return res;
  }

  @override
  Future<Map<String, dynamic>> getProfile() => _request('GET', '/v1/me');

  @override
  Future<void> deleteAccount() async {
    await _request('DELETE', '/v1/me');
    await tokenVault.clear();
  }

  @override
  Future<void> changePassword({
    required String oldPassword,
    required String newPassword,
  }) async {
    await _request(
      'POST',
      '/v1/me/change-password',
      body: <String, dynamic>{
        'old_password': oldPassword,
        'new_password': newPassword,
      },
    );
  }

  @override
  Future<DailyRewardStatusModel> getDailyRewardStatus() async {
    final res = await _request('GET', '/v1/me/daily-reward');
    return DailyRewardStatusModel.fromJson(res);
  }

  @override
  Future<Map<String, dynamic>> claimDailyReward() {
    return _request('POST', '/v1/me/daily-reward/claim');
  }

  @override
  Future<List<AchievementItemModel>> getAchievements() async {
    final res = await _request('GET', '/v1/me/achievements');
    final raw = (res['items'] as List<dynamic>?) ?? const <dynamic>[];
    if (raw.isEmpty) return kDefaultAchievements;
    return raw
        .map((e) => AchievementItemModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<List<TradeContractModel>> getTradeContracts() async {
    final res = await _request('GET', '/v1/contracts');
    final raw = (res['items'] as List<dynamic>?) ?? const <dynamic>[];
    if (raw.isEmpty) return kDefaultTradeContracts;
    return raw
        .map((e) => TradeContractModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<Map<String, dynamic>> fulfillTradeContract(
    int contractId, {
    required int shipId,
  }) {
    return _request(
      'POST',
      '/v1/contracts/$contractId/fulfill',
      body: <String, dynamic>{'ship_id': shipId},
    );
  }

  @override
  Future<List<dynamic>> getLedger({String? cursor}) async {
    final qParam = (cursor != null && cursor.trim().isNotEmpty)
        ? '?cursor=${Uri.encodeQueryComponent(cursor.trim())}'
        : '';
    final res = await _request('GET', '/v1/me/ledger$qParam');
    return (res['items'] as List<dynamic>?) ?? const <dynamic>[];
  }

  @override
  Future<Map<String, dynamic>> getIntel(
    String portCode,
    String commodityCode,
  ) {
    final p = Uri.encodeQueryComponent(portCode.trim());
    final c = Uri.encodeQueryComponent(commodityCode.trim());
    return _request('GET', '/v1/intel?port=$p&commodity=$c');
  }

  @override
  Future<LegalDocumentModel> getLegalDocuments() async {
    final res = await _request('GET', '/v1/legal');
    return LegalDocumentModel.fromJson(res);
  }

  @override
  Future<List<PortModel>> getPorts() async {
    final res = await _request('GET', '/v1/world');
    final raw = (res['ports'] as List<dynamic>?) ?? const <dynamic>[];
    return raw
        .map((e) => PortModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<List<MapPortNode>> getWorldPorts() async {
    final res = await _request('GET', '/v1/world/ports');
    final raw = (res['items'] as List<dynamic>?) ?? const <dynamic>[];
    if (raw.isEmpty) return kNusantaraPortNodes;
    return raw
        .map((e) => MapPortNode.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<List<NpcCaptain>> getNpcCaptains() async {
    final res = await _request('GET', '/v1/world/npc-captains');
    final raw = (res['items'] as List<dynamic>?) ?? const <dynamic>[];
    if (raw.isEmpty) return buildDefaultNpcCaptains();
    return raw
        .map((e) => NpcCaptain.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<List<CommodityCatalogItemModel>> getWorldCommodities() async {
    final res = await _request('GET', '/v1/world/commodities');
    final raw = (res['items'] as List<dynamic>?) ?? const <dynamic>[];
    if (raw.isEmpty) return kExtendedCommoditiesCatalog;
    return raw
        .map((e) =>
            CommodityCatalogItemModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<List<WorldEventItemModel>> getWorldEvents() async {
    final res = await _request('GET', '/v1/world/events');
    final activeRaw = (res['active_events'] as List<dynamic>?) ??
        (res['items'] as List<dynamic>?) ??
        const <dynamic>[];
    return activeRaw
        .map((e) => WorldEventItemModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<List<MarketItemModel>> getMarket(String portCode) async {
    final res = await _request('GET', '/v1/world/market/$portCode');
    final raw = (res['items'] as List<dynamic>?) ?? const <dynamic>[];
    return raw
        .map((e) => MarketItemModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<List<PricePointModel>> getPriceHistory(
    String portCode,
    String commodity,
  ) async {
    final res = await _request(
      'GET',
      '/v1/world/price-history?port=$portCode&commodity=$commodity&ticks=48',
    );
    final raw = (res['points'] as List<dynamic>?) ?? const <dynamic>[];
    return raw
        .map((e) => PricePointModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<List<ShipModel>> getShips() async {
    final res = await _request('GET', '/v1/ships');
    final items = (res['items'] as List<dynamic>?) ?? const <dynamic>[];
    return items
        .map((e) => ShipModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<ShipModel> getPrimaryShip() async {
    final ships = await getShips();
    if (ships.isEmpty) {
      return const ShipModel(
        id: 1,
        name: 'Kapal Perintis',
        capacity: 35,
        status: 'docked',
        portId: 1,
        destPort: null,
        arriveTick: null,
        etaTicks: 0,
        cargo: <CargoItemModel>[],
      );
    }
    final detail = await _request('GET', '/v1/ships/${ships.first.id}');
    return ShipModel.fromJson(detail);
  }

  @override
  Future<ShipModel> buyShip({
    required String name,
    required int portId,
    required ShipTierSpecModel tierSpec,
  }) async {
    final res = await _request(
      'POST',
      '/v1/ships/buy',
      body: {
        'name': name,
        'port_id': portId,
        'ship_type': tierSpec.code,
        'tier': tierSpec.tier,
      },
    );
    final shipJson =
        (res['ship'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    return ShipModel.fromJson(shipJson);
  }

  @override
  Future<Map<String, dynamic>> getShipRules(int shipId) {
    return _request('GET', '/v1/ships/$shipId/rules');
  }

  @override
  Future<List<RuleTemplateModel>> getRuleTemplates() async {
    final res = await _request('GET', '/v1/rule-templates');
    final raw = (res['items'] as List<dynamic>?) ?? const <dynamic>[];
    return raw
        .map((e) => RuleTemplateModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<List<RuleValidationErrorModel>> validateRules(String source) async {
    final res = await _request(
      'POST',
      '/v1/rules/validate',
      body: {'source': source},
    );
    final raw = (res['errors'] as List<dynamic>?) ?? const <dynamic>[];
    return raw
        .map((e) => RuleValidationErrorModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<int> saveShipRules(
    int shipId,
    int baseVersion,
    String source,
  ) async {
    final res = await _request(
      'PUT',
      '/v1/ships/$shipId/rules',
      body: {'base_version': baseVersion, 'source': source},
    );
    return (res['version'] as num?)?.toInt() ?? (baseVersion + 1);
  }

  @override
  Future<SandboxResultModel> simulateRules(
    int shipId,
    String source,
    int ticks,
  ) async {
    final res = await _request(
      'POST',
      '/v1/ships/$shipId/rules/simulate',
      body: {'source': source, 'ticks': ticks},
    );
    return SandboxResultModel.fromJson(res);
  }

  @override
  Future<List<ActionLogItemModel>> getShipLogs(int shipId) async {
    final res = await _request('GET', '/v1/ships/$shipId/log?limit=30');
    final raw = (res['items'] as List<dynamic>?) ?? const <dynamic>[];
    return raw
        .map((e) => ActionLogItemModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<List<LeaderboardItemModel>> getLeaderboard() async {
    final res = await _request('GET', '/v1/leaderboard?limit=50');
    final raw = (res['items'] as List<dynamic>?) ?? const <dynamic>[];
    return raw
        .map((e) => LeaderboardItemModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<List<P2pOrderItemModel>> getP2pOrders() async {
    final res = await _request('GET', '/v1/p2p/orders');
    final raw = (res['items'] as List<dynamic>?) ?? const <dynamic>[];
    return raw
        .map((e) => P2pOrderItemModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<P2pOrderItemModel> createP2pOrder({
    required String orderType,
    required int shipId,
    required int commodityId,
    required int qty,
    required int unitPrice,
    int? targetPlayerId,
  }) async {
    final body = <String, dynamic>{
      'order_type': orderType,
      'ship_id': shipId,
      'commodity_id': commodityId,
      'qty': qty,
      'unit_price': unitPrice,
    };
    if (targetPlayerId != null && targetPlayerId > 0) {
      body['target_player_id'] = targetPlayerId;
    }
    final res = await _request('POST', '/v1/p2p/orders', body: body);
    return P2pOrderItemModel.fromJson(res);
  }

  @override
  Future<void> acceptP2pOrder(int orderId, int shipId) async {
    await _request(
      'POST',
      '/v1/p2p/orders/$orderId/accept',
      body: {'ship_id': shipId},
    );
  }

  @override
  Future<void> cancelP2pOrder(int orderId) async {
    await _request('POST', '/v1/p2p/orders/$orderId/cancel');
  }

  @override
  Future<String> compileBlocks(Map<String, dynamic> blockJson) async {
    final res = await _request(
      'POST',
      '/v1/dsl/compile-blocks',
      body: blockJson,
    );
    return (res['dsl'] as String?) ?? (res['source'] as String?) ?? '';
  }

  @override
  Future<Map<String, dynamic>> repairShip(int shipId) {
    return _request(
      'POST',
      '/v1/ships/repair',
      body: <String, dynamic>{'ship_id': shipId},
    );
  }

  @override
  Future<Map<String, dynamic>> equipWeapon({
    required int shipId,
    required String weapon,
    int qty = 1,
  }) {
    return _request(
      'POST',
      '/v1/ships/equip',
      body: <String, dynamic>{
        'ship_id': shipId,
        'weapon': weapon,
        'qty': qty,
      },
    );
  }

  @override
  Future<Map<String, dynamic>> getCombatLogsAndNotifications() {
    return _request('GET', '/v1/logs');
  }

  @override
  Future<List<DailyQuestItemModel>> getQuests() async {
    final res = await _request('GET', '/v1/quests');
    final raw = (res['items'] as List<dynamic>?) ?? const <dynamic>[];
    if (raw.isEmpty) return kDefaultDailyQuests;
    return raw
        .map((e) => DailyQuestItemModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<Map<String, dynamic>> claimQuest(int questId) {
    return _request('POST', '/v1/quests/$questId/claim');
  }

  @override
  Future<int> advanceTutorial() async {
    final res = await _request('POST', '/v1/tutorial/advance');
    return (res['tutorial_step'] as num?)?.toInt() ?? 1;
  }

  @override
  Future<List<GuildSummaryModel>> getGuilds({String query = ''}) async {
    final qParam = query.trim().isNotEmpty
        ? '?q=${Uri.encodeQueryComponent(query.trim())}'
        : '';
    final res = await _request('GET', '/v1/guilds$qParam');
    final raw = (res['items'] as List<dynamic>?) ?? const <dynamic>[];
    if (raw.isEmpty && query.trim().isEmpty) return kDefaultGuildDirectory;
    return raw
        .map((e) => GuildSummaryModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<GuildDetailModel> getGuildDetail(int guildId) async {
    final res = await _request('GET', '/v1/guilds/$guildId');
    return GuildDetailModel.fromJson(res);
  }

  @override
  Future<GuildDetailModel> createGuild({
    required String name,
    String? code,
    String description = '',
  }) async {
    final body = <String, dynamic>{
      'name': name,
      'description': description,
    };
    if (code != null && code.trim().isNotEmpty) {
      body['code'] = code.trim();
    }
    final res = await _request('POST', '/v1/guilds', body: body);
    final newId = (res['id'] as num?)?.toInt() ?? 1;
    return getGuildDetail(newId);
  }

  @override
  Future<GuildDetailModel> joinGuild(int guildId) async {
    await _request('POST', '/v1/guilds/$guildId/join');
    return getGuildDetail(guildId);
  }

  @override
  Future<void> leaveGuild(int guildId) async {
    await _request('POST', '/v1/guilds/$guildId/leave');
  }

  @override
  Future<Map<String, dynamic>> donateToGuild(int amount) {
    return _request(
      'POST',
      '/v1/guilds/donate',
      body: <String, dynamic>{'amount': amount},
    );
  }

  @override
  Future<Map<String, dynamic>> attackGuildWorldBoss(
    int guildId, {
    int? shipId,
  }) {
    return _request(
      'POST',
      '/v1/guilds/$guildId/attack-boss',
      body: shipId != null
          ? <String, dynamic>{'ship_id': shipId}
          : <String, dynamic>{},
    );
  }
}

// ============================================================================
// 3. Komponen Grafik Harga 24 Jam (CustomPainter)
// ============================================================================

class PriceHistoryChart extends StatelessWidget {
  final List<PricePointModel> points;

  const PriceHistoryChart({super.key, required this.points});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (points.isEmpty) {
      return const SizedBox(
        height: 120,
        child: Center(child: Text('Belum ada riwayat harga')),
      );
    }
    return SizedBox(
      height: 140,
      width: double.infinity,
      child: CustomPaint(
        painter: _PriceSparklinePainter(points: points, isDark: isDark),
      ),
    );
  }
}

class _PriceSparklinePainter extends CustomPainter {
  final List<PricePointModel> points;
  final bool isDark;

  _PriceSparklinePainter({required this.points, required this.isDark});

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(10),
    );
    final bgGradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: const <Color>[
        Color(0xFF281815),
        Color(0xFF3E2723),
        Color(0xFF1A0F0D),
      ],
    );
    canvas.drawRRect(
      rrect,
      Paint()..shader = bgGradient.createShader(Offset.zero & size),
    );
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = const Color(0x99FFD700)
        ..strokeWidth = 1.2
        ..style = PaintingStyle.stroke,
    );

    // Garis bantu horizontal emas tipis
    final gridPaint = Paint()
      ..color = const Color(0x22F5DEB3)
      ..strokeWidth = 0.8;
    for (int g = 1; g <= 3; g++) {
      final gy = (size.height / 4) * g;
      canvas.drawLine(Offset(12, gy), Offset(size.width - 12, gy), gridPaint);
    }

    if (points.length < 2) return;

    int minPrice = points.first.price;
    int maxPrice = points.first.price;
    for (final p in points) {
      if (p.price < minPrice) minPrice = p.price;
      if (p.price > maxPrice) maxPrice = p.price;
    }
    final range = (maxPrice - minPrice) <= 0 ? 1 : (maxPrice - minPrice);

    final linePaint = Paint()
      ..color = MaritimePalette.gold
      ..strokeWidth = 2.6
      ..style = PaintingStyle.stroke;

    final path = Path();
    final fillPath = Path();
    for (int i = 0; i < points.length; i++) {
      final x = (i / (points.length - 1)) * (size.width - 24) + 12;
      final normalizedY = (points[i].price - minPrice) / range;
      final y = size.height - 16 - normalizedY * (size.height - 32);
      if (i == 0) {
        path.moveTo(x, y);
        fillPath.moveTo(x, size.height - 12);
        fillPath.lineTo(x, y);
      } else {
        path.lineTo(x, y);
        fillPath.lineTo(x, y);
      }
      if (i == points.length - 1) {
        fillPath.lineTo(x, size.height - 12);
        fillPath.close();
      }
    }

    final areaGradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: const <Color>[
        Color(0x55FFD700),
        Color(0x05FFD700),
      ],
    );
    canvas.drawPath(
      fillPath,
      Paint()..shader = areaGradient.createShader(Offset.zero & size),
    );
    canvas.drawPath(path, linePaint);
  }

  @override
  bool shouldRepaint(covariant _PriceSparklinePainter oldDelegate) {
    return oldDelegate.points != points || oldDelegate.isDark != isDark;
  }
}

// ============================================================================
// 4. Aplikasi Utama Jalur Rempah (Provider + Dark Mode + 5 Tab v0.5)
// ============================================================================

class JalurRempahApp extends StatefulWidget {
  final JalurRempahApiClient? apiClient;
  final TokenVault? tokenVault;
  final ThemeController? themeController;
  final bool? showTitleScreen;

  const JalurRempahApp({
    super.key,
    this.apiClient,
    this.tokenVault,
    this.themeController,
    this.showTitleScreen,
  });

  @override
  State<JalurRempahApp> createState() => _JalurRempahAppState();
}

class _JalurRempahAppState extends State<JalurRempahApp> {
  late final TokenVault _vault;
  late final JalurRempahApiClient _api;
  late final ThemeController _themeController;
  bool _authenticated = false;
  late bool _showingTitleScreen;

  static bool get _isFlutterTestEnvironment {
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
    _vault = widget.tokenVault ?? SecureTokenVault();
    _themeController = widget.themeController ?? ThemeController();
    _showingTitleScreen =
        widget.showTitleScreen ?? (!_isFlutterTestEnvironment);
    AudioManager().playBgm();
    _api = widget.apiClient ??
        HttpJalurRempahApiClient(
          baseUrl: const String.fromEnvironment(
            'API_BASE_URL',
            defaultValue: 'https://api.bacanova.my.id',
          ),
          tokenVault: _vault,
          onForceLogout: () {
            if (mounted) {
              setState(() {
                _authenticated = false;
              });
            }
          },
        );
    _checkInitialAuth();
  }

  Future<void> _checkInitialAuth() async {
    try {
      final token = await _vault.readAccessToken();
      if (token != null && token.isNotEmpty && mounted) {
        setState(() {
          _authenticated = true;
          _showingTitleScreen = false;
        });
      }
    } catch (_) {}
  }

  Future<void> _handleLogout() async {
    try {
      final refreshToken = await _vault.readRefreshToken();
      if (refreshToken != null && refreshToken.isNotEmpty) {
        await _api.logout(refreshToken);
      }
    } catch (_) {}
    try {
      await _vault.clear();
    } catch (_) {}
    if (mounted) {
      setState(() {
        _authenticated = false;
        _showingTitleScreen = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<ThemeController>.value(
      value: _themeController,
      child: ListenableBuilder(
        listenable: _themeController,
        builder: (context, _) {
          return Consumer<ThemeController>(
            builder: (context, themeCtrl, _) {
              return MaterialApp(
                title: 'Jalur Rempah',
                debugShowCheckedModeBanner: false,
                theme: themeCtrl.lightTheme,
                darkTheme: themeCtrl.darkTheme,
                themeMode: themeCtrl.themeMode,
                home: _authenticated
                    ? MainDashboardShell(
                        api: _api,
                        onLogout: () {
                          _handleLogout();
                        },
                      )
                    : _showingTitleScreen
                        ? TitleScreen(
                            onStartVoyage: () {
                              setState(() {
                                _showingTitleScreen = false;
                              });
                            },
                          )
                        : AuthScreen(
                            api: _api,
                            onAuthenticated: () {
                              setState(() {
                                _authenticated = true;
                              });
                            },
                          ),
              );
            },
          );
        },
      ),
    );
  }
}

// ============================================================================
// 4B. Layar Judul Sinematik (Title Screen)
// ============================================================================

class TitleScreen extends StatelessWidget {
  final VoidCallback onStartVoyage;

  const TitleScreen({
    super.key,
    required this.onStartVoyage,
  });

  static bool get _isFlutterTestEnvironment {
    try {
      return const bool.fromEnvironment('FLUTTER_TEST') ||
          Platform.environment.containsKey('FLUTTER_TEST');
    } catch (_) {
      return false;
    }
  }

  Future<void> _showThemeSettingsDialog(BuildContext context) async {
    final themeCtrl = Provider.of<ThemeController>(context, listen: false);
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return Consumer<ThemeController>(
          builder: (context, ctrl, _) {
            return AlertDialog(
              key: const Key('title_screen_settings_dialog'),
              backgroundColor: const Color(0xFF2C1B10),
              title: Text(
                '⚙️ Pengaturan Pelayaran',
                style: MaritimePalette.cinzel(
                  color: const Color(0xFFFFD700),
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Mode Tema:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        ChoiceChip(
                          label: const Text('Gelap'),
                          selected: ctrl.themeMode == ThemeMode.dark,
                          onSelected: (_) =>
                              themeCtrl.setThemeMode(ThemeMode.dark),
                        ),
                        ChoiceChip(
                          label: const Text('Terang'),
                          selected: ctrl.themeMode == ThemeMode.light,
                          onSelected: (_) =>
                              themeCtrl.setThemeMode(ThemeMode.light),
                        ),
                        ChoiceChip(
                          label: const Text('Sistem'),
                          selected: ctrl.themeMode == ThemeMode.system,
                          onSelected: (_) =>
                              themeCtrl.setThemeMode(ThemeMode.system),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Gaya Peta Dunia:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        ChoiceChip(
                          label: const Text('Kuno Berwarna'),
                          selected: ctrl.mapStyle == MapStyle.vintageColor,
                          onSelected: (_) =>
                              themeCtrl.setMapStyle(MapStyle.vintageColor),
                        ),
                        ChoiceChip(
                          label: const Text('Kuno Sepia'),
                          selected: ctrl.mapStyle == MapStyle.vintageSepia,
                          onSelected: (_) =>
                              themeCtrl.setMapStyle(MapStyle.vintageSepia),
                        ),
                        ChoiceChip(
                          label: const Text('Modern'),
                          selected: ctrl.mapStyle == MapStyle.modern,
                          onSelected: (_) =>
                              themeCtrl.setMapStyle(MapStyle.modern),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Tutup'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final floatingShip = Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xAA1A0F08),
        border: Border.all(color: const Color(0xFFFFD700), width: 1.8),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x66FFD700),
            blurRadius: 16,
            spreadRadius: 2,
          ),
        ],
      ),
      child: const Text(
        '⛵',
        style: TextStyle(fontSize: 36),
      ),
    );

    final animatedShip = _isFlutterTestEnvironment
        ? floatingShip.animate().moveY(
              begin: -8,
              end: 8,
              duration: 900.ms,
              curve: Curves.easeInOut,
            )
        : floatingShip
            .animate(
              onPlay: (controller) => controller.repeat(reverse: true),
            )
            .moveY(
              begin: -10,
              end: 10,
              duration: 1600.ms,
              curve: Curves.easeInOut,
            );

    return Scaffold(
      key: const Key('cinematic_title_screen'),
      backgroundColor: const Color(0xFF0A192F),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Background gambar kapal layar (assets/splash.png)
          Image.asset(
            'assets/splash.png',
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) {
              return Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: <Color>[
                      Color(0xFF0A192F),
                      Color(0xFF1A0F08),
                    ],
                  ),
                ),
              );
            },
          ),
          // 2. Overlay hitam transparan (opacity 0.4) agar teks terbaca jelas
          Container(
            // ignore: deprecated_member_use
            color: Colors.black.withOpacity(0.4),
          ),
          // 3. Konten Utama Title Screen
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const SizedBox(height: 16),
                  // Bagian Atas-Tengah: Ikon Kompas, Judul "JALUR REMPAH", & Subtitle
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(22),
                        child: Image.asset(
                          'assets/icon.png',
                          width: 88,
                          height: 88,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const Icon(
                            Icons.explore,
                            size: 72,
                            color: Color(0xFFFFD700),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'JALUR REMPAH',
                        textAlign: TextAlign.center,
                        style: MaritimePalette.cinzelDecorative(
                          color: const Color(0xFFFFD700),
                          fontSize: 34,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 2.0,
                          shadows: const <Shadow>[
                            Shadow(
                              color: Colors.black,
                              blurRadius: 12,
                              offset: Offset(0, 4),
                            ),
                          ],
                        ),
                      )
                          .animate()
                          .fadeIn(duration: 1.seconds)
                          .scale(),
                      const SizedBox(height: 10),
                      Text(
                        'Jelajahi Nusantara, Kuasai Rempah',
                        textAlign: TextAlign.center,
                        style: MaritimePalette.crimsonText(
                          color: const Color(0xFFF5DEB3),
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ],
                  ),
                  // Bagian Bawah: Ikon Kapal Melayang + Dua Tombol Besar
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(child: animatedShip),
                      const SizedBox(height: 24),
                      SizedBox(
                        height: 52,
                        child: ElevatedButton.icon(
                          key: const Key('title_start_voyage_button'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFFFD700),
                            foregroundColor: Colors.black,
                            elevation: 8,
                            shadowColor: Colors.black,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onPressed: () {
                            HapticFeedback.lightImpact();
                            AudioManager().playSfx('click');
                            onStartVoyage();
                          },
                          icon: const Icon(
                            Icons.sailing,
                            color: Colors.black,
                          ),
                          label: Text(
                            'MULAI PELAYARAN',
                            style: MaritimePalette.cinzel(
                              color: Colors.black,
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.2,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 48,
                        child: OutlinedButton.icon(
                          key: const Key('title_settings_button'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFFFFD700),
                            backgroundColor: const Color(0xAA1A0F08),
                            side: const BorderSide(
                              color: Color(0xFFFFD700),
                              width: 1.8,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onPressed: () {
                            HapticFeedback.lightImpact();
                            AudioManager().playSfx('click');
                            _showThemeSettingsDialog(context);
                          },
                          icon: const Icon(
                            Icons.settings_outlined,
                            color: Color(0xFFFFD700),
                          ),
                          label: Text(
                            'PENGATURAN',
                            style: MaritimePalette.cinzel(
                              color: const Color(0xFFFFD700),
                              fontSize: 14.5,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.0,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Widget pembungkus Tab Pasar/Peta yang mengatur orientasi layar otomatis:
/// Landscape saat berada di Tab Pasar/Peta, dan kembali ke Portrait saat keluar tab.
class MarketScreen extends StatefulWidget {
  final Widget Function(BuildContext context, Orientation orientation) builder;

  const MarketScreen({
    super.key,
    required this.builder,
  });

  @override
  State<MarketScreen> createState() => _MarketScreenState();
}

class _MarketScreenState extends State<MarketScreen> {
  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations(<DeviceOrientation>[
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations(<DeviceOrientation>[
      DeviceOrientation.portraitUp,
    ]);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return OrientationBuilder(
      builder: (context, orientation) => widget.builder(context, orientation),
    );
  }
}

// ============================================================================
// 5. Layar Autentikasi & Layar Hukum (ToS v1.0 & UU PDP)
// ============================================================================

class LegalDocumentsScreen extends StatefulWidget {
  final JalurRempahApiClient api;

  const LegalDocumentsScreen({super.key, required this.api});

  @override
  State<LegalDocumentsScreen> createState() => _LegalDocumentsScreenState();
}

class _LegalDocumentsScreenState extends State<LegalDocumentsScreen> {
  LegalDocumentModel? _legal;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadLegal();
  }

  Future<void> _loadLegal() async {
    try {
      final doc = await widget.api.getLegalDocuments();
      if (!mounted) return;
      setState(() {
        _legal = doc;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final doc = _legal;
    return Scaffold(
      backgroundColor: const Color(0xFF0A192F),
      appBar: AppBar(
        title: const Text('Syarat & Ketentuan & UU PDP'),
      ),
      body: _loading
          ? const Center(child: GameLoadingIndicator(size: 36, label: 'Memuat Dokumen Pelayaran...'))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                MaritimeWoodCard(
                  child: ListTile(
                    leading: const Icon(Icons.verified_user_outlined),
                    title: Text(
                      'Dokumen Hukum Resmi (${doc?.tosVersion ?? 'v1.0'})',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: const Text(
                      'Kepatuhan UU No. 27 Tahun 2022 tentang Pelindungan Data Pribadi (UU PDP)',
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                MaritimeWoodCard(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '1. Syarat & Ketentuan (ToS / EULA)',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(doc?.termsOfService ?? ''),
                        const SizedBox(height: 16),
                        const Text(
                          '2. Kebijakan Privasi (UU PDP No. 27/2022)',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(doc?.privacyPolicyUupdp ?? ''),
                        const SizedBox(height: 16),
                        const Text(
                          '3. Hukum Pelayaran & Code of Conduct',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(doc?.codeOfConduct ?? ''),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class LedgerScreen extends StatefulWidget {
  final JalurRempahApiClient api;

  const LedgerScreen({super.key, required this.api});

  @override
  State<LedgerScreen> createState() => _LedgerScreenState();
}

class _LedgerScreenState extends State<LedgerScreen> {
  List<dynamic> _items = const <dynamic>[];
  bool _loading = true;
  String? _errorMsg;

  @override
  void initState() {
    super.initState();
    _loadLedger();
  }

  String _formatLedgerReason(String rawReason) {
    switch (rawReason.trim().toLowerCase()) {
      case 'starter':
        return 'Modal Awal';
      case 'buy':
        return 'Beli Komoditas';
      case 'sell':
        return 'Jual Komoditas';
      case 'upkeep':
        return 'Upkeep Awak';
      case 'ship_purchase':
        return 'Beli Kapal';
      case 'quest_reward':
        return 'Misi Harian';
      case 'guild_create':
        return 'Buat Aliansi';
      case 'guild_donate':
        return 'Donasi Aliansi';
      case 'repair':
        return 'Perbaikan Kapal';
      case 'equip':
        return 'Pasang Senjata';
      default:
        return rawReason.trim().isEmpty ? 'Mutasi Koin' : rawReason.trim();
    }
  }

  Future<void> _loadLedger() async {
    setState(() {
      _loading = true;
      _errorMsg = null;
    });
    try {
      final items = await widget.api.getLedger();
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMsg = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const Key('ledger_screen'),
      backgroundColor: MaritimePalette.deepOceanBlue,
      appBar: AppBar(
        title: const Text('Buku Mutasi Koin'),
        actions: [
          IconButton(
            key: const Key('refresh_ledger_button'),
            tooltip: 'Segarkan Mutasi',
            icon: const Icon(Icons.refresh),
            onPressed: _loadLedger,
          ),
        ],
      ),
      body: _loading
          ? const Center(
              child: GameLoadingIndicator(
                size: 36,
                label: 'Memuat Buku Mutasi Koin...',
              ),
            )
          : _errorMsg != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: MaritimeWoodCard(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          _errorMsg!,
                          style: const TextStyle(color: Colors.redAccent),
                        ),
                      ),
                    ),
                  ),
                )
              : _items.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: MaritimeWoodCard(
                          child: Padding(
                            padding: EdgeInsets.all(16),
                            child: Text('Belum ada catatan mutasi koin.'),
                          ),
                        ),
                      ),
                    )
                  : ListView.builder(
                      key: const Key('ledger_list_view'),
                      padding: const EdgeInsets.all(16),
                      itemCount: _items.length,
                      itemBuilder: (context, index) {
                        final raw = _items[index];
                        final item = raw is Map<String, dynamic>
                            ? raw
                            : <String, dynamic>{};
                        final id = (item['id'] as num?)?.toInt() ?? (index + 1);
                        final delta = (item['delta'] as num?)?.toInt() ?? 0;
                        final rawReason = (item['reason'] as String?) ?? '';
                        final reasonLabel = _formatLedgerReason(rawReason);
                        final tickNo = (item['tick_no'] as num?)?.toInt();
                        final createdAt = (item['created_at'] as String?) ?? '';
                        final isPositive = delta >= 0;
                        final signedDelta =
                            isPositive ? '+$delta' : '$delta';

                        return MaritimeWoodCard(
                          key: Key('ledger_item_card_$id'),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: isPositive
                                  ? const Color(0xFF14532D)
                                  : const Color(0xFF7F1D1D),
                              child: Icon(
                                isPositive
                                    ? Icons.trending_up
                                    : Icons.trending_down,
                                color: isPositive
                                    ? const Color(0xFF4ADE80)
                                    : const Color(0xFFF87171),
                              ),
                            ),
                            title: Text(
                              '$signedDelta Koin ($reasonLabel)',
                              style: MaritimePalette.cinzel(
                                color: isPositive
                                    ? MaritimePalette.gold
                                    : const Color(0xFFFCA5A5),
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            subtitle: Text(
                              tickNo != null
                                  ? 'Tick #$tickNo${createdAt.isNotEmpty ? ' • $createdAt' : ''}'
                                  : (createdAt.isNotEmpty
                                      ? createdAt
                                      : 'Catatan Kas Armada'),
                              style: const TextStyle(
                                color: MaritimePalette.parchmentMuted,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
    );
  }
}

class AchievementsScreen extends StatefulWidget {
  final JalurRempahApiClient api;

  const AchievementsScreen({
    super.key,
    required this.api,
  });

  @override
  State<AchievementsScreen> createState() => _AchievementsScreenState();
}

class _AchievementsScreenState extends State<AchievementsScreen> {
  bool _loading = true;
  List<AchievementItemModel> _items = kDefaultAchievements;

  @override
  void initState() {
    super.initState();
    _loadAchievements();
  }

  Future<void> _loadAchievements() async {
    setState(() {
      _loading = true;
    });
    try {
      final fetched = await widget.api.getAchievements();
      if (!mounted) return;
      setState(() {
        _items = fetched.isNotEmpty ? fetched : kDefaultAchievements;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _items = kDefaultAchievements;
        _loading = false;
      });
    }
  }

  void _showAchievementDetails(AchievementItemModel ach) {
    HapticFeedback.lightImpact();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          key: Key('achievement_tooltip_snackbar_${ach.code}'),
          content: Text(
            '${ach.iconEmoji} ${ach.title}: ${ach.description} • Hadiah: +${ach.rewardCoins} koin',
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final unlockedCount = _items.where((a) => a.isUnlocked).length;
    return Scaffold(
      key: const Key('achievements_screen'),
      appBar: AppBar(
        title: Text('Pencapaian ($unlockedCount/${_items.length})'),
        actions: [
          IconButton(
            key: const Key('refresh_achievements_button'),
            tooltip: 'Muat Ulang Pencapaian',
            icon: const Icon(Icons.refresh),
            onPressed: _loadAchievements,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : GridView.builder(
              key: const Key('achievements_grid'),
              padding: const EdgeInsets.all(14),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 0.92,
              ),
              itemCount: _items.length,
              itemBuilder: (context, index) {
                final ach = _items[index];
                final isUnlocked = ach.isUnlocked;
                final badgeColor =
                    isUnlocked ? MaritimePalette.gold : Colors.grey;
                return Tooltip(
                  message:
                      '${ach.description} (Hadiah: +${ach.rewardCoins} koin)',
                  child: InkWell(
                    key: Key('achievement_badge_${ach.code}'),
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => _showAchievementDetails(ach),
                    child: MaritimeWoodCard(
                      margin: EdgeInsets.zero,
                      borderColor: badgeColor,
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: isUnlocked
                                  ? MaritimePalette.gold.withValues(alpha: 0.22)
                                  : Colors.grey.withValues(alpha: 0.18),
                              border: Border.all(
                                color: badgeColor,
                                width: 2,
                              ),
                            ),
                            child: Text(
                              ach.iconEmoji,
                              style: TextStyle(
                                fontSize: 22,
                                color: isUnlocked ? null : Colors.grey,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            ach.title,
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13.5,
                              color: isUnlocked
                                  ? MaritimePalette.gold
                                  : Colors.grey.shade400,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            ach.description,
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11.5,
                              color: isUnlocked
                                  ? MaritimePalette.parchment
                                  : Colors.grey.shade500,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            isUnlocked
                                ? 'Terbuka • +${ach.rewardCoins} koin'
                                : 'Terkunci • +${ach.rewardCoins} koin',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: badgeColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}

class AuthScreen extends StatefulWidget {
  final JalurRempahApiClient api;
  final VoidCallback onAuthenticated;

  const AuthScreen({
    super.key,
    required this.api,
    required this.onAuthenticated,
  });

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final TextEditingController _confirmPasswordCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    serverClientId:
        '80116590063-2fqdtofo1d1jmv42qbgki8ej0dns0ori.apps.googleusercontent.com',
    scopes: ['email', 'profile'],
  );
  bool _isRegisterMode = false;
  bool _tosAccepted = true;
  bool _busy = false;
  String? _errorMsg;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmPasswordCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isRegisterMode) {
      final isFormValid = _formKey.currentState?.validate() ?? true;
      if (!isFormValid || _confirmPasswordCtrl.text != _passwordCtrl.text) {
        setState(() {
          _errorMsg = 'Kata sandi tidak cocok';
        });
        return;
      }
    }
    setState(() {
      _busy = true;
      _errorMsg = null;
    });
    try {
      if (_isRegisterMode) {
        if (!_tosAccepted) {
          setState(() {
            _errorMsg = 'Anda harus menyetujui Syarat & Ketentuan';
          });
          return;
        }
        await widget.api.register(
          _emailCtrl.text.trim(),
          _passwordCtrl.text,
          _nameCtrl.text.trim(),
        );
      } else {
        await widget.api.login(
          _emailCtrl.text.trim(),
          _passwordCtrl.text,
        );
      }
      widget.onAuthenticated();
    } catch (e) {
      setState(() {
        _errorMsg = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _submitGoogleSignIn() async {
    setState(() {
      _busy = true;
      _errorMsg = null;
    });
    try {
      final googleUser = await _googleSignIn.signIn();
      if (googleUser == null) return; // pengguna membatalkan
      final googleAuth = await googleUser.authentication;
      final idToken = googleAuth.idToken;
      if (idToken == null || idToken.isEmpty) {
        throw Exception('Google tidak mengembalikan idToken');
      }
      await widget.api.loginWithGoogle(idToken: idToken);
      widget.onAuthenticated();
    } catch (e) {
      if (!mounted) return;
      final msg = 'Google Login gagal: $e';
      setState(() {
        _errorMsg = msg;
      });
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            key: const Key('google_auth_error_snackbar'),
            content: Text(msg),
          ),
        );
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeCtrl = Provider.of<ThemeController>(context);
    final canSubmit = !_busy && (!_isRegisterMode || _tosAccepted);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Jalur Rempah — Masuk Armada'),
        actions: [
          IconButton(
            key: const Key('auth_theme_toggle_button'),
            tooltip: 'Ganti Mode Tema (Terang/Gelap)',
            icon: Icon(
              themeCtrl.themeMode == ThemeMode.dark
                  ? Icons.dark_mode
                  : Icons.light_mode,
            ),
            onPressed: () {
              final nextMode = themeCtrl.themeMode == ThemeMode.dark
                  ? ThemeMode.light
                  : ThemeMode.dark;
              themeCtrl.setThemeMode(nextMode);
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Program Kapal Dagangmu di Nusantara',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              const Text(
                'Otomatisasi armada rempah dengan Bahasa Aturan (DSL), jelajahi 6 pelabuhan Nusantara, dan bangun kejayaan niaga.',
              ),
              const SizedBox(height: 16),
              TextField(
                key: const Key('auth_email_field'),
                controller: _emailCtrl,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('auth_password_field'),
                controller: _passwordCtrl,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Kata Sandi',
                  border: OutlineInputBorder(),
                ),
              ),
              if (_isRegisterMode) ...[
                const SizedBox(height: 12),
                TextFormField(
                  key: const Key('auth_confirm_password_field'),
                  controller: _confirmPasswordCtrl,
                  obscureText: true,
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  decoration: const InputDecoration(
                    labelText: 'Ulangi Kata Sandi',
                    border: OutlineInputBorder(),
                  ),
                  validator: (_) {
                    if (_confirmPasswordCtrl.text != _passwordCtrl.text) {
                      return 'Kata sandi tidak cocok';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('auth_display_name_field'),
                  controller: _nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Nama Tampilan Nahkoda',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                CheckboxListTile(
                  key: const Key('auth_tos_checkbox'),
                  contentPadding: EdgeInsets.zero,
                  value: _tosAccepted,
                  onChanged: (val) {
                    setState(() {
                      _tosAccepted = val ?? false;
                    });
                  },
                  title: const Text(
                    'Saya menyetujui Syarat & Ketentuan',
                    style:
                        TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
                  ),
                  subtitle: const Text(
                    'Persetujuan wajib sesuai UU Pelindungan Data Pribadi (UU PDP) & Hukum In-Game v1.0.',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    key: const Key('auth_read_tos_button'),
                    icon: const Icon(Icons.menu_book_outlined, size: 18),
                    label: const Text('Baca Syarat & Ketentuan'),
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      Navigator.of(context).push(
                        GamePageRoute<void>(
                          page: LegalDocumentsScreen(api: widget.api),
                        ),
                      );
                    },
                  ),
                ),
              ],
              if (_errorMsg != null) ...[
                const SizedBox(height: 12),
                Text(
                  _errorMsg!,
                  style: const TextStyle(color: Colors.red),
                ),
              ],
              const SizedBox(height: 16),
              ElevatedButton(
                key: const Key('auth_submit_button'),
                onPressed: canSubmit
                    ? () {
                        HapticFeedback.lightImpact();
                        AudioManager().playSfx('click');
                        _submit();
                      }
                    : null,
                child: Text(_isRegisterMode ? 'Daftar & Buat Kapal' : 'Masuk'),
              )
                  .animate()
                  .scale(
                    begin: const Offset(0.9, 0.9),
                    end: const Offset(1, 1),
                    duration: 300.ms,
                    curve: Curves.easeOutBack,
                  )
                  .shimmer(duration: 600.ms, color: const Color(0x66FFF5DC)),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                key: const Key('auth_google_login_button'),
                onPressed: _busy ? null : _submitGoogleSignIn,
                icon: const Icon(Icons.g_mobiledata, size: 26),
                label: const Text('Masuk dengan Google'),
              ),
              TextButton(
                key: const Key('auth_toggle_mode_button'),
                onPressed: () {
                  setState(() {
                    _isRegisterMode = !_isRegisterMode;
                    _errorMsg = null;
                  });
                },
                child: Text(
                  _isRegisterMode
                      ? 'Sudah punya akun? Masuk'
                      : 'Belum punya akun? Daftar Baru',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// 6. Shell Dashboard Utama (Pasar & Peta, Bursa P2P, IDE Aturan, Kapal, Profil)
// ============================================================================

class MainDashboardShell extends StatefulWidget {
  final JalurRempahApiClient api;
  final VoidCallback onLogout;

  const MainDashboardShell({
    super.key,
    required this.api,
    required this.onLogout,
  });

  @override
  State<MainDashboardShell> createState() => _MainDashboardShellState();
}

class _MainDashboardShellState extends State<MainDashboardShell>
    with WidgetsBindingObserver {
  int _tabIndex = 0;
  bool _isMapInteracting = false;
  int _currentTick = 100;
  int _combatShakeCounter = 0;
  String? _lastFloatingRewardText;
  String _selectedPortCode = 'banda';
  String _selectedCommodity = 'pala';
  late final NpcSimulationEngine _npcEngine;

  // Data Profil, Rank System, & Progressive Level (Langkah 2 & 3)
  int _playerId = 1;
  String _playerDisplayName = 'Nahkoda_Satu';
  int _playerCoins = 1000;
  int _playerNetWorth = 1350;
  String _playerTitle = 'Juragan';
  int _playerRank = 1;
  int _playerLevel = 1;
  int _playerXpToNextLevel = 3650;
  int _tutorialStep = 0;
  List<DailyQuestItemModel> _dailyQuests = kDefaultDailyQuests;
  String? _questFeedbackBanner;

  // Data Sistem Aliansi Dagang / Guilds & World Boss (Fase 8)
  List<GuildSummaryModel> _guildDirectory = kDefaultGuildDirectory;
  GuildDetailModel? _currentGuild;
  int? _playerGuildId;
  int? _joiningGuildId;
  String _guildSearchQuery = '';
  final _guildSearchCtrl = TextEditingController();
  final _guildCreateNameCtrl =
      TextEditingController(text: 'Aliansi Rempah Nusantara');
  final _guildCreateDescCtrl =
      TextEditingController(text: 'Armada niaga rempah lintas samudra');
  final _guildDonateAmountCtrl = TextEditingController(text: '1000');
  String? _guildFeedbackBanner;

  // Data Dunia, Peta 8 Negara, Pasar, & World Events (Fase 4 & Fase 5)
  List<PortModel> _ports = const <PortModel>[];
  List<MapPortNode> _worldPorts = kNusantaraPortNodes;
  List<CommodityCatalogItemModel> _worldCommodities =
      kExtendedCommoditiesCatalog;
  List<MarketItemModel> _marketItems = const <MarketItemModel>[];
  List<PricePointModel> _priceHistory = const <PricePointModel>[];
  List<WorldEventItemModel> _worldEvents = const <WorldEventItemModel>[];

  // Data Armada, Galangan 5 Tingkat Kapal, & Naval Combat (Fase 6)
  ShipModel? _ship;
  List<ShipModel> _fleet = const <ShipModel>[
    ShipModel(
      id: 1,
      name: 'Kapal Perintis',
      capacity: 35,
      status: 'docked',
      portId: 1,
      destPort: null,
      arriveTick: null,
      etaTicks: 0,
      cargo: <CargoItemModel>[],
    ),
  ];
  int get _fleetCount => _fleet.length;
  int _shipAttackPower = 0;
  int _shipDefensePower = 65;
  int _shipMaxDefensePower = 100;
  List<CombatLogItemModel> _combatLogs = const <CombatLogItemModel>[];
  List<CombatNotificationModel> _combatNotifications =
      const <CombatNotificationModel>[];
  int _unreadCombatNotifications = 0;

  // Data Bursa P2P & Kontrak NPC (Langkah 5 & Fase 3)
  List<P2pOrderItemModel> _p2pOrders = const <P2pOrderItemModel>[];
  List<TradeContractModel> _tradeContracts = kDefaultTradeContracts;
  String _p2pOrderType = 'auction';
  int _p2pCommodityId = 1;
  final _p2pQtyCtrl = TextEditingController(text: '2');
  final _p2pUnitPriceCtrl = TextEditingController(text: '75');
  final _p2pTargetPlayerCtrl = TextEditingController();
  String? _p2pFeedbackBanner;

  // Auto-Tick & Daily Login Reward (Fase 2)
  Timer? _autoTickTimer;
  bool _checkedDailyReward = false;

  // Data IDE Bahasa Aturan & Block Builder (Langkah 6)
  bool _isBlockBuilderMode = false;
  String _blockCondFunc = 'di';
  String _blockCondArg = 'Batavia';
  String _blockActionFunc = 'beli';
  String _blockActionArg = 'pala';

  List<RuleTemplateModel> _templates = const <RuleTemplateModel>[];
  List<RuleValidationErrorModel> _validationErrors =
      const <RuleValidationErrorModel>[];
  SandboxResultModel? _sandboxResult;
  List<ActionLogItemModel> _logs = const <ActionLogItemModel>[];
  List<LeaderboardItemModel> _leaderboard = const <LeaderboardItemModel>[];

  int _ruleVersion = 0;
  final _ruleEditorCtrl = DslSyntaxHighlightController();
  String? _statusBanner;
  String? _fleetNotice;

  void _onNpcSimulationUpdated() {
    if (mounted) {
      setState(() {});
    }
  }

  void _startAutoTickTimer() {
    _autoTickTimer?.cancel();
    _autoTickTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _refreshCoreData(),
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _npcEngine = NpcSimulationEngine();
    _npcEngine.addListener(_onNpcSimulationUpdated);
    _npcEngine.start();
    _autoTickTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _refreshCoreData(),
    );
    _refreshAll();
    _checkDailyRewardOnStartup();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      _npcEngine.pause();
      _autoTickTimer?.cancel();
      _autoTickTimer = null;
    } else if (state == AppLifecycleState.resumed) {
      _npcEngine.resume();
      if (_autoTickTimer == null) {
        _startAutoTickTimer();
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _autoTickTimer?.cancel();
    _autoTickTimer = null;
    _npcEngine.removeListener(_onNpcSimulationUpdated);
    _npcEngine.dispose();
    _ruleEditorCtrl.dispose();
    _p2pQtyCtrl.dispose();
    _p2pUnitPriceCtrl.dispose();
    _p2pTargetPlayerCtrl.dispose();
    _guildSearchCtrl.dispose();
    _guildCreateNameCtrl.dispose();
    _guildCreateDescCtrl.dispose();
    _guildDonateAmountCtrl.dispose();
    super.dispose();
  }

  Future<void> _refreshCoreData() async {
    try {
      final results = await Future.wait<dynamic>(<Future<dynamic>>[
        widget.api.getProfile(),
        widget.api.getShips(),
      ]);
      if (!mounted) return;
      final profile = results[0] as Map<String, dynamic>;
      final shipsList = results[1] as List<ShipModel>;
      setState(() {
        final fetchedCoins =
            (profile['coins'] as num?)?.toInt() ?? _playerCoins;
        if (fetchedCoins > _playerCoins) {
          final delta = fetchedCoins - _playerCoins;
          AudioManager().playSfx('coin');
          HapticFeedback.heavyImpact();
          _lastFloatingRewardText = '+$delta';
        }
        _playerCoins = fetchedCoins;
        _playerNetWorth =
            (profile['net_worth'] as num?)?.toInt() ?? _playerCoins;
        if (widget.api.latestServerTick > 0) {
          _currentTick = widget.api.latestServerTick;
        }
        if (shipsList.isNotEmpty) {
          _fleet = shipsList;
          final activeShip = _ship != null
              ? (_fleet.where((s) => s.id == _ship!.id).firstOrNull ??
                  _fleet.first)
              : _fleet.first;
          _ship = activeShip;
          _shipAttackPower = activeShip.attackPower;
          _shipDefensePower = activeShip.defensePower;
          _shipMaxDefensePower = activeShip.maxDefensePower;
        }
      });
    } catch (_) {
      // Abaikan kegagalan jaringan saat auto-tick periodik
    }
  }

  Future<void> _checkDailyRewardOnStartup() async {
    if (_checkedDailyReward) return;
    _checkedDailyReward = true;
    try {
      final status = await widget.api.getDailyRewardStatus();
      if (!mounted) return;
      if (!status.claimedToday) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _showDailyRewardDialog(status);
          }
        });
      }
    } catch (_) {
      // Abaikan jika gagal mengambil status daily reward
    }
  }

  Future<void> _showDailyRewardDialog(DailyRewardStatusModel status) async {
    const dayRewards = <int>[100, 200, 300, 500, 700, 1000, 2000];
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          key: const Key('daily_reward_dialog'),
          backgroundColor: MaritimePalette.carvedMahogany,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: const BorderSide(color: MaritimePalette.gold, width: 1.5),
          ),
          title: Text(
            'Hadiah Login Harian (Streak: ${status.currentStreak} Hari)',
            style: MaritimePalette.cinzel(
              color: MaritimePalette.gold,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: SizedBox(
            width: 340,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Klaim hadiah harianmu setiap 24 jam! Hari ke-7 memberikan +2.000 Koin & 1 Kapal Tier 2 gratis.',
                  style: TextStyle(
                    color: MaritimePalette.parchment,
                    fontSize: 12.5,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: List<Widget>.generate(7, (idx) {
                    final day = idx + 1;
                    final reward = dayRewards[idx];
                    final isPassed = day <= status.currentStreak;
                    final isCurrentDay = day == status.nextStreak;
                    return Container(
                      key: Key('daily_reward_day_box_$day'),
                      width: 86,
                      padding: const EdgeInsets.symmetric(
                        vertical: 8,
                        horizontal: 6,
                      ),
                      decoration: BoxDecoration(
                        color: isPassed
                            ? MaritimePalette.gold.withValues(alpha: 0.25)
                            : isCurrentDay
                                ? MaritimePalette.weatheredTeak
                                : Colors.black26,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: (isPassed || isCurrentDay)
                              ? MaritimePalette.gold
                              : Colors.grey.shade700,
                          width: isCurrentDay ? 2.0 : 1.2,
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Hari $day',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                              color: isPassed
                                  ? MaritimePalette.gold
                                  : MaritimePalette.parchment,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '+$reward',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: isPassed
                                  ? MaritimePalette.gold
                                  : Colors.amberAccent,
                            ),
                          ),
                          if (day == 7)
                            const Text(
                              '+Kapal T2',
                              style: TextStyle(
                                fontSize: 10,
                                color: MaritimePalette.gold,
                              ),
                            ),
                        ],
                      ),
                    );
                  }),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              key: const Key('close_daily_reward_dialog_button'),
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Nanti'),
            ),
            ElevatedButton.icon(
              key: const Key('claim_daily_reward_button'),
              style: MaritimePalette.goldCoinButtonStyle(),
              onPressed: status.claimedToday
                  ? null
                  : () async {
                      final messenger = ScaffoldMessenger.of(context);
                      Navigator.of(ctx).pop();
                      try {
                        final res = await widget.api.claimDailyReward();
                        if (!mounted) return;
                        final coinsAwarded =
                            (res['coins_awarded'] as num?)?.toInt() ??
                                status.nextRewardCoins;
                        HapticFeedback.heavyImpact();
                        AudioManager().playSfx('coin');
                        setState(() {
                          _playerCoins += coinsAwarded;
                          _playerNetWorth += coinsAwarded;
                          _lastFloatingRewardText = '+2000 koin';
                        });
                        messenger
                          ..hideCurrentSnackBar()
                          ..showSnackBar(
                            SnackBar(
                              key: const Key('daily_reward_claimed_snackbar'),
                              backgroundColor: Colors.green,
                              content: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      'Hadiah harian berhasil diklaim! +$coinsAwarded koin',
                                    ),
                                  ),
                                  const FloatingRewardText(text: '+2000 koin'),
                                ],
                              ),
                            ),
                          );
                      } catch (e) {
                        if (!mounted) return;
                        final errMsg =
                            e.toString().replaceFirst('Exception: ', '');
                        messenger
                          ..hideCurrentSnackBar()
                          ..showSnackBar(
                            SnackBar(
                              backgroundColor: Colors.red,
                              content: Text(errMsg),
                            ),
                          );
                      }
                    },
              icon: const Icon(Icons.card_giftcard, size: 18),
              label: const Text('Klaim Hadiah'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _refreshAll() async {
    final results = await Future.wait<dynamic>(<Future<dynamic>>[
      widget.api.getProfile(),
      widget.api.getPorts(),
      widget.api.getWorldPorts(),
      widget.api.getWorldCommodities(),
      widget.api.getWorldEvents(),
      widget.api.getMarket(_selectedPortCode),
      widget.api.getPriceHistory(_selectedPortCode, _selectedCommodity),
      widget.api.getShips(),
      widget.api.getRuleTemplates(),
      widget.api.getNpcCaptains(),
      widget.api.getTradeContracts(),
    ]);

    final profile = results[0] as Map<String, dynamic>;
    final ports = results[1] as List<PortModel>;
    final worldPorts = results[2] as List<MapPortNode>;
    final worldCommodities = results[3] as List<CommodityCatalogItemModel>;
    final events = results[4] as List<WorldEventItemModel>;
    final market = results[5] as List<MarketItemModel>;
    final history = results[6] as List<PricePointModel>;
    final shipsList = results[7] as List<ShipModel>;
    final templates = results[8] as List<RuleTemplateModel>;
    final npcCaptains = results[9] as List<NpcCaptain>;
    final contracts = results[10] as List<TradeContractModel>;
    final ShipModel fallbackShip = shipsList.isNotEmpty
        ? shipsList.first
        : await widget.api.getPrimaryShip();

    if (!mounted) return;
    setState(() {
      _playerId = (profile['id'] as num?)?.toInt() ?? 1;
      _playerDisplayName =
          (profile['display_name'] as String?) ?? 'Nahkoda_Satu';
      final fetchedCoins = (profile['coins'] as num?)?.toInt() ?? 1000;
      if (fetchedCoins > _playerCoins) {
        final delta = fetchedCoins - _playerCoins;
        AudioManager().playSfx('coin');
        HapticFeedback.heavyImpact();
        _lastFloatingRewardText = '+$delta';
      }
      _playerCoins = fetchedCoins;
      _playerNetWorth =
          (profile['net_worth'] as num?)?.toInt() ?? _playerCoins;
      _playerRank = (profile['rank'] as num?)?.toInt() ?? 1;
      final rawTitle = profile['title'] as String?;
      _playerTitle = (rawTitle != null && rawTitle.isNotEmpty)
          ? rawTitle
          : computeRankTitleForNetWorth(_playerNetWorth);

      _playerLevel = (profile['level'] as num?)?.toInt() ??
          computePlayerLevelForNetWorth(_playerNetWorth);
      _playerXpToNextLevel =
          (profile['xp_to_next_level'] as num?)?.toInt() ??
              computeXpToNextLevelForNetWorth(_playerNetWorth);
      _tutorialStep =
          (profile['tutorial_step'] as num?)?.toInt() ?? _tutorialStep;
      _playerGuildId = (profile['guild_id'] as num?)?.toInt();

      _ports = ports;
      _worldPorts = worldPorts
          .map((p) => MapPortNode(
                id: p.id,
                code: p.code,
                name: p.name,
                countryCode: p.countryCode,
                countryName: p.countryName,
                relX: p.relX,
                relY: p.relY,
                minLevelRequired: p.minLevelRequired,
                isLocked: p.isLocked || (p.minLevelRequired > _playerLevel),
              ))
          .toList();
      _worldCommodities = worldCommodities
          .map((c) => CommodityCatalogItemModel(
                id: c.id,
                code: c.code,
                name: c.name,
                category: c.category,
                originPort: c.originPort,
                countryCode: c.countryCode,
                countryName: c.countryName,
                basePrice: c.basePrice,
                rarity: c.rarity,
                description: c.description,
                minLevelRequired: c.minLevelRequired,
                isLocked: c.isLocked || (c.minLevelRequired > _playerLevel),
              ))
          .toList();
      _worldEvents = events;
      _marketItems = market;
      _priceHistory = history;
      if (events.isNotEmpty && events.first.tickNo > 0) {
        _currentTick = events.first.tickNo;
      } else if (history.isNotEmpty && history.last.tickNo > 0) {
        _currentTick = history.last.tickNo;
      } else {
        _currentTick = widget.api.latestServerTick;
      }
      _fleet = shipsList.isNotEmpty ? shipsList : <ShipModel>[fallbackShip];
      final ShipModel activeShip = _ship != null
          ? (_fleet.where((s) => s.id == _ship!.id).firstOrNull ?? _fleet.first)
          : _fleet.first;
      _ship = activeShip;
      _templates = templates;
      if (contracts.isNotEmpty) {
        _tradeContracts = contracts;
      }
      _shipAttackPower = activeShip.attackPower;
      _shipDefensePower = activeShip.defensePower;
      _shipMaxDefensePower = activeShip.maxDefensePower;
      _npcEngine.updateCaptains(npcCaptains, ports: _worldPorts);
    });

    try {
      final combatPayload = await widget.api.getCombatLogsAndNotifications();
      final rawNotifs =
          (combatPayload['notifications'] as List<dynamic>?) ??
              const <dynamic>[];
      final rawCombatLogs =
          (combatPayload['combat_logs'] as List<dynamic>?) ??
              const <dynamic>[];
      if (!mounted) return;
      final parsedNotifs = rawNotifs
          .map((e) =>
              CombatNotificationModel.fromJson(e as Map<String, dynamic>))
          .toList();
      final parsedLogs = rawCombatLogs
          .map((e) => CombatLogItemModel.fromJson(e as Map<String, dynamic>))
          .toList();
      setState(() {
        _combatNotifications = parsedNotifs;
        _combatLogs = parsedLogs;
        _unreadCombatNotifications = parsedNotifs.length;
        if (parsedNotifs.any((n) => n.severity == 'danger')) {
          AudioManager().playSfx('cannon');
          HapticFeedback.heavyImpact();
          _combatShakeCounter += 1;
        }
        if (parsedLogs.isNotEmpty && _shipDefensePower == 100) {
          _shipDefensePower = parsedLogs.first.shipDefenseAfter;
        }
      });
    } catch (_) {
      // Abaikan jika endpoint log belum memiliki data
    }
  }

  Future<void> _loadTabData(int tabIndex) async {
    final shipId = _ship?.id ?? 1;
    try {
      switch (tabIndex) {
        case 1:
          final res = await Future.wait<dynamic>(<Future<dynamic>>[
            widget.api.getP2pOrders(),
            widget.api.getTradeContracts(),
          ]);
          final p2p = res[0] as List<P2pOrderItemModel>;
          final contracts = res[1] as List<TradeContractModel>;
          if (!mounted) return;
          setState(() {
            _p2pOrders = p2p;
            if (contracts.isNotEmpty) {
              _tradeContracts = contracts;
            }
          });
          break;
        case 2:
          final res = await Future.wait<dynamic>(<Future<dynamic>>[
            widget.api.getShipRules(shipId),
            widget.api.getRuleTemplates(),
          ]);
          final rules = res[0] as Map<String, dynamic>;
          final templates = res[1] as List<RuleTemplateModel>;
          if (!mounted) return;
          setState(() {
            _ruleVersion = (rules['version'] as num?)?.toInt() ?? 0;
            if (_ruleEditorCtrl.text.isEmpty) {
              _ruleEditorCtrl.text = (rules['source'] as String?) ?? '';
            }
            _templates = templates;
          });
          break;
        case 3:
          final logs = await widget.api.getShipLogs(shipId);
          if (!mounted) return;
          setState(() {
            _logs = logs;
          });
          break;
        case 4:
          final lb = await widget.api.getLeaderboard();
          if (mounted) {
            setState(() {
              _leaderboard = lb;
            });
          }
          try {
            final quests = await widget.api.getQuests();
            if (!mounted) return;
            setState(() {
              _dailyQuests = quests;
            });
          } catch (_) {
            // Fallback ke kDefaultDailyQuests
          }
          break;
        case 5:
          final guilds = await widget.api.getGuilds(query: _guildSearchQuery);
          final myGuildId = _playerGuildId;
          GuildDetailModel? detail;
          if (myGuildId != null && myGuildId > 0) {
            detail = await widget.api.getGuildDetail(myGuildId);
          }
          if (!mounted) return;
          setState(() {
            _guildDirectory = guilds;
            if (detail != null) {
              _currentGuild = detail;
            }
          });
          break;
      }
    } catch (_) {
      // Abaikan kegagalan jaringan saat lazy load tab
    }
  }

  Future<void> _joinGuild(int guildId) async {
    if (_joiningGuildId != null) return;
    setState(() {
      _joiningGuildId = guildId;
    });
    final messenger = ScaffoldMessenger.of(context);
    try {
      final joined = await widget.api.joinGuild(guildId);
      if (!mounted) return;
      setState(() {
        _currentGuild = joined;
        _guildFeedbackBanner = 'Anda resmi bergabung ke dalam ${joined.name}!';
      });
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            key: Key('guild_join_success_snackbar'),
            backgroundColor: Colors.green,
            content: Text('Berhasil bergabung dengan Aliansi!'),
          ),
        );
      await _refreshAll();
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString().replaceFirst('Exception: ', '');
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            key: const Key('guild_join_error_snackbar'),
            backgroundColor: Colors.red,
            content: Text(msg),
          ),
        );
    } finally {
      if (mounted) {
        setState(() {
          _joiningGuildId = null;
        });
      }
    }
  }

  Future<void> _selectPort(String portCode) async {
    final market = await widget.api.getMarket(portCode);
    final history = await widget.api.getPriceHistory(
      portCode,
      _selectedCommodity,
    );
    if (!mounted) return;
    setState(() {
      _selectedPortCode = portCode;
      _marketItems = market;
      _priceHistory = history;
    });
  }

  int _referenceMarketPriceForCommodity(int commodityId) {
    final cat = kExtendedCommoditiesCatalog
            .where((c) => c.id == commodityId)
            .firstOrNull ??
        kExtendedCommoditiesCatalog.first;
    final live = _marketItems
        .where((m) => m.commodity.toLowerCase() == cat.code.toLowerCase())
        .firstOrNull;
    return live?.price ?? cat.basePrice;
  }

  String _resolvePortDisplayName(String portCode, String? fallbackName) {
    if (fallbackName != null && fallbackName.trim().isNotEmpty) {
      return fallbackName.trim();
    }
    final fromWorld = _worldPorts
        .where((p) => p.code.toLowerCase() == portCode.toLowerCase())
        .firstOrNull;
    if (fromWorld != null && fromWorld.name.isNotEmpty) {
      return fromWorld.name;
    }
    final fromPorts = _ports
        .where((p) => p.code.toLowerCase() == portCode.toLowerCase())
        .firstOrNull;
    if (fromPorts != null && fromPorts.name.isNotEmpty) {
      return fromPorts.name;
    }
    if (portCode.isEmpty) return 'Pelabuhan';
    return portCode[0].toUpperCase() + portCode.substring(1).toLowerCase();
  }

  Future<void> _showMarketIntelBottomSheet(
    String commodityCode,
    String commodityName,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    Map<String, dynamic> intelPayload;
    try {
      intelPayload = await widget.api.getIntel(
        _selectedPortCode,
        commodityCode,
      );
    } catch (e) {
      if (!mounted) return;
      final errMsg = e.toString().replaceFirst('Exception: ', '');
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            key: const Key('market_intel_error_snackbar'),
            backgroundColor: Colors.red,
            content: Text(errMsg),
          ),
        );
      return;
    }
    if (!mounted) return;

    final rawItems =
        (intelPayload['items'] as List<dynamic>?) ?? const <dynamic>[];
    final matchingItems = rawItems.where((raw) {
      if (raw is! Map<String, dynamic>) return false;
      final cCode = (raw['commodity_code'] as String?)?.toLowerCase();
      return cCode == null ||
          cCode.isEmpty ||
          cCode == commodityCode.toLowerCase();
    }).toList();
    final effectiveItems =
        matchingItems.isNotEmpty ? matchingItems : rawItems;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: MaritimePalette.carvedMahogany,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        side: BorderSide(color: MaritimePalette.gold, width: 1.5),
      ),
      builder: (ctx) {
        return SafeArea(
          key: const Key('intel_bottom_sheet'),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.travel_explore,
                      color: MaritimePalette.gold,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Intelijen Harga Pelabuhan Lain (${commodityName.toUpperCase()})',
                        style: MaritimePalette.cinzel(
                          color: MaritimePalette.gold,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                const Text(
                  'Catatan harga jual terakhir yang diketahui awak kapal di berbagai pelabuhan tujuan:',
                  style: TextStyle(
                    color: MaritimePalette.parchmentMuted,
                    fontSize: 12.5,
                  ),
                ),
                const SizedBox(height: 12),
                if (effectiveItems.isEmpty)
                  const MaritimeWoodCard(
                    child: Padding(
                      padding: EdgeInsets.all(14),
                      child: Text('Belum ada data intelijen pelabuhan lain.'),
                    ),
                  )
                else
                  ...effectiveItems.map((raw) {
                    final item = raw is Map<String, dynamic>
                        ? raw
                        : <String, dynamic>{};
                    final portCode = (item['port_code'] as String?) ?? 'banda';
                    final portName = _resolvePortDisplayName(
                      portCode,
                      item['port_name'] as String?,
                    );
                    final price = (item['price'] as num?)?.toInt() ?? 0;
                    final stock = (item['stock'] as num?)?.toInt() ?? 0;
                    final tickSeen =
                        (item['tick_seen'] as num?)?.toInt() ?? _currentTick;
                    final ageTicks = (item['age_ticks'] as num?)?.toInt() ?? 0;

                    return MaritimeWoodCard(
                      key: Key('intel_port_card_${portCode.toLowerCase()}'),
                      child: ListTile(
                        leading: const CircleAvatar(
                          backgroundColor: MaritimePalette.darkWoodBrown,
                          child: Icon(
                            Icons.anchor,
                            color: MaritimePalette.gold,
                            size: 18,
                          ),
                        ),
                        title: Text(
                          '$portName: $price koin',
                          style: MaritimePalette.cinzel(
                            color: MaritimePalette.gold,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        subtitle: Text(
                          'Stok: $stock • Tick #$tickSeen ($ageTicks tick lalu)',
                          style: const TextStyle(
                            color: MaritimePalette.parchment,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    );
                  }),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  key: const Key('close_intel_sheet_button'),
                  style: MaritimePalette.goldCoinButtonStyle(),
                  onPressed: () => Navigator.of(ctx).pop(),
                  icon: const Icon(Icons.check_circle_outline),
                  label: const Text('Tutup Intel'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ==========================================================================
  // TAB 1: PASAR NUSANTARA, PETA CUSTOMPAINTER, WORLD EVENTS, & 10 KOMODITAS
  // ==========================================================================

  Widget _buildMarketTab() {
    final activeSpecialEvents =
        _worldEvents.where((e) => e.isActive && e.isSpecialAlert).toList();
    final eventPortIds = activeSpecialEvents
        .where((e) => e.portId != null)
        .map((e) => e.portId!)
        .toSet();

    final int primaryShipId =
        _ship?.id ?? (_fleet.isNotEmpty ? _fleet.first.id : 1);
    final shipMarkers = _fleet
        .map(
          (s) => MapShipMarker(
            id: s.id,
            name: s.name,
            status: s.status,
            currentPortId: s.portId,
            destinationPortId: s.destPort,
            departTick: s.departTick ??
                (s.arriveTick != null
                    ? (s.arriveTick! - (s.etaTicks > 0 ? s.etaTicks * 2 : 10))
                    : null),
            arriveTick: s.arriveTick,
            tier: s.tier,
            isPrimary: s.id == primaryShipId,
          ),
        )
        .toList();

    // Gabungkan data harga pasar live dengan katalog 10 komoditas Nusantara
    final liveByCode = <String, MarketItemModel>{
      for (final m in _marketItems) m.commodity.toLowerCase(): m,
    };

    return MarketScreen(
      builder: (context, orientation) {
        final isLandscape = orientation == Orientation.landscape;
        return Stack(
          children: [
            ListView(
              physics: _isMapInteracting
                  ? const NeverScrollableScrollPhysics()
                  : null,
              padding: const EdgeInsets.all(16),
              children: [
        if (_tutorialStep == 0)
          MaritimeWoodCard(
            key: const Key('tutorial_onboarding_banner'),
            color: const Color(0xFFDBEAFE),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.school_outlined, color: Color(0xFF1D4ED8)),
                      SizedBox(width: 8),
                      Text(
                        'Panduan Kapten Baru (Tutorial Onboarding)',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1E3A8A),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Selamat datang Kapten! Ayo buka tab Pasar dan beli 10 Garam.',
                    style: TextStyle(color: MaritimePalette.parchment),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton(
                      key: const Key('tutorial_advance_button'),
                      onPressed: () async {
                        final nextStep = await widget.api.advanceTutorial();
                        if (!mounted) return;
                        setState(() {
                          _tutorialStep = nextStep > 0 ? nextStep : 1;
                        });
                      },
                      child: const Text('Mengerti'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        // Banner Peringatan World Events Aktif (Langkah 4)
        if (activeSpecialEvents.isNotEmpty)
          ...activeSpecialEvents.map((ev) {
            final isDanger =
                ev.eventCode == 'WABAH_HAMA' || ev.eventCode == 'EMBARGO_PERANG';
            return MaritimeWoodCard(
              key: const Key('world_event_alert_banner'),
              color: isDanger
                  ? const Color(0xFFFEE2E2)
                  : const Color(0xFFFEF3C7),
              child: ListTile(
                leading: Icon(
                  isDanger ? Icons.warning_amber_rounded : Icons.air_rounded,
                  color: isDanger
                      ? const Color(0xFFB91C1C)
                      : const Color(0xFFB45309),
                ),
                title: Text(
                  'EVENT DUNIA AKTIF: ${ev.title}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: isDanger
                        ? const Color(0xFFFCA5A5)
                        : MaritimePalette.gold,
                  ),
                ),
                subtitle: Text(
                  ev.description.isNotEmpty
                      ? ev.description
                      : 'Wabah Hama di Banda! Harga Pala naik.',
                  style: TextStyle(
                    color: MaritimePalette.parchment,
                  ),
                ),
              ),
            );
          }),
        MaritimeWoodCard(
          key: const Key('season_event_banner'),
          child: const ListTile(
            leading: Icon(Icons.explore_outlined),
            title: Text('Musim Dunia: Angin Muson & Kabut Informasi Aktif'),
            subtitle: Text(
              'Gunakan harga_terakhir(p, k), ambil(slot), simpan(slot, v), dan musim() di Bahasa Aturan.',
            ),
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'Peta Pelabuhan Nusantara',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 6),
        NusantaraMapWidget(
          selectedPortCode: _selectedPortCode,
          ports: _worldPorts,
          ships: shipMarkers,
          npcPositions: _npcEngine.npcPositions,
          eventPortIds: eventPortIds,
          currentTick: _currentTick,
          height: isLandscape ? 320 : 260,
          onSelectPort: _selectPort,
          onInteractionStart: () {
            if (!_isMapInteracting) {
              setState(() {
                _isMapInteracting = true;
              });
            }
          },
          onInteractionEnd: () {
            if (_isMapInteracting) {
              setState(() {
                _isMapInteracting = false;
              });
            }
          },
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: _worldPorts.map((wp) {
            final matchingTreasury = _ports
                .where((p) => p.code == wp.code)
                .firstOrNull
                ?.treasury;
            final selected = wp.code == _selectedPortCode;
            final labelText = wp.isLocked
                ? '🔒 ${wp.name} (Lv.${wp.minLevelRequired})'
                : (matchingTreasury != null
                    ? '${wp.name} (Kas: $matchingTreasury)'
                    : wp.name);
            return ChoiceChip(
              key: Key('port_chip_${wp.code}'),
              label: Text(
                labelText,
                style: TextStyle(
                  color: wp.isLocked ? Colors.grey : null,
                ),
              ),
              selected: selected && !wp.isLocked,
              onSelected: (_) {
                if (wp.isLocked) {
                  NusantaraMapWidget.showLockedPortFeedback(context, wp);
                } else {
                  _selectPort(wp.code);
                }
              },
            );
          }).toList(),
        ),
        const SizedBox(height: 16),
        Text(
          'Harga Pasar & Katalog Komoditas Dunia di ${_selectedPortCode.toUpperCase()} (Level $_playerLevel)',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        ..._worldCommodities.map((cat) {
          final live = liveByCode[cat.code];
          final displayPrice = live?.price ?? cat.basePrice;
          final displayStock = live?.stock ?? 320;
          final displayTarget = live?.target ?? 400;

          void handleCommodityTapOrTrade() {
            if (cat.isLocked) {
              showDialog<void>(
                context: context,
                builder: (ctx) => AlertDialog(
                  key: const Key('locked_commodity_dialog'),
                  title: Text('🔒 ${cat.name} Terkunci'),
                  content: Text(
                    'Komoditas ini berasal dari ${cat.countryName} yang membutuhkan Level ${cat.minLevelRequired}.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      child: const Text('Mengerti'),
                    ),
                  ],
                ),
              );
              return;
            }
            final messenger = ScaffoldMessenger.of(context);
            setState(() {
              _selectedCommodity = cat.code;
            });
            messenger
              ..hideCurrentSnackBar()
              ..showSnackBar(
                SnackBar(
                  key: Key('market_trade_success_snackbar_${cat.code}'),
                  backgroundColor: Colors.green,
                  content: Text(
                    'Berhasil memilih produk ${cat.name} ($displayPrice koin)!',
                  ),
                ),
              );
            if (live != null) {
              widget.api
                  .getPriceHistory(
                _selectedPortCode,
                cat.code,
              )
                  .then((hist) {
                if (!mounted) return;
                setState(() {
                  _priceHistory = hist;
                });
              }).catchError((Object e) {
                if (!mounted) return;
                final msg = e.toString().replaceFirst('Exception: ', '');
                messenger
                  ..hideCurrentSnackBar()
                  ..showSnackBar(
                    SnackBar(
                      key: Key('market_trade_error_snackbar_${cat.code}'),
                      backgroundColor: Colors.red,
                      content: Text(msg),
                    ),
                  );
              });
            }
          }

          final isSelectedCommodity =
              _selectedCommodity.toLowerCase() == cat.code.toLowerCase();

          return Opacity(
            opacity: cat.isLocked ? 0.5 : 1.0,
            child: MaritimeWoodCard(
              key: Key('market_commodity_${cat.code}'),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ListTile(
                    leading: CircleAvatar(
                      backgroundColor:
                          cat.isLocked ? Colors.grey.shade400 : null,
                      child: Text(
                        cat.isLocked
                            ? '🔒'
                            : cat.code.substring(0, 2).toUpperCase(),
                      ),
                    ),
                    title: Row(
                      children: [
                        Text(
                          cat.code.toUpperCase(),
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            cat.isLocked
                                ? '• 🔒 ${cat.name} (Lv.${cat.minLevelRequired})'
                                : '• ${cat.name} (${cat.category})',
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12.5),
                          ),
                        ),
                      ],
                    ),
                    subtitle: Text(
                      cat.isLocked
                          ? 'Negara: ${cat.countryName} (${cat.originPort}) | Butuh Level ${cat.minLevelRequired}'
                          : 'Asal: ${cat.originPort} (${cat.countryName}) | Stok: $displayStock / Target: $displayTarget',
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '$displayPrice koin',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 6),
                        IconButton(
                          key: Key('market_trade_button_${cat.code}'),
                          tooltip: cat.isLocked
                              ? 'Terkunci (Butuh Level ${cat.minLevelRequired})'
                              : 'Beli / Jual ${cat.name}',
                          icon: Icon(
                            cat.isLocked
                                ? Icons.lock_outline
                                : Icons.anchor,
                            color: cat.isLocked
                                ? Colors.grey
                                : MaritimePalette.gold,
                          ),
                          onPressed: handleCommodityTapOrTrade,
                        ),
                      ],
                    ),
                    onTap: handleCommodityTapOrTrade,
                  ),
                  if (isSelectedCommodity && !cat.isLocked)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: ElevatedButton.icon(
                        key: const Key('market_intel_button'),
                        style: MaritimePalette.goldCoinButtonStyle(),
                        onPressed: () {
                          HapticFeedback.lightImpact();
                          AudioManager().playSfx('click');
                          _showMarketIntelBottomSheet(cat.code, cat.name);
                        },
                        icon: const Icon(Icons.travel_explore, size: 18),
                        label: const Text('Lihat Intel Harga Pelabuhan Lain'),
                      ),
                    ),
                ],
              ),
            ),
          );
        }),
        const SizedBox(height: 16),
        Text(
          'Grafik Harga 24 Jam (${_selectedCommodity.toUpperCase()})',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        PriceHistoryChart(points: _priceHistory),
      ],
            ),
            if (isLandscape)
              Positioned(
                top: 8,
                left: 16,
                child: IgnorePointer(
                  child: Container(
                    key: const Key('landscape_floating_hud_badge'),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xCC281815),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: MaritimePalette.gold,
                        width: 1.2,
                      ),
                    ),
                    child: Text(
                      '🧭 Mode Peta Landscape • Pelabuhan: ${_selectedPortCode.toUpperCase()}',
                      style: MaritimePalette.cinzel(
                        color: MaritimePalette.gold,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
            Positioned(
              top: 0,
              left: 16,
              right: 16,
              child: WorldNewsMarquee(
                text: _npcEngine.latestNews,
              ),
            ),
          ],
        );
      },
    );
  }

  // ==========================================================================
  // TAB 2: BURSA P2P TRADING (AUCTION HOUSE & DIRECT TRADE — LANGKAH 5)
  // ==========================================================================

  Future<void> _submitCreateP2pOrder() async {
    final qty = int.tryParse(_p2pQtyCtrl.text.trim()) ?? 0;
    final unitPrice = int.tryParse(_p2pUnitPriceCtrl.text.trim()) ?? 0;
    final refPrice = _referenceMarketPriceForCommodity(_p2pCommodityId);
    final minAllowed = (refPrice * 0.5).ceil();
    final maxAllowed = (refPrice * 2.0).floor();

    if (qty <= 0) {
      setState(() {
        _p2pFeedbackBanner = 'Jumlah komoditas harus lebih dari 0.';
      });
      return;
    }

    if (unitPrice < minAllowed || unitPrice > maxAllowed) {
      setState(() {
        _p2pFeedbackBanner =
            'Peringatan Anti-RMT: Harga per unit ($unitPrice koin) berada di luar batas 50%-200% harga pasar ($minAllowed - $maxAllowed koin)!';
      });
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    try {
      final targetPid = _p2pOrderType == 'direct'
          ? int.tryParse(_p2pTargetPlayerCtrl.text.trim())
          : null;
      final created = await widget.api.createP2pOrder(
        orderType: _p2pOrderType,
        shipId: _ship?.id ?? 1,
        commodityId: _p2pCommodityId,
        qty: qty,
        unitPrice: unitPrice,
        targetPlayerId: targetPid,
      );
      if (!mounted) return;
      final successMsg =
          'Order P2P #${created.id} (${created.commodityCode.toUpperCase()} x${created.qty}) berhasil dipasang di Escrow!';
      setState(() {
        _p2pOrders = <P2pOrderItemModel>[created, ..._p2pOrders];
        _p2pFeedbackBanner = successMsg;
      });
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            key: const Key('p2p_create_order_success_snackbar'),
            backgroundColor: Colors.green,
            content: Text('Berhasil! $successMsg'),
          ),
        );
    } catch (e) {
      if (!mounted) return;
      final errMsg = e.toString().replaceFirst('Exception: ', '');
      setState(() {
        _p2pFeedbackBanner = errMsg;
      });
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            key: const Key('p2p_create_order_error_snackbar'),
            backgroundColor: Colors.red,
            content: Text(errMsg),
          ),
        );
    }
  }

  Widget _buildBursaP2pTab() {
    final refPrice = _referenceMarketPriceForCommodity(_p2pCommodityId);
    final minAllowed = (refPrice * 0.5).ceil();
    final maxAllowed = (refPrice * 2.0).floor();
    final enteredPrice = int.tryParse(_p2pUnitPriceCtrl.text.trim()) ?? refPrice;
    final isOutOfRange = enteredPrice < minAllowed || enteredPrice > maxAllowed;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Bursa P2P Nusantara (Auction House & Direct Trade)',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        const Text(
          'Jual-beli rempah antar-pemain dengan sistem Escrow otomatis dan perlindungan Anti-RMT (50% - 200% harga pasar).',
        ),
        const SizedBox(height: 12),
        MaritimeWoodCard(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Buat Tawaran Jual',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        key: const Key('p2p_order_type_dropdown'),
                        isExpanded: true,
                        initialValue: _p2pOrderType,
                        decoration: const InputDecoration(
                          labelText: 'Tipe Bursa',
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'auction',
                            child: Text('Auction House (Publik)'),
                          ),
                          DropdownMenuItem(
                            value: 'direct',
                            child: Text('Direct Trade (Khusus)'),
                          ),
                        ],
                        onChanged: (v) {
                          if (v != null) {
                            setState(() {
                              _p2pOrderType = v;
                            });
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Builder(
                        builder: (context) {
                          final unlockedCommodities = _worldCommodities
                              .where((c) =>
                                  !c.isLocked &&
                                  c.minLevelRequired <= _playerLevel)
                              .toList();
                          final dropdownItems = unlockedCommodities.isNotEmpty
                              ? unlockedCommodities
                              : _worldCommodities.take(4).toList();
                          if (!dropdownItems
                              .any((c) => c.id == _p2pCommodityId)) {
                            _p2pCommodityId = dropdownItems.first.id;
                          }
                          return DropdownButtonFormField<int>(
                            key: const Key('p2p_commodity_dropdown'),
                            isExpanded: true,
                            initialValue: _p2pCommodityId,
                            decoration: InputDecoration(
                              labelText:
                                  'Produk Terbuka (Lv.$_playerLevel: ${dropdownItems.length} item)',
                              border: const OutlineInputBorder(),
                            ),
                            items: dropdownItems
                                .map(
                                  (c) => DropdownMenuItem<int>(
                                    value: c.id,
                                    child: Text('${c.name} (${c.code})'),
                                  ),
                                )
                                .toList(),
                            onChanged: (v) {
                              if (v != null) {
                                setState(() {
                                  _p2pCommodityId = v;
                                  _p2pUnitPriceCtrl.text =
                                      _referenceMarketPriceForCommodity(v)
                                          .toString();
                                });
                              }
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        key: const Key('p2p_qty_field'),
                        controller: _p2pQtyCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Jumlah (Qty)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        key: const Key('p2p_unit_price_field'),
                        controller: _p2pUnitPriceCtrl,
                        keyboardType: TextInputType.number,
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          labelText:
                              'Harga/Unit (Batas $minAllowed-$maxAllowed)',
                          border: const OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),
                if (_p2pOrderType == 'direct') ...[
                  const SizedBox(height: 10),
                  TextField(
                    key: const Key('p2p_target_player_field'),
                    controller: _p2pTargetPlayerCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'ID Pemain Tujuan (Direct Trade)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
                if (isOutOfRange) ...[
                  const SizedBox(height: 10),
                  Container(
                    key: const Key('p2p_price_warning_banner'),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEE2E2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'Peringatan: Harga $enteredPrice koin di luar batas wajar 50%-200% harga pasar ($minAllowed - $maxAllowed koin).',
                      style: const TextStyle(
                        color: Color(0xFF991B1B),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                FilledButton.icon(
                  key: const Key('p2p_create_order_button'),
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    AudioManager().playSfx('click');
                    _submitCreateP2pOrder();
                  },
                  icon: const Icon(Icons.anchor),
                  label: const Text('Pasang Tawaran di Bursa P2P'),
                )
                    .animate()
                    .scale(
                      begin: const Offset(0.9, 0.9),
                      end: const Offset(1, 1),
                      duration: 300.ms,
                    )
                    .shimmer(duration: 600.ms, color: const Color(0x66FFF5DC)),
              ],
            ),
          ),
        ),
        if (_p2pFeedbackBanner != null) ...[
          const SizedBox(height: 8),
          MaritimeWoodCard(
            key: const Key('p2p_feedback_banner'),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(_p2pFeedbackBanner!),
            ),
          ),
        ],
        const SizedBox(height: 14),
        const Text(
          'Daftar Order Book Aktif',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        ..._p2pOrders.map((ord) {
          final isMine = ord.sellerId == _playerId || ord.sellerName == 'Anda';
          return MaritimeWoodCard(
            key: Key('p2p_order_card_${ord.id}'),
            child: ListTile(
              leading: CircleAvatar(
                child: Text(
                  ord.orderType == 'direct' ? 'DT' : 'AH',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              title: Text(
                '${ord.commodityCode.toUpperCase()} x${ord.qty} • ${ord.unitPrice} koin/unit (Total: ${ord.totalPrice})',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                'Penjual: ${ord.sellerName} | Pelabuhan: ${ord.portCode.toUpperCase()} | Status: ${ord.status}',
              ),
              trailing: Wrap(
                spacing: 6,
                children: [
                  if (!isMine && ord.status == 'open')
                    FilledButton.tonal(
                      key: Key('p2p_accept_button_${ord.id}'),
                      onPressed: () async {
                        final messenger = ScaffoldMessenger.of(context);
                        try {
                          await widget.api.acceptP2pOrder(
                            ord.id,
                            _ship?.id ?? 1,
                          );
                          if (!mounted) return;
                          final msg =
                              'Berhasil membeli/menerima Order #${ord.id}!';
                          setState(() {
                            _p2pOrders = _p2pOrders
                                .where((x) => x.id != ord.id)
                                .toList();
                            _p2pFeedbackBanner = msg;
                          });
                          messenger
                            ..hideCurrentSnackBar()
                            ..showSnackBar(
                              SnackBar(
                                key: Key('p2p_accept_success_snackbar_${ord.id}'),
                                backgroundColor: Colors.green,
                                content: Text(msg),
                              ),
                            );
                        } catch (e) {
                          if (!mounted) return;
                          final errMsg =
                              e.toString().replaceFirst('Exception: ', '');
                          setState(() {
                            _p2pFeedbackBanner = errMsg;
                          });
                          messenger
                            ..hideCurrentSnackBar()
                            ..showSnackBar(
                              SnackBar(
                                key: Key('p2p_accept_error_snackbar_${ord.id}'),
                                backgroundColor: Colors.red,
                                content: Text(errMsg),
                              ),
                            );
                        }
                      },
                      child: const Text('Beli/Terima'),
                    ),
                  if (isMine && ord.status == 'open')
                    OutlinedButton(
                      key: Key('p2p_cancel_button_${ord.id}'),
                      onPressed: () async {
                        final messenger = ScaffoldMessenger.of(context);
                        try {
                          await widget.api.cancelP2pOrder(ord.id);
                          if (!mounted) return;
                          final msg =
                              'Order #${ord.id} dibatalkan; barang dikembalikan dari Escrow ke kapal.';
                          setState(() {
                            _p2pOrders = _p2pOrders
                                .where((x) => x.id != ord.id)
                                .toList();
                            _p2pFeedbackBanner = msg;
                          });
                          messenger
                            ..hideCurrentSnackBar()
                            ..showSnackBar(
                              SnackBar(
                                key: Key('p2p_cancel_success_snackbar_${ord.id}'),
                                backgroundColor: Colors.green,
                                content: Text('Berhasil! $msg'),
                              ),
                            );
                        } catch (e) {
                          if (!mounted) return;
                          final errMsg =
                              e.toString().replaceFirst('Exception: ', '');
                          setState(() {
                            _p2pFeedbackBanner = errMsg;
                          });
                          messenger
                            ..hideCurrentSnackBar()
                            ..showSnackBar(
                              SnackBar(
                                key: Key('p2p_cancel_error_snackbar_${ord.id}'),
                                backgroundColor: Colors.red,
                                content: Text(errMsg),
                              ),
                            );
                        }
                      },
                      child: const Text('Batalkan'),
                    ),
                ],
              ),
            ),
          );
        }),
        const SizedBox(height: 18),
        const Text(
          'Kontrak Dagang Tersedia',
          key: Key('npc_trade_contracts_section'),
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        ..._tradeContracts.map((c) {
          final isOpen = c.status == 'open';
          return MaritimeWoodCard(
            key: Key('trade_contract_card_${c.id}'),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          c.displayTitle,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      Chip(
                        label: Text(
                          '+${c.rewardCoins} koin',
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.bold,
                            color: MaritimePalette.gold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Pelabuhan Tujuan: ${_resolvePortDisplayName(c.portCode, null)} • Komoditas: ${c.commodityCode.toUpperCase()} (${c.qty} unit) • Pembuat: ${c.creatorName}',
                    style: const TextStyle(fontSize: 12.5),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: isOpen
                        ? FilledButton.tonalIcon(
                            key: Key('fulfill_contract_button_${c.id}'),
                            onPressed: () async {
                              final messenger = ScaffoldMessenger.of(context);
                              try {
                                final res =
                                    await widget.api.fulfillTradeContract(
                                  c.id,
                                  shipId: _ship?.id ?? 1,
                                );
                                if (!mounted) return;
                                final rw =
                                    (res['reward_coins'] as num?)?.toInt() ??
                                        c.rewardCoins;
                                HapticFeedback.heavyImpact();
                                AudioManager().playSfx('coin');
                                final msg =
                                    'Kontrak #${c.id} terpenuhi! Hadiah +$rw koin masuk ke kas Anda.';
                                setState(() {
                                  _playerCoins += rw;
                                  _playerNetWorth += rw;
                                  _lastFloatingRewardText = '+$rw koin';
                                  _tradeContracts = _tradeContracts
                                      .where((item) => item.id != c.id)
                                      .toList();
                                  _p2pFeedbackBanner = msg;
                                });
                                messenger
                                  ..hideCurrentSnackBar()
                                  ..showSnackBar(
                                    SnackBar(
                                      key: Key(
                                        'fulfill_contract_success_snackbar_${c.id}',
                                      ),
                                      backgroundColor: Colors.green,
                                      content: Text('Berhasil! $msg'),
                                    ),
                                  );
                              } catch (e) {
                                if (!mounted) return;
                                final errMsg =
                                    e.toString().replaceFirst('Exception: ', '');
                                setState(() {
                                  _p2pFeedbackBanner = errMsg;
                                });
                                messenger
                                  ..hideCurrentSnackBar()
                                  ..showSnackBar(
                                    SnackBar(
                                      key: Key(
                                        'fulfill_contract_error_snackbar_${c.id}',
                                      ),
                                      backgroundColor: Colors.red,
                                      content: Text(errMsg),
                                    ),
                                  );
                              }
                            },
                            icon: const Icon(
                              Icons.assignment_turned_in_outlined,
                              size: 18,
                            ),
                            label: const Text('Penuhi Kontrak'),
                          )
                        : const Text(
                            'Selesai ✓',
                            style: TextStyle(
                              color: Colors.green,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  // ==========================================================================
  // TAB 3: IDE EDITOR BAHASA ATURAN & BLOCK BUILDER (PILAR 4 — LANGKAH 6)
  // ==========================================================================

  Future<void> _validateCurrentRules() async {
    final errs = await widget.api.validateRules(_ruleEditorCtrl.text);
    if (!mounted) return;
    setState(() {
      _validationErrors = errs;
      _statusBanner = errs.isEmpty
          ? 'Aturan valid (0 galat).'
          : 'Ditemukan ${errs.length} galat pada aturan.';
    });
  }

  Future<void> _saveCurrentRules() async {
    final shipId = _ship?.id ?? 1;
    final errs = await widget.api.validateRules(_ruleEditorCtrl.text);
    if (errs.isNotEmpty) {
      if (!mounted) return;
      setState(() {
        _validationErrors = errs;
        _statusBanner = 'Gagal simpan: perbaiki galat validasi lebih dulu.';
      });
      return;
    }
    final newVer = await widget.api.saveShipRules(
      shipId,
      _ruleVersion,
      _ruleEditorCtrl.text,
    );
    if (!mounted) return;
    setState(() {
      _ruleVersion = newVer;
      _validationErrors = const <RuleValidationErrorModel>[];
      _statusBanner = 'Aturan berhasil disimpan (versi $newVer).';
    });
  }

  Future<void> _runSandbox() async {
    final shipId = _ship?.id ?? 1;
    final sim = await widget.api.simulateRules(
      shipId,
      _ruleEditorCtrl.text,
      200,
    );
    if (!mounted) return;
    setState(() {
      _sandboxResult = sim;
      _statusBanner =
          'Sandbox ${sim.ticks} tick selesai: delta ${sim.finalCoinsDelta} koin (${sim.trades} transaksi).';
    });
  }

  Future<void> _compileAndInsertBlock() async {
    final payload = <String, dynamic>{
      'type': 'IF',
      'condition': <String, dynamic>{
        'func': _blockCondFunc,
        'args': <String>[_blockCondArg],
      },
      'action': <String, dynamic>{
        'func': _blockActionFunc,
        'args': <String>[_blockActionArg],
      },
    };
    final dslLine = await widget.api.compileBlocks(payload);
    if (!mounted) return;
    setState(() {
      final current = _ruleEditorCtrl.text.trim();
      _ruleEditorCtrl.text =
          current.isEmpty ? dslLine : '$current\n$dslLine';
      _statusBanner = 'Blok berhasil dikompilasi ke DSL: $dslLine';
    });
  }

  Widget _buildRuleEditorTab() {
    final condArgsOptions = _blockCondFunc == 'di' || _blockCondFunc == 'rute_ke'
        ? const <String>[
            'Banda',
            'Ternate',
            'Surabaya',
            'Malaka',
            'Makassar',
            'Batavia',
          ]
        : kExtendedCommoditiesCatalog.map((c) => c.code).toList();

    final actionArgsOptions = _blockActionFunc == 'berlayar'
        ? const <String>[
            'Banda',
            'Ternate',
            'Surabaya',
            'Malaka',
            'Makassar',
            'Batavia',
          ]
        : kExtendedCommoditiesCatalog.map((c) => c.code).toList();

    if (!condArgsOptions.contains(_blockCondArg)) {
      _blockCondArg = condArgsOptions.first;
    }
    if (!actionArgsOptions.contains(_blockActionArg)) {
      _blockActionArg = actionArgsOptions.first;
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'IDE Bahasa Aturan (v$_ruleVersion)',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            if (_templates.isNotEmpty)
              DropdownButton<String>(
                key: const Key('template_dropdown'),
                hint: const Text('Pilih Templat'),
                items: _templates
                    .map(
                      (t) => DropdownMenuItem<String>(
                        value: t.id,
                        child: Text(t.title),
                      ),
                    )
                    .toList(),
                onChanged: (tplId) {
                  final tpl =
                      _templates.where((t) => t.id == tplId).firstOrNull;
                  if (tpl != null) {
                    setState(() {
                      _ruleEditorCtrl.text = tpl.source;
                    });
                  }
                },
              ),
          ],
        ),
        const SizedBox(height: 8),
        // Sakelar Mode Teks & Mode Blok (Langkah 6)
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                key: const Key('mode_text_button'),
                onPressed: () {
                  setState(() {
                    _isBlockBuilderMode = false;
                  });
                },
                icon: const Icon(Icons.code),
                label: const Text('Mode Teks (IDE)'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton.tonalIcon(
                key: const Key('mode_block_button'),
                onPressed: () {
                  setState(() {
                    _isBlockBuilderMode = true;
                  });
                },
                icon: const Icon(Icons.extension_outlined),
                label: const Text('Mode Blok (Visual)'),
              ),
            ),
          ],
        ),
        if (_isBlockBuilderMode) ...[
          const SizedBox(height: 12),
          MaritimeWoodCard(
            key: const Key('block_builder_panel'),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Penyusun Blok Visual (Jika [Kondisi] -> Maka [Aksi])',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      const Text(
                        'JIKA ',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.blue,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: DropdownButton<String>(
                          key: const Key('block_condition_func_dropdown'),
                          isExpanded: true,
                          value: _blockCondFunc,
                          items: const [
                            DropdownMenuItem(
                              value: 'di',
                              child: Text('di(Pelabuhan)'),
                            ),
                            DropdownMenuItem(
                              value: 'harga',
                              child: Text('harga(Produk)'),
                            ),
                            DropdownMenuItem(
                              value: 'stok_kapal',
                              child: Text('stok_kapal(Produk)'),
                            ),
                            DropdownMenuItem(
                              value: 'stok_pasar',
                              child: Text('stok_pasar(Produk)'),
                            ),
                          ],
                          onChanged: (v) {
                            if (v != null) {
                              setState(() {
                                _blockCondFunc = v;
                              });
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: DropdownButton<String>(
                          key: const Key('block_condition_arg_dropdown'),
                          isExpanded: true,
                          value: _blockCondArg,
                          items: condArgsOptions
                              .map(
                                (a) => DropdownMenuItem(
                                  value: a,
                                  child: Text(a),
                                ),
                              )
                              .toList(),
                          onChanged: (v) {
                            if (v != null) {
                              setState(() {
                                _blockCondArg = v;
                              });
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Text(
                        'MAKA ',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.blue,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: DropdownButton<String>(
                          key: const Key('block_action_func_dropdown'),
                          isExpanded: true,
                          value: _blockActionFunc,
                          items: const [
                            DropdownMenuItem(
                              value: 'beli',
                              child: Text('beli(Produk)'),
                            ),
                            DropdownMenuItem(
                              value: 'jual',
                              child: Text('jual(Produk)'),
                            ),
                            DropdownMenuItem(
                              value: 'berlayar',
                              child: Text('berlayar(Pelabuhan)'),
                            ),
                          ],
                          onChanged: (v) {
                            if (v != null) {
                              setState(() {
                                _blockActionFunc = v;
                              });
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: DropdownButton<String>(
                          key: const Key('block_action_arg_dropdown'),
                          isExpanded: true,
                          value: _blockActionArg,
                          items: actionArgsOptions
                              .map(
                                (a) => DropdownMenuItem(
                                  value: a,
                                  child: Text(a),
                                ),
                              )
                              .toList(),
                          onChanged: (v) {
                            if (v != null) {
                              setState(() {
                                _blockActionArg = v;
                              });
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  FilledButton.icon(
                    key: const Key('compile_block_button'),
                    onPressed: _compileAndInsertBlock,
                    icon: const Icon(Icons.add_circle_outline),
                    label: const Text('Tambahkan ke Editor (Compile Block)'),
                  ),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 10),
        TextField(
          key: const Key('rule_editor_field'),
          controller: _ruleEditorCtrl,
          maxLines: 10,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 13.5),
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            helperText:
                'Syntax Highlighting Aktif: kata kunci (jika, maka, aturan) berwarna biru.',
            hintText:
                'aturan beli_pala:\n  biar batas = harga_terakhir(Batavia, pala) - 20\n  jika di(Banda) dan harga(pala) < batas\n  maka beli(pala, maks)',
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton(
              key: const Key('validate_rules_button'),
              onPressed: _validateCurrentRules,
              child: const Text('Validasi'),
            ),
            ElevatedButton(
              key: const Key('save_rules_button'),
              onPressed: () {
                HapticFeedback.lightImpact();
                AudioManager().playSfx('click');
                _saveCurrentRules();
              },
              child: const Text('Simpan Aturan'),
            )
                .animate()
                .scale(
                  begin: const Offset(0.9, 0.9),
                  end: const Offset(1, 1),
                  duration: 300.ms,
                )
                .shimmer(duration: 600.ms, color: const Color(0x66FFF5DC)),
            FilledButton.tonal(
              key: const Key('simulate_rules_button'),
              onPressed: _runSandbox,
              child: const Text('Uji Sandbox 200 Tick'),
            ),
          ],
        ),
        if (_statusBanner != null) ...[
          const SizedBox(height: 12),
          MaritimeWoodCard(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                _statusBanner!,
                key: const Key('rule_status_banner'),
              ),
            ),
          ),
        ],
        if (_validationErrors.isNotEmpty) ...[
          const SizedBox(height: 8),
          ..._validationErrors.map(
            (e) => ListTile(
              leading: const Icon(Icons.error_outline, color: Colors.red),
              title: Text('[${e.code}] Baris ${e.line}, Kolom ${e.column}'),
              subtitle: Text(e.message),
            ),
          ),
        ],
        if (_sandboxResult != null) ...[
          const SizedBox(height: 8),
          MaritimeWoodCard(
            child: ListTile(
              title: Text(
                'Hasil Sandbox (${_sandboxResult!.ticks} tick): Delta ${_sandboxResult!.finalCoinsDelta} koin',
              ),
              subtitle: Text(
                'Transaksi: ${_sandboxResult!.trades} | ${_sandboxResult!.disclaimer}',
              ),
            ),
          ),
        ],
      ],
    );
  }

  // ==========================================================================
  // TAB 4: ARMADA KAPAL, KATALOG 5 TINGKAT KAPAL NUSANTARA, & LOG AKSI
  // ==========================================================================

  Future<void> _purchaseShipTier(ShipTierSpecModel tierSpec) async {
    if (_fleetCount >= 5) return;
    final messenger = ScaffoldMessenger.of(context);
    if (_playerCoins < tierSpec.price) {
      setState(() {
        _fleetNotice = 'Koin tidak cukup';
      });
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            key: Key('buy_ship_error_snackbar_${tierSpec.code}'),
            backgroundColor: Colors.red,
            content: const Text('Koin tidak cukup'),
          ),
        );
      return;
    }

    HapticFeedback.lightImpact();
    AudioManager().playSfx('click');

    final oldCoins = _playerCoins;
    final oldFleet = List<ShipModel>.from(_fleet);
    final nextNum = _fleetCount + 1;
    final shipName = '${tierSpec.name} #$nextNum';
    final tempShip = ShipModel(
      id: DateTime.now().millisecondsSinceEpoch,
      name: shipName,
      capacity: tierSpec.capacity,
      status: 'docked',
      portId: _ship?.portId ?? 1,
      destPort: null,
      arriveTick: null,
      etaTicks: 0,
      tier: tierSpec.tier,
      shipType: tierSpec.code,
      shipClass: tierSpec.shipClass,
      speedMultiplier: tierSpec.speedMultiplier,
      defensePower: tierSpec.hullHp,
      maxDefensePower: tierSpec.hullHp,
      cargo: const <CargoItemModel>[],
    );
    final notice =
        '${tierSpec.name} (${tierSpec.shipClass}, Kapasitas ${tierSpec.capacity}, Harga ${tierSpec.price} koin) ditambahkan ke armada (#$nextNum).';

    setState(() {
      _playerCoins -= tierSpec.price;
      _fleet = <ShipModel>[..._fleet, tempShip];
      _fleetNotice = notice;
    });
    AudioManager().playSfx('success');
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          key: Key('buy_ship_success_snackbar_${tierSpec.code}'),
          backgroundColor: Colors.green,
          content: const Text('Kapal berhasil dibeli!'),
        ),
      );

    widget.api
        .buyShip(
      name: shipName,
      portId: _ship?.portId ?? 1,
      tierSpec: tierSpec,
    )
        .then((created) {
      if (!mounted) return;
      setState(() {
        _fleet =
            _fleet.map((s) => s.id == tempShip.id ? created : s).toList();
      });
    }).catchError((Object e) {
      if (!mounted) return;
      final errMsg = e.toString().replaceFirst('Exception: ', '');
      setState(() {
        _playerCoins = oldCoins;
        _fleet = oldFleet;
        _fleetNotice = errMsg;
      });
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            key: Key('buy_ship_error_snackbar_${tierSpec.code}'),
            backgroundColor: Colors.red,
            content: Text(errMsg),
          ),
        );
    });
  }

  Future<void> _showRepairConfirmationDialog() async {
    final shipId = _ship?.id ?? 1;
    final missingHp =
        (_shipMaxDefensePower - _shipDefensePower).clamp(0, _shipMaxDefensePower);
    final repairCost = missingHp == 0 ? 0 : (missingHp * 2);

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        key: const Key('repair_confirm_dialog'),
        title: const Text('Perbaiki Lambung Kapal'),
        content: Text(
          missingHp == 0
              ? 'Lambung kapal sudah dalam kondisi prima (100% HP).'
              : 'Biaya perbaikan: $repairCost koin (2 koin per HP untuk memulihkan $missingHp HP). Lanjutkan perbaikan?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Batal'),
          ),
          FilledButton(
            key: const Key('confirm_repair_button'),
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              Navigator.of(ctx).pop();
              try {
                final res = await widget.api.repairShip(shipId);
                if (!mounted) return;
                setState(() {
                  _shipDefensePower =
                      (res['defense_power'] as num?)?.toInt() ??
                          _shipMaxDefensePower;
                  _fleet = _fleet
                      .map((s) => s.id == shipId
                          ? s.copyWith(defensePower: _shipDefensePower)
                          : s)
                      .toList();
                  if (_ship != null && _ship!.id == shipId) {
                    _ship = _ship!.copyWith(defensePower: _shipDefensePower);
                  }
                  _fleetNotice =
                      'Kapal berhasil diperbaiki ke $_shipDefensePower/$_shipMaxDefensePower HP (Biaya: $repairCost koin).';
                });
                messenger
                  ..hideCurrentSnackBar()
                  ..showSnackBar(
                    const SnackBar(
                      key: Key('repair_ship_success_snackbar'),
                      backgroundColor: Colors.green,
                      content: Text('Berhasil memperbaiki lambung kapal!'),
                    ),
                  );
              } catch (e) {
                if (!mounted) return;
                final errMsg = e.toString().replaceFirst('Exception: ', '');
                setState(() {
                  _fleetNotice = errMsg;
                });
                messenger
                  ..hideCurrentSnackBar()
                  ..showSnackBar(
                    SnackBar(
                      key: const Key('repair_ship_error_snackbar'),
                      backgroundColor: Colors.red,
                      content: Text(errMsg),
                    ),
                  );
              }
            },
            child: const Text('Perbaiki Sekarang'),
          ),
        ],
      ),
    );
  }

  Future<void> _showEquipWeaponSheet() async {
    final shipId = _ship?.id ?? 1;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        key: const Key('equip_weapon_sheet'),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
              const Text(
                'Pasang Persenjataan Kapal',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              const Text(
                'Pilih senjata dari muatan kapal atau gudang pelabuhan untuk meningkatkan Attack Power (ATK):',
              ),
              const SizedBox(height: 12),
              MaritimeWoodCard(
                child: ListTile(
                  key: const Key('equip_meriam_button'),
                  leading: const Icon(Icons.shield_outlined),
                  title: const Text(
                    'Meriam Kaliber Berat (+35 ATK)',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: const Text(
                    'Artileri jarak jauh Eropa untuk menghancurkan kapal Bajak Laut.',
                  ),
                  trailing: const Text('+35 ATK'),
                  onTap: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    Navigator.of(ctx).pop();
                    try {
                      final res = await widget.api.equipWeapon(
                        shipId: shipId,
                        weapon: 'meriam',
                        qty: 1,
                      );
                      if (!mounted) return;
                      final added =
                          (res['attack_power_added'] as num?)?.toInt() ?? 35;
                      final msg =
                          'Meriam (+35 ATK) berhasil dipasang! Total ATK kapal: ${_shipAttackPower + added}.';
                      setState(() {
                        _shipAttackPower += added;
                        _fleet = _fleet
                            .map((s) => s.id == shipId
                                ? s.copyWith(attackPower: _shipAttackPower)
                                : s)
                            .toList();
                        if (_ship != null && _ship!.id == shipId) {
                          _ship = _ship!.copyWith(attackPower: _shipAttackPower);
                        }
                        _fleetNotice = msg;
                      });
                      messenger
                        ..hideCurrentSnackBar()
                        ..showSnackBar(
                          SnackBar(
                            key: const Key('equip_meriam_success_snackbar'),
                            backgroundColor: Colors.green,
                            content: Text('Berhasil! $msg'),
                          ),
                        );
                    } catch (e) {
                      if (!mounted) return;
                      final errMsg =
                          e.toString().replaceFirst('Exception: ', '');
                      setState(() {
                        _fleetNotice = errMsg;
                      });
                      messenger
                        ..hideCurrentSnackBar()
                        ..showSnackBar(
                          SnackBar(
                            key: const Key('equip_meriam_error_snackbar'),
                            backgroundColor: Colors.red,
                            content: Text(errMsg),
                          ),
                        );
                    }
                  },
                ),
              ),
              MaritimeWoodCard(
                child: ListTile(
                  key: const Key('equip_katana_button'),
                  leading: const Icon(Icons.security_outlined),
                  title: const Text(
                    'Katana Baja Sakai (+15 ATK)',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: const Text(
                    'Senjata jarak dekat kru kapal untuk menghalau serbuan perompak.',
                  ),
                  trailing: const Text('+15 ATK'),
                  onTap: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    Navigator.of(ctx).pop();
                    try {
                      final res = await widget.api.equipWeapon(
                        shipId: shipId,
                        weapon: 'katana',
                        qty: 1,
                      );
                      if (!mounted) return;
                      final added =
                          (res['attack_power_added'] as num?)?.toInt() ?? 15;
                      final msg =
                          'Katana (+15 ATK) berhasil dipasang! Total ATK kapal: ${_shipAttackPower + added}.';
                      setState(() {
                        _shipAttackPower += added;
                        _fleet = _fleet
                            .map((s) => s.id == shipId
                                ? s.copyWith(attackPower: _shipAttackPower)
                                : s)
                            .toList();
                        if (_ship != null && _ship!.id == shipId) {
                          _ship = _ship!.copyWith(attackPower: _shipAttackPower);
                        }
                        _fleetNotice = msg;
                      });
                      messenger
                        ..hideCurrentSnackBar()
                        ..showSnackBar(
                          SnackBar(
                            key: const Key('equip_katana_success_snackbar'),
                            backgroundColor: Colors.green,
                            content: Text('Berhasil! $msg'),
                          ),
                        );
                    } catch (e) {
                      if (!mounted) return;
                      final errMsg =
                          e.toString().replaceFirst('Exception: ', '');
                      setState(() {
                        _fleetNotice = errMsg;
                      });
                      messenger
                        ..hideCurrentSnackBar()
                        ..showSnackBar(
                          SnackBar(
                            key: const Key('equip_katana_error_snackbar'),
                            backgroundColor: Colors.red,
                            content: Text(errMsg),
                          ),
                        );
                    }
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

  Widget _buildShipsTab() {
    final defaultTier2 = kShipTiersCatalog[1]; // Pencalang Niaga (1.500 koin)
    final int primaryShipId =
        _ship?.id ?? (_fleet.isNotEmpty ? _fleet.first.id : 1);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Armada Kapal Anda',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            Container(
              key: const Key('fleet_total_counter_badge'),
              padding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 4,
              ),
              decoration: BoxDecoration(
                color: MaritimePalette.darkWoodBrown,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: MaritimePalette.gold,
                  width: 1.2,
                ),
              ),
              child: Text(
                'Total Armada: $_fleetCount/5 Kapal',
                style: MaritimePalette.cinzel(
                  color: MaritimePalette.gold,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ListView.builder(
          key: const Key('fleet_ships_list_view'),
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _fleet.length,
          itemBuilder: (context, index) {
            final ShipModel shipItem = _fleet[index];
            final bool isPrimary = shipItem.id == primaryShipId;
            final int maxHp = isPrimary
                ? (_shipMaxDefensePower <= 0 ? 100 : _shipMaxDefensePower)
                : (shipItem.maxDefensePower <= 0
                    ? 100
                    : shipItem.maxDefensePower);
            final int curHp = (isPrimary
                    ? _shipDefensePower
                    : shipItem.defensePower)
                .clamp(0, maxHp);
            final int atk =
                isPrimary ? _shipAttackPower : shipItem.attackPower;
            final double hpRatio = (curHp / maxHp).clamp(0.0, 1.0);
            final Color hpBarColor = hpRatio > 0.5 ? Colors.green : Colors.red;
            final int usedCargo =
                shipItem.cargo.fold<int>(0, (sum, c) => sum + c.qty);
            final String cargoSummary = shipItem.cargo.isEmpty
                ? 'Kosong'
                : shipItem.cargo
                    .map((c) => '${c.commodity}: ${c.qty}')
                    .join(', ');

            return MaritimeWoodCard(
              key: isPrimary
                  ? const Key('primary_ship_combat_card')
                  : Key('fleet_ship_card_${shipItem.id}'),
              borderColor:
                  isPrimary ? MaritimePalette.gold : const Color(0x66FFD700),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (isPrimary &&
                              (_combatLogs.isNotEmpty || curHp < maxHp))
                            FloatingRewardText(
                              key: const Key('ship_damage_floating_text'),
                              text:
                                  '-${_combatLogs.firstOrNull?.damage ?? (maxHp - curHp)} HP',
                              isDamage: true,
                            ),
                          Icon(
                            Icons.sailing,
                            size: 28,
                            color: isPrimary
                                ? MaritimePalette.gold
                                : MaritimePalette.parchment,
                          ),
                        ],
                      ),
                      title: Text(
                        '${shipItem.name} • Tier ${shipItem.tier} (${shipItem.shipClass})',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(
                        'Status: ${shipItem.status} | Kapasitas Palka: $usedCargo/${shipItem.capacity} unit (Muatan: $cargoSummary) | ETA: ${shipItem.etaTicks} tick',
                      ),
                      trailing: isPrimary
                          ? OutlinedButton(
                              key: const Key('buy_ship_button'),
                              onPressed: _fleetCount >= 5
                                  ? null
                                  : () => _purchaseShipTier(defaultTier2),
                              child: const Text('Beli Kapal (1.500)'),
                            )
                          : null,
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      runSpacing: 4,
                      children: [
                        Text(
                          'HP Lambung Kapal (Defense): $curHp / $maxHp HP',
                          key: isPrimary
                              ? const Key('ship_hp_status_text')
                              : Key('ship_hp_status_text_${shipItem.id}'),
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        Text(
                          'Attack Power (ATK): $atk',
                          key: isPrimary
                              ? const Key('ship_attack_power_text')
                              : Key('ship_attack_power_text_${shipItem.id}'),
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        key: isPrimary
                            ? const Key('ship_hp_progress_bar')
                            : Key('ship_hp_progress_bar_${shipItem.id}'),
                        value: hpRatio,
                        color: hpBarColor,
                        minHeight: 10,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        FilledButton.tonalIcon(
                          key: Key('activate_primary_ship_button_${shipItem.id}'),
                          style: FilledButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                          ),
                          onPressed: isPrimary
                              ? null
                              : () {
                                  setState(() {
                                    _ship = shipItem;
                                    _shipAttackPower = shipItem.attackPower;
                                    _shipDefensePower = shipItem.defensePower;
                                    _shipMaxDefensePower =
                                        shipItem.maxDefensePower;
                                    _fleetNotice =
                                        '${shipItem.name} diaktifkan sebagai Kapal Utama.';
                                  });
                                },
                          icon: Icon(
                            isPrimary ? Icons.star : Icons.star_border,
                            size: 16,
                          ),
                          label: const Text('Aktifkan sebagai Kapal Utama'),
                        ),
                        if (isPrimary) ...[
                          FilledButton.tonalIcon(
                            key: const Key('repair_ship_button'),
                            style: FilledButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                            ),
                            onPressed: _showRepairConfirmationDialog,
                            icon: const Icon(
                              Icons.build_circle_outlined,
                              size: 16,
                            ),
                            label: const Text('Perbaiki Kapal (2 Koin/HP)'),
                          ),
                          OutlinedButton.icon(
                            key: const Key('equip_weapon_button'),
                            style: OutlinedButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                            ),
                            onPressed: _showEquipWeaponSheet,
                            icon: const Icon(Icons.shield_outlined, size: 16),
                            label: const Text('Pasang Senjata'),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ).animate(key: ValueKey<int>(_combatShakeCounter)).shake(
                  duration: 500.ms,
                  hz: 5,
                );
          },
        ),
        if (_fleetNotice != null) ...[
          const SizedBox(height: 8),
          MaritimeWoodCard(
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Text(_fleetNotice!, key: const Key('fleet_notice_text')),
            ),
          ),
        ],
        const SizedBox(height: 14),
        const Text(
          'Galangan Kapal Nusantara (5 Tingkat & Spesifikasi Armada)',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 6),
        ...kShipTiersCatalog.map(
          (tier) => MaritimeWoodCard(
            key: Key('ship_tier_card_${tier.code}'),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          '${tier.name} • ${tier.shipClass}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14.5,
                          ),
                        ),
                      ),
                      Chip(
                        label: Text(
                          '${tier.price} koin',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                  Text(tier.description, style: const TextStyle(fontSize: 12.5)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 12,
                    runSpacing: 4,
                    children: [
                      Text('Palka: ${tier.capacity} unit'),
                      Text('Kecepatan: ${tier.speedMultiplier}x'),
                      Text('Lambung: ${tier.hullHp} HP'),
                      Text(
                        'Awak: ${tier.crewCount} (Upkeep ${tier.upkeepPerTick}/tick)',
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.tonalIcon(
                      key: Key('buy_ship_tier_${tier.code}'),
                      onPressed: _fleetCount >= 5
                          ? null
                          : () => _purchaseShipTier(tier),
                      icon: const Icon(Icons.sailing, size: 18),
                      label: Text('Beli ${tier.name} (${tier.price} koin)'),
                    )
                        .animate()
                        .scale(
                          begin: const Offset(0.9, 0.9),
                          end: const Offset(1, 1),
                          duration: 300.ms,
                        )
                        .shimmer(
                          duration: 600.ms,
                          color: const Color(0x66FFF5DC),
                        ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        const Text(
          'Log Pertempuran (Naval Combat & Bajak Laut)',
          key: Key('combat_logs_section'),
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        ..._combatLogs.map(
          (cl) => MaritimeWoodCard(
            key: Key('combat_log_card_${cl.id}'),
            child: ListTile(
              leading: Icon(
                cl.outcome == 'player_victory'
                    ? Icons.military_tech
                    : Icons.warning_amber_rounded,
                color: cl.outcome == 'player_victory'
                    ? Colors.green
                    : Colors.red,
              ),
              title: Text(
                cl.outcome == 'player_victory'
                    ? 'Tick #${cl.tickNo} — Menang lawan ${cl.pirateName} (+${cl.bountyCoins} Koin)'
                    : 'Tick #${cl.tickNo} — Diserang ${cl.pirateName} (-${cl.damage} HP)',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text(cl.detail),
            ),
          ),
        ),
        const SizedBox(height: 14),
        const Text(
          'Log Aksi & Alasan Evaluasi Aturan',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        ..._logs.map(
          (l) => MaritimeWoodCard(
            child: ListTile(
              title: Text('Tick #${l.tickNo} — ${l.action} (${l.result})'),
              subtitle: Text('${l.ruleName}: ${l.detail}'),
            ),
          ),
        ),
      ],
    );
  }

  // ==========================================================================
  // TAB 5: PROFIL NAHKODA, PENGATURAN TEMA, & PERINGKAT (LANGKAH 1 & 3)
  // ==========================================================================

  Widget _buildLeaderboardAndProfileTab() {
    final themeCtrl = Provider.of<ThemeController>(context);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Kartu Profil Nahkoda & Gelar (GET /v1/me — Langkah 3)
        MaritimeWoodCard(
          key: const Key('player_profile_card'),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const CircleAvatar(
                      radius: 24,
                      child: Icon(Icons.anchor, size: 26),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _playerDisplayName,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'Gelar: $_playerTitle • Peringkat #$_playerRank',
                            key: const Key('profile_rank_title_text'),
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 16,
                  runSpacing: 8,
                  children: [
                    Text(
                      'Total Kekayaan (Net Worth): $_playerNetWorth koin',
                      key: const Key('profile_net_worth_text'),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text('Kas Tunai: $_playerCoins koin'),
                    Text('Armada Aktif: $_fleetCount/5 kapal'),
                  ],
                ),
                const SizedBox(height: 14),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    key: const Key('profile_level_progress_bar'),
                    value: computeLevelProgressFraction(
                      _playerLevel,
                      _playerNetWorth,
                    ),
                    minHeight: 9,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Level $_playerLevel — $_playerXpToNextLevel koin lagi menuju Level ${_playerLevel + 1}',
                  key: const Key('profile_level_xp_text'),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Expanded(
              child: Text(
                'Misi Harian (Daily Quests — Reset 00:00)',
                key: Key('daily_quests_section'),
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
            if (_lastFloatingRewardText != null)
              FloatingRewardText(
                key: Key('floating_reward_badge_$_lastFloatingRewardText'),
                text: _lastFloatingRewardText!,
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (_questFeedbackBanner != null) ...[
          MaritimeWoodCard(
            key: const Key('quest_feedback_banner'),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Text(_questFeedbackBanner!),
            ),
          ),
          const SizedBox(height: 8),
        ],
        ..._dailyQuests.map((q) {
          final ratio = (q.progress / (q.targetValue <= 0 ? 1 : q.targetValue))
              .clamp(0.0, 1.0);
          return MaritimeWoodCard(
            key: Key('quest_card_${q.code}'),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          q.title,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14.5,
                          ),
                        ),
                      ),
                      Text(
                        '+${q.rewardCoins} Koin • +${q.rewardXp} EXP',
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(q.description, style: const TextStyle(fontSize: 12.5)),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(5),
                    child: LinearProgressIndicator(
                      key: Key('quest_progress_bar_${q.code}'),
                      value: ratio,
                      minHeight: 8,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Progres: ${q.progress}/${q.targetValue}',
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (q.isCompleted && !q.isClaimed)
                        FilledButton.tonalIcon(
                          key: Key('claim_quest_button_${q.code}'),
                          onPressed: () async {
                            final messenger = ScaffoldMessenger.of(context);
                            try {
                              final res = await widget.api.claimQuest(q.id);
                              if (!mounted) return;
                              final rwCoins =
                                  (res['reward_coins'] as num?)?.toInt() ??
                                      q.rewardCoins;
                              final rwXp =
                                  (res['reward_xp'] as num?)?.toInt() ??
                                      q.rewardXp;
                              HapticFeedback.heavyImpact();
                              AudioManager().playSfx('coin');
                              final msg =
                                  'Hadiah misi "${q.title}" berhasil diklaim: +$rwCoins Koin & +$rwXp EXP!';
                              setState(() {
                                _lastFloatingRewardText = '+$rwCoins';
                                _playerCoins += rwCoins;
                                _playerNetWorth += rwCoins;
                                _dailyQuests = _dailyQuests
                                    .map((item) => item.id == q.id
                                        ? item.copyWith(isClaimed: true)
                                        : item)
                                    .toList();
                                _questFeedbackBanner = msg;
                              });
                              messenger
                                ..hideCurrentSnackBar()
                                ..showSnackBar(
                                  SnackBar(
                                    key: Key(
                                      'claim_quest_success_snackbar_${q.code}',
                                    ),
                                    backgroundColor: Colors.green,
                                    content: Text('Berhasil! $msg'),
                                  ),
                                );
                            } catch (e) {
                              if (!mounted) return;
                              final errMsg =
                                  e.toString().replaceFirst('Exception: ', '');
                              setState(() {
                                _questFeedbackBanner = errMsg;
                              });
                              messenger
                                ..hideCurrentSnackBar()
                                ..showSnackBar(
                                  SnackBar(
                                    key: Key(
                                      'claim_quest_error_snackbar_${q.code}',
                                    ),
                                    backgroundColor: Colors.red,
                                    content: Text(errMsg),
                                  ),
                                );
                            }
                          },
                          icon: const Icon(Icons.card_giftcard, size: 17),
                          label: const Text('Klaim Hadiah'),
                        )
                      else if (q.isClaimed)
                        const Text(
                          'Sudah Diklaim ✓',
                          style: TextStyle(
                            color: Colors.green,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          );
        }),
        const SizedBox(height: 12),
        // Pengaturan Tema Global & Dark Mode (Langkah 1 — shared_preferences)
        MaritimeWoodCard(
          key: const Key('theme_settings_card'),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Pengaturan Tema & Mode Gelap (Tersimpan Otomatis)',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    ChoiceChip(
                      key: const Key('theme_mode_system_chip'),
                      label: const Text('Sistem (System)'),
                      selected: themeCtrl.themeMode == ThemeMode.system,
                      onSelected: (_) =>
                          themeCtrl.setThemeMode(ThemeMode.system),
                    ),
                    ChoiceChip(
                      key: const Key('theme_mode_light_chip'),
                      label: const Text('Terang (Light)'),
                      selected: themeCtrl.themeMode == ThemeMode.light,
                      onSelected: (_) =>
                          themeCtrl.setThemeMode(ThemeMode.light),
                    ),
                    ChoiceChip(
                      key: const Key('theme_mode_dark_chip'),
                      label: const Text('Gelap (Dark)'),
                      selected: themeCtrl.themeMode == ThemeMode.dark,
                      onSelected: (_) =>
                          themeCtrl.setThemeMode(ThemeMode.dark),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    ChoiceChip(
                      key: const Key('theme_palette_nusantara_chip'),
                      label: const Text('Tema Nusantara (Rempah Amber)'),
                      selected:
                          themeCtrl.palette == SpiceThemePalette.nusantara,
                      onSelected: (_) =>
                          themeCtrl.setPalette(SpiceThemePalette.nusantara),
                    ),
                    ChoiceChip(
                      key: const Key('theme_palette_samudra_chip'),
                      label: const Text('Tema Samudra (Biru Laut)'),
                      selected: themeCtrl.palette == SpiceThemePalette.samudra,
                      onSelected: (_) =>
                          themeCtrl.setPalette(SpiceThemePalette.samudra),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                const Divider(height: 1),
                const SizedBox(height: 12),
                const Text(
                  'Gaya Peta',
                  key: Key('map_style_section_title'),
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<MapStyle>(
                    key: const Key('map_style_segmented_button'),
                    segments: const <ButtonSegment<MapStyle>>[
                      ButtonSegment<MapStyle>(
                        value: MapStyle.vintageColor,
                        label: Text('Kuno Berwarna'),
                        icon: Icon(Icons.map_outlined, size: 18),
                      ),
                      ButtonSegment<MapStyle>(
                        value: MapStyle.vintageSepia,
                        label: Text('Kuno Sepia'),
                        icon: Icon(Icons.history_edu_outlined, size: 18),
                      ),
                      ButtonSegment<MapStyle>(
                        value: MapStyle.modern,
                        label: Text('Modern'),
                        icon: Icon(Icons.public_outlined, size: 18),
                      ),
                    ],
                    selected: <MapStyle>{themeCtrl.mapStyle},
                    onSelectionChanged: (Set<MapStyle> selection) {
                      if (selection.isNotEmpty) {
                        themeCtrl.setMapStyle(selection.first);
                      }
                    },
                  ),
                ),
                const SizedBox(height: 14),
                const Divider(height: 1),
                const SizedBox(height: 12),
                const Text(
                  'Kualitas Grafis',
                  key: Key('graphics_quality_section_title'),
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<GraphicsQuality>(
                  key: const Key('graphics_quality_dropdown'),
                  isExpanded: true,
                  initialValue: themeCtrl.graphicsQuality,
                  decoration: const InputDecoration(
                    labelText: 'Pilih Tingkat Kualitas Grafis',
                    border: OutlineInputBorder(),
                  ),
                  items: const <DropdownMenuItem<GraphicsQuality>>[
                    DropdownMenuItem<GraphicsQuality>(
                      value: GraphicsQuality.low,
                      child: Text('Low (Hemat Baterai)'),
                    ),
                    DropdownMenuItem<GraphicsQuality>(
                      value: GraphicsQuality.medium,
                      child: Text('Medium'),
                    ),
                    DropdownMenuItem<GraphicsQuality>(
                      value: GraphicsQuality.high,
                      child: Text('High'),
                    ),
                    DropdownMenuItem<GraphicsQuality>(
                      value: GraphicsQuality.ultra,
                      child: Text('Ultra (4K)'),
                    ),
                  ],
                  onChanged: (GraphicsQuality? val) {
                    if (val != null) {
                      HapticFeedback.lightImpact();
                      themeCtrl.setGraphicsQuality(val);
                    }
                  },
                ),
                const SizedBox(height: 6),
                const Text(
                  'Ultra membutuhkan HP dengan RAM besar dan gambar resolusi tinggi (min. 2000x1000 piksel)',
                  key: Key('graphics_quality_description'),
                  style: TextStyle(fontSize: 12.0),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'Peringkat Kekayaan Bersih Nusantara',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        ..._leaderboard.map(
          (item) => MaritimeWoodCard(
            child: ListTile(
              leading: CircleAvatar(child: Text('#${item.rank}')),
              title: Text(item.displayName),
              subtitle: Text('Gelar: ${item.title}'),
              trailing: Text(
                '${item.netWorth} koin',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'Serikat Dagang & Kontrak Pengiriman (Fase 2)',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        const MaritimeWoodCard(
          key: Key('guilds_contracts_card'),
          child: ListTile(
            leading: Icon(Icons.handshake_outlined),
            title: Text('Serikat Rempah Nusantara & Kontrak Pengiriman'),
            subtitle: Text(
              'Penuhi kontrak pengiriman komoditas di pelabuhan tujuan dengan escrow kas pelabuhan terjamin.',
            ),
          ),
        ),
        const SizedBox(height: 16),
        MaritimeWoodCard(
          key: const Key('ledger_menu_card'),
          child: ListTile(
            key: const Key('open_ledger_tile'),
            leading: const Icon(
              Icons.receipt_long_outlined,
              color: MaritimePalette.gold,
            ),
            title: const Text(
              'Buku Mutasi Koin',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: const Text(
              'Lihat riwayat keluar-masuk koin armada (Beli Kapal, Misi Harian, & Niaga).',
            ),
            trailing: ElevatedButton(
              key: const Key('open_ledger_button'),
              style: MaritimePalette.goldCoinButtonStyle(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
              ),
              onPressed: _openLedgerScreen,
              child: const Text('Buka'),
            ),
            onTap: _openLedgerScreen,
          ),
        ),
        const SizedBox(height: 12),
        MaritimeWoodCard(
          key: const Key('achievements_menu_card'),
          child: ListTile(
            key: const Key('open_achievements_tile'),
            leading: const Icon(
              Icons.emoji_events_outlined,
              color: MaritimePalette.gold,
            ),
            title: const Text(
              'Pencapaian',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: const Text(
              'Lihat 15 lencana pencapaian nahkoda Nusantara dan hadiah koinnya.',
            ),
            trailing: ElevatedButton(
              key: const Key('open_achievements_button'),
              style: MaritimePalette.goldCoinButtonStyle(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
              ),
              onPressed: _openAchievementsScreen,
              child: const Text('Pencapaian'),
            ),
            onTap: _openAchievementsScreen,
          ),
        ),
        const SizedBox(height: 12),
        MaritimeWoodCard(
          key: const Key('change_password_menu_card'),
          child: ListTile(
            leading: const Icon(
              Icons.lock_reset_outlined,
              color: MaritimePalette.gold,
            ),
            title: const Text(
              'Keamanan Akun',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: const Text(
              'Perbarui kata sandi akun Anda. Semua sesi lama akan dicabut.',
            ),
            trailing: ElevatedButton(
              key: const Key('change_password_button'),
              style: MaritimePalette.goldCoinButtonStyle(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
              ),
              onPressed: _showChangePasswordDialog,
              child: const Text('Ganti Kata Sandi'),
            ),
            onTap: _showChangePasswordDialog,
          ),
        ),
        const SizedBox(height: 16),
        MaritimeWoodCard(
          key: const Key('delete_account_card'),
          borderColor: const Color(0xFFF87171),
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Zona Berbahaya — Pelindungan Data Pribadi (UU PDP)',
                style: MaritimePalette.cinzel(
                  color: const Color(0xFFFCA5A5),
                  fontSize: 13.5,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Anda berhak menghapus dan menganonimkan akun secara permanen kapan saja sesuai UU No. 27 Tahun 2022.',
                style: TextStyle(
                  color: MaritimePalette.parchmentMuted,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 10),
              ElevatedButton.icon(
                key: const Key('delete_account_button'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: MaritimePalette.crimsonWax,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: const BorderSide(
                      color: Color(0xFFF87171),
                      width: 1.2,
                    ),
                  ),
                ),
                onPressed: _showDeleteAccountDialog,
                icon: const Icon(
                  Icons.delete_forever_outlined,
                  color: Colors.white,
                ),
                label: Text(
                  'Hapus Akun (UU PDP)',
                  style: MaritimePalette.cinzel(
                    color: Colors.white,
                    fontSize: 13.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _openLedgerScreen() {
    HapticFeedback.lightImpact();
    AudioManager().playSfx('click');
    Navigator.of(context).push(
      GamePageRoute<void>(
        page: LedgerScreen(api: widget.api),
      ),
    );
  }

  void _openAchievementsScreen() {
    HapticFeedback.lightImpact();
    AudioManager().playSfx('click');
    Navigator.of(context).push(
      GamePageRoute<void>(
        page: AchievementsScreen(api: widget.api),
      ),
    );
  }

  Future<void> _showChangePasswordDialog() async {
    String oldPw = '';
    String newPw = '';
    String confirmPw = '';
    String? dialogError;

    final changed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              key: const Key('change_password_dialog'),
              backgroundColor: MaritimePalette.carvedMahogany,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: const BorderSide(color: MaritimePalette.gold, width: 1.5),
              ),
              title: Text(
                'Ganti Kata Sandi',
                style: MaritimePalette.cinzel(
                  color: MaritimePalette.gold,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      key: const Key('change_pw_old_field'),
                      obscureText: true,
                      onChanged: (val) {
                        oldPw = val;
                      },
                      decoration: const InputDecoration(
                        labelText: 'Kata Sandi Lama',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      key: const Key('change_pw_new_field'),
                      obscureText: true,
                      onChanged: (val) {
                        newPw = val;
                      },
                      decoration: const InputDecoration(
                        labelText: 'Kata Sandi Baru',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      key: const Key('change_pw_confirm_field'),
                      obscureText: true,
                      onChanged: (val) {
                        confirmPw = val;
                      },
                      decoration: const InputDecoration(
                        labelText: 'Ulangi Kata Sandi Baru',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    if (dialogError != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        dialogError!,
                        style:
                            const TextStyle(color: Colors.red, fontSize: 12.5),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  key: const Key('cancel_change_password_button'),
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('Batal'),
                ),
                ElevatedButton(
                  key: const Key('confirm_change_password_button'),
                  style: MaritimePalette.goldCoinButtonStyle(),
                  onPressed: () async {
                    if (newPw != confirmPw) {
                      setDialogState(() {
                        dialogError = 'Kata sandi tidak cocok';
                      });
                      return;
                    }
                    if (newPw.length < 8) {
                      setDialogState(() {
                        dialogError = 'Kata sandi baru minimal 8 karakter';
                      });
                      return;
                    }
                    try {
                      await widget.api.changePassword(
                        oldPassword: oldPw,
                        newPassword: newPw,
                      );
                      if (ctx.mounted) {
                        Navigator.of(ctx).pop(true);
                      }
                    } catch (e) {
                      setDialogState(() {
                        dialogError =
                            e.toString().replaceFirst('Exception: ', '');
                      });
                    }
                  },
                  child: const Text('Simpan & Keluar'),
                ),
              ],
            );
          },
        );
      },
    );

    if (changed == true && mounted) {
      widget.onLogout();
    }
  }

  Future<void> _showDeleteAccountDialog() async {
    String confirmInput = '';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final isConfirmedText = confirmInput.trim() == 'HAPUS';
            return AlertDialog(
              key: const Key('delete_account_dialog'),
              backgroundColor: MaritimePalette.carvedMahogany,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: const BorderSide(color: Color(0xFFF87171), width: 1.5),
              ),
              title: Text(
                'Konfirmasi Hapus Akun (UU PDP)',
                style: MaritimePalette.cinzel(
                  color: const Color(0xFFFCA5A5),
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Tindakan ini akan menganonimkan data pribadi Anda dan menghapus seluruh kapal serta progres secara permanen. Ketik kata "HAPUS" di bawah ini untuk mengonfirmasi:',
                    style: TextStyle(
                      color: MaritimePalette.parchment,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    key: const Key('delete_account_confirm_field'),
                    onChanged: (val) {
                      setDialogState(() {
                        confirmInput = val;
                      });
                    },
                    decoration: const InputDecoration(
                      labelText: 'Ketik HAPUS',
                      hintText: 'HAPUS',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  key: const Key('cancel_delete_account_button'),
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('Batal'),
                ),
                ElevatedButton.icon(
                  key: const Key('confirm_delete_account_button'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: MaritimePalette.crimsonWax,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: isConfirmedText
                      ? () => Navigator.of(ctx).pop(true)
                      : null,
                  icon: const Icon(Icons.delete_forever_outlined, size: 18),
                  label: const Text('Konfirmasi Hapus'),
                ),
              ],
            );
          },
        );
      },
    );

    if (confirmed == true) {
      final messenger = ScaffoldMessenger.of(context);
      try {
        await widget.api.deleteAccount();
        if (!mounted) return;
        widget.onLogout();
      } catch (e) {
        if (!mounted) return;
        final errMsg = e.toString().replaceFirst('Exception: ', '');
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              key: const Key('delete_account_error_snackbar'),
              backgroundColor: Colors.red,
              content: Text(errMsg),
            ),
          );
      }
    }
  }

  // ==========================================================================
  // TAB 6: SISTEM ALIANSI DAGANG (GUILDS) & WORLD BOSS (FASE 8)
  // ==========================================================================

  Future<void> _showCreateGuildDialog() async {
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          key: const Key('create_guild_dialog'),
          title: const Text('Buat Aliansi Baru (5.000 Koin)'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Biaya pendirian sebesar 5.000 Koin akan langsung disetorkan sebagai modal awal Kas Aliansi (tercatat di ledger).',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('create_guild_name_field'),
                controller: _guildCreateNameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Nama Aliansi Dagang',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                key: const Key('create_guild_desc_field'),
                controller: _guildCreateDescCtrl,
                decoration: const InputDecoration(
                  labelText: 'Semboyan / Deskripsi Aliansi',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Batal'),
            ),
            FilledButton.icon(
              key: const Key('confirm_create_guild_button'),
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                final name = _guildCreateNameCtrl.text.trim().isEmpty
                    ? 'Aliansi Rempah Nusantara'
                    : _guildCreateNameCtrl.text.trim();
                final desc = _guildCreateDescCtrl.text.trim();
                Navigator.of(ctx).pop();
                try {
                  final created = await widget.api.createGuild(
                    name: name,
                    description: desc,
                  );
                  if (!mounted) return;
                  final msg =
                      'Aliansi "${created.name}" berhasil didirikan! 5.000 Koin telah masuk ke Kas Guild.';
                  setState(() {
                    _currentGuild = created;
                    if (_playerCoins >= 5000) {
                      _playerCoins -= 5000;
                    }
                    _guildFeedbackBanner = msg;
                  });
                  messenger
                    ..hideCurrentSnackBar()
                    ..showSnackBar(
                      SnackBar(
                        key: const Key('create_guild_success_snackbar'),
                        backgroundColor: Colors.green,
                        content: Text('Berhasil! $msg'),
                      ),
                    );
                } catch (e) {
                  if (!mounted) return;
                  final errMsg = e.toString().replaceFirst('Exception: ', '');
                  setState(() {
                    _guildFeedbackBanner = errMsg;
                  });
                  messenger
                    ..hideCurrentSnackBar()
                    ..showSnackBar(
                      SnackBar(
                        key: const Key('create_guild_error_snackbar'),
                        backgroundColor: Colors.red,
                        content: Text(errMsg),
                      ),
                    );
                }
              },
              icon: const Icon(Icons.shield),
              label: const Text('Dirikan Aliansi (5.000 Koin)'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showDonateGuildDialog(GuildDetailModel guild) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          key: const Key('donate_guild_dialog'),
          title: Text('Donasi ke Kas ${guild.name}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Setorkan koin pribadi Anda ke Kas Aliansi. Jika Kas Aliansi melampaui 10.000 Koin, World Boss "Bajak Laut Armada Besar" akan muncul di peta!',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('donate_guild_amount_field'),
                controller: _guildDonateAmountCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Jumlah Koin Donasi',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Batal'),
            ),
            FilledButton.icon(
              key: const Key('confirm_donate_guild_button'),
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                final amount =
                    int.tryParse(_guildDonateAmountCtrl.text.trim()) ?? 1000;
                Navigator.of(ctx).pop();
                if (amount <= 0) return;
                try {
                  final res = await widget.api.donateToGuild(amount);
                  if (!mounted) return;
                  final newTreasury =
                      (res['treasury_coins'] as num?)?.toInt() ??
                          (guild.treasuryCoins + amount);
                  final bossNowActive = newTreasury > 10000 ||
                      ((res['boss_active'] as bool?) ??
                          guild.worldBoss.isActive);
                  final msg =
                      'Berhasil menyetor $amount Koin ke Kas Aliansi! Total Kas Guild kini $newTreasury Koin.';
                  setState(() {
                    if (_playerCoins >= amount) {
                      _playerCoins -= amount;
                    }
                    _currentGuild = guild.copyWith(
                      treasuryCoins: newTreasury,
                      totalGuildWealth: guild.totalGuildWealth + amount,
                      worldBoss: GuildWorldBossModel(
                        isActive: bossNowActive,
                        name: 'Bajak Laut Armada Besar',
                        hp: bossNowActive
                            ? (guild.worldBoss.hp > 0
                                ? guild.worldBoss.hp
                                : 500)
                            : 0,
                        maxHp: 500,
                        portId: 1,
                      ),
                    );
                    _guildFeedbackBanner = msg;
                  });
                  messenger
                    ..hideCurrentSnackBar()
                    ..showSnackBar(
                      SnackBar(
                        key: const Key('donate_guild_success_snackbar'),
                        backgroundColor: Colors.green,
                        content: Text(msg),
                      ),
                    );
                } catch (e) {
                  if (!mounted) return;
                  final errMsg = e.toString().replaceFirst('Exception: ', '');
                  setState(() {
                    _guildFeedbackBanner = errMsg;
                  });
                  messenger
                    ..hideCurrentSnackBar()
                    ..showSnackBar(
                      SnackBar(
                        key: const Key('donate_guild_error_snackbar'),
                        backgroundColor: Colors.red,
                        content: Text(errMsg),
                      ),
                    );
                }
              },
              icon: const Icon(Icons.volunteer_activism),
              label: const Text('Setor Donasi'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildGuildAllianceTab() {
    final guild = _currentGuild;
    final filteredGuilds = _guildDirectory.where((g) {
      if (_guildSearchQuery.isEmpty) return true;
      final q = _guildSearchQuery.toLowerCase();
      return g.name.toLowerCase().contains(q) ||
          g.code.toLowerCase().contains(q) ||
          g.description.toLowerCase().contains(q);
    }).toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_guildFeedbackBanner != null)
          MaritimeWoodCard(
            key: const Key('guild_feedback_banner'),
            color: const Color(0xFFDCFCE7),
            child: ListTile(
              leading:
                  const Icon(Icons.shield_outlined, color: MaritimePalette.gold),
              title: Text(
                _guildFeedbackBanner!,
                style: const TextStyle(
                  color: MaritimePalette.parchment,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        if (guild == null) ...[
          MaritimeWoodCard(
            key: const Key('guild_discovery_header_card'),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.shield_outlined, size: 28),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Aliansi Dagang Nusantara (🛡️ Guilds)',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Bergabunglah dengan Aliansi Dagang untuk menghimpun Kas Aliansi dan menumpas World Boss "Bajak Laut Armada Besar" bersama-sama, atau dirikan Aliansi baru.',
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      key: const Key('create_guild_button'),
                      onPressed: _showCreateGuildDialog,
                      icon: const Icon(Icons.add_moderator_outlined),
                      label: const Text('Buat Aliansi Baru (5.000 Koin)'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('guild_search_field'),
            controller: _guildSearchCtrl,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              labelText: 'Cari Aliansi Dagang (nama atau kode)...',
              border: OutlineInputBorder(),
            ),
            onChanged: (val) {
              setState(() {
                _guildSearchQuery = val.trim();
              });
            },
          ),
          const SizedBox(height: 12),
          const Text(
            'Daftar Aliansi Dagang Tersedia',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          ...filteredGuilds.map(
            (g) => MaritimeWoodCard(
              key: Key('guild_list_card_${g.code}'),
              child: ListTile(
                leading: const CircleAvatar(
                  child: Icon(Icons.shield_outlined),
                ),
                title: Text(
                  g.name,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(
                  '${g.description}\nPemimpin: ${g.leaderName} • Anggota: ${g.memberCount} • Kas: ${g.treasuryCoins} Koin',
                ),
                isThreeLine: true,
                trailing: FilledButton.tonal(
                  key: Key('join_guild_button_${g.code}'),
                  onPressed: _joiningGuildId != null
                      ? null
                      : () {
                          HapticFeedback.lightImpact();
                          AudioManager().playSfx('click');
                          _joinGuild(g.id);
                        },
                  child: _joiningGuildId == g.id
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: GameLoadingIndicator(size: 18),
                        )
                      : const Text('Gabung'),
                )
                    .animate()
                    .scale(
                      begin: const Offset(0.9, 0.9),
                      end: const Offset(1, 1),
                      duration: 300.ms,
                    )
                    .shimmer(duration: 600.ms, color: const Color(0x66FFF5DC)),
              ),
            ),
          ),
        ] else ...[
          MaritimeWoodCard(
            key: const Key('guild_dashboard_card'),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const CircleAvatar(
                        radius: 22,
                        child: Icon(Icons.shield, size: 26),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              guild.name,
                              key: const Key('guild_dashboard_name'),
                              style: const TextStyle(
                                fontSize: 19,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              'Kode: @${guild.code} • Pemimpin: ${guild.leaderName}',
                              style: const TextStyle(fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                      OutlinedButton.icon(
                        key: const Key('leave_guild_button'),
                        onPressed: () async {
                          final messenger = ScaffoldMessenger.of(context);
                          try {
                            await widget.api.leaveGuild(guild.id);
                            if (!mounted) return;
                            final msg =
                                'Anda telah keluar dari ${guild.name}.';
                            setState(() {
                              _currentGuild = null;
                              _guildFeedbackBanner = msg;
                            });
                            messenger
                              ..hideCurrentSnackBar()
                              ..showSnackBar(
                                SnackBar(
                                  key: const Key('leave_guild_success_snackbar'),
                                  backgroundColor: Colors.green,
                                  content: Text('Berhasil! $msg'),
                                ),
                              );
                          } catch (e) {
                            if (!mounted) return;
                            final errMsg =
                                e.toString().replaceFirst('Exception: ', '');
                            setState(() {
                              _guildFeedbackBanner = errMsg;
                            });
                            messenger
                              ..hideCurrentSnackBar()
                              ..showSnackBar(
                                SnackBar(
                                  key: const Key('leave_guild_error_snackbar'),
                                  backgroundColor: Colors.red,
                                  content: Text(errMsg),
                                ),
                              );
                          }
                        },
                        icon: const Icon(Icons.exit_to_app, size: 17),
                        label: const Text('Keluar'),
                      ),
                    ],
                  ),
                  if (guild.description.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(guild.description),
                  ],
                  const Divider(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Kas Guild (Treasury)',
                            style: TextStyle(fontSize: 13),
                          ),
                          Text(
                            '${guild.treasuryCoins} Koin',
                            key: const Key('guild_dashboard_treasury'),
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          const Text(
                            'Total Kekayaan Aliansi',
                            style: TextStyle(fontSize: 13),
                          ),
                          Text(
                            '${guild.totalGuildWealth} Koin',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      key: const Key('donate_guild_button'),
                      onPressed: () => _showDonateGuildDialog(guild),
                      icon: const Icon(Icons.volunteer_activism_outlined),
                      label: const Text('Donasi ke Kas Guild'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (guild.treasuryCoins > 10000 || guild.worldBoss.isActive)
            MaritimeWoodCard(
              key: const Key('guild_world_boss_card'),
              color: const Color(0xFFFEE2E2),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.directions_boat_filled,
                          color: Color(0xFFB91C1C),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'WORLD BOSS AKTIF: ${guild.worldBoss.name}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: MaritimePalette.gold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Kas Guild melampaui 10.000 Koin! Bajak Laut Armada Besar muncul di peta. HP Boss: ${guild.worldBoss.hp}/${guild.worldBoss.maxHp}',
                      style: const TextStyle(color: MaritimePalette.parchment),
                    ),
                    const SizedBox(height: 8),
                    LinearProgressIndicator(
                      value: guild.worldBoss.maxHp > 0
                          ? (guild.worldBoss.hp / guild.worldBoss.maxHp)
                              .clamp(0.0, 1.0)
                          : 0.0,
                      color: Colors.red.shade700,
                      backgroundColor: Colors.red.shade100,
                      minHeight: 8,
                    ),
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton.icon(
                        key: const Key('attack_world_boss_button'),
                        onPressed: () async {
                          final messenger = ScaffoldMessenger.of(context);
                          HapticFeedback.heavyImpact();
                          AudioManager().playSfx('cannon');
                          setState(() {
                            _combatShakeCounter += 1;
                          });
                          try {
                            final res = await widget.api.attackGuildWorldBoss(
                              guild.id,
                              shipId: _ship?.id,
                            );
                            if (!mounted) return;
                            final hpAfter =
                                (res['boss_hp_after'] as num?)?.toInt() ??
                                    (guild.worldBoss.hp - 60).clamp(0, 500);
                            final dmg =
                                (res['damage_dealt'] as num?)?.toInt() ?? 60;
                            final msg =
                                'Kapal Anda menyerang ${guild.worldBoss.name} (-${dmg} HP, sisa $hpAfter/${guild.worldBoss.maxHp} HP)!';
                            setState(() {
                              _currentGuild = guild.copyWith(
                                worldBoss: GuildWorldBossModel(
                                  isActive: hpAfter > 0,
                                  name: guild.worldBoss.name,
                                  hp: hpAfter,
                                  maxHp: guild.worldBoss.maxHp,
                                  portId: guild.worldBoss.portId,
                                ),
                              );
                              _guildFeedbackBanner = msg;
                            });
                            messenger
                              ..hideCurrentSnackBar()
                              ..showSnackBar(
                                SnackBar(
                                  key: const Key('attack_boss_success_snackbar'),
                                  backgroundColor: Colors.green,
                                  content: Text('Berhasil! $msg'),
                                ),
                              );
                          } catch (e) {
                            if (!mounted) return;
                            final errMsg =
                                e.toString().replaceFirst('Exception: ', '');
                            setState(() {
                              _guildFeedbackBanner = errMsg;
                            });
                            messenger
                              ..hideCurrentSnackBar()
                              ..showSnackBar(
                                SnackBar(
                                  key: const Key('attack_boss_error_snackbar'),
                                  backgroundColor: Colors.red,
                                  content: Text(errMsg),
                                ),
                              );
                          }
                        },
                        icon: const Icon(Icons.gps_fixed),
                        label: const Text('Kirim Kapal Serang Bersama'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 12),
          Text(
            'Daftar Anggota Aliansi (${guild.members.length} Nahkoda)',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          ...guild.members.map(
            (m) => MaritimeWoodCard(
              key: Key('guild_member_tile_${m.playerId}'),
              child: ListTile(
                leading: CircleAvatar(
                  child: Text('Lv${m.level}'),
                ),
                title: Text(
                  m.displayName,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(
                  'Peran: ${m.role.toUpperCase()} • Kekayaan: ${m.netWorth} Koin',
                ),
                trailing: Chip(
                  label: Text(m.role.toUpperCase()),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeCtrl = Provider.of<ThemeController>(context);
    final pages = <Widget>[
      _buildMarketTab(),
      _buildBursaP2pTab(),
      _buildRuleEditorTab(),
      _buildShipsTab(),
      _buildLeaderboardAndProfileTab(),
      _buildGuildAllianceTab(),
    ];

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 10,
        title: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: MaritimePalette.carvedMahogany,
                border: Border.all(color: MaritimePalette.gold, width: 1.5),
                boxShadow: const <BoxShadow>[
                  BoxShadow(
                    color: Colors.black54,
                    blurRadius: 4,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: const Icon(
                Icons.anchor,
                size: 18,
                color: MaritimePalette.gold,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _playerDisplayName,
                    key: const Key('hud_captain_name'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: MaritimePalette.cinzel(
                      color: MaritimePalette.gold,
                      fontSize: 13.5,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    'Jalur Rempah • $_playerTitle',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: MaritimePalette.crimsonText(
                      color: MaritimePalette.parchmentMuted,
                      fontSize: 11.5,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            Container(
              key: const Key('hud_coin_box'),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: <Color>[
                    Color(0xFF281815),
                    Color(0xFF3E2723),
                  ],
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: MaritimePalette.gold,
                  width: 1.4,
                ),
                boxShadow: const <BoxShadow>[
                  BoxShadow(
                    color: Color(0x99000000),
                    blurRadius: 4,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: AnimatedCoinCounter(
                key: const Key('hud_animated_coin_text'),
                coins: _playerCoins,
              ),
            ),
          ],
        ),
        actions: [
          ListenableBuilder(
            listenable: AudioManager(),
            builder: (context, _) {
              final muted = AudioManager().isMuted;
              return IconButton(
                key: const Key('appbar_mute_toggle_button'),
                visualDensity: VisualDensity.compact,
                tooltip: muted ? 'Nyalakan Suara (Unmute)' : 'Matikan Suara (Mute)',
                icon: Icon(
                  muted ? Icons.volume_off : Icons.volume_up,
                  size: 20,
                ),
                onPressed: () {
                  AudioManager().toggleMute();
                },
              );
            },
          ),
          IconButton(
            key: const Key('appbar_notification_bell_button'),
            visualDensity: VisualDensity.compact,
            tooltip: 'Notifikasi Pertempuran Laut',
            icon: Badge(
              key: const Key('appbar_notification_badge'),
              isLabelVisible: _unreadCombatNotifications > 0,
              backgroundColor: Colors.red,
              label: Text('$_unreadCombatNotifications'),
              child: const Icon(Icons.notifications_outlined, size: 20),
            ),
            onPressed: () {
              HapticFeedback.heavyImpact();
              AudioManager().playSfx('cannon');
              setState(() {
                _unreadCombatNotifications = 0;
                _combatShakeCounter += 1;
              });
              final latest = _combatNotifications.firstOrNull;
              if (latest != null) {
                final isDanger = latest.severity == 'danger';
                final snackText = isDanger
                    ? 'Bajak Laut menyerang kapal Anda! -35 HP, 4 Pala dirampas.'
                    : 'Anda mengalahkan Bajak Laut! +200 Koin.';
                ScaffoldMessenger.of(context)
                  ..hideCurrentSnackBar()
                  ..showSnackBar(
                    SnackBar(
                      key: const Key('combat_alert_snackbar'),
                      backgroundColor: isDanger
                          ? Colors.red.shade700
                          : Colors.green.shade700,
                      content: Text(snackText),
                    ),
                  );
              }
            },
          ),
          IconButton(
            key: const Key('appbar_theme_cycle_button'),
            visualDensity: VisualDensity.compact,
            tooltip: 'Ganti Tema (System / Light / Dark)',
            icon: Icon(
              themeCtrl.themeMode == ThemeMode.dark
                  ? Icons.dark_mode
                  : themeCtrl.themeMode == ThemeMode.light
                      ? Icons.light_mode
                      : Icons.brightness_auto,
              size: 20,
            ),
            onPressed: () {
              AudioManager().playSfx('click');
              final next = themeCtrl.themeMode == ThemeMode.system
                  ? ThemeMode.dark
                  : themeCtrl.themeMode == ThemeMode.dark
                      ? ThemeMode.light
                      : ThemeMode.system;
              themeCtrl.setThemeMode(next);
            },
          ),
          IconButton(
            key: const Key('refresh_dashboard_button'),
            visualDensity: VisualDensity.compact,
            onPressed: () {
              AudioManager().playSfx('click');
              _refreshAll();
            },
            icon: const Icon(Icons.refresh, size: 20),
          ),
          IconButton(
            key: const Key('logout_button'),
            visualDensity: VisualDensity.compact,
            onPressed: () {
              AudioManager().playSfx('click');
              widget.onLogout();
            },
            icon: const Icon(Icons.logout, size: 20),
          ),
        ],
      ),
      body: pages[_tabIndex],
      bottomNavigationBar: WoodenBottomNavBar(
        selectedIndex: _tabIndex,
        onDestinationSelected: (idx) {
          ScaffoldMessenger.of(context).clearSnackBars();
          setState(() {
            _tabIndex = idx;
          });
          _loadTabData(idx);
        },
      ),
    );
  }
}