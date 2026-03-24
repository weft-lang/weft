/// <reference types="tree-sitter-cli/dsl" />
// tree-sitter grammar for the Weft programming language
// weft.now — set-theoretic types, algebraic effects, explicit memory

const PREC = {
  ASSIGN:     1,
  RANGE:      2,
  PIPE:       3,
  OR:         4,
  AND:        5,
  COMPARE:    6,
  BITOR:      7,
  BITXOR:     8,
  BITAND:     9,
  SHIFT:      10,
  ADD:        11,
  MULTIPLY:   12,
  UNARY:      13,
  POSTFIX:    14,
  CALL:       15,
  FIELD:      16,
};

module.exports = grammar({
  name: 'weft',

  extras: $ => [/\s/, $.line_comment, $.doc_comment],

  word: $ => $.identifier,

  supertypes: $ => [$._expression, $._declaration, $._type, $._pattern],

  conflicts: $ => [],

  rules: {
    source_file: $ => repeat($._declaration),

    // ================================================================
    // Declarations
    // ================================================================

    _declaration: $ => choice(
      $.function_declaration,
      $.type_declaration,
      $.trait_declaration,
      $.impl_block,
      $.effect_declaration,
      $.use_declaration,
    ),

    use_declaration: $ => seq('use', field('path', $.string)),

    function_declaration: $ => seq(
      'fn',
      field('name', $.identifier),
      optional(field('type_parameters', $.type_parameters)),
      field('parameters', $.parameters),
      optional(field('return_type', $._return_type)),
      optional(field('where_clause', $.where_clause)),
      field('body', $.block),
    ),

    type_declaration: $ => seq(
      'type',
      field('name', $.type_identifier),
      optional(field('type_parameters', $.type_parameters)),
      '{', field('body', choice($.record_body, $.variant_body)), '}',
    ),

    record_body: $ => commaSep1($.record_field),
    record_field: $ => seq(field('name', $.identifier), ':', field('type', $._type)),

    variant_body: $ => commaSep1($.variant),
    variant: $ => seq(
      field('name', $.type_identifier),
      optional(field('payload', $.variant_payload)),
    ),
    variant_payload: $ => seq('(', commaSep1($._type), ')'),

    trait_declaration: $ => seq(
      'trait', field('name', $.type_identifier),
      optional(field('type_parameters', $.type_parameters)),
      '{', repeat($.function_signature), '}',
    ),

    function_signature: $ => seq(
      'fn', field('name', $.identifier),
      field('parameters', $.parameters),
      optional(field('return_type', $._return_type)),
    ),

    impl_block: $ => seq(
      'impl',
      optional(field('impl_type_parameters', $.type_parameters)),
      choice(
        seq(field('trait', $.type_identifier), 'for', field('type', $.type_identifier)),
        field('type', $.type_identifier),
      ),
      '{', repeat($.function_declaration), '}',
    ),

    effect_declaration: $ => seq(
      'effect', field('name', $.type_identifier),
      '{', repeat($.function_signature), '}',
    ),

    // ================================================================
    // Parameters and return types
    // ================================================================

    parameters: $ => seq('(', commaSep($.parameter), ')'),
    parameter: $ => seq(field('name', $.identifier), ':', field('type', $._type)),

    _return_type: $ => choice($.pure_return_type, $.effect_return_type),
    pure_return_type: $ => seq('->', field('type', $._type)),
    effect_return_type: $ => seq('-[', field('effects', $.effect_list), ']>', field('type', $._type)),
    effect_list: $ => commaSep1($.type_identifier),

    type_parameters: $ => seq('<', commaSep1($.type_parameter), '>'),
    type_parameter: $ => seq(
      field('name', $.type_identifier),
      optional(seq(':', field('bound', $.type_bound))),
    ),
    type_bound: $ => seq($._type, repeat(seq('&', $._type))),

    where_clause: $ => seq('where', commaSep1($.where_predicate)),
    where_predicate: $ => seq(field('type', $.type_identifier), ':', field('bound', $.type_bound)),

    // ================================================================
    // Types
    // ================================================================

    _type: $ => choice(
      $.primitive_type,
      $.type_identifier,
      $.generic_type,
      $.union_type,
      $.intersection_type,
      $.complement_type,
      $.optional_type,
      $.function_type,
      $.parenthesized_type,
      $.never_type,
    ),

    primitive_type: $ => choice('i64', 'str', 'bool', 'nil'),
    never_type: $ => 'never',

    generic_type: $ => prec(PREC.CALL, seq(field('name', $.type_identifier), '<', commaSep1($._type), '>')),
    union_type: $ => prec.left(1, seq(field('left', $._type), '|', field('right', $._type))),
    intersection_type: $ => prec.left(2, seq(field('left', $._type), '&', field('right', $._type))),
    complement_type: $ => prec(3, seq('~', field('type', $._type))),
    optional_type: $ => prec.left(4, seq(field('type', $._type), '?')),
    function_type: $ => seq(
      '(', commaSep($._type), ')',
      choice(
        seq('->', field('return_type', $._type)),
        seq('-[', field('effects', $.effect_list), ']>', field('return_type', $._type)),
      ),
    ),
    parenthesized_type: $ => seq('(', $._type, ')'),

    // ================================================================
    // Statements (inside blocks)
    // ================================================================

    _statement: $ => choice(
      $.let_statement,
      $.let_mut_statement,
      $.assignment_statement,
      $.expression_statement,
    ),

    let_statement: $ => seq(
      'let', field('name', $.identifier),
      optional(seq(':', field('type', $._type))),
      '=', field('value', $._expression),
    ),

    let_mut_statement: $ => seq(
      'let', 'mut', field('name', $.identifier),
      optional(seq(':', field('type', $._type))),
      '=', field('value', $._expression),
    ),

    assignment_statement: $ => prec.right(PREC.ASSIGN, seq(
      field('name', $.identifier),
      '=', field('value', $._expression),
    )),

    expression_statement: $ => $._expression,

    block: $ => seq('{', repeat($._statement), '}'),

    // ================================================================
    // Expressions
    // ================================================================

    _expression: $ => choice(
      $.identifier,
      $.type_identifier,
      $.integer,
      $.string,
      $.boolean,
      $.nil_literal,
      $.binary_expression,
      $.unary_expression,
      $.call_expression,
      $.method_call_expression,
      $.field_expression,
      $.optional_chain_expression,
      $.pipe_expression,
      $.try_expression,
      $.if_expression,
      $.if_let_expression,
      $.match_expression,
      $.while_expression,
      $.for_expression,
      $.loop_expression,
      $.handle_expression,
      $.resume_expression,
      $.return_expression,
      $.break_expression,
      $.continue_expression,
      $.lambda_expression,
      $.block,
      $.variant_expression,
      $.record_expression,
      $.parenthesized_expression,
    ),

    integer: $ => /[0-9]+/,

    string: $ => seq(
      '"',
      repeat(choice($.interpolation, $.escape_sequence, $.string_content)),
      '"',
    ),
    string_content: $ => token.immediate(prec(1, /[^"\\{]+/)),
    escape_sequence: $ => token.immediate(seq('\\', choice('n', 't', '\\', '"', '0'))),
    interpolation: $ => seq(
      token.immediate(prec(2, '{')),
      field('expression', $.identifier),
      '}',
    ),

    boolean: $ => choice('true', 'false'),
    nil_literal: $ => 'nil',

    binary_expression: $ => {
      const table = [
        [PREC.RANGE,    '..'],
        [PREC.OR,       'or'],
        [PREC.AND,      'and'],
        [PREC.COMPARE,  choice('==', '!=', '<', '>', '<=', '>=')],
        [PREC.BITOR,    'bor'],
        [PREC.BITXOR,   'bxor'],
        [PREC.BITAND,   'band'],
        [PREC.SHIFT,    choice('bshl', 'bshr')],
        [PREC.ADD,      choice('+', '-')],
        [PREC.MULTIPLY, choice('*', '/', '%')],
      ];
      return choice(...table.map(([precedence, operator]) =>
        prec.left(precedence, seq(
          field('left', $._expression),
          field('operator', operator),
          field('right', $._expression),
        ))
      ));
    },

    unary_expression: $ => choice(
      prec(PREC.UNARY, seq('not', field('operand', $._expression))),
      prec(PREC.UNARY, seq(field('operator', '-'), field('operand', $._expression))),
    ),

    call_expression: $ => prec(PREC.CALL, seq(
      field('function', $.identifier), '(', commaSep($._expression), ')',
    )),

    method_call_expression: $ => prec.left(PREC.FIELD + 1, seq(
      field('receiver', $._expression), '.', field('method', $.identifier), '(', commaSep($._expression), ')',
    )),

    field_expression: $ => prec.left(PREC.FIELD, seq(
      field('receiver', $._expression), '.', field('field', $.identifier),
    )),

    optional_chain_expression: $ => prec.left(PREC.FIELD, seq(
      field('receiver', $._expression), '?.', field('field', $.identifier),
    )),

    pipe_expression: $ => prec.left(PREC.PIPE, seq(
      field('value', $._expression), '|>', field('function', $._expression),
    )),

    try_expression: $ => prec.left(PREC.POSTFIX, seq(
      field('expression', $._expression), token.immediate('?'),
    )),

    if_expression: $ => prec.right(seq(
      'if', field('condition', $._expression),
      field('consequence', $.block),
      optional(seq('else', field('alternative', choice($.block, $.if_expression)))),
    )),

    if_let_expression: $ => prec.right(seq(
      'if', 'let', field('pattern', $._pattern),
      '=', field('value', $._expression),
      field('consequence', $.block),
      optional(seq('else', field('alternative', choice($.block, $.if_expression)))),
    )),

    match_expression: $ => seq(
      'match', field('value', $._expression),
      '{', repeat($.match_arm), '}',
    ),

    match_arm: $ => seq(
      field('pattern', $._pattern),
      optional(seq('if', field('guard', $._expression))),
      '->', field('body', $._expression),
    ),

    while_expression: $ => seq('while', field('condition', $._expression), field('body', $.block)),
    for_expression: $ => seq('for', field('variable', $.identifier), 'in', field('iterator', $._expression), field('body', $.block)),
    loop_expression: $ => seq('loop', field('body', $.block)),

    handle_expression: $ => seq(
      'handle', field('expression', $._expression),
      '{', repeat($.handler_clause), '}',
    ),

    handler_clause: $ => seq(
      field('effect', $.type_identifier), '.', field('operation', $.identifier),
      '(', commaSep($.identifier), ')',
      '->', field('body', $._expression),
    ),

    resume_expression: $ => seq('resume', '(', field('value', $._expression), ')'),
    return_expression: $ => prec.right(seq('return', optional(field('value', $._expression)))),
    break_expression: $ => prec.right(seq('break', optional(seq('(', field('value', $._expression), ')')))),
    continue_expression: $ => 'continue',

    lambda_expression: $ => prec.right(-1, seq(
      choice(
        field('parameter', $.identifier),
        seq('(', commaSep(choice($.parameter, $.identifier)), ')'),
      ),
      '=>', field('body', $._expression),
    )),

    variant_expression: $ => prec(PREC.CALL, seq(
      field('name', $.type_identifier), '(', commaSep1($._expression), ')',
    )),

    record_expression: $ => prec(PREC.CALL, seq(
      field('type', $.type_identifier), '{', commaSep1($.field_initializer), '}',
    )),

    field_initializer: $ => seq(field('name', $.identifier), ':', field('value', $._expression)),

    parenthesized_expression: $ => seq('(', $._expression, ')'),

    // ================================================================
    // Patterns
    // ================================================================

    _pattern: $ => choice(
      $.wildcard_pattern,
      $.binding_pattern,
      $.integer_pattern,
      $.constructor_pattern,
      $.boolean,
    ),

    wildcard_pattern: $ => '_',
    binding_pattern: $ => $.identifier,
    integer_pattern: $ => $.integer,
    constructor_pattern: $ => seq(
      field('name', $.type_identifier),
      optional(seq('(', commaSep1($._pattern), ')')),
    ),

    // ================================================================
    // Identifiers and comments
    // ================================================================

    identifier: $ => /[a-z_][a-zA-Z0-9_]*/,
    type_identifier: $ => /[A-Z][a-zA-Z0-9_]*/,

    doc_comment: $ => token(prec(1, seq('---', /[^\n]*/))),
    line_comment: $ => token(seq('--', /[^\n]*/)),
  },
});

function commaSep(rule) { return optional(commaSep1(rule)); }
function commaSep1(rule) { return seq(rule, repeat(seq(',', rule)), optional(',')); }
