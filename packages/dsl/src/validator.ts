import { COMMODITIES_SEED, PORTS_SEED } from '@jalur-rempah/shared';
import {
  DslValueType,
  DslExprNode,
  DslActionNode,
  DslValidationError,
  DslValidationResult,
  DslLimitsConfig,
  DSL_DEFAULT_LIMITS,
  createDslError,
} from './types.js';
import { parseDsl } from './parser.js';

export const KEYWORDS = new Set<string>([
  'aturan',
  'biar',
  'jika',
  'maka',
  'dan',
  'atau',
  'bukan',
  'maks',
  'semua',
  'benar',
  'salah',
]);

export const PORT_CONSTANTS = new Map<string, number>(
  PORTS_SEED.map((p) => [p.code.toLowerCase(), p.id]),
);

export const COMMODITY_CONSTANTS = new Map<string, number>(
  COMMODITIES_SEED.map((c) => [c.code.toLowerCase(), c.id]),
);

export interface FunctionSignature {
  readonly name: string;
  readonly argTypes: readonly DslValueType[];
  readonly returnType: DslValueType;
}

export const READ_FUNCTIONS = new Map<string, FunctionSignature>([
  ['di', { name: 'di', argTypes: ['pelabuhan'], returnType: 'bool' }],
  ['koin', { name: 'koin', argTypes: [], returnType: 'angka' }],
  [
    'muatan_bebas',
    { name: 'muatan_bebas', argTypes: [], returnType: 'angka' },
  ],
  ['kapasitas', { name: 'kapasitas', argTypes: [], returnType: 'angka' }],
  [
    'stok_kapal',
    { name: 'stok_kapal', argTypes: ['komoditas'], returnType: 'angka' },
  ],
  [
    'stok_pelabuhan',
    { name: 'stok_pelabuhan', argTypes: ['komoditas'], returnType: 'angka' },
  ],
  ['harga', { name: 'harga', argTypes: ['komoditas'], returnType: 'angka' }],
  [
    'harga_di',
    {
      name: 'harga_di',
      argTypes: ['pelabuhan', 'komoditas'],
      returnType: 'angka',
    },
  ],
  [
    'harga_terakhir',
    {
      name: 'harga_terakhir',
      argTypes: ['pelabuhan', 'komoditas'],
      returnType: 'angka',
    },
  ],
  ['ambil', { name: 'ambil', argTypes: ['angka'], returnType: 'angka' }],
  ['musim', { name: 'musim', argTypes: [], returnType: 'angka' }],
  ['jarak', { name: 'jarak', argTypes: ['pelabuhan'], returnType: 'angka' }],
  ['tick', { name: 'tick', argTypes: [], returnType: 'angka' }],
]);

export const ACTION_NAMES = new Set<string>([
  'beli',
  'jual',
  'berlayar',
  'tunggu',
  'simpan',
]);

const ALL_KNOWN_IDENTS: readonly string[] = [
  ...Array.from(READ_FUNCTIONS.keys()),
  ...Array.from(ACTION_NAMES),
  ...Array.from(PORT_CONSTANTS.keys()),
  ...Array.from(COMMODITY_CONSTANTS.keys()),
  ...Array.from(KEYWORDS),
].sort();

function levenshteinDistance(a: string, b: string): number {
  const m = a.length;
  const n = b.length;
  const dp: number[][] = Array.from({ length: m + 1 }, () =>
    new Array<number>(n + 1).fill(0),
  );
  for (let i = 0; i <= m; i++) dp[i]![0] = i;
  for (let j = 0; j <= n; j++) dp[0]![j] = j;

  for (let i = 1; i <= m; i++) {
    for (let j = 1; j <= n; j++) {
      const cost = a[i - 1] === b[j - 1] ? 0 : 1;
      dp[i]![j] = Math.min(
        (dp[i - 1]?.[j] ?? 0) + 1,
        (dp[i]?.[j - 1] ?? 0) + 1,
        (dp[i - 1]?.[j - 1] ?? 0) + cost,
      );
    }
  }
  return dp[m]?.[n] ?? 99;
}

export function suggestIdentifier(
  unknownLower: string,
  candidates: readonly string[] = ALL_KNOWN_IDENTS,
): string | null {
  let bestCandidate: string | null = null;
  let bestDist = 3; // suggest only if distance <= 2
  for (const cand of candidates) {
    const dist = levenshteinDistance(unknownLower, cand);
    if (dist < bestDist) {
      bestDist = dist;
      bestCandidate = cand;
    }
  }
  return bestCandidate;
}

export function isReservedRuleName(lowerName: string): boolean {
  return (
    KEYWORDS.has(lowerName) ||
    READ_FUNCTIONS.has(lowerName) ||
    ACTION_NAMES.has(lowerName) ||
    PORT_CONSTANTS.has(lowerName) ||
    COMMODITY_CONSTANTS.has(lowerName)
  );
}

export function validateDsl(
  source: string,
  limits: DslLimitsConfig = DSL_DEFAULT_LIMITS,
): DslValidationResult {
  const parseRes = parseDsl(source, limits);
  const errors: DslValidationError[] = [...parseRes.errors];

  if (parseRes.rules.length === 0 && errors.length === 0) {
    errors.push(
      createDslError(
        1,
        1,
        'SYNTAX_ERROR',
        'Program Bahasa Aturan harus memiliki minimal 1 aturan.',
      ),
    );
  }

  if (parseRes.rules.length > limits.maxRules) {
    const extraRule = parseRes.rules[limits.maxRules]!;
    errors.push(
      createDslError(
        extraRule.span.line,
        extraRule.span.column,
        'LIMIT_RULES',
        `Jumlah aturan (${parseRes.rules.length}) melebihi batas maksimal ${limits.maxRules} aturan per program.`,
      ),
    );
  }

  const seenRuleNames = new Set<string>();

  function inferExprType(
    expr: DslExprNode,
    localTypes: ReadonlyMap<string, DslValueType>,
  ): DslValueType | null {
    switch (expr.kind) {
      case 'number_literal':
        return 'angka';
      case 'bool_literal':
        return 'bool';
      case 'keyword_arg':
        errors.push(
          createDslError(
            expr.span.line,
            expr.span.column,
            'BAD_KEYWORD_ARG',
            `Kata kunci '${expr.keyword}' hanya boleh digunakan sebagai argumen kedua pada aksi beli/jual.`,
          ),
        );
        return null;
      case 'paren':
        return inferExprType(expr.expr, localTypes);
      case 'ident': {
        const localType = localTypes.get(expr.lowerName);
        if (localType !== undefined) {
          return localType;
        }
        if (PORT_CONSTANTS.has(expr.lowerName)) {
          return 'pelabuhan';
        }
        if (COMMODITY_CONSTANTS.has(expr.lowerName)) {
          return 'komoditas';
        }
        const suggestion = suggestIdentifier(expr.lowerName, [
          ...ALL_KNOWN_IDENTS,
          ...Array.from(localTypes.keys()),
        ]);
        const hint = suggestion ? ` Maksud Anda '${suggestion}'?` : '';
        errors.push(
          createDslError(
            expr.span.line,
            expr.span.column,
            'UNKNOWN_IDENT',
            `Pengenal atau konstanta '${expr.name}' tidak dikenal.${hint}`,
          ),
        );
        return null;
      }
      case 'unary': {
        const opType = inferExprType(expr.operand, localTypes);
        if (!opType) return null;
        if (expr.op === '-') {
          if (opType !== 'angka') {
            errors.push(
              createDslError(
                expr.span.line,
                expr.span.column,
                'TYPE_MISMATCH',
                `Operator unari '-' membutuhkan tipe 'angka', tetapi menerima '${opType}'.`,
              ),
            );
            return null;
          }
          return 'angka';
        }
        if (expr.op === 'bukan') {
          if (opType !== 'bool') {
            errors.push(
              createDslError(
                expr.span.line,
                expr.span.column,
                'TYPE_MISMATCH',
                `Operator 'bukan' membutuhkan tipe 'bool', tetapi menerima '${opType}'.`,
              ),
            );
            return null;
          }
          return 'bool';
        }
        return null;
      }
      case 'binary': {
        const lType = inferExprType(expr.left, localTypes);
        const rType = inferExprType(expr.right, localTypes);
        if (!lType || !rType) return null;

        if (expr.op === 'dan' || expr.op === 'atau') {
          if (lType !== 'bool' || rType !== 'bool') {
            errors.push(
              createDslError(
                expr.span.line,
                expr.span.column,
                'TYPE_MISMATCH',
                `Operator logika '${expr.op}' membutuhkan kedua sisi bertipe 'bool' (diterima '${lType}' dan '${rType}').`,
              ),
            );
            return null;
          }
          return 'bool';
        }

        if (
          expr.op === '+' ||
          expr.op === '-' ||
          expr.op === '*' ||
          expr.op === '/' ||
          expr.op === '%'
        ) {
          if (lType !== 'angka' || rType !== 'angka') {
            errors.push(
              createDslError(
                expr.span.line,
                expr.span.column,
                'TYPE_MISMATCH',
                `Operator aritmetika '${expr.op}' membutuhkan kedua sisi bertipe 'angka' (diterima '${lType}' dan '${rType}').`,
              ),
            );
            return null;
          }
          return 'angka';
        }

        if (
          expr.op === '<' ||
          expr.op === '<=' ||
          expr.op === '>' ||
          expr.op === '>='
        ) {
          if (lType !== 'angka' || rType !== 'angka') {
            errors.push(
              createDslError(
                expr.span.line,
                expr.span.column,
                'TYPE_MISMATCH',
                `Perbandingan urutan '${expr.op}' hanya berlaku untuk tipe 'angka' (diterima '${lType}' dan '${rType}').`,
              ),
            );
            return null;
          }
          return 'bool';
        }

        if (expr.op === '==' || expr.op === '!=') {
          if (lType !== rType) {
            errors.push(
              createDslError(
                expr.span.line,
                expr.span.column,
                'TYPE_MISMATCH',
                `Perbandingan '${expr.op}' membutuhkan tipe yang sama (diterima '${lType}' dan '${rType}').`,
              ),
            );
            return null;
          }
          return 'bool';
        }
        return null;
      }
      case 'call': {
        const sig = READ_FUNCTIONS.get(expr.lowerName);
        if (!sig) {
          const suggestion = suggestIdentifier(
            expr.lowerName,
            Array.from(READ_FUNCTIONS.keys()),
          );
          const hint = suggestion ? ` Maksud Anda '${suggestion}'?` : '';
          errors.push(
            createDslError(
              expr.span.line,
              expr.span.column,
              'UNKNOWN_IDENT',
              `Fungsi '${expr.name}' tidak dikenal.${hint}`,
            ),
          );
          return null;
        }

        if (expr.args.length !== sig.argTypes.length) {
          errors.push(
            createDslError(
              expr.span.line,
              expr.span.column,
              'ARITY_MISMATCH',
              `Fungsi '${sig.name}' membutuhkan ${sig.argTypes.length} argumen, tetapi diberikan ${expr.args.length}.`,
            ),
          );
          return sig.returnType;
        }

        for (let i = 0; i < sig.argTypes.length; i++) {
          const expected = sig.argTypes[i]!;
          const argNode = expr.args[i]!;
          const actual = inferExprType(argNode, localTypes);
          if (actual && actual !== expected) {
            errors.push(
              createDslError(
                argNode.span.line,
                argNode.span.column,
                'TYPE_MISMATCH',
                `Argumen ke-${i + 1} fungsi '${sig.name}' harus bertipe '${expected}', tetapi menerima '${actual}'.`,
              ),
            );
          }
        }
        return sig.returnType;
      }
    }
  }

  function validateAction(
    action: DslActionNode,
    localTypes: ReadonlyMap<string, DslValueType>,
  ): void {
    if (!ACTION_NAMES.has(action.lowerName)) {
      const suggestion = suggestIdentifier(
        action.lowerName,
        Array.from(ACTION_NAMES),
      );
      const hint = suggestion ? ` Maksud Anda '${suggestion}'?` : '';
      errors.push(
        createDslError(
          action.span.line,
          action.span.column,
          'UNKNOWN_IDENT',
          `Aksi '${action.name}' tidak dikenal.${hint}`,
        ),
      );
      return;
    }

    if (action.lowerName === 'tunggu') {
      if (action.args.length !== 0) {
        errors.push(
          createDslError(
            action.span.line,
            action.span.column,
            'ARITY_MISMATCH',
            `Aksi 'tunggu' tidak menerima argumen, tetapi diberikan ${action.args.length}.`,
          ),
        );
      }
      return;
    }

    if (action.lowerName === 'berlayar') {
      if (action.args.length !== 1) {
        errors.push(
          createDslError(
            action.span.line,
            action.span.column,
            'ARITY_MISMATCH',
            `Aksi 'berlayar' membutuhkan 1 argumen pelabuhan, tetapi diberikan ${action.args.length}.`,
          ),
        );
        return;
      }
      const arg0 = action.args[0]!;
      const t0 = inferExprType(arg0, localTypes);
      if (t0 && t0 !== 'pelabuhan') {
        errors.push(
          createDslError(
            arg0.span.line,
            arg0.span.column,
            'TYPE_MISMATCH',
            `Argumen 'berlayar' harus bertipe 'pelabuhan', tetapi menerima '${t0}'.`,
          ),
        );
      }
      return;
    }

    if (action.lowerName === 'simpan') {
      if (action.args.length !== 2) {
        errors.push(
          createDslError(
            action.span.line,
            action.span.column,
            'ARITY_MISMATCH',
            `Aksi 'simpan' membutuhkan 2 argumen (slot, nilai), tetapi diberikan ${action.args.length}.`,
          ),
        );
        return;
      }
      const arg0 = action.args[0]!;
      const arg1 = action.args[1]!;
      const t0 = inferExprType(arg0, localTypes);
      if (t0 && t0 !== 'angka') {
        errors.push(
          createDslError(
            arg0.span.line,
            arg0.span.column,
            'TYPE_MISMATCH',
            `Argumen pertama 'simpan' (slot) harus bertipe 'angka', tetapi menerima '${t0}'.`,
          ),
        );
      }
      const t1 = inferExprType(arg1, localTypes);
      if (t1 && t1 !== 'angka') {
        errors.push(
          createDslError(
            arg1.span.line,
            arg1.span.column,
            'TYPE_MISMATCH',
            `Argumen kedua 'simpan' (nilai) harus bertipe 'angka', tetapi menerima '${t1}'.`,
          ),
        );
      }
      return;
    }

    if (action.lowerName === 'beli' || action.lowerName === 'jual') {
      if (action.args.length !== 2) {
        errors.push(
          createDslError(
            action.span.line,
            action.span.column,
            'ARITY_MISMATCH',
            `Aksi '${action.lowerName}' membutuhkan 2 argumen (komoditas, jumlah), tetapi diberikan ${action.args.length}.`,
          ),
        );
        return;
      }

      const arg0 = action.args[0]!;
      const arg1 = action.args[1]!;

      const t0 = inferExprType(arg0, localTypes);
      if (t0 && t0 !== 'komoditas') {
        errors.push(
          createDslError(
            arg0.span.line,
            arg0.span.column,
            'TYPE_MISMATCH',
            `Argumen pertama '${action.lowerName}' harus bertipe 'komoditas', tetapi menerima '${t0}'.`,
          ),
        );
      }

      if (arg1.kind === 'keyword_arg') {
        if (action.lowerName === 'beli' && arg1.keyword !== 'maks') {
          errors.push(
            createDslError(
              arg1.span.line,
              arg1.span.column,
              'BAD_KEYWORD_ARG',
              `Aksi 'beli' hanya mengizinkan kata kunci 'maks' sebagai argumen kedua, bukan '${arg1.keyword}'.`,
            ),
          );
        } else if (action.lowerName === 'jual' && arg1.keyword !== 'semua') {
          errors.push(
            createDslError(
              arg1.span.line,
              arg1.span.column,
              'BAD_KEYWORD_ARG',
              `Aksi 'jual' hanya mengizinkan kata kunci 'semua' sebagai argumen kedua, bukan '${arg1.keyword}'.`,
            ),
          );
        }
      } else {
        const t1 = inferExprType(arg1, localTypes);
        if (t1 && t1 !== 'angka') {
          errors.push(
            createDslError(
              arg1.span.line,
              arg1.span.column,
              'TYPE_MISMATCH',
              `Argumen kedua '${action.lowerName}' harus bertipe 'angka' atau kata kunci '${action.lowerName === 'beli' ? 'maks' : 'semua'}', tetapi menerima '${t1}'.`,
            ),
          );
        }
      }
    }
  }

  for (const rule of parseRes.rules) {
    if (isReservedRuleName(rule.lowerName)) {
      errors.push(
        createDslError(
          rule.nameSpan.line,
          rule.nameSpan.column,
          'RESERVED_NAME',
          `Nama aturan '${rule.name}' tidak boleh menggunakan kata kunci, fungsi, aksi, atau konstanta dunia.`,
        ),
      );
    }

    if (seenRuleNames.has(rule.lowerName)) {
      errors.push(
        createDslError(
          rule.nameSpan.line,
          rule.nameSpan.column,
          'DUPLICATE_RULE',
          `Nama aturan '${rule.name}' sudah digunakan sebelumnya di program ini.`,
        ),
      );
    } else {
      seenRuleNames.add(rule.lowerName);
    }

    if (rule.nodeCount > limits.maxNodesPerRule) {
      errors.push(
        createDslError(
          rule.span.line,
          rule.span.column,
          'LIMIT_NODES',
          `Aturan '${rule.name}' memiliki ${rule.nodeCount} node AST, melebihi batas maksimal ${limits.maxNodesPerRule} node per aturan.`,
        ),
      );
    }

    if (rule.maxDepth > limits.maxExprDepth) {
      errors.push(
        createDslError(
          rule.span.line,
          rule.span.column,
          'LIMIT_DEPTH',
          `Aturan '${rule.name}' memiliki kedalaman ekspresi ${rule.maxDepth}, melebihi batas maksimal ${limits.maxExprDepth}.`,
        ),
      );
    }

    const localTypes = new Map<string, DslValueType>();
    for (const binding of rule.bindings ?? []) {
      if (isReservedRuleName(binding.lowerName)) {
        errors.push(
          createDslError(
            binding.span.line,
            binding.span.column,
            'RESERVED_NAME',
            `Nama variabel lokal '${binding.name}' tidak boleh menggunakan kata kunci, fungsi, aksi, atau konstanta dunia.`,
          ),
        );
      }
      const bType = inferExprType(binding.expr, localTypes);
      if (bType) {
        localTypes.set(binding.lowerName, bType);
      }
    }

    const condType = inferExprType(rule.condition, localTypes);
    if (condType && condType !== 'bool') {
      errors.push(
        createDslError(
          rule.condition.span.line,
          rule.condition.span.column,
          'TYPE_MISMATCH',
          `Kondisi 'jika' pada aturan '${rule.name}' harus menghasilkan tipe 'bool', tetapi menghasilkan '${condType}'.`,
        ),
      );
    }

    validateAction(rule.action, localTypes);
  }

  if (errors.length > 0) {
    return {
      valid: false,
      errors,
    };
  }

  return {
    valid: true,
    errors: [],
    ast: {
      ast_version: 1,
      rules: parseRes.rules,
    },
  };
}

export function compileDsl(
  source: string,
  limits: DslLimitsConfig = DSL_DEFAULT_LIMITS,
): DslValidationResult {
  return validateDsl(source, limits);
}
