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
      if (find.textContaining('Kapal Perintis').evaluate().isEmpty) {
        await tester.scrollUntilVisible(
          find.textContaining('Kapal Perintis'),
          -200,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
      }
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
}
