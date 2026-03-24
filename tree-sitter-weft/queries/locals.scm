; Weft local variable scoping queries

; Scopes
(block) @local.scope
(function_declaration) @local.scope
(lambda_expression) @local.scope
(for_expression) @local.scope
(match_arm) @local.scope
(handler_clause) @local.scope

; Definitions
(let_expression
  name: (identifier) @local.definition)

(let_mut_expression
  name: (identifier) @local.definition)

(parameter
  name: (identifier) @local.definition)

(function_declaration
  name: (identifier) @local.definition)

(for_expression
  variable: (identifier) @local.definition)

; References
(identifier) @local.reference
