import Weft.Compiler

namespace Weft

theorem semantics_eq_refl
    {α : Type}
    (sem : Semantics α)
    (artifact : α) :
    SemanticEq sem artifact artifact := by
  intro input behavior
  constructor <;> intro h <;> exact h

theorem semantics_eq_symm
    {α : Type}
    (sem : Semantics α)
    {lhs rhs : α}
    (hEq : SemanticEq sem lhs rhs) :
    SemanticEq sem rhs lhs := by
  intro input behavior
  exact Iff.symm (hEq input behavior)

theorem semantics_eq_trans
    {α : Type}
    (sem : Semantics α)
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
    {α β γ : Type}
    {sourceSem : Semantics α}
    {midSem : Semantics β}
    {targetSem : Semantics γ}
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
    (pipeline : CompilerPipeline)
    (sourceSem : Semantics pipeline.Source)
    (parsedSem : Semantics pipeline.Parsed)
    (typedSem : Semantics pipeline.Typed)
    (irSem : Semantics pipeline.IR)
    (nativeSem : Semantics pipeline.Native)
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
    {α : Type}
    (sem : Semantics α)
    {compiler₁ compiler₂ compiler₃ : α}
    (h₁₂ : SemanticEq sem compiler₁ compiler₂)
    (h₂₃ : SemanticEq sem compiler₂ compiler₃) :
    SemanticEq sem compiler₁ compiler₃ :=
  semantics_eq_trans sem h₁₂ h₂₃

end Weft
