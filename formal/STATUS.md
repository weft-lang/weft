# Formal Theorem Status

This file tracks what the current Lean development buys us toward the end goal:

> a full end-to-end theorem for the self-hosted Weft compiler, with well-founded
> semantic support for parsing, checking, lowering, code generation, object
> emission, runtime effects, and observable input/output behavior across
> bootstrap generations.

The percentages below are deliberately rough. They are here to keep us honest
about what is still missing, not to pretend the remaining work is linear.

## Overall Progress

Roughly **66%** of the way to the complete theorem.

That estimate is based on:

- the staged compiler theorem backbone being in place
- concrete source-to-machine theorems existing for pure and handled-effect cores
- result/effect semantic soundness already reaching emitted code
- handled-effect observations now lifted into explicit generic `IOEvent`
  query/reply behaviors rather than only raw effect-name traces
- whole-`Ty` kernel subtype obligations can now feed expected-type theorems for
  compiled and staged executions rather than stopping at the `CoreSetTy`
  representable fragment
- the whole-`Ty` kernel subtype layer is now structurally computable rather
  than only theorem-facing
- function types in the kernel theory/model now respect effect-set subtyping,
  so pure functions and effect-bounded functions participate in the executable
  whole-`Ty` checker rather than remaining exact-equality atoms
- bootstrap-parity reasoning is now instantiated for emitted handled-effect
  machine artifacts over explicit observed `IOEvent` behaviors
- bootstrap-parity reasoning now also reaches the raw handled-effect machine
  trace/result semantics underneath the `IOEvent` observation layer
- those emitted-artifact bootstrap lemmas now carry both trace-only and
  result-carrying purity/effect-boundedness contracts rather than only
  extensional behavior equality
- DNF/subtyping work moving beyond the tiny finite core
- but the real runtime, unsafe/alloc boundaries, continuation semantics, and
  native object-format bridge still being mostly unproved

## Progress By Area

| Area | Rough Status | What is done |
|------|--------------|--------------|
| Compiler composition backbone | 90% | Generic stage-composition theorem and bootstrap-stability shape are in place. |
| Pure core source-to-machine correctness | 85% | Concrete compiler, staged pipeline, and typed-result preservation are proved. |
| Handled-effect core correctness | 80% | Trace-preserving compilation, staged effectful compiler theorem, and machine-level effect/result conformance are proved. |
| Result-carrying semantic observations | 90% | Successful staged compilations now preserve and reflect trace/result behaviors, representable expected types can be restated at the whole-`Ty` kernel-tag semantic level, the handled-effect fragment has explicit query/reply observation theorems in the generic `IOEvent` space, staged/compiled expected-type theorems now work through an executable whole-`Ty` kernel subtype layer rather than only the finite `CoreSetTy` bridge, and semantic equivalence of surface compiler generations can be transferred to emitted machine artifacts together with the current pure/effect-bounded typed-result contracts. |
| Set-theoretic normalization/subtyping | 69% | Finite core DNF/subtype theorem is proved, whole-`Ty` boolean structure normalizes to an atomized DNF semantics, theory-aware unsatisfiability implies semantic subtyping under sound valuations, the kernel theory has a concrete tag-level semantic model with explicit pointer-flavor separation facts such as `rc T & mptr U` being empty, and there is now a structurally computable whole-`Ty` kernel subtype checker over normalized obligations. Full semantic subtyping for richer constructors is still missing. |
| Runtime semantics (`IO`, `Alloc`, `Unsafe`) | 23% | We now have a concrete tag-level semantic model for runtime values plus explicit observable query/reply event semantics for the handled-effect fragment, and we can already rule out impossible runtime tag overlaps like `rc`/`mptr` collisions. Full `IO`/allocation/unsafe runtime behaviors are still missing. |
| Continuations / handler operational model | 10% | Tail-resumptive handled-effect core exists, but full continuation semantics is not yet formalized. |
| Native backend / object emission bridge | 10% | Machine model exists for core targets, but not a real aarch64/Mach-O semantic bridge. |
| Self-hosted whole-compiler theorem | 12% | The theorem shape exists, its handled-effect fragment now speaks in generic observable `IOEvent` behaviors, bootstrap-style semantic parity has been instantiated for emitted artifacts of the staged handled-effect pipeline, and the current typed pure/effect-bounded contracts can be transferred across those emitted-artifact parity lemmas. It is still not connected to the real compiler/runtime stack. |

## What Each Checkpoint Means

Current frontier:

- bootstrap parity for observed emitted artifacts
  The generic bootstrap theorem is no longer only a library lemma sitting above
  the real formal pipeline. We now specialize it to the staged handled-effect
  compiler and use the staged source/machine `iff` theorems to transfer
  semantic equivalence of surface compiler generations into semantic
  equivalence of their emitted machine artifacts, for both trace-only and
  result-carrying `IOEvent` observations. Concretely: the self-hosted theorem
  story now reaches actual emitted artifacts in the current formal fragment,
  not just abstract compiler values.

- contract-preserving bootstrap transfer
  The emitted-artifact bootstrap layer now carries the fragment’s existing
  semantic contracts in both forms: trace-only purity/effect-boundedness for
  plain observed behaviors, and purity/effect-boundedness plus whole-`Ty`
  kernel-typed results for result-carrying behaviors. Concretely: bootstrap
  parity in the current fragment is no longer only about extensional behavior
  sets; it preserves the semantic contracts we actually want to keep stable
  across compiler generations.

- observation-shape exclusion for the handled-effect fragment
  The current `IOEvent` layer now proves not only that observed events are
  effect queries justified by inferred capabilities, but also that no other
  runtime-event constructors can appear at all in traces produced by this
  fragment. Concretely: the formal observation language is now honest about the
  current fragment’s limits while we work toward real `IO`/allocation/unsafe
  events.

- function-effect subtyping in the kernel model/checker
  The kernel theory and concrete tag model now recognize effect-set subtyping
  for function atoms instead of treating them as exact-equality leaves. We now
  prove and compute facts like `(A) -> B <: (A) -[E]> B` and, more generally,
  `fn A -[E1]> B <: fn A -[E2]> B` whenever `E1 ⊆ E2`. Concretely: the
  whole-`Ty` semantic/checker story now matches one of the kernel’s core
  effect-subtyping commitments rather than leaving function effects outside the
  executable subtype layer.

- raw machine bootstrap parity for handled effects
  The staged handled-effect bootstrap layer no longer speaks only in the
  external `IOEvent` observation language. We now also transfer semantic
  equivalence of surface compiler generations directly into semantic
  equivalence of emitted artifacts under the underlying raw machine trace and
  result semantics, and we carry the corresponding inferred-effect, pure
  trace-free, and kernel-typed result contracts through that layer.
  Concretely: the bootstrap theorem story now reaches both the observed
  interface and the lower-level machine semantics that generate it.

- executable whole-`Ty` kernel subtype checking for compiled/staged expected-type theorems
  The formal development no longer has to route every expected-type theorem
  through the finite `CoreSetTy.ofTy` bridge. We now have a kernel-theory
  boolean decision layer over normalized whole-`Ty` subtype obligations, and it
  is now structurally computable rather than implemented as a classical
  `decide` wrapper. We use that executable layer to prove that compiled and
  staged executions respect requested whole-`Ty` kernel semantics even when the
  target type lies outside the old tiny boolean fragment. Concretely: the
  compiler theorem’s expected-type side has moved from theorem-shaped subtype
  plumbing toward a checker we can actually extract and trust computationally.

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

- `4ace9fe` `formal: certify kernel subtype witnesses`
  The new whole-`Ty` kernel subtype layer now certifies concrete kernel facts
  directly: `rc T <: ptr T`, `mptr T <: ptr T`, and emptiness of `rc T & mptr U`
  all evaluate to `true` in the decision layer. Concretely: the new checker is
  no longer only theorem-shaped plumbing; it already recognizes the core kernel
  pointer facts we need it to recognize.

- executable kernel subtype normalization/checking
  `kernelSubtypeb` is no longer defined by classical `decide` over the Prop
  `Unsat KernelTheory.theory`. We now compute it structurally using boolean
  equality on `Ty`/`TyAtom`, boolean implication/disjointness for kernel atoms,
  and boolean unsatisfiability checks on normalized clauses/DNFs. Concretely:
  the staged whole-`Ty` expected-type theorems now sit on top of an executable
  kernel checker rather than a theorem-only placeholder.

- observed bootstrap artifact parity
  The staged handled-effect fragment now has explicit lemmas transferring
  semantic equivalence of surface programs through compilation into semantic
  equivalence of emitted code under the observed `IOEvent` semantics. Chaining
  those lemmas with the generic bootstrap transitivity theorem yields the first
  concrete “compiler generation parity implies emitted artifact parity” story
  in the current formal development.

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
3. Extend the new computable whole-`Ty` kernel subtype checker so it reasons
   about richer semantic obligations, then push the staged compiler theorem
   outward from effect-query observations to real observable runtime events:
   `IO`, allocation, unsafe boundaries, object emission, and full bootstrap
   parity against the self-hosted compiler artifacts.

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
