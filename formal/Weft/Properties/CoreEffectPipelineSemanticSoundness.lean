import Weft.Properties.CoreEffectPipelineCorrectness
import Weft.Properties.CoreEffectSubtypeChecking

namespace Weft.CoreEffects

open Weft.SafetyCore

theorem staged_compile_eq_emitClosed
    {surface : SurfaceExpr}
    {code : Code}
    (hCompile : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile surface = .ok code) :
    code = emitClosed (lower (parseSurface surface)) := by
  unfold Weft.CompilerPipeline.compile Weft.Stage.comp stagedCompilerPipeline at hCompile
  cases hCheck : check (parseSurface surface) with
  | none =>
      simp [parseStage, typecheckStage, lowerStage, emitStage, hCheck] at hCompile
  | some checked =>
      simp [parseStage, typecheckStage, lowerStage, emitStage, hCheck] at hCompile
      exact hCompile.symm

theorem staged_compile_correct
    {oracle : Oracle}
    {surface : SurfaceExpr}
    {code : Code}
    {value : RuntimeVal}
    {trace : List Weft.EffectName}
    (hCompile : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile surface = .ok code)
    (hEval : Eval oracle (parseSurface surface) value trace) :
    Exec oracle code [] [value] trace := by
  have hCode : code = emitClosed (lower (parseSurface surface)) :=
    staged_compile_eq_emitClosed hCompile
  subst code
  exact emit_correct oracle (lower (parseSurface surface)) value trace (lower_eval_preserves hEval)

theorem staged_pure_result_respects_expected_type
    {oracle : Oracle}
    {surface : SurfaceExpr}
    {expected : Weft.Ty}
    {code : Code}
    {value : RuntimeVal}
    {trace : List Weft.EffectName}
    (hCompile : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile surface = .ok code)
    (hCheck : checkAgainst (parseSurface surface) expected = true)
    (hPure : inferEffects (parseSurface surface) = some Weft.EffectSet.empty)
    (hEval : Eval oracle (parseSurface surface) value trace) :
    Exec oracle code [] [value] trace ∧
      (∀ effect : Weft.EffectName, effect ∉ trace) ∧
      ∃ expectedCore : Weft.CoreSetTy,
        Weft.CoreSetTy.ofTy expected = some expectedCore ∧
        expectedCore.denotes value.toCoreAtom := by
  have hCode : code = emitClosed (lower (parseSurface surface)) :=
    staged_compile_eq_emitClosed hCompile
  have hExec : Exec oracle code [] [value] trace := staged_compile_correct hCompile hEval
  have hCore :
      Exec oracle (compileClosed (parseSurface surface)) [] [value] trace ∧
        (∀ effect : Weft.EffectName, effect ∉ trace) ∧
        ∃ expectedCore : Weft.CoreSetTy,
          Weft.CoreSetTy.ofTy expected = some expectedCore ∧
          expectedCore.denotes value.toCoreAtom :=
    compiled_pure_result_respects_expected_type hCheck hPure hEval
  exact ⟨hExec, hCore.2.1, hCore.2.2⟩

end Weft.CoreEffects
