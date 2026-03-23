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
8. `Weft/CoreSubtype.lean` + `Weft/Properties/CoreSubtypeSoundness.lean`
   A finite semantic core for union/intersection/complement, with decision
   procedures for emptiness and subtyping plus proofs that subtyping is exactly
   emptiness of `A & ~B` on the finite model.
9. `Weft/Properties/CoreTypecheckCorrectness.lean`
   The staged core checker now has a proved specification: inferred types are
   sound, complete for the safety core, and unique.
10. `Weft/Properties/CoreSubtypeChecking.lean`
    A subtype-aware checking layer over inferred core types, with proofs that a
    successful expected-type check is both complete for the representable core
    fragment and semantically respected by evaluation results.
11. `Weft/CoreEffectMachine.lean` + `Weft/Properties/CoreEffectCompilerCorrectness.lean`
    A concrete effectful compiler target for handled effects, with exact
    preservation of both result values and effect traces through compilation.
12. `Weft/CoreEffectPipeline.lean` + `Weft/Properties/CoreEffectPipelineCorrectness.lean`
    A staged handled-effect pipeline, parameterized by the effect oracle and
    proved with the same whole-compiler composition theorem as the pure core.

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
