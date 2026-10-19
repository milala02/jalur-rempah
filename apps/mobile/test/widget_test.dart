import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jalur_rempah_mobile/main.dart';

class FakeJalurRempahApiClient implements JalurRempahApiClient {
  int savedVersion = 0;
  String savedSource = '';

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
      ),
    ];
  }
}

void main() {
  testWidgets(
    'M5 & Phase 2 — Alur kritis klien Flutter: Masuk -> Pasar & Musim -> Editor Aturan & Sandbox -> Armada Multi-Kapal & Log -> Peringkat & Serikat Dagang',
    (WidgetTester tester) async {
      final fakeApi = FakeJalurRempahApiClient();
      await tester.pumpWidget(JalurRempahApp(apiClient: fakeApi));

      // 1. Layar Masuk
      expect(find.byKey(const Key('auth_submit_button')), findsOneWidget);
      await tester.tap(find.byKey(const Key('auth_submit_button')));
      await tester.pumpAndSettle();

      // 2. Layar Pasar, Musim, & Pelabuhan
      expect(find.byKey(const Key('season_event_banner')), findsOneWidget);
      expect(find.text('Peta Pelabuhan Nusantara'), findsOneWidget);
      expect(find.text('PALA'), findsOneWidget);

      // 3. Pindah ke tab Editor Aturan
      await tester.tap(find.byKey(const Key('nav_rules')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('rule_editor_field')),
        'aturan beli_pala: jika di(Banda) maka beli(pala, maks)',
      );
      await tester.tap(find.byKey(const Key('save_rules_button')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Aturan berhasil disimpan'), findsOneWidget);

      // Uji Sandbox 200 Tick
      await tester.tap(find.byKey(const Key('simulate_rules_button')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Delta 420 koin'), findsOneWidget);

      // 4. Pindah ke tab Kapal & Log + Uji Multi-Kapal
      await tester.tap(find.byKey(const Key('nav_ship')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Kapal Perintis'), findsOneWidget);
      expect(find.textContaining('beli(pala,12)'), findsOneWidget);

      await tester.tap(find.byKey(const Key('buy_ship_button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('fleet_notice_text')), findsOneWidget);

      // 5. Pindah ke tab Peringkat & Serikat Dagang
      await tester.tap(find.byKey(const Key('nav_leaderboard')));
      await tester.pumpAndSettle();
      expect(find.text('Nahkoda_Satu'), findsOneWidget);
      expect(find.byKey(const Key('guilds_contracts_card')), findsOneWidget);
    },
  );
}
