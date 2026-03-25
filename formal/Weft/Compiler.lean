import Weft.Effects

namespace Weft

inductive IOEvent : Type where
  | stdinChunk : List UInt8 -> IOEvent
  | stdoutChunk : List UInt8 -> IOEvent
  | stderrChunk : List UInt8 -> IOEvent
  | openFile : String -> IOEvent
  | writeFile : String -> List UInt8 -> IOEvent
  | effectQuery : EffectName -> Bool -> IOEvent
  | alloc : Nat -> IOEvent
  | free : Nat -> IOEvent
  deriving Repr, DecidableEq

structure Behavior : Type where
  trace : List IOEvent
  exitCode : Int
  deriving Repr, DecidableEq

abbrev Input : Type := List UInt8
abbrev Semantics (α : Type) (β : Type := Behavior) : Type := α -> Input -> β -> Prop

structure Stage (α β : Type) where
  compile : α -> Except String β

namespace Stage

def comp {α β γ : Type} (s₂ : Stage β γ) (s₁ : Stage α β) : Stage α γ where
  compile source :=
    match s₁.compile source with
    | .error err => .error err
    | .ok mid => s₂.compile mid

end Stage

def SemanticsPreserving
    {Obs : Type}
    {α γ : Type}
    (sourceSem : Semantics α Obs)
    (targetSem : Semantics γ Obs)
    (stage : Stage α γ) : Prop :=
  ∀ source artifact input behavior,
    stage.compile source = .ok artifact ->
    sourceSem source input behavior ->
    targetSem artifact input behavior

def SemanticsReflecting
    {Obs : Type}
    {α γ : Type}
    (sourceSem : Semantics α Obs)
    (targetSem : Semantics γ Obs)
    (stage : Stage α γ) : Prop :=
  ∀ source artifact input behavior,
    stage.compile source = .ok artifact ->
    targetSem artifact input behavior ->
    sourceSem source input behavior

def SemanticEq {Obs : Type} {α : Type} (sem : Semantics α Obs) (lhs rhs : α) : Prop :=
  ∀ input behavior, sem lhs input behavior ↔ sem rhs input behavior

structure CompilerPipeline where
  Source : Type
  Parsed : Type
  Typed : Type
  IR : Type
  Native : Type
  parse : Stage Source Parsed
  typecheck : Stage Parsed Typed
  lower : Stage Typed IR
  emit : Stage IR Native

namespace CompilerPipeline

def compile (pipeline : CompilerPipeline) : Stage pipeline.Source pipeline.Native :=
  Stage.comp pipeline.emit (Stage.comp pipeline.lower (Stage.comp pipeline.typecheck pipeline.parse))

end CompilerPipeline

end Weft
