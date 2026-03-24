# Formal Theorem Status

This file tracks what the current Lean development buys us toward the end goal:

> a full end-to-end theorem for the self-hosted Weft compiler, with well-founded
> semantic support for parsing, checking, lowering, code generation, object
> emission, runtime effects, and observable input/output behavior across
> bootstrap generations.

The percentages below are deliberately rough. They are here to keep us honest
about what is still missing, not to pretend the remaining work is linear.

## Overall Progress

Roughly **58%** of the way to the complete theorem.

That estimate is based on:

- the staged compiler theorem backbone being in place
- concrete source-to-machine theorems existing for pure and handled-effect cores
- result/effect semantic soundness already reaching emitted code
- handled-effect observations now lifted into explicit generic `IOEvent`
  query/reply behaviors rather than only raw effect-name traces
- whole-`Ty` kernel subtype obligations can now feed expected-type theorems for
  compiled and staged executions rather than stopping at the `CoreSetTy`
  representable fragment
- DNF/subtyping work moving beyond the tiny finite core
- but the real runtime, unsafe/alloc boundaries, continuation semantics, and
  native object-format bridge still being mostly unproved

## Progress By Area

| Area | Rough Status | What is done |
|------|--------------|--------------|
| Compiler composition backbone | 90% | Generic stage-composition theorem and bootstrap-stability shape are in place. |
| Pure core source-to-machine correctness | 85% | Concrete compiler, staged pipeline, and typed-result preservation are proved. |
| Handled-effect core correctness | 80% | Trace-preserving compilation, staged effectful compiler theorem, and machine-level effect/result conformance are proved. |
| Result-carrying semantic observations | 87% | Successful staged compilations now preserve and reflect trace/result behaviors, representable expected types can be restated at the whole-`Ty` kernel-tag semantic level, the handled-effect fragment has explicit query/reply observation theorems in the generic `IOEvent` space, and staged/compiled expected-type theorems now also work through the whole-`Ty` kernel subtype layer rather than only the finite `CoreSetTy` bridge. |
| Set-theoretic normalization/subtyping | 64% | Finite core DNF/subtype theorem is proved, whole-`Ty` boolean structure normalizes to an atomized DNF semantics, theory-aware unsatisfiability implies semantic subtyping under sound valuations, the kernel theory has a concrete tag-level semantic model with explicit pointer-flavor separation facts such as `rc T & mptr U` being empty, and there is now a theorem-facing whole-`Ty` kernel subtype decision layer. A fully computable/extracted whole-`Ty` checker is still missing. |
| Runtime semantics (`IO`, `Alloc`, `Unsafe`) | 23% | We now have a concrete tag-level semantic model for runtime values plus explicit observable query/reply event semantics for the handled-effect fragment, and we can already rule out impossible runtime tag overlaps like `rc`/`mptr` collisions. Full `IO`/allocation/unsafe runtime behaviors are still missing. |
| Continuations / handler operational model | 10% | Tail-resumptive handled-effect core exists, but full continuation semantics is not yet formalized. |
| Native backend / object emission bridge | 10% | Machine model exists for core targets, but not a real aarch64/Mach-O semantic bridge. |
| Self-hosted whole-compiler theorem | 7% | The theorem shape exists and its handled-effect fragment now speaks in generic observable `IOEvent` behaviors, but it is not yet connected to the real compiler/runtime stack. |

## What Each Checkpoint Means

Current frontier:

- whole-`Ty` kernel subtype checking for compiled/staged expected-type theorems
  The formal development no longer has to route every expected-type theorem
  through the finite `CoreSetTy.ofTy` bridge. We now have a kernel-theory
  boolean decision layer over normalized whole-`Ty` subtype obligations, and we
  use it to prove that compiled and staged executions respect requested
  whole-`Ty` kernel semantics even when the target type lies outside the old
  tiny boolean fragment. Concretely: the compiler theorem’s expected-type side
  has started moving from the surrogate finite checker model into the actual
  whole-`Ty` kernel theory.

- pointer-flavor separation in the kernel tag model
  The kernel theory now distinguishes `rc` and `mptr` values semantically, not
  just by constructor names in the syntax. We prove their intersection is empty
  in the theory-aware DNF layer and in the concrete kernel-tag model.
  Concretely: the formal runtime story can now rule out a class of impossible
  aliasing/tag-collision cases instead of leaving them as unstated intuition.

- generic `IOEvent` query/reply observations for compiled handled effects
  The handled-effect theorem no longer has to speak only in internal
  `List EffectName` traces. We now interpret compiled and staged executions as
  generic observable `IOEvent` behaviors carrying explicit effect-query replies,
  prove source/machine equivalence at that level, and show every observed event
  is already justified by the inferred effect set. Concretely: the theorem now
  talks in a runtime-observation language much closer to the eventual full
  `IO`/allocation/unsafe semantics instead of an internal bookkeeping list.

- whole-`Ty` tagged result semantics for compiled executions
  The staged handled-effect pipeline no longer stops at finite-core denotation
  facts like `expectedCore.denotes value.toCoreAtom`. We now bridge those facts
  into whole-`Ty` kernel-tag semantics for every type the current checker can
  represent. Concretely: accepted compiled programs can be stated as producing
  results that inhabit the requested whole-`Ty` semantics in the runtime tag
  model, not merely a tiny auxiliary core domain.

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

- `dff034b` `formal: add kernel tag semantic model`
  The kernel atom theory now has an explicit runtime-flavored model instead of
  only abstract admissible valuations. We formalize concrete tags for
  primitives, functions, records, nominals, and pointer flavors, prove the
  kernel theory is sound for those tags, and derive runtime-facing corollaries
  showing that concrete `rc` and `mptr` tags satisfy `ptr` semantics while
  `bool & int` stays empty on every kernel tag.

- `57b289d` `formal: lift staged results to kernel tag semantics`
  The staged handled-effect theorem now reaches beyond the finite `CoreSetTy`
  checker model. We prove that every representable expected type can be
  interpreted equivalently in the whole-`Ty` kernel-tag semantics, then lift
  the compiled/staged expected-type theorems through that bridge. Concretely:
  successful compiled executions can now be stated as producing results that
  inhabit the requested whole-`Ty` runtime-tag semantics, not just the tiny
  core denotation domain.

- `071f0f5` `formal: observe handled effects as io events`
  The handled-effect fragment now exposes its behavior through explicit generic
  `IOEvent.effectQuery` observations rather than only raw effect-name traces.
  We prove staged source/machine equivalence for those observations and carry
  typed-result theorems through the result-carrying observed behaviors.
  Concretely: the compiler theorem can now talk about observed query/reply
  runtime behavior, not only about an internal list of effect names.

- `38f567a` `formal: constrain observed io behaviors`
  Observable handled-effect `IOEvent` traces are now proved precise rather than
  merely present: every event in the compiled/staged observed trace is exactly
  an oracle-mediated effect query whose effect lies in the inferred effect set,
  and pure accepted programs have empty observed traces. Concretely: the new
  runtime-observation layer is already semantically disciplined, not just a new
  notation for the old traces.

- `46d6aab` `formal: separate pointer tag flavors`
  The kernel theory and concrete tag model now explicitly rule out overlap
  between `rc` and `mptr` pointer flavors. We prove `rc T & mptr U` is
  unsatisfiable in the theory-aware DNF layer and empty at every concrete
  kernel tag. Concretely: pointer-kind separation is now a proved semantic
  invariant rather than an informal expectation.

- `43bd73a` `formal: decide whole-ty kernel subtype`
  We now expose a kernel-theory boolean decision layer for normalized whole-`Ty`
  subtype obligations and use it to state compiled/staged expected-type
  theorems beyond the finite `CoreSetTy` fragment. Concretely: accepted staged
  handled-effect executions can now be shown to inhabit requested whole-`Ty`
  kernel semantics through the kernel subtype theory itself, not only through a
  bridge from the tiny representable core.

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
3. Replace the current theorem-facing whole-`Ty` kernel subtype decision layer
   with a fully computable one, then push the staged compiler theorem outward
   from effect-query observations to real observable runtime events: `IO`,
   allocation, unsafe boundaries, object emission, and bootstrap parity.

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
