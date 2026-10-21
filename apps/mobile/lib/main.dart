import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'catalog_models.dart';
import 'nusantara_map.dart';
import 'syntax_highlight_controller.dart';
import 'theme_controller.dart';

export 'catalog_models.dart';
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
      portId: (json['port_id'] as num?)?.toInt(),
      destPort: (json['dest_port'] as num?)?.toInt(),
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
  final String portCode;
  final String commodityCode;
  final int qty;
  final int rewardCoins;
  final String status;

  const TradeContractModel({
    required this.id,
    required this.portCode,
    required this.commodityCode,
    required this.qty,
    required this.rewardCoins,
    required this.status,
  });

  factory TradeContractModel.fromJson(Map<String, dynamic> json) {
    return TradeContractModel(
      id: (json['id'] as num?)?.toInt() ?? 0,
      portCode: (json['port_code'] as String?) ?? 'banda',
      commodityCode: (json['commodity_code'] as String?) ?? 'pala',
      qty: (json['qty'] as num?)?.toInt() ?? 1,
      rewardCoins: (json['reward_coins'] as num?)?.toInt() ?? 100,
      status: (json['status'] as String?) ?? 'open',
    );
  }
}

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

  // Fase 9: Autentikasi Google (POST /v1/auth/google)
  Future<Map<String, dynamic>> loginWithGoogle({String idToken = ''}) async {
    const configuredClientId = String.fromEnvironment(
      'GOOGLE_CLIENT_ID',
      defaultValue: '',
    );
    if (idToken.trim().isEmpty && configuredClientId.trim().isEmpty) {
      throw Exception('Google Login belum dikonfigurasi');
    }
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
          'Kebijakan Privasi (Kepatuhan UU No. 27 Tahun 2022 tentang Pelindungan Data Pribadi / UU PDP): Kami hanya menyimpan email, hash sandi scrypt, dan log simulasi kapal. Anda berhak menghapus & menganonimkan akun kapan saja melalui fitur Hapus Akun (DELETE /v1/me).',
      codeOfConduct:
          'Hukum In-Game (Code of Conduct): Transaksi P2P wajib berada pada rentang 50%-200% harga pasar. Pelanggaran dikenai Shadowban hingga Permanent Ban.',
    );
  }

  Future<List<MapPortNode>> getWorldPorts() async {
    return kNusantaraPortNodes;
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
  final HttpClient _http = HttpClient();

  HttpJalurRempahApiClient({
    required this.baseUrl,
    required this.tokenVault,
  });

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
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
    final decoded = text.isNotEmpty
        ? (jsonDecode(text) as Map<String, dynamic>)
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
    const configuredClientId = String.fromEnvironment(
      'GOOGLE_CLIENT_ID',
      defaultValue: '',
    );
    final effectiveToken = idToken.trim();
    if (effectiveToken.isEmpty && configuredClientId.trim().isEmpty) {
      try {
        await _request(
          'POST',
          '/v1/auth/google',
          body: <String, dynamic>{'id_token': ''},
        );
      } catch (_) {
        throw Exception('Google Login belum dikonfigurasi');
      }
      throw Exception('Google Login belum dikonfigurasi');
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
    final bgPaint = Paint()
      ..color = isDark ? const Color(0xFF1E293B) : const Color(0xFFF5EFE6)
      ..style = PaintingStyle.fill;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Offset.zero & size,
        const Radius.circular(8),
      ),
      bgPaint,
    );

    if (points.length < 2) return;

    int minPrice = points.first.price;
    int maxPrice = points.first.price;
    for (final p in points) {
      if (p.price < minPrice) minPrice = p.price;
      if (p.price > maxPrice) maxPrice = p.price;
    }
    final range = (maxPrice - minPrice) <= 0 ? 1 : (maxPrice - minPrice);

    final linePaint = Paint()
      ..color = isDark ? const Color(0xFFFBBF24) : const Color(0xFF8B4513)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;

    final path = Path();
    for (int i = 0; i < points.length; i++) {
      final x = (i / (points.length - 1)) * (size.width - 24) + 12;
      final normalizedY = (points[i].price - minPrice) / range;
      final y = size.height - 16 - normalizedY * (size.height - 32);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
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
  final ThemeController? themeController;

  const JalurRempahApp({
    super.key,
    this.apiClient,
    this.themeController,
  });

  @override
  State<JalurRempahApp> createState() => _JalurRempahAppState();
}

class _JalurRempahAppState extends State<JalurRempahApp> {
  late final TokenVault _vault;
  late final JalurRempahApiClient _api;
  late final ThemeController _themeController;
  bool _authenticated = false;

  @override
  void initState() {
    super.initState();
    _vault = InMemorySecureTokenVault();
    _themeController = widget.themeController ?? ThemeController();
    _api = widget.apiClient ??
        HttpJalurRempahApiClient(
          baseUrl: const String.fromEnvironment(
            'API_BASE_URL',
            defaultValue: 'https://api.bacanova.my.id',
          ),
          tokenVault: _vault,
        );
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<ThemeController>.value(
      value: _themeController,
      child: Consumer<ThemeController>(
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
                      setState(() {
                        _authenticated = false;
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
      ),
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
      appBar: AppBar(
        title: const Text('Syarat & Ketentuan & UU PDP'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
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
                Card(
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
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  bool _isRegisterMode = false;
  bool _tosAccepted = true;
  bool _busy = false;
  String? _errorMsg;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
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
      const configuredClientId = String.fromEnvironment(
        'GOOGLE_CLIENT_ID',
        defaultValue: '',
      );
      await widget.api.loginWithGoogle(
        idToken: configuredClientId.isNotEmpty ? 'google_oauth_id_token' : '',
      );
      widget.onAuthenticated();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMsg = 'Google Login belum dikonfigurasi';
      });
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            key: Key('google_auth_error_snackbar'),
            content: Text('Google Login belum dikonfigurasi'),
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
                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
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
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => LegalDocumentsScreen(api: widget.api),
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
              onPressed: canSubmit ? _submit : null,
              child: Text(_isRegisterMode ? 'Daftar & Buat Kapal' : 'Masuk'),
            ),
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

class _MainDashboardShellState extends State<MainDashboardShell> {
  int _tabIndex = 0;
  String _selectedPortCode = 'banda';
  String _selectedCommodity = 'pala';

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
  List<ShipModel> _fleet = const <ShipModel>[];
  int _fleetCount = 1;
  int _shipAttackPower = 0;
  int _shipDefensePower = 65;
  int _shipMaxDefensePower = 100;
  List<CombatLogItemModel> _combatLogs = const <CombatLogItemModel>[];
  List<CombatNotificationModel> _combatNotifications =
      const <CombatNotificationModel>[];
  int _unreadCombatNotifications = 0;

  // Data Bursa P2P (Langkah 5)
  List<P2pOrderItemModel> _p2pOrders = const <P2pOrderItemModel>[];
  String _p2pOrderType = 'auction';
  int _p2pCommodityId = 1;
  final _p2pQtyCtrl = TextEditingController(text: '2');
  final _p2pUnitPriceCtrl = TextEditingController(text: '75');
  final _p2pTargetPlayerCtrl = TextEditingController();
  String? _p2pFeedbackBanner;

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

  @override
  void initState() {
    super.initState();
    _refreshAll();
  }

  @override
  void dispose() {
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

  Future<void> _refreshAll() async {
    final profile = await widget.api.getProfile();
    final ports = await widget.api.getPorts();
    final worldPorts = await widget.api.getWorldPorts();
    final worldCommodities = await widget.api.getWorldCommodities();
    final events = await widget.api.getWorldEvents();
    final market = await widget.api.getMarket(_selectedPortCode);
    final history = await widget.api.getPriceHistory(
      _selectedPortCode,
      _selectedCommodity,
    );
    final ship = await widget.api.getPrimaryShip();
    final shipsList = await widget.api.getShips();
    final rules = await widget.api.getShipRules(ship.id);
    final templates = await widget.api.getRuleTemplates();
    final logs = await widget.api.getShipLogs(ship.id);
    final lb = await widget.api.getLeaderboard();
    final p2p = await widget.api.getP2pOrders();

    if (!mounted) return;
    setState(() {
      _playerId = (profile['id'] as num?)?.toInt() ?? 1;
      _playerDisplayName =
          (profile['display_name'] as String?) ?? 'Nahkoda_Satu';
      _playerCoins = (profile['coins'] as num?)?.toInt() ?? 1000;
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
      _tutorialStep = (profile['tutorial_step'] as num?)?.toInt() ?? _tutorialStep;

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
      _ship = ship;
      _fleet = shipsList.isNotEmpty ? shipsList : <ShipModel>[ship];
      _fleetCount = _fleet.length;
      _ruleVersion = (rules['version'] as num?)?.toInt() ?? 0;
      if (_ruleEditorCtrl.text.isEmpty) {
        _ruleEditorCtrl.text = (rules['source'] as String?) ?? '';
      }
      _templates = templates;
      _logs = logs;
      _leaderboard = lb;
      _p2pOrders = p2p;
      _shipAttackPower = ship.attackPower;
      _shipDefensePower = ship.defensePower;
      _shipMaxDefensePower = ship.maxDefensePower;
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
        if (parsedLogs.isNotEmpty && _shipDefensePower == 100) {
          _shipDefensePower = parsedLogs.first.shipDefenseAfter;
        }
      });
    } catch (_) {
      // Abaikan jika endpoint log belum memiliki data
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

    try {
      final guilds = await widget.api.getGuilds(query: _guildSearchQuery);
      final myGuildId = (profile['guild_id'] as num?)?.toInt();
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
    } catch (_) {
      // Fallback ke direktori default
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

    final shipMarkers = _fleet
        .map(
          (s) => MapShipMarker(
            id: s.id,
            name: s.name,
            status: s.status,
            portId: s.portId,
            destPortId: s.destPort,
            tier: s.tier,
          ),
        )
        .toList();

    // Gabungkan data harga pasar live dengan katalog 10 komoditas Nusantara
    final liveByCode = <String, MarketItemModel>{
      for (final m in _marketItems) m.commodity.toLowerCase(): m,
    };

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_tutorialStep == 0)
          Card(
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
                    style: TextStyle(color: Color(0xFF1E40AF)),
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
            return Card(
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
                        ? const Color(0xFF7F1D1D)
                        : const Color(0xFF78350F),
                  ),
                ),
                subtitle: Text(
                  ev.description.isNotEmpty
                      ? ev.description
                      : 'Wabah Hama di Banda! Harga Pala naik.',
                  style: TextStyle(
                    color: isDanger
                        ? const Color(0xFF991B1B)
                        : const Color(0xFF92400E),
                  ),
                ),
              ),
            );
          }),
        Card(
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
          eventPortIds: eventPortIds,
          onSelectPort: _selectPort,
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

          void handleCommodityTapOrTrade() async {
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
            if (live != null) {
              final hist = await widget.api.getPriceHistory(
                _selectedPortCode,
                cat.code,
              );
              if (!mounted) return;
              setState(() {
                _selectedCommodity = cat.code;
                _priceHistory = hist;
              });
            } else {
              setState(() {
                _selectedCommodity = cat.code;
              });
            }
          }

          return Opacity(
            opacity: cat.isLocked ? 0.5 : 1.0,
            child: Card(
              key: Key('market_commodity_${cat.code}'),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: cat.isLocked ? Colors.grey.shade400 : null,
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
                            : Icons.shopping_bag_outlined,
                      ),
                      onPressed: handleCommodityTapOrTrade,
                    ),
                  ],
                ),
                onTap: handleCommodityTapOrTrade,
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
      setState(() {
        _p2pOrders = <P2pOrderItemModel>[created, ..._p2pOrders];
        _p2pFeedbackBanner =
            'Order P2P #${created.id} (${created.commodityCode.toUpperCase()} x${created.qty}) berhasil dipasang di Escrow!';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _p2pFeedbackBanner = e.toString();
      });
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
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Buat Tawaran Jual Baru (POST /v1/p2p/orders)',
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
                  onPressed: _submitCreateP2pOrder,
                  icon: const Icon(Icons.gavel_outlined),
                  label: const Text('Pasang Tawaran di Bursa P2P'),
                ),
              ],
            ),
          ),
        ),
        if (_p2pFeedbackBanner != null) ...[
          const SizedBox(height: 8),
          Card(
            key: const Key('p2p_feedback_banner'),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(_p2pFeedbackBanner!),
            ),
          ),
        ],
        const SizedBox(height: 14),
        const Text(
          'Daftar Order Book Aktif (GET /v1/p2p/orders)',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        ..._p2pOrders.map((ord) {
          final isMine = ord.sellerId == _playerId || ord.sellerName == 'Anda';
          return Card(
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
                        await widget.api.acceptP2pOrder(
                          ord.id,
                          _ship?.id ?? 1,
                        );
                        if (!mounted) return;
                        setState(() {
                          _p2pOrders = _p2pOrders
                              .where((x) => x.id != ord.id)
                              .toList();
                          _p2pFeedbackBanner =
                              'Berhasil membeli/menerima Order #${ord.id}!';
                        });
                      },
                      child: const Text('Beli/Terima'),
                    ),
                  if (isMine && ord.status == 'open')
                    OutlinedButton(
                      key: Key('p2p_cancel_button_${ord.id}'),
                      onPressed: () async {
                        await widget.api.cancelP2pOrder(ord.id);
                        if (!mounted) return;
                        setState(() {
                          _p2pOrders = _p2pOrders
                              .where((x) => x.id != ord.id)
                              .toList();
                          _p2pFeedbackBanner =
                              'Order #${ord.id} dibatalkan; barang dikembalikan dari Escrow ke kapal.';
                        });
                      },
                      child: const Text('Batalkan'),
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
          Card(
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
              onPressed: _saveCurrentRules,
              child: const Text('Simpan Aturan'),
            ),
            FilledButton.tonal(
              key: const Key('simulate_rules_button'),
              onPressed: _runSandbox,
              child: const Text('Uji Sandbox 200 Tick'),
            ),
          ],
        ),
        if (_statusBanner != null) ...[
          const SizedBox(height: 12),
          Card(
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
          Card(
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
    final nextNum = _fleetCount + 1;
    final shipName = '${tierSpec.name} #$nextNum';
    final created = await widget.api.buyShip(
      name: shipName,
      portId: _ship?.portId ?? 1,
      tierSpec: tierSpec,
    );
    if (!mounted) return;
    setState(() {
      _fleetCount += 1;
      _fleet = <ShipModel>[..._fleet, created];
      _fleetNotice =
          '${tierSpec.name} (${tierSpec.shipClass}, Kapasitas ${tierSpec.capacity}, Harga ${tierSpec.price} koin) ditambahkan ke armada (#$_fleetCount).';
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
              Navigator.of(ctx).pop();
              final res = await widget.api.repairShip(shipId);
              if (!mounted) return;
              setState(() {
                _shipDefensePower =
                    (res['defense_power'] as num?)?.toInt() ??
                        _shipMaxDefensePower;
                _fleetNotice =
                    'Kapal berhasil diperbaiki ke $_shipDefensePower/$_shipMaxDefensePower HP (Biaya: $repairCost koin).';
              });
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
                'Pasang Persenjataan Kapal (POST /v1/ships/equip)',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              const Text(
                'Pilih senjata dari muatan kapal atau gudang pelabuhan untuk meningkatkan Attack Power (ATK):',
              ),
              const SizedBox(height: 12),
              Card(
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
                    Navigator.of(ctx).pop();
                    final res = await widget.api.equipWeapon(
                      shipId: shipId,
                      weapon: 'meriam',
                      qty: 1,
                    );
                    if (!mounted) return;
                    setState(() {
                      final added =
                          (res['attack_power_added'] as num?)?.toInt() ??
                              35;
                      _shipAttackPower += added;
                      _fleetNotice =
                          'Meriam (+35 ATK) berhasil dipasang! Total ATK kapal: $_shipAttackPower.';
                    });
                  },
                ),
              ),
              Card(
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
                    Navigator.of(ctx).pop();
                    final res = await widget.api.equipWeapon(
                      shipId: shipId,
                      weapon: 'katana',
                      qty: 1,
                    );
                    if (!mounted) return;
                    setState(() {
                      final added =
                          (res['attack_power_added'] as num?)?.toInt() ??
                              15;
                      _shipAttackPower += added;
                      _fleetNotice =
                          'Katana (+15 ATK) berhasil dipasang! Total ATK kapal: $_shipAttackPower.';
                    });
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

  Widget _buildShipLogTab() {
    final s = _ship;
    final defaultTier2 = kShipTiersCatalog[1]; // Pencalang Niaga (1.500 koin)
    final maxHp = _shipMaxDefensePower <= 0 ? 100 : _shipMaxDefensePower;
    final curHp = _shipDefensePower.clamp(0, maxHp);
    final hpRatio = (curHp / maxHp).clamp(0.0, 1.0);
    final hpBarColor = hpRatio > 0.5 ? Colors.green : Colors.red;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          key: const Key('primary_ship_combat_card'),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.directions_boat, size: 32),
                  title: Text(
                    s?.name ?? 'Kapal Perintis',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    'Status: ${s?.status ?? 'docked'} | Kapasitas: ${s?.capacity ?? 35} | Armada: $_fleetCount/5 kapal | ETA: ${s?.etaTicks ?? 0} tick',
                  ),
                  trailing: OutlinedButton(
                    key: const Key('buy_ship_button'),
                    onPressed: _fleetCount >= 5
                        ? null
                        : () => _purchaseShipTier(defaultTier2),
                    child: const Text('Beli Kapal (1.500)'),
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  runSpacing: 4,
                  children: [
                    Text(
                      'HP Lambung Kapal (Defense): $curHp / $maxHp HP',
                      key: const Key('ship_hp_status_text'),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      'Attack Power (ATK): $_shipAttackPower',
                      key: const Key('ship_attack_power_text'),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    key: const Key('ship_hp_progress_bar'),
                    value: hpRatio,
                    color: hpBarColor,
                    minHeight: 10,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.tonalIcon(
                      key: const Key('repair_ship_button'),
                      onPressed: _showRepairConfirmationDialog,
                      icon: const Icon(Icons.build_circle_outlined, size: 18),
                      label: const Text('Perbaiki Kapal (2 Koin/HP)'),
                    ),
                    OutlinedButton.icon(
                      key: const Key('equip_weapon_button'),
                      onPressed: _showEquipWeaponSheet,
                      icon: const Icon(Icons.shield_outlined, size: 18),
                      label: const Text('Pasang Senjata'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        if (_fleetNotice != null) ...[
          const SizedBox(height: 8),
          Card(
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
          (tier) => Card(
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
                      icon: const Icon(Icons.add_shopping_cart, size: 18),
                      label: Text('Beli ${tier.name} (${tier.price} koin)'),
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
          (cl) => Card(
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
          (l) => Card(
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
        Card(
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
        const Text(
          'Misi Harian (Daily Quests — Reset 00:00)',
          key: Key('daily_quests_section'),
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        if (_questFeedbackBanner != null) ...[
          Card(
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
          return Card(
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
                            final res = await widget.api.claimQuest(q.id);
                            if (!mounted) return;
                            final rwCoins =
                                (res['reward_coins'] as num?)?.toInt() ??
                                    q.rewardCoins;
                            final rwXp =
                                (res['reward_xp'] as num?)?.toInt() ??
                                    q.rewardXp;
                            setState(() {
                              _playerCoins += rwCoins;
                              _playerNetWorth += rwCoins;
                              _dailyQuests = _dailyQuests
                                  .map((item) => item.id == q.id
                                      ? item.copyWith(isClaimed: true)
                                      : item)
                                  .toList();
                              _questFeedbackBanner =
                                  'Hadiah misi "${q.title}" berhasil diklaim: +$rwCoins Koin & +$rwXp EXP!';
                            });
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
        Card(
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
          (item) => Card(
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
        const Card(
          key: Key('guilds_contracts_card'),
          child: ListTile(
            leading: Icon(Icons.handshake_outlined),
            title: Text('Serikat Rempah Nusantara & Kontrak Pengiriman'),
            subtitle: Text(
              'Penuhi kontrak pengiriman komoditas di pelabuhan tujuan dengan escrow kas pelabuhan terjamin.',
            ),
          ),
        ),
      ],
    );
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
                  setState(() {
                    _currentGuild = created;
                    if (_playerCoins >= 5000) {
                      _playerCoins -= 5000;
                    }
                    _guildFeedbackBanner =
                        'Aliansi "${created.name}" berhasil didirikan! 5.000 Koin telah masuk ke Kas Guild.';
                  });
                } catch (e) {
                  if (!mounted) return;
                  setState(() {
                    _guildFeedbackBanner = e.toString();
                  });
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
                    _guildFeedbackBanner =
                        'Berhasil menyetor $amount Koin ke Kas Aliansi! Total Kas Guild kini $newTreasury Koin.';
                  });
                } catch (e) {
                  if (!mounted) return;
                  setState(() {
                    _guildFeedbackBanner = e.toString();
                  });
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
          Card(
            key: const Key('guild_feedback_banner'),
            color: const Color(0xFFDCFCE7),
            child: ListTile(
              leading:
                  const Icon(Icons.shield_outlined, color: Color(0xFF166534)),
              title: Text(
                _guildFeedbackBanner!,
                style: const TextStyle(
                  color: Color(0xFF14532D),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        if (guild == null) ...[
          Card(
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
            (g) => Card(
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
                  onPressed: () async {
                    final joined = await widget.api.joinGuild(g.id);
                    if (!mounted) return;
                    setState(() {
                      _currentGuild = joined;
                      _guildFeedbackBanner =
                          'Anda resmi bergabung ke dalam ${joined.name}!';
                    });
                  },
                  child: const Text('Gabung'),
                ),
              ),
            ),
          ),
        ] else ...[
          Card(
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
                          await widget.api.leaveGuild(guild.id);
                          if (!mounted) return;
                          setState(() {
                            _currentGuild = null;
                            _guildFeedbackBanner =
                                'Anda telah keluar dari ${guild.name}.';
                          });
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
            Card(
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
                              color: Color(0xFF7F1D1D),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Kas Guild melampaui 10.000 Koin! Bajak Laut Armada Besar muncul di peta. HP Boss: ${guild.worldBoss.hp}/${guild.worldBoss.maxHp}',
                      style: const TextStyle(color: Color(0xFF991B1B)),
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
                            _guildFeedbackBanner =
                                'Kapal Anda menyerang ${guild.worldBoss.name} (-${dmg} HP, sisa $hpAfter/${guild.worldBoss.maxHp} HP)!';
                          });
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
            (m) => Card(
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
      _buildShipLogTab(),
      _buildLeaderboardAndProfileTab(),
      _buildGuildAllianceTab(),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text('Jalur Rempah • $_playerTitle'),
        actions: [
          IconButton(
            key: const Key('appbar_notification_bell_button'),
            tooltip: 'Notifikasi Pertempuran Laut',
            icon: Badge(
              key: const Key('appbar_notification_badge'),
              isLabelVisible: _unreadCombatNotifications > 0,
              backgroundColor: Colors.red,
              label: Text('$_unreadCombatNotifications'),
              child: const Icon(Icons.notifications_outlined),
            ),
            onPressed: () {
              setState(() {
                _unreadCombatNotifications = 0;
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
            tooltip: 'Ganti Tema (System / Light / Dark)',
            icon: Icon(
              themeCtrl.themeMode == ThemeMode.dark
                  ? Icons.dark_mode
                  : themeCtrl.themeMode == ThemeMode.light
                      ? Icons.light_mode
                      : Icons.brightness_auto,
            ),
            onPressed: () {
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
            onPressed: _refreshAll,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            key: const Key('logout_button'),
            onPressed: widget.onLogout,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: pages[_tabIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tabIndex,
        onDestinationSelected: (idx) {
          setState(() {
            _tabIndex = idx;
          });
        },
        destinations: const [
          NavigationDestination(
            key: Key('nav_market'),
            icon: Icon(Icons.map_outlined),
            label: 'Pasar',
          ),
          NavigationDestination(
            key: Key('nav_bursa'),
            icon: Icon(Icons.storefront_outlined),
            label: 'Bursa',
          ),
          NavigationDestination(
            key: Key('nav_rules'),
            icon: Icon(Icons.code),
            label: 'Aturan',
          ),
          NavigationDestination(
            key: Key('nav_ship'),
            icon: Icon(Icons.directions_boat_outlined),
            label: 'Kapal & Log',
          ),
          NavigationDestination(
            key: Key('nav_leaderboard'),
            icon: Icon(Icons.leaderboard_outlined),
            label: 'Peringkat',
          ),
          NavigationDestination(
            key: Key('nav_guild'),
            icon: Icon(Icons.shield_outlined),
            label: 'Aliansi',
          ),
        ],
      ),
    );
  }
}
