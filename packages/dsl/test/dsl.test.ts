import { describe, it, expect } from 'vitest';
import fc from 'fast-check';
import { WORLD_CONFIG } from '@jalur-rempah/shared';
import {
  stepWorld,
  WorldState,
  WorldPlayerState,
  WorldPortState,
  WorldShipState,
  computeCanonicalStateHash,
} from '../../econ/src/index.js';
import {
  tokenizeDsl,
  parseDsl,
  validateDsl,
  compileDsl,
  evaluateDslProgram,
  createDslShipRuleDecider,
  RULE_TEMPLATES,
  DSL_DEFAULT_LIMITS,
} from '../src/index.js';

function createTestWorld(overrides?: {
  coins?: bigint;
  status?: 'docked' | 'sailing' | 'grounded';
  portId?: number;
  cargoPala?: bigint;
  cargoCengkeh?: bigint;
  shipCapacity?: number;
  bandaPalaStock?: bigint;
  bandaPalaPrice?: bigint;
  bandaTreasury?: bigint;
}): WorldState {
  const coins = overrides?.coins ?? 1000n;
  const status = overrides?.status ?? 'docked';
  const portId = overrides?.portId ?? 1; // 1 = Banda
  const cargoPala = overrides?.cargoPala ?? 0n;
  const cargoCengkeh = overrides?.cargoCengkeh ?? 0n;
  const shipCapacity = overrides?.shipCapacity ?? 35;

  const players = new Map<bigint, WorldPlayerState>([
    [
      1n,
      {
        id: 1n,
        coins,
        initialCoins: coins,
        ledgerSum: coins,
        lastRescueTick: null,
        rescueCount: 0,
      },
    ],
  ]);

  const ports = new Map<number, WorldPortState>([
    [
      1,
      {
        id: 1,
        code: 'banda',
        name: 'Banda',
        treasury: overrides?.bandaTreasury ?? 50000n,
        initialTreasury: overrides?.bandaTreasury ?? 50000n,
      },
    ],
    [
      2,
      {
        id: 2,
        code: 'ternate',
        name: 'Ternate',
        treasury: 50000n,
        initialTreasury: 50000n,
      },
    ],
    [
      3,
      {
        id: 3,
        code: 'surabaya',
        name: 'Surabaya',
        treasury: 50000n,
        initialTreasury: 50000n,
      },
    ],
    [
      4,
      {
        id: 4,
        code: 'malaka',
        name: 'Malaka',
        treasury: 50000n,
        initialTreasury: 50000n,
      },
    ],
    [
      5,
      {
        id: 5,
        code: 'makassar',
        name: 'Makassar',
        treasury: 50000n,
        initialTreasury: 50000n,
      },
    ],
    [
      6,
      {
        id: 6,
        code: 'batavia',
        name: 'Batavia',
        treasury: 50000n,
        initialTreasury: 50000n,
      },
    ],
  ]);

  const markets = new Map();
  const basePrices: Record<number, bigint> = {
    1: 70n,
    2: 90n,
    3: 20n,
    4: 45n,
  };
  for (let p = 1; p <= 6; p++) {
    for (let c = 1; c <= 4; c++) {
      const isBandaPala = p === 1 && c === 1;
      markets.set(`${p}:${c}`, {
        port_id: p,
        commodity_id: c,
        stock: isBandaPala ? (overrides?.bandaPalaStock ?? 400n) : 400n,
        target: 400n,
        production: 0n,
        consumption: 0n,
        capacity: 1600n,
        price: isBandaPala
          ? (overrides?.bandaPalaPrice ?? 70n)
          : (basePrices[c] ?? 50n),
      });
    }
  }

  const ships = new Map<bigint, WorldShipState>([
    [
      1n,
      {
        id: 1n,
        playerId: 1n,
        capacity: shipCapacity,
        status,
        portId,
        destPort: status === 'sailing' ? 5 : null,
        arriveTick: status === 'sailing' ? 10 : null,
        cargo: new Map([
          [1, cargoPala],
          [2, cargoCengkeh],
          [3, 0n],
          [4, 0n],
        ]),
      },
    ],
  ]);

  const state: WorldState = {
    tickNo: 0,
    players,
    ports,
    markets,
    ships,
    cumulativeUpkeepSink: 0n,
    cumulativeSource: 0n,
    stateHash: '',
  };
  state.stateHash = computeCanonicalStateHash(state);
  return state;
}

describe('M3 — packages/dsl: Lexer, Parser, Validator Statis, Evaluator, & Integrasi stepWorld (docs/05 v0.2)', () => {
  it('1. Golden test: 32 program Bahasa Aturan valid menghasilkan AST terkompilasi dengan struktur deterministik', () => {
    const goldenPrograms: readonly string[] = [
      // 1-4: Contoh utama docs/05
      `aturan beli_pala: jika di(Banda) dan harga(pala) < 40 dan muatan_bebas() > 0 maka beli(pala, maks)`,
      `aturan jual_pala: jika di(Batavia) dan stok_kapal(pala) > 0 dan harga(pala) > 70 maka jual(pala, semua)`,
      `aturan ke_batavia: jika stok_kapal(pala) > 0 maka berlayar(Batavia)`,
      `aturan ke_banda: jika stok_kapal(pala) == 0 maka berlayar(Banda)`,
      // 5-10: Semua fungsi baca & perbandingan
      `aturan cek_koin: jika koin() >= 500 maka beli(cengkeh, 5)`,
      `aturan cek_kapasitas: jika kapasitas() == 35 dan muatan_bebas() <= 10 maka tunggu()`,
      `aturan cek_stok_pasar: jika stok_pelabuhan(garam) > 200 maka beli(garam, 10)`,
      `aturan cek_harga_jarak: jika harga_di(Batavia, pala) - harga(pala) > jarak(Batavia) * 3 maka beli(pala, maks)`,
      `aturan cek_tick_genap: jika tick() % 2 == 0 maka tunggu()`,
      `aturan cek_tick_ganjil: jika tick() % 2 != 0 maka berlayar(Makassar)`,
      // 11-16: Operator logika & unari
      `aturan logika_bukan: jika bukan di(Malaka) dan benar maka berlayar(Malaka)`,
      `aturan logika_atau: jika di(Banda) atau di(Ternate) maka tunggu()`,
      `aturan logika_campur: jika (di(Banda) atau di(Ternate)) dan muatan_bebas() > 0 maka beli(pala, 3)`,
      `aturan unari_negatif: jika -10 < 0 dan koin() + -50 > 100 maka tunggu()`,
      `aturan boolean_literal: jika benar dan bukan salah maka tunggu()`,
      `aturan perbandingan_komoditas: jika pala == pala dan cengkeh != garam maka tunggu()`,
      // 17-22: Semua pelabuhan & komoditas (case-insensitive)
      `aturan semua_pelabuhan_1: jika di(BANDA) atau di(ternate) atau di(Makassar) maka berlayar(Surabaya)`,
      `aturan semua_pelabuhan_2: jika di(SURABAYA) atau di(batavia) atau di(Malaka) maka berlayar(Banda)`,
      `aturan komoditas_cengkeh: jika harga(CENGKEH) <= 95 maka beli(cengkeh, maks)`,
      `aturan komoditas_garam: jika stok_kapal(GARAM) >= 1 maka jual(garam, semua)`,
      `aturan komoditas_kain: jika harga_di(Malaka, KAIN) < harga(kain) maka jual(kain, 5)`,
      `aturan ekspresi_hitung: jika (harga(pala) * 2 + 10) / 3 >= 40 maka beli(pala, 1 + 2 * 3)`,
      // 23-28: Komentar & multi-aturan
      `# Komentar baris pertama\naturan dengan_komentar:\n  # Komentar di tengah\n  jika di(Banda) # komentar akhir baris\n  maka tunggu()`,
      `aturan r1: jika di(Banda) maka beli(pala, maks)\naturan r2: jika di(Banda) maka berlayar(Batavia)`,
      `aturan r_jual_eksplisit: jika stok_kapal(pala) >= 5 maka jual(pala, 5)`,
      `aturan r_beli_eksplisit: jika koin() > 300 maka beli(garam, 10)`,
      `aturan r_sama_pelabuhan: jika Banda != Batavia maka tunggu()`,
      `aturan r_kurung_dalam: jika (((koin() > 10))) maka tunggu()`,
      // 29-32: Templat aturan siap pakai dari RULE_TEMPLATES
      ...RULE_TEMPLATES.map((t) => t.source),
    ];

    expect(goldenPrograms.length).toBeGreaterThanOrEqual(32);

    for (const src of goldenPrograms) {
      const compiled = compileDsl(src);
      expect(compiled.valid).toBe(true);
      expect(compiled.errors).toEqual([]);
      expect(compiled.ast).toBeDefined();
      expect(compiled.ast?.ast_version).toBe(1);
      expect((compiled.ast?.rules.length ?? 0) >= 1).toBe(true);
    }
  });

  it('2. Kode galat validasi statis: setiap dari 11 kode galat statis di docs/05 terdeteksi dengan baris/kolom tepat & saran nama', () => {
    // 1. SYNTAX_ERROR (baris 2, kolom 3: kurang kata kunci "maka")
    const errSyntax = validateDsl(
      `aturan uji_sintaks:\n  jika di(Banda) beli(pala, maks)`,
    );
    expect(errSyntax.valid).toBe(false);
    expect(errSyntax.errors[0]?.code).toBe('SYNTAX_ERROR');
    expect(errSyntax.errors[0]?.line).toBe(2);
    expect(errSyntax.errors[0]?.baris).toBe(2);
    expect((errSyntax.errors[0]?.column ?? 0) >= 18).toBe(true);

    // 2. UNKNOWN_IDENT + saran "Maksud Anda 'harga'?"
    const errUnknown = validateDsl(
      `aturan uji_ident:\n  jika hargaa(pala) < 50 maka tunggu()`,
    );
    expect(errUnknown.valid).toBe(false);
    expect(errUnknown.errors[0]?.code).toBe('UNKNOWN_IDENT');
    expect(errUnknown.errors[0]?.line).toBe(2);
    expect(errUnknown.errors[0]?.column).toBe(8);
    expect(errUnknown.errors[0]?.message.includes('harga')).toBe(true);

    // 3. ARITY_MISMATCH
    const errArity = validateDsl(
      `aturan uji_aritas: jika harga(pala, cengkeh) < 50 maka tunggu()`,
    );
    expect(errArity.valid).toBe(false);
    expect(errArity.errors[0]?.code).toBe('ARITY_MISMATCH');

    // 4. TYPE_MISMATCH (kondisi bukan bool / argumen salah tipe)
    const errType1 = validateDsl(`aturan uji_tipe1: jika koin() maka tunggu()`);
    expect(errType1.valid).toBe(false);
    expect(errType1.errors[0]?.code).toBe('TYPE_MISMATCH');

    const errType2 = validateDsl(
      `aturan uji_tipe2: jika di(pala) maka berlayar(Banda)`,
    );
    expect(errType2.valid).toBe(false);
    expect(errType2.errors[0]?.code).toBe('TYPE_MISMATCH');

    // 5. DUPLICATE_RULE (case-insensitive)
    const errDup = validateDsl(
      `aturan rute_utama: jika benar maka tunggu()\naturan RUTE_UTAMA: jika benar maka tunggu()`,
    );
    expect(errDup.valid).toBe(false);
    expect(errDup.errors.some((e) => e.code === 'DUPLICATE_RULE')).toBe(true);

    // 6. RESERVED_NAME (nama aturan memakai kata kunci / fungsi / konstanta dunia)
    const errReserved1 = validateDsl(`aturan beli: jika benar maka tunggu()`);
    expect(errReserved1.valid).toBe(false);
    expect(errReserved1.errors[0]?.code).toBe('RESERVED_NAME');

    const errReserved2 = validateDsl(`aturan banda: jika benar maka tunggu()`);
    expect(errReserved2.valid).toBe(false);
    expect(errReserved2.errors[0]?.code).toBe('RESERVED_NAME');

    // 7. BAD_KEYWORD_ARG (maks pada jual, semua pada beli, atau maks di dalam ekspresi)
    const errBadKw1 = validateDsl(
      `aturan salah_kw1: jika benar maka beli(pala, semua)`,
    );
    expect(errBadKw1.valid).toBe(false);
    expect(errBadKw1.errors[0]?.code).toBe('BAD_KEYWORD_ARG');

    const errBadKw2 = validateDsl(
      `aturan salah_kw2: jika benar maka jual(pala, maks)`,
    );
    expect(errBadKw2.valid).toBe(false);
    expect(errBadKw2.errors[0]?.code).toBe('BAD_KEYWORD_ARG');

    // 8. LIMIT_RULES (> 16 aturan)
    const seventeenRules = Array.from(
      { length: 17 },
      (_, i) => `aturan r_${i + 1}: jika benar maka tunggu()`,
    ).join('\n');
    const errLimitRules = validateDsl(seventeenRules);
    expect(errLimitRules.valid).toBe(false);
    expect(errLimitRules.errors.some((e) => e.code === 'LIMIT_RULES')).toBe(
      true,
    );

    // 9. LIMIT_NODES (> 64 node AST dalam 1 aturan)
    const manyTerms = Array.from({ length: 35 }, () => '1').join(' + ');
    const errLimitNodes = validateDsl(
      `aturan terlalu_banyak_node: jika ${manyTerms} > 0 maka tunggu()`,
    );
    expect(errLimitNodes.valid).toBe(false);
    expect(errLimitNodes.errors.some((e) => e.code === 'LIMIT_NODES')).toBe(
      true,
    );

    // 10. LIMIT_LENGTH (> 4.000 karakter)
    const longComment = '# ' + 'x'.repeat(4010) + '\naturan a: jika benar maka tunggu()';
    const errLimitLen = validateDsl(longComment);
    expect(errLimitLen.valid).toBe(false);
    expect(errLimitLen.errors[0]?.code).toBe('LIMIT_LENGTH');

    // 11. LIMIT_DEPTH (> 12 kedalaman ekspresi)
    const deepExpr = '('.repeat(14) + 'benar' + ')'.repeat(14);
    const errLimitDepth = validateDsl(
      `aturan terlalu_dalam: jika ${deepExpr} maka tunggu()`,
    );
    expect(errLimitDepth.valid).toBe(false);
    expect(errLimitDepth.errors.some((e) => e.code === 'LIMIT_DEPTH')).toBe(
      true,
    );
  });

  it('3. Evaluator: tabel kebenaran, prioritas operator, dan ke-3 kode galat runtime (DIV_ZERO, OVERFLOW, BUDGET_EXCEEDED)', () => {
    const world = createTestWorld({ coins: 1200n, portId: 1, cargoPala: 5n });

    // Prioritas operator: 2 + 3 * 4 == 14 (bukan 20), dan `dan` mengikat lebih kuat dari `atau`
    const progPrecedence = compileDsl(`
      aturan salah_hitung:
        jika 2 + 3 * 4 == 20 dan salah atau salah
        maka berlayar(Ternate)
      aturan benar_hitung:
        jika salah atau 2 + 3 * 4 == 14 dan -7 / 2 == -3 dan 7 % 4 == 3
        maka beli(pala, 2)
    `);
    expect(progPrecedence.valid).toBe(true);
    const evalPrec = Array.from(
      evaluateDslProgram(progPrecedence.ast!, {
        ship: world.ships.get(1n)!,
        player: world.players.get(1n)!,
        state: world,
      }),
    );
    expect(evalPrec.length).toBe(1);
    expect(evalPrec[0]?.ruleName).toBe('benar_hitung');
    expect(evalPrec[0]?.type).toBe('buy');

    // Galat runtime 1: DIV_ZERO -> aturan dilewati ('skip'), evaluasi lanjut ke aturan di bawahnya
    const progDivZero = compileDsl(`
      aturan bagi_nol:
        jika 10 / (koin() - 1200) > 0
        maka berlayar(Ternate)
      aturan cadangan_aman:
        jika di(Banda)
        maka tunggu()
    `);
    expect(progDivZero.valid).toBe(true);
    const evDivZero = Array.from(
      evaluateDslProgram(progDivZero.ast!, {
        ship: world.ships.get(1n)!,
        player: world.players.get(1n)!,
        state: world,
      }),
    );
    expect(evDivZero.length).toBe(2);
    expect(evDivZero[0]?.type).toBe('skip');
    if (evDivZero[0]?.type === 'skip') {
      expect(evDivZero[0].skipCode).toBe('DIV_ZERO');
    }
    expect(evDivZero[1]?.ruleName).toBe('cadangan_aman');
    expect(evDivZero[1]?.type).toBe('wait');

    // Galat runtime 2: OVERFLOW (> Number.MAX_SAFE_INTEGER) -> aturan dilewati, lanjut ke aturan berikutnya
    const progOverflow = compileDsl(`
      aturan meluap:
        jika 9007199254740991 + 10 > 0
        maka berlayar(Ternate)
      aturan aman_setelah_overflow:
        jika benar
        maka tunggu()
    `);
    expect(progOverflow.valid).toBe(true);
    const evOverflow = Array.from(
      evaluateDslProgram(progOverflow.ast!, {
        ship: world.ships.get(1n)!,
        player: world.players.get(1n)!,
        state: world,
      }),
    );
    expect(evOverflow[0]?.type).toBe('skip');
    if (evOverflow[0]?.type === 'skip') {
      expect(evOverflow[0].skipCode).toBe('OVERFLOW');
    }
    expect(evOverflow[1]?.ruleName).toBe('aman_setelah_overflow');

    // Galat runtime 3: BUDGET_EXCEEDED -> anggaran evaluasi habis di tengah evaluasi
    const heavyCond = Array.from({ length: 8 }, () => 'koin() + 1 > 0').join(
      ' dan ',
    );
    const sixteenHeavyRules = Array.from(
      { length: 16 },
      (_, i) => `aturan berat_${i + 1}: jika ${heavyCond} dan salah maka tunggu()`,
    ).join('\n');
    const progBudget = compileDsl(sixteenHeavyRules);
    expect(progBudget.valid).toBe(true);
    const evBudget = Array.from(
      evaluateDslProgram(
        progBudget.ast!,
        {
          ship: world.ships.get(1n)!,
          player: world.players.get(1n)!,
          state: world,
        },
        { ...DSL_DEFAULT_LIMITS, maxEvalBudget: 50 },
      ),
    );
    expect(
      evBudget.some((a) => a.type === 'skip' && a.skipCode === 'BUDGET_EXCEEDED'),
    ).toBe(true);
  });

  it('4. Jatuh ke aturan berikutnya (fallthrough) & seluruh 11 kode kegagalan aksi pada stepWorld', () => {
    const worldFallthrough = createTestWorld({
      coins: 150n,
      portId: 1,
      bandaPalaStock: 0n,
      shipCapacity: 10,
      cargoCengkeh: 8n,
    });

    const progFallthrough = compileDsl(`
      aturan coba_beli_stok_habis:
        jika di(Banda) maka beli(pala, 1)
      aturan coba_beli_kemahalan:
        jika di(Banda) maka beli(cengkeh, 2)
      aturan coba_beli_kargo_penuh:
        jika di(Banda) maka beli(garam, 5)
      aturan coba_layar_pelabuhan_sama:
        jika di(Banda) maka berlayar(Banda)
      aturan layar_ke_makassar:
        jika di(Banda) maka berlayar(Makassar)
    `);
    expect(progFallthrough.valid).toBe(true);

    const decider = createDslShipRuleDecider(
      new Map([[1n, progFallthrough.ast!]]),
    );
    const { events } = stepWorld(
      worldFallthrough,
      decider,
      {
        ...WORLD_CONFIG,
        PORT_INCOME_ENABLED: false,
        DEMAND_SHOCK_ENABLED: false,
        SCALE_MARKET_WITH_FLEET: false,
      },
      101,
    );

    expect(events.actionEvents.length).toBe(5);
    expect(events.actionEvents[0]?.failureCode).toBe('OUT_OF_STOCK');
    expect(events.actionEvents[1]?.failureCode).toBe('INSUFFICIENT_COINS');
    expect(events.actionEvents[2]?.failureCode).toBe('CARGO_FULL');
    expect(events.actionEvents[3]?.failureCode).toBe('SAME_PORT');
    expect(events.actionEvents[4]?.result).toBe('berlayar');
    expect(worldFallthrough.ships.get(1n)?.status).toBe('sailing');

    const worldEdge = createTestWorld({
      coins: 500n,
      portId: 1,
      cargoPala: 5n,
      bandaPalaStock: 1600n,
      bandaTreasury: 10n,
    });
    const progEdge = compileDsl(`
      aturan jual_nol:
        jika benar maka jual(pala, 0)
      aturan jual_gudang_penuh:
        jika benar maka jual(pala, 2)
      aturan beli_maks_koin_kurang:
        jika benar maka beli(cengkeh, maks)
      aturan layar_rute_tidak_ada:
        jika benar maka berlayar(Batavia)
    `);
    expect(progEdge.valid).toBe(true);
    worldEdge.players.get(1n)!.coins = 5n;
    worldEdge.players.get(1n)!.initialCoins = 5n;
    worldEdge.players.get(1n)!.ledgerSum = 5n;

    const { events: evEdge } = stepWorld(
      worldEdge,
      createDslShipRuleDecider(new Map([[1n, progEdge.ast!]])),
      {
        ...WORLD_CONFIG,
        PORT_INCOME_ENABLED: false,
        DEMAND_SHOCK_ENABLED: false,
        SCALE_MARKET_WITH_FLEET: false,
      },
      101,
    );
    expect(evEdge.actionEvents[0]?.failureCode).toBe('ZERO_QUANTITY');
    expect(evEdge.actionEvents[1]?.failureCode).toBe('PORT_WAREHOUSE_FULL');
    expect(evEdge.actionEvents[2]?.failureCode).toBe('ZERO_QUANTITY');

    const worldLowTreasury = createTestWorld({
      coins: 500n,
      portId: 1,
      cargoPala: 5n,
      bandaPalaStock: 400n,
      bandaTreasury: 10n,
    });
    const progLowTreasury = compileDsl(`
      aturan jual_kas_kurang:
        jika benar maka jual(pala, 2)
      aturan layar_ke_invalid:
        jika benar maka tunggu()
    `);
    const { events: evLowT } = stepWorld(
      worldLowTreasury,
      createDslShipRuleDecider(new Map([[1n, progLowTreasury.ast!]])),
      {
        ...WORLD_CONFIG,
        PORT_INCOME_ENABLED: false,
        DEMAND_SHOCK_ENABLED: false,
        SCALE_MARKET_WITH_FLEET: false,
      },
      101,
    );
    expect(evLowT.actionEvents[0]?.failureCode).toBe('PORT_TREASURY_LOW');
    expect(evLowT.actionEvents[1]?.result).toBe('menunggu');
  });

  it('5. Kapal grounded: beli dan berlayar gagal GROUNDED, jual dan tunggu diizinkan (docs/05 & docs/09 v0.2)', () => {
    const worldGrounded = createTestWorld({
      coins: 0n,
      status: 'docked',
      portId: 6, // Batavia
      cargoPala: 4n,
    });
    const progGrounded = compileDsl(`
      aturan coba_beli_saat_grounded:
        jika di(Batavia) maka beli(garam, 1)
      aturan coba_layar_saat_grounded:
        jika di(Batavia) maka berlayar(Surabaya)
      aturan jual_darurat_saat_grounded:
        jika stok_kapal(pala) > 0 maka jual(pala, semua)
    `);
    expect(progGrounded.valid).toBe(true);

    const { events } = stepWorld(
      worldGrounded,
      createDslShipRuleDecider(new Map([[1n, progGrounded.ast!]])),
      {
        ...WORLD_CONFIG,
        PORT_INCOME_ENABLED: false,
        DEMAND_SHOCK_ENABLED: false,
        SCALE_MARKET_WITH_FLEET: false,
        RESCUE_ENABLED: false,
      },
      101,
    );

    expect(events.actionEvents.length).toBe(3);
    expect(events.actionEvents[0]?.failureCode).toBe('GROUNDED');
    expect(events.actionEvents[1]?.failureCode).toBe('GROUNDED');
    expect(events.actionEvents[2]?.result).toBe('ok');
    expect((worldGrounded.players.get(1n)?.coins ?? 0n) > 200n).toBe(true);
  });

  it('6. Determinisme (1.000 pengulangan identik) & Fuzzing Parser (2.000 input acak/malformed tanpa crash atau hang)', () => {
    const src = RULE_TEMPLATES[0]!.source;
    const compiled = compileDsl(src);
    expect(compiled.valid).toBe(true);

    const baseWorld = createTestWorld({ coins: 1000n, portId: 1 });
    const firstOut = JSON.stringify(
      Array.from(
        evaluateDslProgram(compiled.ast!, {
          ship: baseWorld.ships.get(1n)!,
          player: baseWorld.players.get(1n)!,
          state: baseWorld,
        }),
      ),
      (_k, v) => (typeof v === 'bigint' ? v.toString() : (v as unknown)),
    );

    for (let i = 0; i < 1000; i++) {
      const out = JSON.stringify(
        Array.from(
          evaluateDslProgram(compiled.ast!, {
            ship: baseWorld.ships.get(1n)!,
            player: baseWorld.players.get(1n)!,
            state: baseWorld,
          }),
        ),
        (_k, v) => (typeof v === 'bigint' ? v.toString() : (v as unknown)),
      );
      expect(out).toBe(firstOut);
    }

    // Fuzzing dengan fast-check: string acak dan token gabungan tidak pernah melempar uncaught exception
    fc.assert(
      fc.property(fc.string({ minLength: 0, maxLength: 300 }), (randomStr) => {
        const t0 = Date.now();
        const res = validateDsl(randomStr);
        const elapsed = Date.now() - t0;
        expect(typeof res.valid).toBe('boolean');
        expect(Array.isArray(res.errors)).toBe(true);
        expect(elapsed < 100).toBe(true);
      }),
      { numRuns: 1000 },
    );

    const tokenPieces = [
      'aturan ',
      'r1',
      ':',
      ' biar ',
      'margin = 10 ',
      ' jika ',
      ' maka ',
      ' dan ',
      ' atau ',
      ' bukan ',
      '(',
      ')',
      'harga(pala)',
      'harga_terakhir(Batavia, pala)',
      'ambil(0)',
      'musim()',
      'di(Banda)',
      'beli(pala, maks)',
      'jual(cengkeh, semua)',
      'berlayar(Batavia)',
      'simpan(0, 42)',
      'tunggu()',
      '<',
      '==',
      '+',
      '/',
      '0',
      '42',
      'maks',
      'semua',
      '# komentar\n',
    ];
    fc.assert(
      fc.property(
        fc.array(fc.constantFrom(...tokenPieces), {
          minLength: 1,
          maxLength: 40,
        }),
        (pieces) => {
          const fuzzSrc = pieces.join('');
          const tok = tokenizeDsl(fuzzSrc);
          expect(Array.isArray(tok.tokens)).toBe(true);
          const parsed = parseDsl(fuzzSrc);
          expect(Array.isArray(parsed.errors)).toBe(true);
          const validated = validateDsl(fuzzSrc);
          expect(typeof validated.valid).toBe('boolean');
        },
      ),
      { numRuns: 1000 },
    );
  });

  it('7. Ekstensi Pasca-MVP (Phase 2): variabel lokal biar, memori kapal simpan/ambil, kabut informasi harga_terakhir, dan musim()', () => {
    const world = createTestWorld({
      coins: 1000n,
      portId: 1, // Banda
      bandaPalaPrice: 35n,
    });

    const progPhase2 = compileDsl(`
      aturan catat_harga_banda:
        biar harga_kini = harga(pala)
        jika di(Banda) dan ambil(0) == 0
        maka simpan(0, harga_kini)

      aturan beli_berdasarkan_intel:
        biar target_jual = harga_terakhir(Batavia, pala)
        biar ongkos_rute = jarak(Batavia) * 3
        biar selisih = target_jual - ambil(0)
        jika di(Banda) dan musim() >= 1 dan selisih > ongkos_rute
        maka beli(pala, 4)
    `);
    expect(progPhase2.valid).toBe(true);
    expect(progPhase2.ast?.rules[0]?.bindings?.length).toBe(1);
    expect(progPhase2.ast?.rules[1]?.bindings?.length).toBe(3);

    const shipMemory = new Map<number, bigint>();
    const playerIntel = new Map<
      string,
      { readonly price: bigint; readonly stock: bigint; readonly tickSeen: number }
    >([[`6:1`, { price: 95n, stock: 120n, tickSeen: 2 }]]);

    // Evaluasi pertama: ambil(0) == 0 -> menjalankan simpan(0, 35)
    const firstActions = Array.from(
      evaluateDslProgram(progPhase2.ast!, {
        ship: world.ships.get(1n)!,
        player: world.players.get(1n)!,
        state: world,
        shipMemory,
        playerIntel,
      }),
    );
    expect(firstActions[0]?.type).toBe('wait');
    if (firstActions[0]?.type === 'wait') {
      expect(firstActions[0].memoryUpdate).toEqual({ slot: 0, value: 35n });
    }
    expect(shipMemory.get(0)).toBe(35n);

    // Evaluasi kedua (setelah memori slot 0 = 35): aturan 1 false, aturan 2 menghitung selisih = 95 - 35 = 60 > ongkos_rute -> beli(pala, 4)
    const secondActions = Array.from(
      evaluateDslProgram(progPhase2.ast!, {
        ship: world.ships.get(1n)!,
        player: world.players.get(1n)!,
        state: world,
        shipMemory,
        playerIntel,
      }),
    );
    expect(secondActions[0]?.ruleName).toBe('beli_berdasarkan_intel');
    expect(secondActions[0]?.type).toBe('buy');
    if (secondActions[0]?.type === 'buy') {
      expect(secondActions[0].commodityId).toBe(1);
      expect(secondActions[0].qty).toBe(4n);
    }
  });
});
