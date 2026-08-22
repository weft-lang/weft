; Weft local definitions and lexical scopes.

(block) @local.scope
(function_declaration) @local.scope
(lambda_expression) @local.scope
(for_expression) @local.scope
(match_arm) @local.scope
(handler_clause) @local.scope

(parameter name: (identifier) @local.definition)
(handler_parameter name: (identifier) @local.definition)
(handler_clause continuation: (identifier) @local.definition)
(function_declaration name: (function_name) @local.definition)
(let_expression pattern: (binding_pattern (identifier) @local.definition))
(for_expression pattern: (binding_pattern (identifier) @local.definition))
(match_arm pattern: (binding_pattern (identifier) @local.definition))

(identifier) @local.reference
