# Weft Formal

Lean 4 formalization for the actual Weft language/kernel and its compiler
pipeline.

The point of this directory is not to prove facts about a cute surrogate
calculus and stop there. The target is the real architecture described in
`internal/docs/kernel.md` and `internal/briefs/design/compiler-as-data.md`:

- set-theoretic types
- effect sets and handler discharge
- explicit unsafe and allocation boundaries
- compiler-as-data pipeline
- end-to-end observable I/O semantics
- self-hosted bootstrap parity

## Current Shape

The first cut lands three things:

1. `Weft/Types.lean`, `Weft/Effects.lean`, `Weft/Syntax.lean`
   A kernel-shaped formal surface for types, capabilities, syntax, and modules.
2. `Weft/SafetyCore.lean` + `Weft/Properties/TypeSafetyCore.lean`
   A proved no-stuck theorem for a core expression fragment.
3. `Weft/Compiler.lean` + `Weft/Properties/CompilerCorrectness.lean`
   A generic end-to-end stage-composition theorem over full observable I/O
   behaviors, including the bootstrap-parity shape we need for self-hosting.
4. `Weft/CoreMachine.lean` + `Weft/Properties/CoreCompilerCorrectness.lean`
   A concrete verified compiler for the proved safety core, giving a real
   source-to-machine preservation theorem rather than only abstract stage laws.
5. `Weft/Properties/CoreSemanticSoundness.lean`
   The compiled result still inhabits the source type for the safety-core
   fragment, so the formal story now has both semantic preservation and typed
   result preservation.
6. `Weft/CorePipeline.lean` + `Weft/Properties/CorePipelineCorrectness.lean`
   A genuinely staged core compiler theorem: surface syntax -> parsed core ->
   checked core -> lowered IR -> machine code, with preservation proved at each
   stage and composed through the generic pipeline theorem.
7. `Weft/CoreEffects.lean` + `Weft/Properties/CoreEffectSoundness.lean`
   A handled-effect core with explicit capability typing and proofs that
   evaluation traces stay within the declared effect set and that handling
   actually confines the handled effect.

## Near-Term Expansion

- real semantic subtyping / DNF normalization
- effect handler operational semantics and discharge proofs
- one-shot continuation linearity
- unsafe boundary and allocation confinement theorems
- lowering correctness
- aarch64 / Mach-O semantic bridge
- whole compiler certification

## Commands

```bash
cd formal
lake build
```

If Lean is not configured globally, a local install can be bootstrapped with a
custom `ELAN_HOME`, for example:

```bash
ELAN_HOME=/tmp/weft-elan elan toolchain install leanprover/lean4:v4.29.0-rc2
ELAN_HOME=/tmp/weft-elan lake build
```
