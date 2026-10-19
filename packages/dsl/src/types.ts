export type DslValueType = 'angka' | 'bool' | 'komoditas' | 'pelabuhan';

export type DslStaticErrorCode =
  | 'SYNTAX_ERROR'
  | 'UNKNOWN_IDENT'
  | 'ARITY_MISMATCH'
  | 'TYPE_MISMATCH'
  | 'DUPLICATE_RULE'
  | 'RESERVED_NAME'
  | 'BAD_KEYWORD_ARG'
  | 'LIMIT_RULES'
  | 'LIMIT_NODES'
  | 'LIMIT_LENGTH'
  | 'LIMIT_DEPTH';

export type DslRuntimeErrorCode =
  | 'DIV_ZERO'
  | 'OVERFLOW'
  | 'BUDGET_EXCEEDED';

export interface DslValidationError {
  readonly line: number;
  readonly column: number;
  readonly code: DslStaticErrorCode;
  readonly message: string;
  readonly baris: number;
  readonly kolom: number;
  readonly kode: DslStaticErrorCode;
  readonly pesan: string;
}

export function createDslError(
  line: number,
  column: number,
  code: DslStaticErrorCode,
  message: string,
): DslValidationError {
  return {
    line,
    column,
    code,
    message,
    baris: line,
    kolom: column,
    kode: code,
    pesan: message,
  };
}

export interface DslLimitsConfig {
  readonly maxRules: number;
  readonly maxNodesPerRule: number;
  readonly maxSourceLength: number;
  readonly maxEvalBudget: number;
  readonly maxExprDepth: number;
}

export const DSL_DEFAULT_LIMITS: DslLimitsConfig = {
  maxRules: 16,
  maxNodesPerRule: 64,
  maxSourceLength: 4000,
  maxEvalBudget: 500,
  maxExprDepth: 12,
} as const;

export type DslBinaryOperator =
  | 'atau'
  | 'dan'
  | '<'
  | '<='
  | '>'
  | '>='
  | '=='
  | '!='
  | '+'
  | '-'
  | '*'
  | '/'
  | '%';

export type DslUnaryOperator = 'bukan' | '-';

export interface SourceSpan {
  readonly line: number;
  readonly column: number;
}

export type DslExprNode =
  | {
      readonly kind: 'number_literal';
      readonly raw: string;
      readonly value: bigint;
      readonly span: SourceSpan;
    }
  | {
      readonly kind: 'bool_literal';
      readonly value: boolean;
      readonly span: SourceSpan;
    }
  | {
      readonly kind: 'ident';
      readonly name: string;
      readonly lowerName: string;
      readonly span: SourceSpan;
    }
  | {
      readonly kind: 'keyword_arg';
      readonly keyword: 'maks' | 'semua';
      readonly span: SourceSpan;
    }
  | {
      readonly kind: 'paren';
      readonly expr: DslExprNode;
      readonly span: SourceSpan;
    }
  | {
      readonly kind: 'unary';
      readonly op: DslUnaryOperator;
      readonly operand: DslExprNode;
      readonly span: SourceSpan;
    }
  | {
      readonly kind: 'binary';
      readonly op: DslBinaryOperator;
      readonly left: DslExprNode;
      readonly right: DslExprNode;
      readonly span: SourceSpan;
    }
  | {
      readonly kind: 'call';
      readonly name: string;
      readonly lowerName: string;
      readonly args: readonly DslExprNode[];
      readonly span: SourceSpan;
    };

export interface DslLetBindingNode {
  readonly kind: 'let_binding';
  readonly name: string;
  readonly lowerName: string;
  readonly expr: DslExprNode;
  readonly span: SourceSpan;
}

export interface DslActionNode {
  readonly kind: 'action';
  readonly name: string;
  readonly lowerName: string;
  readonly args: readonly DslExprNode[];
  readonly span: SourceSpan;
}

export interface DslRuleNode {
  readonly kind: 'rule';
  readonly name: string;
  readonly lowerName: string;
  readonly nameSpan: SourceSpan;
  readonly bindings?: readonly DslLetBindingNode[];
  readonly condition: DslExprNode;
  readonly action: DslActionNode;
  readonly nodeCount: number;
  readonly maxDepth: number;
  readonly span: SourceSpan;
}

export interface CompiledDslProgram {
  readonly ast_version: 1;
  readonly rules: readonly DslRuleNode[];
}

export interface DslValidationResult {
  readonly valid: boolean;
  readonly errors: readonly DslValidationError[];
  readonly ast?: CompiledDslProgram;
}
