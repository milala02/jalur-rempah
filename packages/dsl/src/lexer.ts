import { DslValidationError, createDslError } from './types.js';

export type TokenType =
  | 'IDENT'
  | 'NUMBER'
  | 'COLON'
  | 'COMMA'
  | 'LPAREN'
  | 'RPAREN'
  | 'EQUALS'
  | 'OP'
  | 'EOF';

export interface Token {
  readonly type: TokenType;
  readonly value: string;
  readonly lower: string;
  readonly line: number;
  readonly column: number;
}

export interface TokenizeResult {
  readonly tokens: readonly Token[];
  readonly errors: readonly DslValidationError[];
}

function isAlpha(ch: string): boolean {
  const c = ch.charCodeAt(0);
  return (
    (c >= 65 && c <= 90) ||
    (c >= 97 && c <= 122) ||
    c === 95 // '_'
  );
}

function isDigit(ch: string): boolean {
  const c = ch.charCodeAt(0);
  return c >= 48 && c <= 57;
}

function isAlphaNumeric(ch: string): boolean {
  return isAlpha(ch) || isDigit(ch);
}

export function tokenizeDsl(source: string): TokenizeResult {
  const tokens: Token[] = [];
  const errors: DslValidationError[] = [];

  let i = 0;
  let line = 1;
  let col = 1;
  const len = source.length;

  while (i < len) {
    const ch = source[i]!;

    // Whitespace
    if (ch === ' ' || ch === '\t' || ch === '\r') {
      i += 1;
      col += 1;
      continue;
    }

    if (ch === '\n') {
      i += 1;
      line += 1;
      col = 1;
      continue;
    }

    // Comment (# until end of line)
    if (ch === '#') {
      while (i < len && source[i] !== '\n') {
        i += 1;
        col += 1;
      }
      continue;
    }

    const startLine = line;
    const startCol = col;

    // Single-char delimiters
    if (ch === ':') {
      tokens.push({
        type: 'COLON',
        value: ':',
        lower: ':',
        line: startLine,
        column: startCol,
      });
      i += 1;
      col += 1;
      continue;
    }
    if (ch === ',') {
      tokens.push({
        type: 'COMMA',
        value: ',',
        lower: ',',
        line: startLine,
        column: startCol,
      });
      i += 1;
      col += 1;
      continue;
    }
    if (ch === '(') {
      tokens.push({
        type: 'LPAREN',
        value: '(',
        lower: '(',
        line: startLine,
        column: startCol,
      });
      i += 1;
      col += 1;
      continue;
    }
    if (ch === ')') {
      tokens.push({
        type: 'RPAREN',
        value: ')',
        lower: ')',
        line: startLine,
        column: startCol,
      });
      i += 1;
      col += 1;
      continue;
    }

    // Two-character operators: <=, >=, ==, !=
    const nextCh = i + 1 < len ? source[i + 1]! : '';
    if (
      (ch === '<' && nextCh === '=') ||
      (ch === '>' && nextCh === '=') ||
      (ch === '=' && nextCh === '=') ||
      (ch === '!' && nextCh === '=')
    ) {
      const val = ch + nextCh;
      tokens.push({
        type: 'OP',
        value: val,
        lower: val,
        line: startLine,
        column: startCol,
      });
      i += 2;
      col += 2;
      continue;
    }

    // Single '=' assignment for `biar x = expr`
    if (ch === '=') {
      tokens.push({
        type: 'EQUALS',
        value: '=',
        lower: '=',
        line: startLine,
        column: startCol,
      });
      i += 1;
      col += 1;
      continue;
    }

    // Single-character operators: <, >, +, -, *, /, %
    if (
      ch === '<' ||
      ch === '>' ||
      ch === '+' ||
      ch === '-' ||
      ch === '*' ||
      ch === '/' ||
      ch === '%'
    ) {
      tokens.push({
        type: 'OP',
        value: ch,
        lower: ch,
        line: startLine,
        column: startCol,
      });
      i += 1;
      col += 1;
      continue;
    }

    // Numbers (non-negative decimal integer)
    if (isDigit(ch)) {
      let numStr = '';
      while (i < len && isDigit(source[i]!)) {
        numStr += source[i]!;
        i += 1;
        col += 1;
      }
      tokens.push({
        type: 'NUMBER',
        value: numStr,
        lower: numStr,
        line: startLine,
        column: startCol,
      });
      continue;
    }

    // Identifiers and keywords
    if (isAlpha(ch)) {
      let ident = '';
      while (i < len && isAlphaNumeric(source[i]!)) {
        ident += source[i]!;
        i += 1;
        col += 1;
      }
      tokens.push({
        type: 'IDENT',
        value: ident,
        lower: ident.toLowerCase(),
        line: startLine,
        column: startCol,
      });
      continue;
    }

    // Unexpected character
    errors.push(
      createDslError(
        startLine,
        startCol,
        'SYNTAX_ERROR',
        `Karakter tidak dikenal '${ch}' pada baris ${startLine}, kolom ${startCol}.`,
      ),
    );
    i += 1;
    col += 1;
  }

  tokens.push({
    type: 'EOF',
    value: '',
    lower: '',
    line,
    column: col,
  });

  return { tokens, errors };
}
