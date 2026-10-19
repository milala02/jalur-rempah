import {
  DslExprNode,
  DslActionNode,
  DslRuleNode,
  DslLetBindingNode,
  DslValidationError,
  DslBinaryOperator,
  DSL_DEFAULT_LIMITS,
  DslLimitsConfig,
  createDslError,
} from './types.js';
import { Token, tokenizeDsl } from './lexer.js';

export interface ParseResult {
  readonly rules: readonly DslRuleNode[];
  readonly errors: readonly DslValidationError[];
}

export function countExprNodes(expr: DslExprNode): number {
  switch (expr.kind) {
    case 'number_literal':
    case 'bool_literal':
    case 'ident':
    case 'keyword_arg':
      return 1;
    case 'paren':
      return 1 + countExprNodes(expr.expr);
    case 'unary':
      return 1 + countExprNodes(expr.operand);
    case 'binary':
      return 1 + countExprNodes(expr.left) + countExprNodes(expr.right);
    case 'call':
      return (
        1 + expr.args.reduce((acc, arg) => acc + countExprNodes(arg), 0)
      );
  }
}

export function computeExprDepth(expr: DslExprNode): number {
  switch (expr.kind) {
    case 'number_literal':
    case 'bool_literal':
    case 'ident':
    case 'keyword_arg':
      return 1;
    case 'paren':
      return 1 + computeExprDepth(expr.expr);
    case 'unary':
      return 1 + computeExprDepth(expr.operand);
    case 'binary':
      return (
        1 + Math.max(computeExprDepth(expr.left), computeExprDepth(expr.right))
      );
    case 'call': {
      if (expr.args.length === 0) return 1;
      const maxChild = Math.max(...expr.args.map((a) => computeExprDepth(a)));
      return 1 + maxChild;
    }
  }
}

const MAX_HARD_PARSE_DEPTH = 48;

export function parseDsl(
  source: string,
  limits: DslLimitsConfig = DSL_DEFAULT_LIMITS,
): ParseResult {
  const errors: DslValidationError[] = [];

  if (source.length > limits.maxSourceLength) {
    errors.push(
      createDslError(
        1,
        1,
        'LIMIT_LENGTH',
        `Panjang sumber aturan (${source.length} karakter) melebihi batas maksimal ${limits.maxSourceLength} karakter.`,
      ),
    );
  }

  const lexResult = tokenizeDsl(source);
  for (const lexErr of lexResult.errors) {
    errors.push(lexErr);
  }

  const tokens = lexResult.tokens;
  const rules: DslRuleNode[] = [];
  let pos = 0;

  function peek(): Token {
    return tokens[pos] ?? tokens[tokens.length - 1]!;
  }

  function advance(): Token {
    const t = peek();
    if (t.type !== 'EOF') {
      pos += 1;
    }
    return t;
  }

  function syncToNextRule(): void {
    while (peek().type !== 'EOF') {
      if (peek().type === 'IDENT' && peek().lower === 'aturan') {
        return;
      }
      advance();
    }
  }

  function parsePrimary(depth: number): DslExprNode | null {
    const t = peek();
    if (depth > MAX_HARD_PARSE_DEPTH) {
      errors.push(
        createDslError(
          t.line,
          t.column,
          'LIMIT_DEPTH',
          `Kedalaman ekspresi melebihi batas maksimal ${limits.maxExprDepth}.`,
        ),
      );
      return null;
    }

    if (t.type === 'NUMBER') {
      advance();
      let val = 0n;
      try {
        val = BigInt(t.value);
      } catch {
        val = 0n;
      }
      return {
        kind: 'number_literal',
        raw: t.value,
        value: val,
        span: { line: t.line, column: t.column },
      };
    }

    if (t.type === 'LPAREN') {
      const openTok = advance();
      const inner = parseExpr(depth + 1);
      if (!inner) return null;
      const closeTok = peek();
      if (closeTok.type !== 'RPAREN') {
        errors.push(
          createDslError(
            closeTok.line,
            closeTok.column,
            'SYNTAX_ERROR',
            `Diharapkan tanda kurung tutup ')' tetapi ditemukan '${closeTok.value || 'akhir berkas'}'.`,
          ),
        );
        return null;
      }
      advance();
      return {
        kind: 'paren',
        expr: inner,
        span: { line: openTok.line, column: openTok.column },
      };
    }

    if (t.type === 'IDENT') {
      if (t.lower === 'benar' || t.lower === 'salah') {
        advance();
        return {
          kind: 'bool_literal',
          value: t.lower === 'benar',
          span: { line: t.line, column: t.column },
        };
      }

      if (t.lower === 'maks' || t.lower === 'semua') {
        advance();
        return {
          kind: 'keyword_arg',
          keyword: t.lower,
          span: { line: t.line, column: t.column },
        };
      }

      // Guard against unexpected structural keywords inside an expression
      if (
        t.lower === 'aturan' ||
        t.lower === 'jika' ||
        t.lower === 'maka' ||
        t.lower === 'biar'
      ) {
        errors.push(
          createDslError(
            t.line,
            t.column,
            'SYNTAX_ERROR',
            `Kata kunci '${t.value}' tidak boleh muncul di dalam ekspresi.`,
          ),
        );
        return null;
      }

      const idTok = advance();
      if (peek().type === 'LPAREN') {
        advance(); // consume '('
        const args: DslExprNode[] = [];
        if (peek().type !== 'RPAREN') {
          while (true) {
            const arg = parseExpr(depth + 1);
            if (!arg) return null;
            args.push(arg);
            if (peek().type === 'COMMA') {
              advance();
              continue;
            }
            break;
          }
        }
        if (peek().type !== 'RPAREN') {
          const bad = peek();
          errors.push(
            createDslError(
              bad.line,
              bad.column,
              'SYNTAX_ERROR',
              `Diharapkan ')' setelah argumen fungsi '${idTok.value}'.`,
            ),
          );
          return null;
        }
        advance(); // consume ')'
        return {
          kind: 'call',
          name: idTok.value,
          lowerName: idTok.lower,
          args,
          span: { line: idTok.line, column: idTok.column },
        };
      }

      return {
        kind: 'ident',
        name: idTok.value,
        lowerName: idTok.lower,
        span: { line: idTok.line, column: idTok.column },
      };
    }

    errors.push(
      createDslError(
        t.line,
        t.column,
        'SYNTAX_ERROR',
        `Diharapkan ekspresi tetapi ditemukan '${t.value || 'akhir berkas'}'.`,
      ),
    );
    return null;
  }

  function parseUnary(depth: number): DslExprNode | null {
    const t = peek();
    if (t.type === 'OP' && t.value === '-') {
      advance();
      const operand = parsePrimary(depth + 1);
      if (!operand) return null;
      return {
        kind: 'unary',
        op: '-',
        operand,
        span: { line: t.line, column: t.column },
      };
    }
    return parsePrimary(depth);
  }

  function parseMultiplicative(depth: number): DslExprNode | null {
    let left = parseUnary(depth);
    if (!left) return null;

    while (
      peek().type === 'OP' &&
      (peek().value === '*' || peek().value === '/' || peek().value === '%')
    ) {
      const opTok = advance();
      const right = parseUnary(depth + 1);
      if (!right) return null;
      left = {
        kind: 'binary',
        op: opTok.value as DslBinaryOperator,
        left,
        right,
        span: { line: opTok.line, column: opTok.column },
      };
    }
    return left;
  }

  function parseAdditive(depth: number): DslExprNode | null {
    let left = parseMultiplicative(depth);
    if (!left) return null;

    while (
      peek().type === 'OP' &&
      (peek().value === '+' || peek().value === '-')
    ) {
      const opTok = advance();
      const right = parseMultiplicative(depth + 1);
      if (!right) return null;
      left = {
        kind: 'binary',
        op: opTok.value as DslBinaryOperator,
        left,
        right,
        span: { line: opTok.line, column: opTok.column },
      };
    }
    return left;
  }

  function parseComparison(depth: number): DslExprNode | null {
    const left = parseAdditive(depth);
    if (!left) return null;

    const t = peek();
    if (
      t.type === 'OP' &&
      (t.value === '<' ||
        t.value === '<=' ||
        t.value === '>' ||
        t.value === '>=' ||
        t.value === '==' ||
        t.value === '!=')
    ) {
      const opTok = advance();
      const right = parseAdditive(depth + 1);
      if (!right) return null;
      return {
        kind: 'binary',
        op: opTok.value as DslBinaryOperator,
        left,
        right,
        span: { line: opTok.line, column: opTok.column },
      };
    }
    return left;
  }

  function parseNot(depth: number): DslExprNode | null {
    const t = peek();
    if (t.type === 'IDENT' && t.lower === 'bukan') {
      advance();
      const operand = parseComparison(depth + 1);
      if (!operand) return null;
      return {
        kind: 'unary',
        op: 'bukan',
        operand,
        span: { line: t.line, column: t.column },
      };
    }
    return parseComparison(depth);
  }

  function parseAnd(depth: number): DslExprNode | null {
    let left = parseNot(depth);
    if (!left) return null;

    while (peek().type === 'IDENT' && peek().lower === 'dan') {
      const opTok = advance();
      const right = parseNot(depth + 1);
      if (!right) return null;
      left = {
        kind: 'binary',
        op: 'dan',
        left,
        right,
        span: { line: opTok.line, column: opTok.column },
      };
    }
    return left;
  }

  function parseOr(depth: number): DslExprNode | null {
    let left = parseAnd(depth);
    if (!left) return null;

    while (peek().type === 'IDENT' && peek().lower === 'atau') {
      const opTok = advance();
      const right = parseAnd(depth + 1);
      if (!right) return null;
      left = {
        kind: 'binary',
        op: 'atau',
        left,
        right,
        span: { line: opTok.line, column: opTok.column },
      };
    }
    return left;
  }

  function parseExpr(depth: number): DslExprNode | null {
    return parseOr(depth);
  }

  function parseAction(): DslActionNode | null {
    const idTok = peek();
    if (idTok.type !== 'IDENT') {
      errors.push(
        createDslError(
          idTok.line,
          idTok.column,
          'SYNTAX_ERROR',
          `Diharapkan nama aksi setelah 'maka', tetapi ditemukan '${idTok.value || 'akhir berkas'}'.`,
        ),
      );
      return null;
    }
    advance();

    if (peek().type !== 'LPAREN') {
      const bad = peek();
      errors.push(
        createDslError(
          bad.line,
          bad.column,
          'SYNTAX_ERROR',
          `Diharapkan '(' setelah nama aksi '${idTok.value}'.`,
        ),
      );
      return null;
    }
    advance(); // consume '('

    const args: DslExprNode[] = [];
    if (peek().type !== 'RPAREN') {
      while (true) {
        const argTok = peek();
        if (
          argTok.type === 'IDENT' &&
          (argTok.lower === 'maks' || argTok.lower === 'semua')
        ) {
          advance();
          args.push({
            kind: 'keyword_arg',
            keyword: argTok.lower,
            span: { line: argTok.line, column: argTok.column },
          });
        } else {
          const exprArg = parseExpr(1);
          if (!exprArg) return null;
          args.push(exprArg);
        }

        if (peek().type === 'COMMA') {
          advance();
          continue;
        }
        break;
      }
    }

    if (peek().type !== 'RPAREN') {
      const bad = peek();
      errors.push(
        createDslError(
          bad.line,
          bad.column,
          'SYNTAX_ERROR',
          `Diharapkan ')' untuk menutup aksi '${idTok.value}'.`,
        ),
      );
      return null;
    }
    advance(); // consume ')'

    return {
      kind: 'action',
      name: idTok.value,
      lowerName: idTok.lower,
      args,
      span: { line: idTok.line, column: idTok.column },
    };
  }

  while (peek().type !== 'EOF') {
    const startTok = peek();
    if (startTok.type !== 'IDENT' || startTok.lower !== 'aturan') {
      errors.push(
        createDslError(
          startTok.line,
          startTok.column,
          'SYNTAX_ERROR',
          `Diharapkan kata kunci 'aturan', tetapi ditemukan '${startTok.value}'.`,
        ),
      );
      advance();
      syncToNextRule();
      continue;
    }
    advance(); // consume 'aturan'

    const nameTok = peek();
    if (nameTok.type !== 'IDENT') {
      errors.push(
        createDslError(
          nameTok.line,
          nameTok.column,
          'SYNTAX_ERROR',
          `Diharapkan nama aturan setelah kata kunci 'aturan'.`,
        ),
      );
      syncToNextRule();
      continue;
    }
    advance(); // consume rule name

    if (peek().type !== 'COLON') {
      const bad = peek();
      errors.push(
        createDslError(
          bad.line,
          bad.column,
          'SYNTAX_ERROR',
          `Diharapkan ':' setelah nama aturan '${nameTok.value}'.`,
        ),
      );
      syncToNextRule();
      continue;
    }
    advance(); // consume ':'

    // Optional local variable bindings: `biar <ident> = <ekspresi>`
    const bindings: DslLetBindingNode[] = [];
    let bindingFailed = false;
    while (peek().type === 'IDENT' && peek().lower === 'biar') {
      advance(); // consume 'biar'
      const varTok = peek();
      if (varTok.type !== 'IDENT') {
        errors.push(
          createDslError(
            varTok.line,
            varTok.column,
            'SYNTAX_ERROR',
            `Diharapkan nama variabel setelah 'biar', tetapi ditemukan '${varTok.value || 'akhir berkas'}'.`,
          ),
        );
        bindingFailed = true;
        break;
      }
      advance(); // consume variable name

      const eqTok = peek();
      if (eqTok.type !== 'EQUALS') {
        errors.push(
          createDslError(
            eqTok.line,
            eqTok.column,
            'SYNTAX_ERROR',
            `Diharapkan '=' setelah nama variabel '${varTok.value}' pada deklarasi 'biar'.`,
          ),
        );
        bindingFailed = true;
        break;
      }
      advance(); // consume '='

      const valExpr = parseExpr(1);
      if (!valExpr) {
        bindingFailed = true;
        break;
      }

      bindings.push({
        kind: 'let_binding',
        name: varTok.value,
        lowerName: varTok.lower,
        expr: valExpr,
        span: { line: varTok.line, column: varTok.column },
      });
    }

    if (bindingFailed) {
      syncToNextRule();
      continue;
    }

    const jikaTok = peek();
    if (jikaTok.type !== 'IDENT' || jikaTok.lower !== 'jika') {
      errors.push(
        createDslError(
          jikaTok.line,
          jikaTok.column,
          'SYNTAX_ERROR',
          `Diharapkan kata kunci 'jika' pada aturan '${nameTok.value}', tetapi ditemukan '${jikaTok.value || 'akhir berkas'}'.`,
        ),
      );
      syncToNextRule();
      continue;
    }
    advance(); // consume 'jika'

    const cond = parseExpr(1);
    if (!cond) {
      syncToNextRule();
      continue;
    }

    const makaTok = peek();
    if (makaTok.type !== 'IDENT' || makaTok.lower !== 'maka') {
      errors.push(
        createDslError(
          makaTok.line,
          makaTok.column,
          'SYNTAX_ERROR',
          `Diharapkan kata kunci 'maka' setelah kondisi pada aturan '${nameTok.value}', tetapi ditemukan '${makaTok.value || 'akhir berkas'}'.`,
        ),
      );
      syncToNextRule();
      continue;
    }
    advance(); // consume 'maka'

    const action = parseAction();
    if (!action) {
      syncToNextRule();
      continue;
    }

    const bindingNodes = bindings.reduce(
      (acc, b) => acc + 1 + countExprNodes(b.expr),
      0,
    );
    const condNodes = countExprNodes(cond);
    const actionNodes =
      1 + action.args.reduce((acc, a) => acc + countExprNodes(a), 0);
    const totalNodes = 1 + bindingNodes + condNodes + actionNodes;

    const bindingDepth =
      bindings.length > 0
        ? Math.max(...bindings.map((b) => computeExprDepth(b.expr)))
        : 1;
    const condDepth = computeExprDepth(cond);
    const actionDepth =
      action.args.length > 0
        ? Math.max(...action.args.map((a) => computeExprDepth(a)))
        : 1;
    const maxDepth = Math.max(bindingDepth, condDepth, actionDepth);

    rules.push({
      kind: 'rule',
      name: nameTok.value,
      lowerName: nameTok.lower,
      nameSpan: { line: nameTok.line, column: nameTok.column },
      ...(bindings.length > 0 ? { bindings } : {}),
      condition: cond,
      action,
      nodeCount: totalNodes,
      maxDepth,
      span: { line: startTok.line, column: startTok.column },
    });
  }

  return { rules, errors };
}
