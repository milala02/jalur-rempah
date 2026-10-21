class ShipTierSpecModel {
  final int tier;
  final String code;
  final String name;
  final String shipClass;
  final int capacity;
  final double speedMultiplier;
  final int hullHp;
  final int crewCount;
  final int upkeepPerTick;
  final int price;
  final String description;

  const ShipTierSpecModel({
    required this.tier,
    required this.code,
    required this.name,
    required this.shipClass,
    required this.capacity,
    required this.speedMultiplier,
    required this.hullHp,
    required this.crewCount,
    required this.upkeepPerTick,
    required this.price,
    required this.description,
  });

  factory ShipTierSpecModel.fromJson(Map<String, dynamic> json) {
    return ShipTierSpecModel(
      tier: (json['tier'] as num?)?.toInt() ?? 1,
      code: (json['code'] as String?) ?? 'perahu_layar',
      name: (json['name'] as String?) ?? 'Perahu Layar Perintis',
      shipClass:
          (json['ship_class'] as String?) ?? 'Tingkat I — Perintis Pantai',
      capacity: (json['capacity'] as num?)?.toInt() ?? 35,
      speedMultiplier: (json['speed_multiplier'] as num?)?.toDouble() ?? 1.0,
      hullHp: (json['hull_hp'] as num?)?.toInt() ?? 100,
      crewCount: (json['crew_count'] as num?)?.toInt() ?? 8,
      upkeepPerTick: (json['upkeep_per_tick'] as num?)?.toInt() ?? 1,
      price: (json['price'] as num?)?.toInt() ?? 1000,
      description: (json['description'] as String?) ?? '',
    );
  }
}

const List<ShipTierSpecModel> kShipTiersCatalog = <ShipTierSpecModel>[
  ShipTierSpecModel(
    tier: 1,
    code: 'perahu_layar',
    name: 'Perahu Layar Perintis',
    shipClass: 'Tingkat I — Perintis Pantai',
    capacity: 35,
    speedMultiplier: 1.0,
    hullHp: 100,
    crewCount: 8,
    upkeepPerTick: 1,
    price: 1000,
    description:
        'Perahu kayu jati ringan lincah untuk pelayaran pantai dan antar-pulau dekat.',
  ),
  ShipTierSpecModel(
    tier: 2,
    code: 'pencalang_niaga',
    name: 'Pencalang Niaga',
    shipClass: 'Tingkat II — Saudagar Selat',
    capacity: 60,
    speedMultiplier: 1.15,
    hullHp: 160,
    crewCount: 15,
    upkeepPerTick: 2,
    price: 1500,
    description:
        'Kapal dagang Melayu-Bugis berlambung merbau dengan ruang palka menengah.',
  ),
  ShipTierSpecModel(
    tier: 3,
    code: 'pinisi_nusantara',
    name: 'Pinisi Nusantara',
    shipClass: 'Tingkat III — Penjelajah Samudra',
    capacity: 100,
    speedMultiplier: 1.25,
    hullHp: 250,
    crewCount: 24,
    upkeepPerTick: 3,
    price: 3200,
    description:
        'Kapal layar agung 2 tiang 7 layar dari kayu ulin Sulawesi untuk rute lintas Nusantara.',
  ),
  ShipTierSpecModel(
    tier: 4,
    code: 'kora_kora',
    name: 'Kora-Kora Maluku',
    shipClass: 'Tingkat IV — Pengawal Rempah Cepat',
    capacity: 150,
    speedMultiplier: 1.40,
    hullHp: 360,
    crewCount: 40,
    upkeepPerTick: 4,
    price: 5500,
    description:
        'Kapal cepat kepulauan rempah dengan cadik ganda, dayung taktis, dan layar tanjak.',
  ),
  ShipTierSpecModel(
    tier: 5,
    code: 'jung_samudra',
    name: 'Jung Samudra Majapahit',
    shipClass: 'Tingkat V — Armada Agung Nusantara',
    capacity: 250,
    speedMultiplier: 1.50,
    hullHp: 550,
    crewCount: 75,
    upkeepPerTick: 6,
    price: 9500,
    description:
        'Kapal induk niaga raksasa berlambung empat lapis dengan kapasitas palka terbesar di Nusantara.',
  ),
];

class CommodityCatalogItemModel {
  final int id;
  final String code;
  final String name;
  final String category;
  final String originPort;
  final String countryCode;
  final String countryName;
  final int basePrice;
  final String rarity;
  final String description;
  final int minLevelRequired;
  final bool isLocked;

  const CommodityCatalogItemModel({
    required this.id,
    required this.code,
    required this.name,
    required this.category,
    required this.originPort,
    required this.basePrice,
    required this.rarity,
    required this.description,
    this.countryCode = 'nusantara',
    this.countryName = 'Kepulauan Nusantara',
    this.minLevelRequired = 1,
    this.isLocked = false,
  });

  factory CommodityCatalogItemModel.fromJson(Map<String, dynamic> json) {
    final minLv = (json['min_level_required'] as num?)?.toInt() ?? 1;
    return CommodityCatalogItemModel(
      id: (json['id'] as num?)?.toInt() ?? 1,
      code: (json['code'] as String?) ?? 'pala',
      name: (json['name'] as String?) ?? 'Pala Banda',
      category: (json['category'] as String?) ?? 'Rempah Utama',
      originPort: (json['origin_port_name'] as String?) ??
          (json['origin_port_code'] as String?) ??
          (json['origin_port'] as String?) ??
          'Banda',
      countryCode: (json['country_code'] as String?) ?? 'nusantara',
      countryName:
          (json['country_name'] as String?) ?? 'Kepulauan Nusantara',
      basePrice: (json['base_price'] as num?)?.toInt() ?? 70,
      rarity: (json['rarity'] as String?) ??
          (minLv > 1 ? 'Komoditas Internasional Lv.$minLv' : 'Ekspor Utama'),
      description: (json['description'] as String?) ?? '',
      minLevelRequired: minLv,
      isLocked: (json['is_locked'] as bool?) ?? (minLv > 1),
    );
  }

  CommodityCatalogItemModel copyWithPlayerLevel(int playerLevel) {
    return CommodityCatalogItemModel(
      id: id,
      code: code,
      name: name,
      category: category,
      originPort: originPort,
      countryCode: countryCode,
      countryName: countryName,
      basePrice: basePrice,
      rarity: rarity,
      description: description,
      minLevelRequired: minLevelRequired,
      isLocked: minLevelRequired > playerLevel,
    );
  }
}

const List<CommodityCatalogItemModel> kExtendedCommoditiesCatalog =
    <CommodityCatalogItemModel>[
  CommodityCatalogItemModel(
    id: 1,
    code: 'pala',
    name: 'Pala Banda',
    category: 'Rempah Utama',
    originPort: 'Banda',
    countryCode: 'nusantara',
    countryName: 'Kepulauan Nusantara',
    basePrice: 70,
    rarity: 'Emas Kepulauan',
    description:
        'Biji pala dan fuli wangi asli Kepulauan Banda yang diburu pedagang dunia.',
    minLevelRequired: 1,
    isLocked: false,
  ),
  CommodityCatalogItemModel(
    id: 2,
    code: 'cengkeh',
    name: 'Cengkeh Ternate',
    category: 'Rempah Utama',
    originPort: 'Ternate',
    countryCode: 'nusantara',
    countryName: 'Kepulauan Nusantara',
    basePrice: 90,
    rarity: 'Mahkota Maluku',
    description:
        'Kuncup bunga cengkeh aromatik kualitas kerajaan dari lereng vulkanik Ternate & Tidore.',
    minLevelRequired: 1,
    isLocked: false,
  ),
  CommodityCatalogItemModel(
    id: 3,
    code: 'garam',
    name: 'Garam Laut Jawa',
    category: 'Pangan & Pengawet',
    originPort: 'Surabaya',
    countryCode: 'nusantara',
    countryName: 'Kepulauan Nusantara',
    basePrice: 20,
    rarity: 'Konsumsi Pokok',
    description:
        'Garam kristal putih pesisir Jawa Timur & Madura untuk pengawetan logistik pelayaran.',
    minLevelRequired: 1,
    isLocked: false,
  ),
  CommodityCatalogItemModel(
    id: 4,
    code: 'kain',
    name: 'Kain Tenun & Sutra',
    category: 'Tekstil & Barter',
    originPort: 'Malaka',
    countryCode: 'malaka_sultanate',
    countryName: 'Kesultanan Malaka',
    basePrice: 45,
    rarity: 'Niaga Saudagar',
    description:
        'Kain tenun ikat, batik pesisir, dan sutra perdagangan lintas selat untuk barter rempah.',
    minLevelRequired: 1,
    isLocked: false,
  ),
  // 8 Komoditas Internasional Eksklusif Baru (Fase 5 — Progressive Unlocking Levels 4..7)
  CommodityCatalogItemModel(
    id: 5,
    code: 'kuda_arab',
    name: 'Kuda Arab',
    category: 'Mewah',
    originPort: 'Mekkah',
    countryCode: 'arab',
    countryName: 'Arab',
    basePrice: 350,
    rarity: 'Eksklusif Arab (Lv.4)',
    description:
        'Kuda pacu bangsawan garis keturunan murni dari Semenanjung Arab.',
    minLevelRequired: 4,
    isLocked: true,
  ),
  CommodityCatalogItemModel(
    id: 6,
    code: 'kemenyan',
    name: 'Kemenyan',
    category: 'Aromatik',
    originPort: 'Mekkah',
    countryCode: 'arab',
    countryName: 'Arab',
    basePrice: 180,
    rarity: 'Eksklusif Arab (Lv.4)',
    description:
        'Getah harum luban pilihan dari jalur kafilah Arab untuk wewangian dan upacara.',
    minLevelRequired: 4,
    isLocked: true,
  ),
  CommodityCatalogItemModel(
    id: 7,
    code: 'katana',
    name: 'Katana',
    category: 'Senjata',
    originPort: 'Sakai',
    countryCode: 'jepang',
    countryName: 'Jepang',
    basePrice: 520,
    rarity: 'Eksklusif Jepang (Lv.5)',
    description:
        'Pedang baja lipat tempaan pandai besi Sakai dengan ketajaman legendaris.',
    minLevelRequired: 5,
    isLocked: true,
  ),
  CommodityCatalogItemModel(
    id: 8,
    code: 'tembaga',
    name: 'Tembaga',
    category: 'Tambang',
    originPort: 'Sakai',
    countryCode: 'jepang',
    countryName: 'Jepang',
    basePrice: 240,
    rarity: 'Eksklusif Jepang (Lv.5)',
    description:
        'Batangan tembaga murni Jepang untuk pencetakan koin dan pelapis lambung kapal.',
    minLevelRequired: 5,
    isLocked: true,
  ),
  CommodityCatalogItemModel(
    id: 9,
    code: 'meriam',
    name: 'Meriam',
    category: 'Senjata',
    originPort: 'Lisbon',
    countryCode: 'eropa',
    countryName: 'Eropa',
    basePrice: 850,
    rarity: 'Eksklusif Eropa (Lv.6)',
    description:
        'Meriam perunggu kaliber berat buatan galangan artileri Lisbon untuk pertahanan armada.',
    minLevelRequired: 6,
    isLocked: true,
  ),
  CommodityCatalogItemModel(
    id: 10,
    code: 'kaca',
    name: 'Kaca',
    category: 'Mewah',
    originPort: 'Lisbon',
    countryCode: 'eropa',
    countryName: 'Eropa',
    basePrice: 420,
    rarity: 'Eksklusif Eropa (Lv.6)',
    description:
        'Kaca kristal bening, cermin bangsawan, dan lensa optik navigasi dari Eropa.',
    minLevelRequired: 6,
    isLocked: true,
  ),
  CommodityCatalogItemModel(
    id: 11,
    code: 'kapas_mesir',
    name: 'Kapas Mesir',
    category: 'Tekstil',
    originPort: 'Kairo',
    countryCode: 'mesir',
    countryName: 'Mesir',
    basePrice: 600,
    rarity: 'Eksklusif Mesir (Lv.7)',
    description:
        'Serat kapas panjang lembah Sungai Nil kualitas tertinggi di dunia.',
    minLevelRequired: 7,
    isLocked: true,
  ),
  CommodityCatalogItemModel(
    id: 12,
    code: 'emas_batangan',
    name: 'Emas Batangan',
    category: 'Tambang',
    originPort: 'Kairo',
    countryCode: 'mesir',
    countryName: 'Mesir',
    basePrice: 1500,
    rarity: 'Eksklusif Mesir (Lv.7)',
    description:
        'Emas murni batangan perbendaharaan Kairo sebagai penyimpan nilai tertinggi.',
    minLevelRequired: 7,
    isLocked: true,
  ),
];

class WorldEventItemModel {
  final int tickNo;
  final String season;
  final String eventCode;
  final String title;
  final String description;
  final int? portId;
  final int? commodityId;
  final int? activeUntilTick;
  final bool isActive;

  const WorldEventItemModel({
    required this.tickNo,
    required this.season,
    required this.eventCode,
    required this.title,
    required this.description,
    this.portId,
    this.commodityId,
    this.activeUntilTick,
    this.isActive = true,
  });

  factory WorldEventItemModel.fromJson(Map<String, dynamic> json) {
    return WorldEventItemModel(
      tickNo: (json['tick_no'] as num?)?.toInt() ?? 0,
      season: (json['season'] as String?) ?? 'muson_barat',
      eventCode: (json['event_code'] as String?) ?? 'MUSON_BARAT',
      title: (json['title'] as String?) ?? 'Angin Muson Barat',
      description: (json['description'] as String?) ?? '',
      portId: (json['port_id'] as num?)?.toInt(),
      commodityId: (json['commodity_id'] as num?)?.toInt(),
      activeUntilTick: (json['active_until_tick'] as num?)?.toInt(),
      isActive: (json['is_active'] as bool?) ?? true,
    );
  }

  bool get isSpecialAlert =>
      eventCode == 'WABAH_HAMA' ||
      eventCode == 'EMBARGO_PERANG' ||
      eventCode == 'ANGIN_MUSON_KENCANG';
}

class P2pOrderItemModel {
  final int id;
  final String orderType;
  final int sellerId;
  final String sellerName;
  final int? targetPlayerId;
  final int portId;
  final String portCode;
  final int commodityId;
  final String commodityCode;
  final int qty;
  final int unitPrice;
  final int totalPrice;
  final int marketPriceAtCreation;
  final String status;
  final int expiresTick;

  const P2pOrderItemModel({
    required this.id,
    required this.orderType,
    required this.sellerId,
    required this.sellerName,
    this.targetPlayerId,
    required this.portId,
    required this.portCode,
    required this.commodityId,
    required this.commodityCode,
    required this.qty,
    required this.unitPrice,
    required this.totalPrice,
    required this.marketPriceAtCreation,
    required this.status,
    required this.expiresTick,
  });

  factory P2pOrderItemModel.fromJson(Map<String, dynamic> json) {
    final q = (json['qty'] as num?)?.toInt() ?? 1;
    final up = (json['unit_price'] as num?)?.toInt() ?? 50;
    return P2pOrderItemModel(
      id: (json['id'] as num?)?.toInt() ?? 0,
      orderType: (json['order_type'] as String?) ?? 'auction',
      sellerId: (json['seller_id'] as num?)?.toInt() ?? 0,
      sellerName: (json['seller_name'] as String?) ?? 'Saudagar',
      targetPlayerId: (json['target_player_id'] as num?)?.toInt(),
      portId: (json['port_id'] as num?)?.toInt() ?? 1,
      portCode: (json['port_code'] as String?) ?? 'banda',
      commodityId: (json['commodity_id'] as num?)?.toInt() ?? 1,
      commodityCode: (json['commodity_code'] as String?) ?? 'pala',
      qty: q,
      unitPrice: up,
      totalPrice: (json['total_price'] as num?)?.toInt() ?? (q * up),
      marketPriceAtCreation:
          (json['market_price_at_creation'] as num?)?.toInt() ?? up,
      status: (json['status'] as String?) ?? 'open',
      expiresTick: (json['expires_tick'] as num?)?.toInt() ?? 1440,
    );
  }
}

class LegalDocumentModel {
  final String tosVersion;
  final String termsOfService;
  final String privacyPolicyUupdp;
  final String codeOfConduct;

  const LegalDocumentModel({
    required this.tosVersion,
    required this.termsOfService,
    required this.privacyPolicyUupdp,
    required this.codeOfConduct,
  });

  factory LegalDocumentModel.fromJson(Map<String, dynamic> json) {
    return LegalDocumentModel(
      tosVersion: (json['tos_version'] as String?) ?? 'v1.0',
      termsOfService: (json['terms_of_service'] as String?) ?? '',
      privacyPolicyUupdp: (json['privacy_policy_uupdp'] as String?) ?? '',
      codeOfConduct: (json['code_of_conduct'] as String?) ?? '',
    );
  }
}

class CombatLogItemModel {
  final int id;
  final int tickNo;
  final int shipId;
  final String pirateName;
  final int damage;
  final bool isPirate;
  final String outcome;
  final int shipAttackPower;
  final int shipDefenseBefore;
  final int shipDefenseAfter;
  final String? lootedCommodityCode;
  final int lootedQty;
  final int bountyCoins;
  final String detail;

  const CombatLogItemModel({
    required this.id,
    required this.tickNo,
    required this.shipId,
    required this.pirateName,
    required this.damage,
    this.isPirate = true,
    required this.outcome,
    required this.shipAttackPower,
    required this.shipDefenseBefore,
    required this.shipDefenseAfter,
    this.lootedCommodityCode,
    required this.lootedQty,
    required this.bountyCoins,
    required this.detail,
  });

  factory CombatLogItemModel.fromJson(Map<String, dynamic> json) {
    return CombatLogItemModel(
      id: (json['id'] as num?)?.toInt() ?? 1,
      tickNo: (json['tick_no'] as num?)?.toInt() ?? 1,
      shipId: (json['ship_id'] as num?)?.toInt() ?? 1,
      pirateName:
          (json['pirate_name'] as String?) ?? 'Bajak Laut Selat Malaka',
      damage: (json['damage'] as num?)?.toInt() ?? 0,
      isPirate: (json['is_pirate'] as bool?) ?? true,
      outcome: (json['outcome'] as String?) ?? 'pirate_victory',
      shipAttackPower: (json['ship_attack_power'] as num?)?.toInt() ?? 0,
      shipDefenseBefore:
          (json['ship_defense_before'] as num?)?.toInt() ?? 100,
      shipDefenseAfter: (json['ship_defense_after'] as num?)?.toInt() ?? 100,
      lootedCommodityCode: json['looted_commodity_code'] as String?,
      lootedQty: (json['looted_qty'] as num?)?.toInt() ?? 0,
      bountyCoins: (json['bounty_coins'] as num?)?.toInt() ?? 0,
      detail: (json['detail'] as String?) ?? '',
    );
  }
}

class CombatNotificationModel {
  final String type;
  final String severity;
  final String title;
  final String message;
  final int tickNo;
  final int shipId;

  const CombatNotificationModel({
    required this.type,
    required this.severity,
    required this.title,
    required this.message,
    required this.tickNo,
    required this.shipId,
  });

  factory CombatNotificationModel.fromJson(Map<String, dynamic> json) {
    return CombatNotificationModel(
      type: (json['type'] as String?) ?? 'NAVAL_COMBAT',
      severity: (json['severity'] as String?) ?? 'danger',
      title: (json['title'] as String?) ?? 'Serangan Bajak Laut!',
      message: (json['message'] as String?) ?? '',
      tickNo: (json['tick_no'] as num?)?.toInt() ?? 0,
      shipId: (json['ship_id'] as num?)?.toInt() ?? 1,
    );
  }
}

class DailyQuestItemModel {
  final int id;
  final int questId;
  final String code;
  final String title;
  final String description;
  final String type;
  final int progress;
  final int targetValue;
  final int rewardCoins;
  final int rewardXp;
  final bool isCompleted;
  final bool isClaimed;

  const DailyQuestItemModel({
    required this.id,
    required this.questId,
    required this.code,
    required this.title,
    required this.description,
    required this.type,
    required this.progress,
    required this.targetValue,
    required this.rewardCoins,
    required this.rewardXp,
    required this.isCompleted,
    required this.isClaimed,
  });

  factory DailyQuestItemModel.fromJson(Map<String, dynamic> json) {
    final prog = (json['progress'] as num?)?.toInt() ?? 0;
    final target = (json['target_value'] as num?)?.toInt() ?? 1;
    return DailyQuestItemModel(
      id: (json['id'] as num?)?.toInt() ?? 1,
      questId: (json['quest_id'] as num?)?.toInt() ?? 1,
      code: (json['code'] as String?) ?? 'first_trade',
      title: (json['title'] as String?) ?? 'Perdagangan Pertama',
      description: (json['description'] as String?) ?? '',
      type: (json['type'] as String?) ?? 'trade',
      progress: prog,
      targetValue: target,
      rewardCoins: (json['reward_coins'] as num?)?.toInt() ?? 100,
      rewardXp: (json['reward_xp'] as num?)?.toInt() ?? 100,
      isCompleted: (json['is_completed'] as bool?) ?? (prog >= target),
      isClaimed: (json['is_claimed'] as bool?) ?? false,
    );
  }

  DailyQuestItemModel copyWith({
    int? progress,
    bool? isCompleted,
    bool? isClaimed,
  }) {
    return DailyQuestItemModel(
      id: id,
      questId: questId,
      code: code,
      title: title,
      description: description,
      type: type,
      progress: progress ?? this.progress,
      targetValue: targetValue,
      rewardCoins: rewardCoins,
      rewardXp: rewardXp,
      isCompleted: isCompleted ?? this.isCompleted,
      isClaimed: isClaimed ?? this.isClaimed,
    );
  }
}

const List<DailyQuestItemModel> kDefaultDailyQuests = <DailyQuestItemModel>[
  DailyQuestItemModel(
    id: 1,
    questId: 1,
    code: 'first_trade',
    title: 'Perdagangan Pertama',
    description: 'Beli atau jual total 10 unit komoditas di pasar atau bursa.',
    type: 'trade',
    progress: 5,
    targetValue: 10,
    rewardCoins: 120,
    rewardXp: 150,
    isCompleted: false,
    isClaimed: false,
  ),
  DailyQuestItemModel(
    id: 2,
    questId: 2,
    code: 'pirate_hunter',
    title: 'Pemburu Bajak Laut',
    description: 'Menangkan 1 pertempuran laut melawan armada Bajak Laut.',
    type: 'combat_win',
    progress: 1,
    targetValue: 1,
    rewardCoins: 200,
    rewardXp: 250,
    isCompleted: true,
    isClaimed: false,
  ),
  DailyQuestItemModel(
    id: 3,
    questId: 3,
    code: 'first_code',
    title: 'Kode Pertama',
    description: 'Simpan 1 aturan otomatisasi Bahasa Aturan (DSL) pada kapalmu.',
    type: 'save_dsl',
    progress: 1,
    targetValue: 1,
    rewardCoins: 100,
    rewardXp: 120,
    isCompleted: true,
    isClaimed: false,
  ),
];

// ============================================================================
// 8. Model Sistem Aliansi Dagang (Guilds) & World Boss (Fase 8)
// ============================================================================

class GuildMemberModel {
  final int playerId;
  final String displayName;
  final String role;
  final int level;
  final int coins;
  final int netWorth;

  const GuildMemberModel({
    required this.playerId,
    required this.displayName,
    required this.role,
    required this.level,
    required this.coins,
    required this.netWorth,
  });

  factory GuildMemberModel.fromJson(Map<String, dynamic> json) {
    return GuildMemberModel(
      playerId: (json['player_id'] as num?)?.toInt() ?? 1,
      displayName: (json['display_name'] as String?) ?? 'Nahkoda',
      role: (json['role'] as String?) ?? 'member',
      level: (json['level'] as num?)?.toInt() ?? 1,
      coins: (json['coins'] as num?)?.toInt() ?? 1000,
      netWorth: (json['net_worth'] as num?)?.toInt() ?? 1350,
    );
  }
}

class GuildWorldBossModel {
  final bool isActive;
  final String name;
  final int hp;
  final int maxHp;
  final int portId;

  const GuildWorldBossModel({
    required this.isActive,
    required this.name,
    required this.hp,
    required this.maxHp,
    required this.portId,
  });

  factory GuildWorldBossModel.fromJson(Map<String, dynamic> json) {
    return GuildWorldBossModel(
      isActive: (json['is_active'] as bool?) ?? false,
      name: (json['name'] as String?) ?? 'Bajak Laut Armada Besar',
      hp: (json['hp'] as num?)?.toInt() ?? 500,
      maxHp: (json['max_hp'] as num?)?.toInt() ?? 500,
      portId: (json['port_id'] as num?)?.toInt() ?? 1,
    );
  }
}

class GuildSummaryModel {
  final int id;
  final String code;
  final String name;
  final String description;
  final String leaderName;
  final int treasuryCoins;
  final int memberCount;
  final bool bossActive;

  const GuildSummaryModel({
    required this.id,
    required this.code,
    required this.name,
    required this.description,
    required this.leaderName,
    required this.treasuryCoins,
    required this.memberCount,
    this.bossActive = false,
  });

  factory GuildSummaryModel.fromJson(Map<String, dynamic> json) {
    return GuildSummaryModel(
      id: (json['id'] as num?)?.toInt() ?? 1,
      code: (json['code'] as String?) ?? 'rempah_nusantara',
      name: (json['name'] as String?) ?? 'Aliansi Rempah Nusantara',
      description: (json['description'] as String?) ?? '',
      leaderName: (json['leader_name'] as String?) ?? 'Laksamana',
      treasuryCoins: (json['treasury_coins'] as num?)?.toInt() ?? 5000,
      memberCount: (json['member_count'] as num?)?.toInt() ?? 1,
      bossActive: (json['boss_active'] as bool?) ?? false,
    );
  }
}

class GuildDetailModel {
  final int id;
  final String code;
  final String name;
  final String description;
  final int leaderId;
  final String leaderName;
  final int treasuryCoins;
  final int totalGuildWealth;
  final GuildWorldBossModel worldBoss;
  final List<GuildMemberModel> members;

  const GuildDetailModel({
    required this.id,
    required this.code,
    required this.name,
    required this.description,
    required this.leaderId,
    required this.leaderName,
    required this.treasuryCoins,
    required this.totalGuildWealth,
    required this.worldBoss,
    required this.members,
  });

  factory GuildDetailModel.fromJson(Map<String, dynamic> json) {
    final rawMembers =
        (json['members'] as List<dynamic>?) ?? const <dynamic>[];
    final membersList = rawMembers
        .map((e) => GuildMemberModel.fromJson(e as Map<String, dynamic>))
        .toList();
    final treasury = (json['treasury_coins'] as num?)?.toInt() ?? 5000;
    final memberNetWorth =
        membersList.fold<int>(0, (acc, m) => acc + m.netWorth);
    final rawBoss = json['world_boss'] as Map<String, dynamic>?;
    return GuildDetailModel(
      id: (json['id'] as num?)?.toInt() ?? 1,
      code: (json['code'] as String?) ?? 'rempah_nusantara',
      name: (json['name'] as String?) ?? 'Aliansi Rempah Nusantara',
      description: (json['description'] as String?) ?? '',
      leaderId: (json['leader_id'] as num?)?.toInt() ?? 1,
      leaderName: (json['leader_name'] as String?) ?? 'Nahkoda_Satu',
      treasuryCoins: treasury,
      totalGuildWealth:
          (json['total_guild_wealth'] as num?)?.toInt() ??
              (treasury + memberNetWorth),
      worldBoss: rawBoss != null
          ? GuildWorldBossModel.fromJson(rawBoss)
          : GuildWorldBossModel(
              isActive: treasury > 10000,
              name: 'Bajak Laut Armada Besar',
              hp: treasury > 10000 ? 500 : 0,
              maxHp: 500,
              portId: 1,
            ),
      members: membersList.isNotEmpty
          ? membersList
          : const <GuildMemberModel>[
              GuildMemberModel(
                playerId: 1,
                displayName: 'Nahkoda_Satu',
                role: 'leader',
                level: 2,
                coins: 5000,
                netWorth: 8500,
              ),
            ],
    );
  }

  GuildDetailModel copyWith({
    int? treasuryCoins,
    int? totalGuildWealth,
    GuildWorldBossModel? worldBoss,
    List<GuildMemberModel>? members,
  }) {
    return GuildDetailModel(
      id: id,
      code: code,
      name: name,
      description: description,
      leaderId: leaderId,
      leaderName: leaderName,
      treasuryCoins: treasuryCoins ?? this.treasuryCoins,
      totalGuildWealth: totalGuildWealth ?? this.totalGuildWealth,
      worldBoss: worldBoss ?? this.worldBoss,
      members: members ?? this.members,
    );
  }
}

const List<GuildSummaryModel> kDefaultGuildDirectory = <GuildSummaryModel>[
  GuildSummaryModel(
    id: 1,
    code: 'armada_malaka',
    name: 'Aliansi Bahari Malaka',
    description: 'Persatuan saudagar selat strategis dan pengawal konvoi rempah.',
    leaderName: 'Laksamana_Hang',
    treasuryCoins: 12500,
    memberCount: 5,
    bossActive: true,
  ),
  GuildSummaryModel(
    id: 2,
    code: 'serikat_ternate',
    name: 'Serikat Cengkeh Ternate',
    description: 'Kongsi niaga penghasil cengkeh dan pala kawasan Maluku.',
    leaderName: 'Sultan_Babul',
    treasuryCoins: 7500,
    memberCount: 3,
    bossActive: false,
  ),
  GuildSummaryModel(
    id: 3,
    code: 'kongsi_batavia',
    name: 'Kongsi Niaga Nusantara',
    description: 'Aliansi pedagang lintas samudra dari Sunda Kelapa hingga Sakai.',
    leaderName: 'Saudagar_Jawa',
    treasuryCoins: 5000,
    memberCount: 2,
    bossActive: false,
  ),
];
