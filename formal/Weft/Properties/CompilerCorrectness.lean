import Weft.Compiler

namespace Weft

theorem semantics_eq_refl
    {Obs : Type}
    {α : Type}
    (sem : Semantics α Obs)
    (artifact : α) :
    SemanticEq sem artifact artifact := by
  intro input behavior
  constructor <;> intro h <;> exact h

theorem semantics_eq_symm
    {Obs : Type}
    {α : Type}
    (sem : Semantics α Obs)
    {lhs rhs : α}
    (hEq : SemanticEq sem lhs rhs) :
    SemanticEq sem rhs lhs := by
  intro input behavior
  exact Iff.symm (hEq input behavior)

theorem semantics_eq_trans
    {Obs : Type}
    {α : Type}
    (sem : Semantics α Obs)
    {lhs mid rhs : α}
    (h₁ : SemanticEq sem lhs mid)
    (h₂ : SemanticEq sem mid rhs) :
    SemanticEq sem lhs rhs := by
  intro input behavior
  constructor
  · intro h
    exact (h₂ input behavior).1 ((h₁ input behavior).1 h)
  · intro h
    exact (h₁ input behavior).2 ((h₂ input behavior).2 h)

theorem preserves_comp
    {Obs : Type}
    {α β γ : Type}
    {sourceSem : Semantics α Obs}
    {midSem : Semantics β Obs}
    {targetSem : Semantics γ Obs}
    {s₁ : Stage α β}
    {s₂ : Stage β γ}
    (h₁ : SemanticsPreserving sourceSem midSem s₁)
    (h₂ : SemanticsPreserving midSem targetSem s₂) :
    SemanticsPreserving sourceSem targetSem (Stage.comp s₂ s₁) := by
  intro source artifact input behavior hCompile hSource
  cases hStage₁ : s₁.compile source with
  | error err =>
      simp [Stage.comp, hStage₁] at hCompile
  | ok mid =>
      simp [Stage.comp, hStage₁] at hCompile
      exact h₂ mid artifact input behavior hCompile (h₁ source mid input behavior hStage₁ hSource)

theorem whole_compiler_theorem
    {Obs : Type}
    (pipeline : CompilerPipeline)
    (sourceSem : Semantics pipeline.Source Obs)
    (parsedSem : Semantics pipeline.Parsed Obs)
    (typedSem : Semantics pipeline.Typed Obs)
    (irSem : Semantics pipeline.IR Obs)
    (nativeSem : Semantics pipeline.Native Obs)
    (hParse : SemanticsPreserving sourceSem parsedSem pipeline.parse)
    (hTypecheck : SemanticsPreserving parsedSem typedSem pipeline.typecheck)
    (hLower : SemanticsPreserving typedSem irSem pipeline.lower)
    (hEmit : SemanticsPreserving irSem nativeSem pipeline.emit) :
    SemanticsPreserving sourceSem nativeSem (CompilerPipeline.compile pipeline) := by
  apply preserves_comp
  · apply preserves_comp
    · apply preserves_comp
      · exact hParse
      · exact hTypecheck
    · exact hLower
  · exact hEmit

theorem bootstrap_semantics_stable
    {Obs : Type}
    {α : Type}
    (sem : Semantics α Obs)
    {compiler₁ compiler₂ compiler₃ : α}
    (h₁₂ : SemanticEq sem compiler₁ compiler₂)
    (h₂₃ : SemanticEq sem compiler₂ compiler₃) :
    SemanticEq sem compiler₁ compiler₃ :=
  semantics_eq_trans sem h₁₂ h₂₃

end Weft
