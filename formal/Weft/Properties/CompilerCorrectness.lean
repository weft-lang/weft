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

theorem reflects_comp
    {Obs : Type}
    {α β γ : Type}
    {sourceSem : Semantics α Obs}
    {midSem : Semantics β Obs}
    {targetSem : Semantics γ Obs}
    {s₁ : Stage α β}
    {s₂ : Stage β γ}
    (h₁ : SemanticsReflecting sourceSem midSem s₁)
    (h₂ : SemanticsReflecting midSem targetSem s₂) :
    SemanticsReflecting sourceSem targetSem (Stage.comp s₂ s₁) := by
  intro source artifact input behavior hCompile hTarget
  cases hStage₁ : s₁.compile source with
  | error err =>
      simp [Stage.comp, hStage₁] at hCompile
  | ok mid =>
      simp [Stage.comp, hStage₁] at hCompile
      exact h₁ source mid input behavior hStage₁ (h₂ mid artifact input behavior hCompile hTarget)

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

theorem whole_compiler_reflection_theorem
    {Obs : Type}
    (pipeline : CompilerPipeline)
    (sourceSem : Semantics pipeline.Source Obs)
    (parsedSem : Semantics pipeline.Parsed Obs)
    (typedSem : Semantics pipeline.Typed Obs)
    (irSem : Semantics pipeline.IR Obs)
    (nativeSem : Semantics pipeline.Native Obs)
    (hParse : SemanticsReflecting sourceSem parsedSem pipeline.parse)
    (hTypecheck : SemanticsReflecting parsedSem typedSem pipeline.typecheck)
    (hLower : SemanticsReflecting typedSem irSem pipeline.lower)
    (hEmit : SemanticsReflecting irSem nativeSem pipeline.emit) :
    SemanticsReflecting sourceSem nativeSem (CompilerPipeline.compile pipeline) := by
  apply reflects_comp
  · apply reflects_comp
    · apply reflects_comp
      · exact hParse
      · exact hTypecheck
    · exact hLower
  · exact hEmit

theorem stage_semantics_iff
    {Obs : Type}
    {α γ : Type}
    {sourceSem : Semantics α Obs}
    {targetSem : Semantics γ Obs}
    {stage : Stage α γ}
    (hPreserve : SemanticsPreserving sourceSem targetSem stage)
    (hReflect : SemanticsReflecting sourceSem targetSem stage)
    {source : α}
    {artifact : γ}
    {input : Input}
    {behavior : Obs}
    (hCompile : stage.compile source = .ok artifact) :
    sourceSem source input behavior ↔ targetSem artifact input behavior := by
  constructor
  · intro hSource
    exact hPreserve source artifact input behavior hCompile hSource
  · intro hTarget
    exact hReflect source artifact input behavior hCompile hTarget

theorem compiled_semanticEq_of_sourceEq
    {Obs : Type}
    {α γ : Type}
    {sourceSem : Semantics α Obs}
    {targetSem : Semantics γ Obs}
    {stage : Stage α γ}
    (hPreserve : SemanticsPreserving sourceSem targetSem stage)
    (hReflect : SemanticsReflecting sourceSem targetSem stage)
    {source₁ source₂ : α}
    {artifact₁ artifact₂ : γ}
    (hCompile₁ : stage.compile source₁ = .ok artifact₁)
    (hCompile₂ : stage.compile source₂ = .ok artifact₂)
    (hEq : SemanticEq sourceSem source₁ source₂) :
    SemanticEq targetSem artifact₁ artifact₂ := by
  intro input behavior
  constructor
  · intro hTarget₁
    have hSource₁ : sourceSem source₁ input behavior :=
      (stage_semantics_iff hPreserve hReflect hCompile₁).2 hTarget₁
    have hSource₂ : sourceSem source₂ input behavior :=
      (hEq input behavior).1 hSource₁
    exact (stage_semantics_iff hPreserve hReflect hCompile₂).1 hSource₂
  · intro hTarget₂
    have hSource₂ : sourceSem source₂ input behavior :=
      (stage_semantics_iff hPreserve hReflect hCompile₂).2 hTarget₂
    have hSource₁ : sourceSem source₁ input behavior :=
      (hEq input behavior).2 hSource₂
    exact (stage_semantics_iff hPreserve hReflect hCompile₁).1 hSource₁

theorem compiled_bootstrap_semantics_stable
    {Obs : Type}
    {α γ : Type}
    {sourceSem : Semantics α Obs}
    {targetSem : Semantics γ Obs}
    {stage : Stage α γ}
    (hPreserve : SemanticsPreserving sourceSem targetSem stage)
    (hReflect : SemanticsReflecting sourceSem targetSem stage)
    {source₁ source₂ source₃ : α}
    {artifact₁ artifact₂ artifact₃ : γ}
    (hCompile₁ : stage.compile source₁ = .ok artifact₁)
    (_hCompile₂ : stage.compile source₂ = .ok artifact₂)
    (hCompile₃ : stage.compile source₃ = .ok artifact₃)
    (h₁₂ : SemanticEq sourceSem source₁ source₂)
    (h₂₃ : SemanticEq sourceSem source₂ source₃) :
    SemanticEq targetSem artifact₁ artifact₃ := by
  have hSource : SemanticEq sourceSem source₁ source₃ :=
    semantics_eq_trans sourceSem h₁₂ h₂₃
  exact compiled_semanticEq_of_sourceEq
    hPreserve hReflect hCompile₁ hCompile₃ hSource

theorem whole_compiler_semantics_iff
    {Obs : Type}
    (pipeline : CompilerPipeline)
    (sourceSem : Semantics pipeline.Source Obs)
    (parsedSem : Semantics pipeline.Parsed Obs)
    (typedSem : Semantics pipeline.Typed Obs)
    (irSem : Semantics pipeline.IR Obs)
    (nativeSem : Semantics pipeline.Native Obs)
    (hParsePreserve : SemanticsPreserving sourceSem parsedSem pipeline.parse)
    (hTypecheckPreserve : SemanticsPreserving parsedSem typedSem pipeline.typecheck)
    (hLowerPreserve : SemanticsPreserving typedSem irSem pipeline.lower)
    (hEmitPreserve : SemanticsPreserving irSem nativeSem pipeline.emit)
    (hParseReflect : SemanticsReflecting sourceSem parsedSem pipeline.parse)
    (hTypecheckReflect : SemanticsReflecting parsedSem typedSem pipeline.typecheck)
    (hLowerReflect : SemanticsReflecting typedSem irSem pipeline.lower)
    (hEmitReflect : SemanticsReflecting irSem nativeSem pipeline.emit)
    {source : pipeline.Source}
    {artifact : pipeline.Native}
    {input : Input}
    {behavior : Obs}
    (hCompile : (CompilerPipeline.compile pipeline).compile source = .ok artifact) :
    sourceSem source input behavior ↔ nativeSem artifact input behavior := by
  exact stage_semantics_iff
    (whole_compiler_theorem
      pipeline sourceSem parsedSem typedSem irSem nativeSem
      hParsePreserve hTypecheckPreserve hLowerPreserve hEmitPreserve)
    (whole_compiler_reflection_theorem
      pipeline sourceSem parsedSem typedSem irSem nativeSem
      hParseReflect hTypecheckReflect hLowerReflect hEmitReflect)
    hCompile

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
