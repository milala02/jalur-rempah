import { ROUTES_SEED } from '@jalur-rempah/shared';
import {
  CompiledDslProgram,
  DslExprNode,
  DslLimitsConfig,
  DSL_DEFAULT_LIMITS,
  DslRuntimeErrorCode,
} from './types.js';
import { PORT_CONSTANTS, COMMODITY_CONSTANTS } from './validator.js';

export interface DslShipSnapshot {
  readonly id: bigint;
  readonly playerId: bigint;
  readonly capacity: number;
  readonly status: 'docked' | 'sailing' | 'grounded';
  readonly portId: number;
  readonly cargo: ReadonlyMap<number, bigint>;
  readonly memory?: Map<number, bigint>;
}

export interface DslPlayerSnapshot {
  readonly id: bigint;
  readonly coins: bigint;
  readonly intel?: ReadonlyMap<string, { readonly price: bigint; readonly stock: bigint; readonly tickSeen: number }>;
}

export interface DslMarketSnapshot {
  readonly port_id: number;
  readonly commodity_id: number;
  readonly stock: bigint;
  readonly price: bigint;
}

export interface DslWorldSnapshot {
  readonly tickNo: number;
  readonly markets: ReadonlyMap<string, DslMarketSnapshot>;
  readonly seasonId?: number;
}

export interface DslEvalContext {
  readonly ship: DslShipSnapshot;
  readonly player: DslPlayerSnapshot;
  readonly state: DslWorldSnapshot;
  readonly shipMemory?: Map<number, bigint>;
  readonly playerIntel?: ReadonlyMap<string, { readonly price: bigint; readonly stock: bigint; readonly tickSeen: number }>;
}

export type DslCandidateAction =
  | {
      readonly ruleName?: string;
      readonly detail?: string;
      readonly type: 'buy';
      readonly commodityId: number;
      readonly qty: bigint | 'maks';
    }
  | {
      readonly ruleName?: string;
      readonly detail?: string;
      readonly type: 'sell';
      readonly commodityId: number;
      readonly qty: bigint | 'semua' | 'maks';
    }
  | {
      readonly ruleName?: string;
      readonly detail?: string;
      readonly type: 'sail';
      readonly destPortId: number;
    }
  | {
      readonly ruleName?: string;
      readonly detail?: string;
      readonly type: 'wait';
      readonly memoryUpdate?: { readonly slot: number; readonly value: bigint };
    }
  | {
      readonly ruleName?: string;
      readonly detail?: string;
      readonly type: 'skip';
      readonly skipCode: DslRuntimeErrorCode;
    };

class DslRuntimeException extends Error {
  readonly code: DslRuntimeErrorCode;
  constructor(code: DslRuntimeErrorCode, message: string) {
    super(message);
    this.code = code;
  }
}

const MAX_SAFE_BIGINT = BigInt(Number.MAX_SAFE_INTEGER);
const MIN_SAFE_BIGINT = -MAX_SAFE_BIGINT;

function toSafeNumber(val: bigint): number {
  if (val > MAX_SAFE_BIGINT || val < MIN_SAFE_BIGINT) {
    throw new DslRuntimeException(
      'OVERFLOW',
      `Nilai ${val.toString()} melampaui batas integer aman (2^53 - 1).`,
    );
  }
  return Number(val);
}

function checkSafeNumber(val: number): number {
  if (!Number.isFinite(val) || Math.abs(val) > Number.MAX_SAFE_INTEGER) {
    throw new DslRuntimeException(
      'OVERFLOW',
      `Hasil perhitungan melampaui batas integer aman (2^53 - 1).`,
    );
  }
  return val;
}

// Precompute shortest distance table across ROUTES_SEED
const SHORTEST_DIST = new Map<string, number>();
function ensureShortestDist(): void {
  if (SHORTEST_DIST.size > 0) return;
  const portIds = [1, 2, 3, 4, 5, 6];
  for (const p1 of portIds) {
    for (const p2 of portIds) {
      SHORTEST_DIST.set(`${p1}:${p2}`, p1 === p2 ? 0 : 999);
    }
  }
  for (const r of ROUTES_SEED) {
    SHORTEST_DIST.set(`${r.from_port}:${r.to_port}`, r.ticks);
  }
  for (const k of portIds) {
    for (const i of portIds) {
      for (const j of portIds) {
        const ik = SHORTEST_DIST.get(`${i}:${k}`) ?? 999;
        const kj = SHORTEST_DIST.get(`${k}:${j}`) ?? 999;
        const ij = SHORTEST_DIST.get(`${i}:${j}`) ?? 999;
        if (ik + kj < ij) {
          SHORTEST_DIST.set(`${i}:${j}`, ik + kj);
        }
      }
    }
  }
}

type RuntimeValue = number | boolean;

/**
 * Generator yang mengevaluasi aturan dari atas ke bawah dengan anggaran node AST bersama
 * per kapal per tick (default 500 node). Hanya mengevaluasi aturan berikutnya jika aturan
 * sebelumnya bernilai false, dilewati karena galat runtime, atau aksinya gagal dieksekusi di stepWorld.
 */
export function* evaluateDslProgram(
  program: CompiledDslProgram,
  ctx: DslEvalContext,
  limits: DslLimitsConfig = DSL_DEFAULT_LIMITS,
): Generator<DslCandidateAction, void, unknown> {
  ensureShortestDist();
  let nodesUsed = 0;
  const activeMemory = ctx.shipMemory ?? ctx.ship.memory ?? new Map<number, bigint>();
  const activeIntel = ctx.playerIntel ?? ctx.player.intel;

  function consumeNode(): void {
    nodesUsed += 1;
    if (nodesUsed > limits.maxEvalBudget) {
      throw new DslRuntimeException(
        'BUDGET_EXCEEDED',
        `Anggaran evaluasi (${limits.maxEvalBudget} node) habis.`,
      );
    }
  }

  function evalExpr(
    expr: DslExprNode,
    localEnv: ReadonlyMap<string, RuntimeValue>,
  ): RuntimeValue {
    consumeNode();

    switch (expr.kind) {
      case 'number_literal':
        return toSafeNumber(expr.value);
      case 'bool_literal':
        return expr.value;
      case 'paren':
        return evalExpr(expr.expr, localEnv);
      case 'ident': {
        const localVal = localEnv.get(expr.lowerName);
        if (localVal !== undefined) return localVal;
        const pId = PORT_CONSTANTS.get(expr.lowerName);
        if (pId !== undefined) return pId;
        const cId = COMMODITY_CONSTANTS.get(expr.lowerName);
        if (cId !== undefined) return cId;
        return 0;
      }
      case 'keyword_arg':
        return 0;
      case 'unary': {
        const val = evalExpr(expr.operand, localEnv);
        if (expr.op === '-') {
          return checkSafeNumber(-(val as number));
        }
        return !(val as boolean);
      }
      case 'binary': {
        if (expr.op === 'dan') {
          const l = evalExpr(expr.left, localEnv) as boolean;
          if (!l) return false;
          return evalExpr(expr.right, localEnv) as boolean;
        }
        if (expr.op === 'atau') {
          const l = evalExpr(expr.left, localEnv) as boolean;
          if (l) return true;
          return evalExpr(expr.right, localEnv) as boolean;
        }

        const l = evalExpr(expr.left, localEnv);
        const r = evalExpr(expr.right, localEnv);

        switch (expr.op) {
          case '+':
            return checkSafeNumber((l as number) + (r as number));
          case '-':
            return checkSafeNumber((l as number) - (r as number));
          case '*':
            return checkSafeNumber((l as number) * (r as number));
          case '/': {
            const divisor = r as number;
            if (divisor === 0) {
              throw new DslRuntimeException(
                'DIV_ZERO',
                'Pembagian dengan nol.',
              );
            }
            return checkSafeNumber(Math.trunc((l as number) / divisor));
          }
          case '%': {
            const divisor = r as number;
            if (divisor === 0) {
              throw new DslRuntimeException('DIV_ZERO', 'Modulo dengan nol.');
            }
            return checkSafeNumber(Math.trunc((l as number) % divisor));
          }
          case '<':
            return (l as number) < (r as number);
          case '<=':
            return (l as number) <= (r as number);
          case '>':
            return (l as number) > (r as number);
          case '>=':
            return (l as number) >= (r as number);
          case '==':
            return l === r;
          case '!=':
            return l !== r;
        }
      }
      case 'call': {
        const evaluatedArgs = expr.args.map((a) => evalExpr(a, localEnv));
        switch (expr.lowerName) {
          case 'di': {
            const targetPort = evaluatedArgs[0] as number;
            return (
              (ctx.ship.status === 'docked' ||
                ctx.ship.status === 'grounded') &&
              ctx.ship.portId === targetPort
            );
          }
          case 'koin':
            return toSafeNumber(ctx.player.coins);
          case 'muatan_bebas': {
            let totalCargo = 0n;
            for (const q of ctx.ship.cargo.values()) totalCargo += q;
            const free = BigInt(ctx.ship.capacity) - totalCargo;
            return toSafeNumber(free > 0n ? free : 0n);
          }
          case 'kapasitas':
            return checkSafeNumber(ctx.ship.capacity);
          case 'stok_kapal': {
            const comId = evaluatedArgs[0] as number;
            return toSafeNumber(ctx.ship.cargo.get(comId) ?? 0n);
          }
          case 'stok_pelabuhan': {
            const comId = evaluatedArgs[0] as number;
            const m = ctx.state.markets.get(`${ctx.ship.portId}:${comId}`);
            return toSafeNumber(m?.stock ?? 0n);
          }
          case 'harga': {
            const comId = evaluatedArgs[0] as number;
            const m = ctx.state.markets.get(`${ctx.ship.portId}:${comId}`);
            return toSafeNumber(m?.price ?? 1n);
          }
          case 'harga_di': {
            const pId = evaluatedArgs[0] as number;
            const comId = evaluatedArgs[1] as number;
            const m = ctx.state.markets.get(`${pId}:${comId}`);
            return toSafeNumber(m?.price ?? 1n);
          }
          case 'harga_terakhir': {
            const pId = evaluatedArgs[0] as number;
            const comId = evaluatedArgs[1] as number;
            // Jika kapal sedang bersandar di pelabuhan tersebut, harga langsung terlihat
            if (
              (ctx.ship.status === 'docked' || ctx.ship.status === 'grounded') &&
              ctx.ship.portId === pId
            ) {
              const mNow = ctx.state.markets.get(`${pId}:${comId}`);
              return toSafeNumber(mNow?.price ?? 1n);
            }
            const intelEntry = activeIntel?.get(`${pId}:${comId}`);
            if (intelEntry !== undefined) {
              return toSafeNumber(intelEntry.price);
            }
            const mFallback = ctx.state.markets.get(`${pId}:${comId}`);
            return toSafeNumber(mFallback?.price ?? 1n);
          }
          case 'ambil': {
            const slot = Math.trunc(evaluatedArgs[0] as number);
            if (slot < 0 || slot > 7) return 0;
            return toSafeNumber(activeMemory.get(slot) ?? 0n);
          }
          case 'musim': {
            if (ctx.state.seasonId !== undefined) {
              return checkSafeNumber(ctx.state.seasonId);
            }
            // Siklus deterministik 24 tick per musim: 1 = Muson Barat, 2 = Muson Timur, 3 = Pancaroba
            return (Math.floor(Math.max(0, ctx.state.tickNo) / 24) % 3) + 1;
          }
          case 'jarak': {
            const destPort = evaluatedArgs[0] as number;
            return SHORTEST_DIST.get(`${ctx.ship.portId}:${destPort}`) ?? 999;
          }
          case 'tick':
            return checkSafeNumber(ctx.state.tickNo);
          default:
            return 0;
        }
      }
    }
  }

  for (const rule of program.rules) {
    try {
      const localEnv = new Map<string, RuntimeValue>();
      for (const binding of rule.bindings ?? []) {
        consumeNode();
        const bVal = evalExpr(binding.expr, localEnv);
        localEnv.set(binding.lowerName, bVal);
      }

      const condResult = evalExpr(rule.condition, localEnv);
      if (condResult !== true) {
        continue;
      }

      // Evaluate action node
      consumeNode();
      const act = rule.action;

      if (act.lowerName === 'tunggu') {
        yield {
          ruleName: rule.name,
          detail: `aturan ${rule.name} cocok: tunggu()`,
          type: 'wait',
        };
        continue;
      }

      if (act.lowerName === 'simpan') {
        const rawSlot = Math.trunc(evalExpr(act.args[0]!, localEnv) as number);
        const slot = Math.max(0, Math.min(7, rawSlot));
        const numVal = Math.trunc(evalExpr(act.args[1]!, localEnv) as number);
        const bigVal = BigInt(numVal);
        activeMemory.set(slot, bigVal);
        yield {
          ruleName: rule.name,
          detail: `aturan ${rule.name} cocok: simpan(${slot}, ${bigVal.toString()})`,
          type: 'wait',
          memoryUpdate: { slot, value: bigVal },
        };
        continue;
      }

      if (act.lowerName === 'berlayar') {
        const destPortId = evalExpr(act.args[0]!, localEnv) as number;
        yield {
          ruleName: rule.name,
          detail: `aturan ${rule.name} cocok: berlayar(${destPortId})`,
          type: 'sail',
          destPortId,
        };
        continue;
      }

      if (act.lowerName === 'beli') {
        const comId = evalExpr(act.args[0]!, localEnv) as number;
        const arg1 = act.args[1]!;
        let qty: bigint | 'maks';
        if (arg1.kind === 'keyword_arg') {
          qty = 'maks';
        } else {
          const numVal = evalExpr(arg1, localEnv) as number;
          qty = BigInt(Math.trunc(numVal));
        }
        yield {
          ruleName: rule.name,
          detail: `aturan ${rule.name} cocok: beli(${comId}, ${qty.toString()})`,
          type: 'buy',
          commodityId: comId,
          qty,
        };
        continue;
      }

      if (act.lowerName === 'jual') {
        const comId = evalExpr(act.args[0]!, localEnv) as number;
        const arg1 = act.args[1]!;
        let qty: bigint | 'semua';
        if (arg1.kind === 'keyword_arg') {
          qty = 'semua';
        } else {
          const numVal = evalExpr(arg1, localEnv) as number;
          qty = BigInt(Math.trunc(numVal));
        }
        yield {
          ruleName: rule.name,
          detail: `aturan ${rule.name} cocok: jual(${comId}, ${qty.toString()})`,
          type: 'sell',
          commodityId: comId,
          qty,
        };
        continue;
      }
    } catch (err) {
      if (err instanceof DslRuntimeException) {
        yield {
          ruleName: rule.name,
          detail: `aturan ${rule.name} dilewati (${err.code}): ${err.message}`,
          type: 'skip',
          skipCode: err.code,
        };
        continue;
      }
      throw err;
    }
  }
}

/**
 * Membuat fungsi ShipRuleDecider yang kompatibel langsung dengan stepWorld(state, decider, config).
 */
export function createDslShipRuleDecider(
  programsByShipId: ReadonlyMap<bigint, CompiledDslProgram>,
  limits: DslLimitsConfig = DSL_DEFAULT_LIMITS,
  extra?: {
    readonly shipMemories?: ReadonlyMap<bigint, Map<number, bigint>>;
    readonly playerIntelByPlayerId?: ReadonlyMap<
      bigint,
      ReadonlyMap<string, { readonly price: bigint; readonly stock: bigint; readonly tickSeen: number }>
    >;
  },
): (
  ship: DslShipSnapshot,
  player: DslPlayerSnapshot,
  state: DslWorldSnapshot,
) => Iterable<DslCandidateAction> {
  return (ship, player, state) => {
    const prog = programsByShipId.get(ship.id);
    if (!prog) {
      return [];
    }
    const shipMemory = extra?.shipMemories?.get(ship.id);
    const playerIntel = extra?.playerIntelByPlayerId?.get(player.id);
    return evaluateDslProgram(
      prog,
      {
        ship,
        player,
        state,
        ...(shipMemory ? { shipMemory } : {}),
        ...(playerIntel ? { playerIntel } : {}),
      },
      limits,
    );
  };
}
