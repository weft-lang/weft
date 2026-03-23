namespace Weft

inductive IOEvent : Type where
  | stdinChunk : List UInt8 -> IOEvent
  | stdoutChunk : List UInt8 -> IOEvent
  | stderrChunk : List UInt8 -> IOEvent
  | openFile : String -> IOEvent
  | writeFile : String -> List UInt8 -> IOEvent
  | alloc : Nat -> IOEvent
  | free : Nat -> IOEvent
  deriving Repr, DecidableEq

structure Behavior : Type where
  trace : List IOEvent
  exitCode : Int
  deriving Repr, DecidableEq

abbrev Input : Type := List UInt8
abbrev Semantics (α : Type) : Type := α -> Input -> Behavior -> Prop

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
    {α β : Type}
    (sourceSem : Semantics α)
    (targetSem : Semantics β)
    (stage : Stage α β) : Prop :=
  ∀ source artifact input behavior,
    stage.compile source = .ok artifact ->
    sourceSem source input behavior ->
    targetSem artifact input behavior

def SemanticEq {α : Type} (sem : Semantics α) (lhs rhs : α) : Prop :=
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
