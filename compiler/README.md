# Compiler modules

The compiler is a Weft package. Its public extension contracts live in the
standard library; importing compiler internals is not the grammar package ABI.

```text
compiler/
  main.weft             CLI and tool handler configurations
  pipeline.weft         compilation orchestration and remaining pass implementation
  weft/                 Weft's own language implementation
    grammar.weft        public Grammar implementation
    check.weft          public CheckedGrammar implementation
    check/              checker storage, bodies, and host-type interpretation
    syntax/             declarations, imports, literals, and concrete syntax graph
    facts/              Weft semantic fact producers
    unicode/            generated language tables
  source/               retained inputs, loading, provenance, and trust policy
  diagnostic/           diagnostic observation, locations, and rendering
  types/                type algebra
  ir/                   internal representations and control-flow analysis
  grammar/              grammar data and interpretation infrastructure
  comptime/             compile-time execution and observed artifact inputs
  project/              sessions, module identity, and reusable checked products
  package/              package resolution, exports, native declarations, and locks
  sdk/                  embedded source archive and product identity
  backend/              native targets, link graphs, and binary formats
    aarch64/            encoding and native code generation
  storage.weft          private compiler storage helpers
```

Use the owning namespace instead of adding flat, prefixed sibling modules.
Import modules under a descriptive local namespace when it makes call sites
clearer, such as `tree_sitter.render(grammar)`. Do not add forwarding modules at
old paths, duplicate representations, or new wildcard trust roots to accommodate
a move. Update source fixtures, generated-source producers, tools, and recursive
source discovery together.

Namespace placement describes ownership, not a claim that all dependencies have
already been separated. The pipeline still contains substantial pass code;
the internal IR still includes surface syntax adapters; grammar registration
and compile-time dispatch still contain guest-specific integration. Removing
those dependencies requires completing the shared semantic contracts, not
renaming them or declaring them public.

Source acquisition and package authority belong to the host, outside a grammar's
parse/check capabilities. Weft-specific syntax and semantic decisions belong
under `weft/`. Shared interpreters accept data: the Tree-sitter renderer consumes
a `SyntaxGrammar`; its command-line caller chooses the Weft syntax graph.

Native and trust-sensitive relocations must remain bootstrappable from the
checked-in root. Until that root knows their new exact paths, `macho.weft`,
`object.weft`, and `source_registration.weft` remain at their old locations.
The identifier table also remains at the old checkout-detection marker until
the refreshed root uses `main.weft`. Remove those old locations and transition
permissions after the canonical root refresh; do not retain compatibility APIs.
