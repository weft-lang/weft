# Formal Theorem Status

This file tracks what the current Lean development buys us toward the end goal:

> a full end-to-end theorem for the self-hosted Weft compiler, with well-founded
> semantic support for parsing, checking, lowering, code generation, object
> emission, runtime effects, and observable input/output behavior across
> bootstrap generations.

The percentages below are deliberately rough. They are here to keep us honest
about what is still missing, not to pretend the remaining work is linear.

## Overall Progress

Roughly **47%** of the way to the complete theorem.

That estimate is based on:

- the staged compiler theorem backbone being in place
- concrete source-to-machine theorems existing for pure and handled-effect cores
- result/effect semantic soundness already reaching emitted code
- DNF/subtyping work moving beyond the tiny finite core
- but the real runtime, unsafe/alloc boundaries, continuation semantics, and
  native object-format bridge still being mostly unproved

## Progress By Area

| Area | Rough Status | What is done |
|------|--------------|--------------|
| Compiler composition backbone | 90% | Generic stage-composition theorem and bootstrap-stability shape are in place. |
| Pure core source-to-machine correctness | 85% | Concrete compiler, staged pipeline, and typed-result preservation are proved. |
| Handled-effect core correctness | 80% | Trace-preserving compilation, staged effectful compiler theorem, and machine-level effect/result conformance are proved. |
| Result-carrying semantic observations | 70% | Successful staged compilations now preserve and reflect trace/result behaviors. |
| Set-theoretic normalization/subtyping | 56% | Finite core DNF/subtype theorem is proved, whole-`Ty` boolean structure normalizes to an atomized DNF semantics, theory-aware unsatisfiability implies semantic subtyping under sound valuations, and the kernel theory now has a concrete tag-level semantic model. Full executable oracle-backed semantic subtyping is still missing. |
| Runtime semantics (`IO`, `Alloc`, `Unsafe`) | 10% | Only abstract observable behavior scaffolding exists so far. |
| Continuations / handler operational model | 10% | Tail-resumptive handled-effect core exists, but full continuation semantics is not yet formalized. |
| Native backend / object emission bridge | 10% | Machine model exists for core targets, but not a real aarch64/Mach-O semantic bridge. |
| Self-hosted whole-compiler theorem | 5% | The theorem shape exists, but it is not yet connected to the real compiler/runtime stack. |

## What Each Checkpoint Means

Current frontier:

- kernel tag semantic model
  The atom theory is no longer justified only by abstract “sound valuations.”
  We now have a concrete tag-level interpretation for primitive values,
  functions, records, nominals, and pointer flavors, plus proofs that the
  kernel theory is sound for those tags. Concretely: `rc` and `mptr` values now
  inhabit `ptr` semantics in an actual model, which is a real step from
  theorem-shape subtyping toward theorem-shape runtime semantics.

- theory-aware atomized subtype rules
  The whole-`Ty` DNF layer is no longer purely structural. We now have an
  explicit semantic theory of atom implication/disjointness and a proof bridge
  from normalized unsatisfiability to semantic subtyping under sound
  valuations. Concretely, this is the first whole-`Ty` step where kernel facts
  like `rc T <: ptr T` live in the theorem story rather than only in prose.

- `a61a4eb` `formal: add theory-aware atomized subtype rules`
  The atomized whole-`Ty` DNF layer now supports explicit implication and
  disjointness assumptions with proofs that normalized unsatisfiability implies
  semantic subtyping under any valuation respecting those assumptions.
  Concretely: the formal development can now express kernel facts like
  `rc T <: ptr T` at the whole-`Ty` semantic level instead of only inside the
  tiny finite core.

- `0e9dee2` `formal: prove staged effect compiler equivalence`
  Successful staged handled-effect compilations are no longer only forward
  preserving. We can also recover source evaluations from compiled executions.
  This is the point where the compiler theorem becomes an `iff` for the current
  effectful fragment.

- `72b2a44` `formal: constrain compiled effect behaviors`
  The machine semantics themselves now satisfy inferred effect bounds. This
  moved effect discipline from source-level executions to compiled behaviors.

- `0a072f8` `formal: carry result semantics through effects`
  The staged theorem now tracks runtime results as part of observed behavior,
  not just traces and exit codes. This is a prerequisite for stating typed
  output correctness semantically.

- `1386cc6` `formal: normalize finite subtype core to dnf`
  The finite set-theoretic core now has a real DNF normalization story instead
  of only pointwise boolean checks. This is the bridge from the tiny finite
  model toward the full Weft type algebra.

- `d9205ad` `formal: normalize whole ty boolean structure`
  This extends normalization beyond the finite core. The theorem gain is not
  yet a full subtyping decision procedure, but we now normalize the real `Ty`
  boolean surface (`|`, `&`, `~`) over opaque rich atoms, prove semantic
  soundness of that normalization, and get semantic idempotence for repeated
  normalization. Concretely: this is the step that makes “real Weft types in
  DNF” true at the normalization layer, even before pointer/record/trait/effect
  semantics are plugged in.

## Current Critical Path

1. Scale DNF normalization from the finite core to the real `Ty` surface with
   opaque atoms for richer constructors.
2. Replace opaque atoms with real semantic relations where the kernel requires
   them: pointer variance, record openness, nominal/trait/conformance, effect
   sets, and eventually continuation-sensitive handler semantics.
3. Push the staged compiler theorem outward to real observable runtime events:
   `IO`, allocation, unsafe boundaries, object emission, and bootstrap parity.

## Missing For The Full Theorem

- full semantic subtyping for real Weft types
- open/closed record semantics
- pointer and RC subtyping semantics
- trait/conformance oracle integration
- full effect-set algebra beyond the handled bool core
- one-shot continuation semantics and handler discharge for the full language
- runtime semantics for `IO`, `Alloc`, and `Unsafe`
- lowering/codegen correctness for real Weft IR
- aarch64 / Mach-O semantic correspondence
- theorem stated over the self-hosted compiler artifacts rather than the current
  core surrogates
