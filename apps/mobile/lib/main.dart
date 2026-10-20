import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';

void main() {
  runApp(const JalurRempahApp());
}

// ============================================================================
// 1. Model Data Kontrak API (docs/08-API-CONTRACT.md — MVP & Phase 2)
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
  });

  factory ShipModel.fromJson(Map<String, dynamic> json) {
    final rawCargo = (json['cargo'] as List<dynamic>?) ?? const <dynamic>[];
    return ShipModel(
      id: (json['id'] as num?)?.toInt() ?? 1,
      name: (json['name'] as String?) ?? 'Kapal Perintis',
      capacity: (json['capacity'] as num?)?.toInt() ?? 35,
      status: (json['status'] as String?) ?? 'docked',
      portId: (json['port_id'] as num?)?.toInt(),
      destPort: (json['dest_port'] as num?)?.toInt(),
      arriveTick: (json['arrive_tick'] as num?)?.toInt(),
      etaTicks: (json['eta_ticks'] as num?)?.toInt() ?? 0,
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

  const LeaderboardItemModel({
    required this.rank,
    required this.displayName,
    required this.netWorth,
  });

  factory LeaderboardItemModel.fromJson(Map<String, dynamic> json) {
    return LeaderboardItemModel(
      rank: (json['rank'] as num?)?.toInt() ?? 0,
      displayName: (json['display_name'] as String?) ?? '',
      netWorth: (json['net_worth'] as num?)?.toInt() ?? 0,
    );
  }
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
}

class HttpJalurRempahApiClient implements JalurRempahApiClient {
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
    req.headers.set('x-client-version', '0.1.0');
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
        errObj?['message']?.toString() ?? 'Permintaan gagal (${resp.statusCode})',
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
      },
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
  Future<List<PortModel>> getPorts() async {
    final res = await _request('GET', '/v1/world');
    final raw = (res['ports'] as List<dynamic>?) ?? const <dynamic>[];
    return raw
        .map((e) => PortModel.fromJson(e as Map<String, dynamic>))
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
  Future<ShipModel> getPrimaryShip() async {
    final res = await _request('GET', '/v1/ships');
    final items = (res['items'] as List<dynamic>?) ?? const <dynamic>[];
    if (items.isEmpty) {
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
    final firstId = ((items.first as Map<String, dynamic>)['id'] as num).toInt();
    final detail = await _request('GET', '/v1/ships/$firstId');
    return ShipModel.fromJson(detail);
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
}

// ============================================================================
// 3. Komponen Grafik Harga 24 Jam (CustomPainter)
// ============================================================================

class PriceHistoryChart extends StatelessWidget {
  final List<PricePointModel> points;

  const PriceHistoryChart({super.key, required this.points});

  @override
  Widget build(BuildContext context) {
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
        painter: _PriceSparklinePainter(points: points),
      ),
    );
  }
}

class _PriceSparklinePainter extends CustomPainter {
  final List<PricePointModel> points;

  _PriceSparklinePainter({required this.points});

  @override
  void paint(Canvas canvas, Size size) {
    final bgPaint = Paint()
      ..color = const Color(0xFFF5EFE6)
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
      ..color = const Color(0xFF8B4513)
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
    return oldDelegate.points != points;
  }
}

// ============================================================================
// 4. Aplikasi Utama Jalur Rempah (5 Layar MVP + Ekstensi Phase 2)
// ============================================================================

class JalurRempahApp extends StatefulWidget {
  final JalurRempahApiClient? apiClient;

  const JalurRempahApp({super.key, this.apiClient});

  @override
  State<JalurRempahApp> createState() => _JalurRempahAppState();
}

class _JalurRempahAppState extends State<JalurRempahApp> {
  late final TokenVault _vault;
  late final JalurRempahApiClient _api;
  bool _authenticated = false;

  @override
  void initState() {
    super.initState();
    _vault = InMemorySecureTokenVault();
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
    return MaterialApp(
      title: 'Jalur Rempah',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF8B4513),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
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
  final _emailCtrl = TextEditingController(text: 'nahkoda@nusantara.id');
  final _passwordCtrl = TextEditingController(text: 'SandiKuat123!');
  final _nameCtrl = TextEditingController(text: 'Nahkoda_Nusantara');
  bool _isRegisterMode = false;
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Jalur Rempah — Masuk Armada'),
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
              onPressed: _busy ? null : _submit,
              child: Text(_isRegisterMode ? 'Daftar & Buat Kapal' : 'Masuk'),
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

  List<PortModel> _ports = const <PortModel>[];
  List<MarketItemModel> _marketItems = const <MarketItemModel>[];
  List<PricePointModel> _priceHistory = const <PricePointModel>[];
  ShipModel? _ship;
  int _fleetCount = 1;
  List<RuleTemplateModel> _templates = const <RuleTemplateModel>[];
  List<RuleValidationErrorModel> _validationErrors =
      const <RuleValidationErrorModel>[];
  SandboxResultModel? _sandboxResult;
  List<ActionLogItemModel> _logs = const <ActionLogItemModel>[];
  List<LeaderboardItemModel> _leaderboard = const <LeaderboardItemModel>[];

  int _ruleVersion = 0;
  final _ruleEditorCtrl = TextEditingController();
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
    super.dispose();
  }

  Future<void> _refreshAll() async {
    final ports = await widget.api.getPorts();
    final market = await widget.api.getMarket(_selectedPortCode);
    final history = await widget.api.getPriceHistory(
      _selectedPortCode,
      _selectedCommodity,
    );
    final ship = await widget.api.getPrimaryShip();
    final rules = await widget.api.getShipRules(ship.id);
    final templates = await widget.api.getRuleTemplates();
    final logs = await widget.api.getShipLogs(ship.id);
    final lb = await widget.api.getLeaderboard();

    if (!mounted) return;
    setState(() {
      _ports = ports;
      _marketItems = market;
      _priceHistory = history;
      _ship = ship;
      _ruleVersion = (rules['version'] as num?)?.toInt() ?? 0;
      if (_ruleEditorCtrl.text.isEmpty) {
        _ruleEditorCtrl.text = (rules['source'] as String?) ?? '';
      }
      _templates = templates;
      _logs = logs;
      _leaderboard = lb;
    });
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

  Widget _buildMarketTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          key: const Key('season_event_banner'),
          color: const Color(0xFFEFE6D5),
          child: const ListTile(
            leading: Icon(Icons.air),
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
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: _ports.map((p) {
            final selected = p.code == _selectedPortCode;
            return ChoiceChip(
              key: Key('port_chip_${p.code}'),
              label: Text('${p.name} (Kas: ${p.treasury})'),
              selected: selected,
              onSelected: (_) => _selectPort(p.code),
            );
          }).toList(),
        ),
        const SizedBox(height: 16),
        Text(
          'Harga Pasar di ${_selectedPortCode.toUpperCase()}',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        ..._marketItems.map(
          (m) => Card(
            child: ListTile(
              title: Text(m.commodity.toUpperCase()),
              subtitle: Text('Stok: ${m.stock} / Target: ${m.target}'),
              trailing: Text(
                '${m.price} koin',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              onTap: () async {
                final hist = await widget.api.getPriceHistory(
                  _selectedPortCode,
                  m.commodity,
                );
                if (!mounted) return;
                setState(() {
                  _selectedCommodity = m.commodity;
                  _priceHistory = hist;
                });
              },
            ),
          ),
        ),
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

  Widget _buildRuleEditorTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Editor Bahasa Aturan (v$_ruleVersion)',
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
                  final tpl = _templates.where((t) => t.id == tplId).firstOrNull;
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
        TextField(
          key: const Key('rule_editor_field'),
          controller: _ruleEditorCtrl,
          maxLines: 10,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
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
            color: const Color(0xFFFFF8E7),
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

  Widget _buildShipLogTab() {
    final s = _ship;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: ListTile(
            title: Text(s?.name ?? 'Kapal Perintis'),
            subtitle: Text(
              'Status: ${s?.status ?? 'docked'} | Kapasitas: ${s?.capacity ?? 35} | Armada: $_fleetCount/5 kapal | ETA: ${s?.etaTicks ?? 0} tick',
            ),
            trailing: OutlinedButton(
              key: const Key('buy_ship_button'),
              onPressed: _fleetCount >= 5
                  ? null
                  : () {
                      setState(() {
                        _fleetCount += 1;
                        _fleetNotice =
                            'Kapal Pinisi #$_fleetCount ditambahkan ke armada.';
                      });
                    },
              child: const Text('Beli Kapal (1.500)'),
            ),
          ),
        ),
        if (_fleetNotice != null) ...[
          const SizedBox(height: 8),
          Text(_fleetNotice!, key: const Key('fleet_notice_text')),
        ],
        const SizedBox(height: 12),
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

  Widget _buildLeaderboardTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
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

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      _buildMarketTab(),
      _buildRuleEditorTab(),
      _buildShipLogTab(),
      _buildLeaderboardTab(),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Jalur Rempah'),
        actions: [
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
        ],
      ),
    );
  }
}
