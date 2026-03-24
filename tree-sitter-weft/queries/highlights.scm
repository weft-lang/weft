; Weft syntax highlighting queries
; weft.now — set-theoretic types, algebraic effects, explicit memory

; ================================================================
; Keywords
; ================================================================

"fn" @keyword.function
"let" @keyword
"mut" @keyword.modifier
"type" @keyword
"trait" @keyword
"impl" @keyword
"for" @keyword
"in" @keyword
"effect" @keyword
"handle" @keyword
"use" @keyword.import

"if" @keyword.conditional
"else" @keyword.conditional
"match" @keyword.conditional
"while" @keyword.repeat
"loop" @keyword.repeat

"return" @keyword.return
"break" @keyword.return
"continue" @keyword.return
"resume" @keyword.return

"where" @keyword

; ================================================================
; Literals
; ================================================================

(integer) @number
(string) @string
(string_content) @string
(escape_sequence) @string.escape
(interpolation "{" @punctuation.special)
(interpolation "}" @punctuation.special)
(interpolation (identifier) @variable)
(boolean) @boolean
(nil_literal) @constant.builtin

; ================================================================
; Types
; ================================================================

(primitive_type) @type.builtin
(never_type) @type.builtin
(type_identifier) @type

; ================================================================
; Functions
; ================================================================

(function_declaration
  name: (identifier) @function)

(function_signature
  name: (identifier) @function)

(call_expression
  function: (identifier) @function.call)

(generic_call_expression
  function: (identifier) @function.call)

(method_call_expression
  method: (identifier) @function.method)

; ================================================================
; Parameters and variables
; ================================================================

(parameter
  name: (identifier) @variable.parameter)

(parameter
  label: (identifier) @variable.parameter)

(for_expression
  variable: (identifier) @variable)

(let_expression
  name: (identifier) @variable)

(let_mut_expression
  name: (identifier) @variable)

(identifier) @variable

; ================================================================
; Fields
; ================================================================

(field_expression
  field: (identifier) @property)

(optional_chain_expression
  field: (identifier) @property)

(record_field
  name: (identifier) @property)

(field_initializer
  name: (identifier) @property)

; ================================================================
; Effects
; ================================================================

(effect_declaration
  name: (type_identifier) @type)

(handler_clause
  effect: (type_identifier) @type)

(handler_clause
  operation: (identifier) @function.method)

(effect_list
  (type_identifier) @attribute)

; ================================================================
; Operators
; ================================================================

(binary_expression
  operator: _ @operator)

(unary_expression
  "not" @operator)

(unary_expression
  "-" @operator)

"|>" @operator
"->" @punctuation.special
"=>" @punctuation.special
"-[" @punctuation.special
"]>" @punctuation.special
".." @operator
"?." @operator

; Keyword operators
"and" @keyword.operator
"or" @keyword.operator
"not" @keyword.operator
"band" @keyword.operator
"bor" @keyword.operator
"bxor" @keyword.operator
"bshl" @keyword.operator
"bshr" @keyword.operator

; ================================================================
; Punctuation
; ================================================================

"(" @punctuation.bracket
")" @punctuation.bracket
"{" @punctuation.bracket
"}" @punctuation.bracket
"[" @punctuation.bracket
"]" @punctuation.bracket
"<" @punctuation.bracket
">" @punctuation.bracket

"," @punctuation.delimiter
":" @punctuation.delimiter
"." @punctuation.delimiter
";" @punctuation.delimiter

; ================================================================
; Comments
; ================================================================

(doc_comment) @comment.documentation
(line_comment) @comment

; ================================================================
; Patterns
; ================================================================

(wildcard_pattern) @variable.builtin

(constructor_pattern
  name: (type_identifier) @constructor)

; ================================================================
; Match arms
; ================================================================

(match_arm
  pattern: (binding_pattern
    (identifier) @variable))
