; Weft syntax highlighting for the current compiler surface.

[ "fn" "let" "const" "type" "trait" "impl" "effect" "test" ] @keyword
[ "pub" "private" "package" "mut" "where" "with" "defer" ] @keyword.modifier
"use" @keyword.import
[ "if" "else" "match" ] @keyword.conditional
[ "while" "for" "in" "loop" ] @keyword.repeat
[ "return" "break" "resume" ] @keyword.return
(continue_expression) @keyword.return
"handle" @keyword

(integer) @number
(float) @number.float
(string) @string
(boolean) @boolean
(nil_literal) @constant.builtin
(nil_pattern) @constant.builtin
(self_expression) @variable.builtin

(primitive_type) @type.builtin
(self_type) @type.builtin
(type_identifier) @type
(constant_identifier) @constant
(ownership_type ownership: _ @keyword.modifier)

(type_declaration name: (type_identifier) @type.definition)
(trait_declaration name: (type_identifier) @type.definition)
(effect_declaration name: (type_identifier) @type.definition)
(variant name: (type_identifier) @constructor)
(constructor_expression constructor: _ @constructor)
(constructor_pattern name: (type_identifier) @constructor)
(qualified_constructor_pattern name: (type_identifier) @constructor)

(function_declaration name: (function_name) @function)
(function_signature name: (function_name) @function)
(call_expression function: (identifier) @function.call)
(call_expression
  function: (field_expression field: (identifier) @function.method))
(handler_clause operation: (identifier) @function.method)

(parameter name: (identifier) @variable.parameter)
(parameter label: (identifier) @variable.parameter)
(handler_parameter name: (identifier) @variable.parameter)
(handler_clause continuation: (identifier) @variable.parameter)
(let_expression pattern: (binding_pattern (identifier) @variable))
(for_expression pattern: (binding_pattern (identifier) @variable))
(field_expression field: (identifier) @property)
(optional_chain_expression field: (identifier) @property)
(record_field name: (identifier) @property)
(record_type_field name: (identifier) @property)
(field_initializer name: (identifier) @property)
(record_pattern_field name: (identifier) @property)
(use_path root: (identifier) @module)
(use_path segment: (identifier) @module)

(binary_expression operator: _ @operator)
(unary_expression operator: _ @operator)
[ "=" "|>" ".." "?." ".*" ".{" "?" ] @operator
[ "and" "or" "not" "band" "bor" "bxor" "bshl" "bshr" ] @keyword.operator
[ "->" "=>" "-[" "]>" ] @punctuation.special

[ "(" ")" "{" "}" "[" "]" "<" ">" ] @punctuation.bracket
[ "," ":" "." ";" ] @punctuation.delimiter

(wildcard_pattern) @variable.builtin
(doc_comment) @comment.documentation
(line_comment) @comment
