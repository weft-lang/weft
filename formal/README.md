# Weft Formal

Lean 4 formalization for the actual Weft language/kernel and its compiler
pipeline.

For rough theorem-progress tracking and checkpoint meaning, see `STATUS.md`.

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
    proved with the same whole-compiler composition theorem as the pure core,
    now strengthened with reverse compilation lemmas so successful staged
    compilations satisfy source/machine semantics `iff`s for both trace-only and
    result-carrying observations.
13. `Weft/Properties/CoreEffectTypecheckCorrectness.lean`,
    `Weft/Properties/CoreEffectSemanticSoundness.lean`,
    `Weft/Properties/CoreEffectSubtypeChecking.lean`
    The handled-effect checker now supports inferred type/effect recovery plus
    subtype-aware expected-type checking, and we can prove both that accepted
    programs only emit inferred effects and that empty-effect accepted programs
    compile to trace-free executions whose results inhabit the requested type.
14. `Weft/Properties/CoreEffectPipelineSemanticSoundness.lean`
    The staged handled-effect pipeline now carries those type and effect-trace
    guarantees all the way from surface syntax to emitted code, including direct
    machine-execution theorems for accepted compiled programs and behavior-level
    trace/result conformance for compiled machine semantics.
15. `Weft/CoreDNF.lean` + `Weft/Properties/CoreDNFSoundness.lean`
    A real DNF normalization layer for the finite core subtype algebra, with
    signed-constraint cubes, structural complement/distribution, normalization
    soundness, round-trip/idempotence semantics, and a DNF emptiness restatement
    of `A <: B` via normalization of `A & ~B`.
16. `Weft/TyDNF.lean` + `Weft/Properties/TyDNFSoundness.lean`
    An atomized DNF normalization layer for the full `Ty` surface: richer
    constructors are carried as opaque atoms, while union/intersection/complement
    normalize structurally. We now have semantic normalization soundness and
    idempotence for whole-`Ty` boolean structure, even before the final
    oracle-aware emptiness decision procedure exists.
17. `Weft/TyTheory.lean` + `Weft/Properties/TyTheorySoundness.lean`
    A theory-aware semantic layer over atomized whole-`Ty` DNF. We can now
    state kernel assumptions like atom implication and disjointness, prove that
    normalized unsatisfiability implies semantic subtyping under sound
    valuations, and instantiate that bridge with concrete kernel facts such as
    `rc T <: ptr T`, `mptr T <: ptr T`, and `bool & int` being empty.
18. `Weft/KernelModel.lean` + `Weft/Properties/KernelModelSoundness.lean`
    A concrete tag-level semantic model for the kernel atom theory. The new
    model gives explicit sound valuations for primitive tags, functions,
    records, nominals, and pointer flavors, then reuses the theory-aware
    subtyping theorems to show that concrete `rc` and `mptr` runtime tags
    inhabit `ptr` semantics and that `bool & int` is empty on every kernel tag.
19. `Weft/Properties/CoreKernelModelBridge.lean`
    A bridge from the finite `CoreSetTy` checker model to whole-`Ty` kernel-tag
    semantics for all representable boolean/set-theoretic types. This lifts the
    handled-effect expected-type theorems from `value.toCoreAtom` denotations to
    concrete whole-`Ty` semantic judgments over runtime tags, including staged
    machine/result behavior theorems.
20. `Weft/Properties/CoreEffectIOObservations.lean`
    The handled-effect compiler theorem now also lives over explicit generic
    `IOEvent.effectQuery` observations rather than only internal effect-name
    traces. We can state staged source/machine equivalence for those observed
    query/reply behaviors, prove pure accepted programs have empty observable
    traces, and show every observed event is exactly an oracle-mediated effect
    query already justified by the inferred effect set. The current handled
    fragment also now proves a negative observation result: emitted artifacts in
    this fragment cannot produce fake `stdin`/`stdout`/`alloc`/`file` events;
    their observable traces are entirely effect queries. Typed results remain
    tracked at the whole-`Ty` kernel-tag level.
21. `Weft/KernelSubtype.lean`
    A whole-`Ty` kernel-theory decision layer for normalized subtype
    obligations, exposed as `kernelSubtypeb`. It is now a genuinely computable
    structural checker rather than a classical `decide` wrapper: `Ty`,
    `TyAtom`, and normalized kernel obligations compare via explicit boolean
    equality/unsatisfiability procedures, and that executable layer already
    drives semantic soundness theorems showing compiled and staged executions
    respect requested whole-`Ty` kernel semantics beyond the old finite
    `CoreSetTy` fragment.
22. `Weft/Properties/CoreEffectBootstrap.lean`
    A bootstrap-parity bridge specialized to the staged handled-effect
    pipeline. It transfers semantic equivalence of surface compiler generations
    through staged compilation into semantic equivalence of their emitted
    machine artifacts, for both trace-only and result-carrying observable
    `IOEvent` behaviors. It also lifts the current typed/effect-disciplined
    contracts through that bridge, so later emitted artifacts inherit the pure
    trace-free and effect-bounded kernel-typed guarantees proved for earlier
    semantically equivalent compiler generations.

## Near-Term Expansion

- scale DNF normalization from the finite core to the real semantic subtype algebra
- extend the new computable whole-`Ty` kernel checker across richer semantic obligations such as record openness, nominal/trait/conformance, and effect-set structure
- grow the handled-effect observation layer into fuller runtime observations for `IO`, allocation, and unsafe boundaries
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
