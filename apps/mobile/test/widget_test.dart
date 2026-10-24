import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jalur_rempah_mobile/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeJalurRempahApiClient extends JalurRempahApiClient {
  int savedVersion = 0;
  String savedSource = '';
  bool logoutCalled = false;
  String? logoutToken;

  @override
  Future<void> logout(String refreshToken) async {
    logoutCalled = true;
    logoutToken = refreshToken;
  }

  @override
  Future<Map<String, dynamic>> login(String email, String password) async {
    return {
      'access_token': 'fake-jwt-token',
      'refresh_token': 'fake-refresh-token',
      'expires_in': 900,
    };
  }

  @override
  Future<Map<String, dynamic>> register(
    String email,
    String password,
    String displayName,
  ) async {
    return {
      'access_token': 'fake-jwt-token',
      'refresh_token': 'fake-refresh-token',
      'expires_in': 900,
    };
  }

  @override
  Future<Map<String, dynamic>> getProfile() async {
    return {
      'id': 1,
      'display_name': 'Nahkoda_Satu',
      'coins': 1000,
      'net_worth': 1350,
      'title': 'Juragan',
      'level': 1,
      'xp_to_next_level': 3650,
      'rank': 1,
    };
  }

  @override
  Future<List<PortModel>> getPorts() async {
    return const [
      PortModel(id: 1, code: 'banda', name: 'Banda', treasury: 50000),
      PortModel(id: 6, code: 'batavia', name: 'Batavia', treasury: 49500),
    ];
  }

  @override
  Future<List<MarketItemModel>> getMarket(String portCode) async {
    return const [
      MarketItemModel(commodity: 'pala', stock: 400, target: 400, price: 70),
      MarketItemModel(commodity: 'cengkeh', stock: 380, target: 400, price: 93),
    ];
  }

  @override
  Future<List<PricePointModel>> getPriceHistory(
    String portCode,
    String commodity,
  ) async {
    return const [
      PricePointModel(tickNo: 1, price: 70, stock: 400),
      PricePointModel(tickNo: 2, price: 72, stock: 390),
      PricePointModel(tickNo: 3, price: 75, stock: 375),
    ];
  }

  @override
  Future<ShipModel> getPrimaryShip() async {
    return const ShipModel(
      id: 1,
      name: 'Kapal Perintis',
      capacity: 35,
      status: 'docked',
      portId: 1,
      destPort: null,
      arriveTick: null,
      etaTicks: 0,
      attackPower: 0,
      defensePower: 65,
      maxDefensePower: 100,
      cargo: [CargoItemModel(commodity: 'pala', qty: 5)],
    );
  }

  @override
  Future<Map<String, dynamic>> getShipRules(int shipId) async {
    return {'version': savedVersion, 'source': savedSource};
  }

  @override
  Future<List<RuleTemplateModel>> getRuleTemplates() async {
    return const [
      RuleTemplateModel(
        id: 'templat-1',
        title: 'Jalur Klasik Pala',
        description: 'Beli pala di Banda, jual di Batavia',
        source:
            'aturan beli_pala:\n  jika di(Banda) dan harga(pala) <= 85\n  maka beli(pala, maks)',
      ),
    ];
  }

  @override
  Future<List<RuleValidationErrorModel>> validateRules(String source) async {
    if (source.trim().isEmpty) {
      return const [
        RuleValidationErrorModel(
          line: 1,
          column: 1,
          code: 'SYNTAX_ERROR',
          message: 'Program Bahasa Aturan harus memiliki minimal 1 aturan.',
        ),
      ];
    }
    return const [];
  }

  @override
  Future<int> saveShipRules(
    int shipId,
    int baseVersion,
    String source,
  ) async {
    savedVersion = baseVersion + 1;
    savedSource = source;
    return savedVersion;
  }

  @override
  Future<SandboxResultModel> simulateRules(
    int shipId,
    String source,
    int ticks,
  ) async {
    return SandboxResultModel(
      ticks: ticks,
      finalCoinsDelta: 420,
      trades: 6,
      disclaimer: 'Simulasi perkiraan snapshot.',
    );
  }

  @override
  Future<List<ActionLogItemModel>> getShipLogs(int shipId) async {
    return const [
      ActionLogItemModel(
        id: 1,
        tickNo: 10,
        ruleName: 'beli_pala',
        action: 'beli(pala,12)',
        result: 'ok',
        detail: 'aturan beli_pala cocok: harga 70 <= 85',
      ),
    ];
  }

  @override
  Future<List<LeaderboardItemModel>> getLeaderboard() async {
    return const [
      LeaderboardItemModel(
        rank: 1,
        displayName: 'Nahkoda_Satu',
        netWorth: 1350,
        title: 'Juragan',
      ),
    ];
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets(
    'M5, Phase 2, Fase 4, Fase 5, & Fase 6 (v0.7) — Alur lengkap klien Flutter: Masuk -> Lonceng Notifikasi Bajak Laut -> Peta 8 Negara & Gembok -> Bursa P2P -> IDE Block Builder -> HP Kapal, Perbaikan, Pasang Meriam/Katana & Log Pertempuran -> Profil Level Progress Bar',
    (WidgetTester tester) async {
      final fakeApi = FakeJalurRempahApiClient();
      await tester.pumpWidget(JalurRempahApp(apiClient: fakeApi));

      // 1. Layar Masuk & Uji tombol "Masuk dengan Google" (Login & Register)
      expect(find.byKey(const Key('auth_submit_button')), findsOneWidget);
      expect(find.byKey(const Key('auth_google_login_button')), findsOneWidget);
      expect(find.text('Masuk dengan Google'), findsOneWidget);
      final googleCalls = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/google_sign_in'),
        (MethodCall call) async {
          googleCalls.add(call.method);
          return null; // init -> null, signIn -> null (dibatalkan pengguna)
        },
      );
      await tester.tap(find.byKey(const Key('auth_google_login_button')));
      await tester.pumpAndSettle();
      expect(googleCalls, contains('signIn'));
      expect(find.textContaining('belum dikonfigurasi'), findsNothing);

      await tester.tap(find.byKey(const Key('auth_submit_button')));
      await tester.pumpAndSettle();

      // 2. Uji Lonceng Notifikasi Pertempuran di AppBar Global (Badge Merah -> SnackBar Serangan Bajak Laut)
      expect(
        find.byKey(const Key('appbar_notification_bell_button')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('appbar_notification_badge')),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const Key('appbar_notification_bell_button')),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Bajak Laut menyerang kapal Anda! -35 HP, 4 Pala dirampas.'),
        findsOneWidget,
      );

      // 2b. Uji Pop-up Tutorial Onboarding (tutorial_step == 0) & tombol Mengerti
      expect(find.byKey(const Key('tutorial_onboarding_banner')), findsOneWidget);
      expect(
        find.text('Selamat datang Kapten! Ayo buka tab Pasar dan beli 10 Garam.'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('tutorial_advance_button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('tutorial_onboarding_banner')), findsNothing);

      // 3. Layar Pasar, Banner World Events, Peta 8 Negara, & Gembok Pelabuhan (Lisbon Lv.6)
      expect(find.byKey(const Key('world_event_alert_banner')), findsOneWidget);
      expect(find.byKey(const Key('season_event_banner')), findsOneWidget);
      expect(find.byKey(const Key('nusantara_map_canvas')), findsOneWidget);
      expect(find.text('Peta Pelabuhan Nusantara'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.byKey(const Key('port_chip_lisbon')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      // Uji ketuk pelabuhan Lisbon yang terkunci (Level 6) -> muncul dialog terkunci
      expect(find.byKey(const Key('port_chip_lisbon')), findsOneWidget);
      await tester.tap(find.byKey(const Key('port_chip_lisbon')));
      await tester.pumpAndSettle();
      expect(
        find.text('Pelabuhan Lisbon terkunci. Butuh Level 6 untuk membuka.'),
        findsWidgets,
      );
      await tester.tap(find.text('Mengerti'));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('PALA'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(find.text('PALA'), findsOneWidget);

      // Tutup dialog jika masih ada yang terbuka
      if (find.byType(AlertDialog).evaluate().isNotEmpty || find.byType(Dialog).evaluate().isNotEmpty) {
        if (find.text('Mengerti').evaluate().isNotEmpty) {
          await tester.tap(find.text('Mengerti').first);
        } else if (find.text('Tutup').evaluate().isNotEmpty) {
          await tester.tap(find.text('Tutup').first);
        }
        await tester.pumpAndSettle();
      }

      // 4. Pindah ke tab Bursa P2P
      ScaffoldMessenger.of(tester.element(find.byType(Scaffold).first)).clearSnackBars();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('nav_bursa')));
      await tester.pumpAndSettle();
      if (find.textContaining('Bursa P2P Nusantara').evaluate().isEmpty) {
        await tester.scrollUntilVisible(
          find.textContaining('Bursa P2P Nusantara'),
          -100,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
      }
      expect(
        find.textContaining('Bursa P2P Nusantara'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('p2p_create_order_button')), findsOneWidget);

      // 5. Pindah ke tab Editor Aturan & Block Builder
      await tester.tap(find.byKey(const Key('nav_rules')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('mode_block_button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('block_builder_panel')), findsOneWidget);
      await tester.tap(find.byKey(const Key('compile_block_button')));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('jika di(Batavia) maka beli(pala)'),
        findsWidgets,
      );

      await tester.enterText(
        find.byKey(const Key('rule_editor_field')),
        'aturan beli_pala: jika di(Banda) maka beli(pala, maks)',
      );
      await tester.scrollUntilVisible(
        find.byKey(const Key('save_rules_button')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('save_rules_button')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Aturan berhasil disimpan'), findsOneWidget);

      // Uji Sandbox 200 Tick
      await tester.scrollUntilVisible(
        find.byKey(const Key('simulate_rules_button')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('simulate_rules_button')));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const Key('rule_status_banner')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Delta 420 koin'), findsOneWidget);

      // 6. Pindah ke tab Kapal & Log + Uji HP Bar, Perbaiki Kapal (Repair), Pasang Senjata (Equip), & Log Pertempuran
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('nav_ship')));
      await tester.pumpAndSettle();
      if (find.byKey(const Key('fleet_total_counter_badge')).hitTestable().evaluate().isEmpty) {
        await tester.scrollUntilVisible(
          find.byKey(const Key('fleet_total_counter_badge')),
          -200,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
      }
      expect(find.text('Total Armada: 1/5 Kapal'), findsOneWidget);
      expect(find.byKey(const Key('fleet_ships_list_view')), findsOneWidget);
      expect(find.textContaining('Kapal Perintis'), findsOneWidget);
      expect(find.byKey(const Key('ship_hp_progress_bar')), findsOneWidget);
      expect(find.byKey(const Key('ship_attack_power_text')), findsOneWidget);

      // Uji Perbaiki Kapal (POST /v1/ships/repair)
      await tester.tap(find.byKey(const Key('repair_ship_button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('repair_confirm_dialog')), findsOneWidget);
      expect(find.textContaining('2 koin per HP'), findsOneWidget);
      await tester.tap(find.byKey(const Key('confirm_repair_button')));
      await tester.pumpAndSettle();
      expect(find.textContaining('100 / 100 HP'), findsOneWidget);

      // Uji Pasang Senjata Meriam (+35 ATK, POST /v1/ships/equip)
      await tester.tap(find.byKey(const Key('equip_weapon_button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('equip_weapon_sheet')), findsOneWidget);
      await tester.tap(find.byKey(const Key('equip_meriam_button')));
      await tester.pumpAndSettle();
      expect(find.text('Attack Power (ATK): 35'), findsOneWidget);

      await tester.tap(find.byKey(const Key('buy_ship_button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('fleet_notice_text')), findsOneWidget);

      // 7. Pindah ke tab Peringkat, Profil Gelar, Progress Bar Level, & Tema Dark Mode
      await tester.tap(find.byKey(const Key('nav_leaderboard')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('player_profile_card')), findsOneWidget);
      expect(
        find.byKey(const Key('profile_level_progress_bar')),
        findsOneWidget,
      );
      expect(
        find.text('Level 1 — 3650 koin lagi menuju Level 2'),
        findsOneWidget,
      );
      expect(find.textContaining('Gelar: Juragan'), findsWidgets);
      expect(find.text('Nahkoda_Satu'), findsWidgets);
      expect(find.byKey(const Key('daily_quests_section')), findsOneWidget);
      expect(find.byKey(const Key('quest_progress_bar_first_trade')), findsOneWidget);
      expect(find.byKey(const Key('claim_quest_button_pirate_hunter')), findsOneWidget);
      await Scrollable.ensureVisible(
        tester.element(find.byKey(const Key('claim_quest_button_pirate_hunter'))),
        alignment: 0.5,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('claim_quest_button_pirate_hunter')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('quest_feedback_banner')), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byKey(const Key('theme_settings_card')),
        200.0,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('theme_settings_card')), findsOneWidget);

      // 8. Pindah ke tab Aliansi (🛡️ Fase 8): Pencarian, Buat Aliansi Baru (5.000 Koin), Dashboard Guild, Donasi, & World Boss
      await tester.tap(find.byKey(const Key('nav_guild')));
      await tester.pumpAndSettle();
      if (find.byKey(const Key('create_guild_button')).evaluate().isEmpty) {
        await tester.scrollUntilVisible(
          find.byKey(const Key('create_guild_button')),
          -200.0,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
      }
      expect(find.byKey(const Key('guild_search_field')), findsOneWidget);
      expect(find.byKey(const Key('create_guild_button')), findsOneWidget);
      expect(find.text('Buat Aliansi Baru (5.000 Koin)'), findsOneWidget);

      // Buat Aliansi Baru (5.000 Koin) -> masuk ke Dashboard Guild
      await tester.tap(find.byKey(const Key('create_guild_button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('create_guild_dialog')), findsOneWidget);
      await tester.tap(find.byKey(const Key('confirm_create_guild_button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('guild_dashboard_card')), findsOneWidget);
      expect(find.byKey(const Key('guild_dashboard_name')), findsOneWidget);
      expect(find.byKey(const Key('guild_dashboard_treasury')), findsOneWidget);
      expect(find.byKey(const Key('donate_guild_button')), findsOneWidget);

      // Donasi 6.000 Koin ke Kas Guild -> Kas menjadi 11.000 Koin (> 10.000) -> World Boss "Bajak Laut Armada Besar" muncul!
      await tester.tap(find.byKey(const Key('donate_guild_button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('donate_guild_dialog')), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('donate_guild_amount_field')),
        '6000',
      );
      await tester.tap(find.byKey(const Key('confirm_donate_guild_button')));
      await tester.pumpAndSettle();

      expect(find.text('11000 Koin'), findsOneWidget);
      expect(find.byKey(const Key('guild_world_boss_card')), findsOneWidget);
      expect(find.byKey(const Key('attack_world_boss_button')), findsOneWidget);
    },
  );

  testWidgets(
    'Fitur Intelijen Harga (GET /v1/intel), Buku Mutasi Koin (GET /v1/me/ledger), dan Hapus Akun UU PDP (DELETE /v1/me)',
    (WidgetTester tester) async {
      final fakeApi = FakeJalurRempahApiClient();
      final vault = InMemorySecureTokenVault();
      await vault.saveTokens(
        accessToken: 'initial-access',
        refreshToken: 'initial-refresh',
      );
      await tester.pumpWidget(
        JalurRempahApp(
          apiClient: fakeApi,
          tokenVault: vault,
          showTitleScreen: false,
        ),
      );
      await tester.pumpAndSettle();

      // 1. Uji Intelijen Harga di Tab Pasar
      await tester.tap(find.byKey(const Key('tutorial_advance_button')));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('PALA'),
        100.0,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await Scrollable.ensureVisible(
        tester.element(find.text('PALA')),
        alignment: 0.5,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('PALA'));
      await tester.pumpAndSettle();
      expect(find.text('Lihat Intel Harga Pelabuhan Lain'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('market_intel_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('market_intel_button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('intel_bottom_sheet')), findsOneWidget);
      expect(find.text('Banda: 70 koin'), findsOneWidget);
      expect(find.text('Lisbon: 150 koin'), findsOneWidget);
      await tester.tap(find.byKey(const Key('close_intel_sheet_button')));
      await tester.pumpAndSettle();

      // 2. Uji Buku Mutasi Koin di Tab Profil
      await tester.tap(find.byKey(const Key('nav_leaderboard')));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const Key('open_ledger_button')),
        200.0,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(find.text('Buku Mutasi Koin'), findsOneWidget);
      await tester.tap(find.byKey(const Key('open_ledger_button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('ledger_screen')), findsOneWidget);
      expect(find.text('+120 Koin (Misi Harian)'), findsOneWidget);
      expect(find.text('-500 Koin (Beli Kapal)'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();

      // 3. Uji Hapus Akun (UU PDP) dengan konfirmasi ganda "HAPUS"
      await tester.scrollUntilVisible(
        find.byKey(const Key('delete_account_button')),
        200.0,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(find.text('Hapus Akun (UU PDP)'), findsOneWidget);
      await tester.tap(find.byKey(const Key('delete_account_button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('delete_account_dialog')), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('delete_account_confirm_field')),
        'HAPUS',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirm_delete_account_button')));
      await tester.pumpAndSettle();

      // Token dibersihkan & kembali ke layar Login
      expect(await vault.readAccessToken(), isNull);
      expect(find.byKey(const Key('auth_submit_button')), findsOneWidget);
    },
  );

  testWidgets(
    'Simulasi NPC Client-Side (WorldNewsMarquee & NpcSimulationEngine) dan Seluruh Armada Kapal (ListView.builder 3/5 Kapal & Aktifkan Kapal Utama)',
    (WidgetTester tester) async {
      final fakeApi = _MultiShipFakeApiClient();
      final vault = InMemorySecureTokenVault();
      await vault.saveTokens(
        accessToken: 'initial-access',
        refreshToken: 'initial-refresh',
      );
      await tester.pumpWidget(
        JalurRempahApp(
          apiClient: fakeApi,
          tokenVault: vault,
          showTitleScreen: false,
        ),
      );
      await tester.pumpAndSettle();

      // 1. Verifikasi Ticker Berita Dunia (WorldNewsMarquee) di Tab Pasar & Posisi NPC di Peta
      expect(find.byKey(const Key('world_news_marquee')), findsOneWidget);
      expect(find.byKey(const Key('world_news_marquee_text')), findsOneWidget);
      final mapWidget = tester.widget<NusantaraMapWidget>(
        find.byType(NusantaraMapWidget),
      );
      expect(mapWidget.npcPositions.length, equals(20));
      expect(mapWidget.ships.length, equals(3));
      expect(
        mapWidget.ships.where((s) => s.isPrimary).single.id,
        equals(1),
      );

      // 2. Pindah ke Tab Kapal dan verifikasi seluruh 3 kapal dirender oleh ListView.builder
      await tester.tap(find.byKey(const Key('nav_ship')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('fleet_total_counter_badge')), findsOneWidget);
      expect(find.text('Total Armada: 3/5 Kapal'), findsOneWidget);
      expect(find.byKey(const Key('fleet_ships_list_view')), findsOneWidget);
      expect(find.textContaining('Kapal Perintis'), findsOneWidget);
      expect(find.textContaining('Pinisi Nusantara'), findsOneWidget);
      expect(find.textContaining('Jung Majapahit'), findsOneWidget);

      // 3. Klik tombol "Aktifkan sebagai Kapal Utama" pada kapal ke-2 (id: 2)
      final activateShip2Btn = find.byKey(
        const Key('activate_primary_ship_button_2'),
      );
      await tester.ensureVisible(activateShip2Btn);
      await tester.pumpAndSettle();
      await tester.tap(activateShip2Btn);
      await tester.pumpAndSettle();
      expect(
        find.text('Pinisi Nusantara diaktifkan sebagai Kapal Utama.'),
        findsOneWidget,
      );

      // 4. Kembali ke Tab Pasar dan pastikan kapal utama di Peta berubah menjadi kapal id: 2
      await tester.tap(find.byKey(const Key('nav_market')));
      await tester.pumpAndSettle();
      final updatedMapWidget = tester.widget<NusantaraMapWidget>(
        find.byType(NusantaraMapWidget),
      );
      expect(
        updatedMapWidget.ships.where((s) => s.isPrimary).single.id,
        equals(2),
      );
    },
  );

  testWidgets(
    'Batch A — Konfirmasi Password Register, Daily Reward Dialog, Kontrak NPC di Bursa, Pencapaian 2-Kolom, & Ganti Kata Sandi',
    (WidgetTester tester) async {
      final batchApi = _BatchAFakeApiClient();
      final vault = InMemorySecureTokenVault();
      await tester.pumpWidget(
        JalurRempahApp(
          apiClient: batchApi,
          tokenVault: vault,
          showTitleScreen: false,
        ),
      );

      // 1. Uji Konfirmasi Password di Register
      await tester.tap(find.byKey(const Key('auth_toggle_mode_button')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('auth_confirm_password_field')),
        findsOneWidget,
      );
      await tester.enterText(
        find.byKey(const Key('auth_email_field')),
        'kapten@nusantara.id',
      );
      await tester.enterText(
        find.byKey(const Key('auth_password_field')),
        'rahasia123',
      );
      await tester.enterText(
        find.byKey(const Key('auth_confirm_password_field')),
        'berbeda999',
      );
      await tester.pumpAndSettle();
      expect(find.text('Kata sandi tidak cocok'), findsWidgets);

      // Samakan password & daftar
      await tester.enterText(
        find.byKey(const Key('auth_confirm_password_field')),
        'rahasia123',
      );
      await tester.enterText(
        find.byKey(const Key('auth_display_name_field')),
        'Kapten_Rempah',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('auth_submit_button')));
      await tester.pumpAndSettle();

      // 2. Uji Pop-up Daily Reward (7 kotak hari + Klaim Hadiah -> +2000 koin)
      expect(find.byKey(const Key('daily_reward_dialog')), findsOneWidget);
      for (var d = 1; d <= 7; d++) {
        expect(
          find.byKey(Key('daily_reward_day_box_$d')),
          findsOneWidget,
        );
      }
      await tester.tap(find.byKey(const Key('claim_daily_reward_button')));
      await tester.pumpAndSettle();
      expect(find.text('+2000 koin'), findsWidgets);

      // 3. Uji Kontrak Dagang NPC di Tab Bursa
      ScaffoldMessenger.of(
        tester.element(find.byType(Scaffold).first),
      ).clearSnackBars();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('nav_bursa')));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const Key('npc_trade_contracts_section')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(find.text('Kontrak Dagang Tersedia'), findsOneWidget);
      final fulfillBtn = find.byKey(const Key('fulfill_contract_button_101'));
      await tester.ensureVisible(fulfillBtn);
      await tester.pumpAndSettle();
      await tester.tap(fulfillBtn);
      await tester.pumpAndSettle();
      expect(batchApi.fulfilledContractId, equals(101));

      // 4. Uji Halaman Pencapaian & Ganti Kata Sandi di Tab Profil
      ScaffoldMessenger.of(
        tester.element(find.byType(Scaffold).first),
      ).clearSnackBars();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('nav_leaderboard')));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const Key('open_achievements_button')),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('open_achievements_button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('achievements_screen')), findsOneWidget);
      expect(
        find.byKey(const Key('achievement_badge_pelaut_pertama')),
        findsOneWidget,
      );
      await tester.pageBack();
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.byKey(const Key('change_password_button')),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('change_password_button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('change_password_dialog')), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('change_pw_old_field')),
        'rahasia123',
      );
      await tester.enterText(
        find.byKey(const Key('change_pw_new_field')),
        'sandibaru123',
      );
      await tester.enterText(
        find.byKey(const Key('change_pw_confirm_field')),
        'sandibaru123',
      );
      await tester.tap(
        find.byKey(const Key('confirm_change_password_button')),
      );
      await tester.pumpAndSettle();
      expect(batchApi.passwordChanged, isTrue);
      // Setelah ganti password sukses, dipaksa kembali ke layar login
      expect(find.byKey(const Key('auth_submit_button')), findsOneWidget);
    },
  );
}

class _BatchAFakeApiClient extends FakeJalurRempahApiClient {
  int? fulfilledContractId;
  bool passwordChanged = false;

  @override
  Future<DailyRewardStatusModel> getDailyRewardStatus() async {
    return const DailyRewardStatusModel(
      claimedToday: false,
      currentStreak: 6,
      nextStreak: 7,
      nextRewardCoins: 2000,
    );
  }

  @override
  Future<Map<String, dynamic>> fulfillTradeContract(
    int contractId, {
    required int shipId,
  }) async {
    fulfilledContractId = contractId;
    return <String, dynamic>{
      'id': contractId,
      'status': 'fulfilled',
      'reward_coins': 2000,
    };
  }

  @override
  Future<void> changePassword({
    required String oldPassword,
    required String newPassword,
  }) async {
    passwordChanged = true;
  }
}

class _MultiShipFakeApiClient extends FakeJalurRempahApiClient {
  @override
  Future<List<ShipModel>> getShips() async {
    return const <ShipModel>[
      ShipModel(
        id: 1,
        name: 'Kapal Perintis',
        capacity: 50,
        status: 'docked',
        portId: 1,
        destPort: null,
        arriveTick: null,
        etaTicks: 0,
        tier: 1,
        shipType: 'perahu_layar',
        shipClass: 'Perahu',
        attackPower: 10,
        defensePower: 90,
        maxDefensePower: 100,
        cargo: <CargoItemModel>[CargoItemModel(commodity: 'pala', qty: 10)],
      ),
      ShipModel(
        id: 2,
        name: 'Pinisi Nusantara',
        capacity: 300,
        status: 'sailing',
        portId: 2,
        destPort: 6,
        arriveTick: 18,
        etaTicks: 4,
        tier: 3,
        shipType: 'pinisi_nusantara',
        shipClass: 'Pinisi',
        attackPower: 35,
        defensePower: 220,
        maxDefensePower: 250,
        cargo: <CargoItemModel>[CargoItemModel(commodity: 'cengkeh', qty: 40)],
      ),
      ShipModel(
        id: 3,
        name: 'Jung Majapahit',
        capacity: 1500,
        status: 'docked',
        portId: 6,
        destPort: null,
        arriveTick: null,
        etaTicks: 0,
        tier: 5,
        shipType: 'jung_majapahit',
        shipClass: 'Jung',
        attackPower: 70,
        defensePower: 600,
        maxDefensePower: 600,
        cargo: <CargoItemModel>[],
      ),
    ];
  }
}
