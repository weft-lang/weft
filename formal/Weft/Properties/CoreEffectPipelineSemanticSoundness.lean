import Weft.Properties.CoreEffectPipelineCorrectness
import Weft.Properties.CoreKernelModelBridge
import Weft.Properties.CoreEffectSubtypeChecking

namespace Weft.CoreEffects

open Weft.SafetyCore

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

theorem staged_result_respects_effects_and_expected_type
    {oracle : Oracle}
    {surface : SurfaceExpr}
    {expected : Weft.Ty}
    {effects : Weft.EffectSet}
    {code : Code}
    {value : RuntimeVal}
    {trace : List Weft.EffectName}
    (hCompile : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile surface = .ok code)
    (hCheck : checkAgainst (parseSurface surface) expected = true)
    (hEffects : inferEffects (parseSurface surface) = some effects)
    (hEval : Eval oracle (parseSurface surface) value trace) :
    Exec oracle code [] [value] trace ∧
      (∀ effect : Weft.EffectName, effect ∈ trace -> effect ∈ effects.elems) ∧
      ∃ expectedCore : Weft.CoreSetTy,
        Weft.CoreSetTy.ofTy expected = some expectedCore ∧
        expectedCore.denotes value.toCoreAtom := by
  have hExec : Exec oracle code [] [value] trace :=
    staged_compile_correct hCompile hEval
  have hCore :
      Exec oracle (compileClosed (parseSurface surface)) [] [value] trace ∧
        (∀ effect : Weft.EffectName, effect ∈ trace -> effect ∈ effects.elems) ∧
        ∃ expectedCore : Weft.CoreSetTy,
          Weft.CoreSetTy.ofTy expected = some expectedCore ∧
          expectedCore.denotes value.toCoreAtom :=
    compiled_result_respects_effects_and_expected_type hCheck hEffects hEval
  exact ⟨hExec, hCore.2.1, hCore.2.2⟩

theorem staged_machine_pure_result_respects_expected_type
    {oracle : Oracle}
    {surface : SurfaceExpr}
    {expected : Weft.Ty}
    {code : Code}
    {value : RuntimeVal}
    {trace : List Weft.EffectName}
    (hCompile : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile surface = .ok code)
    (hCheck : checkAgainst (parseSurface surface) expected = true)
    (hPure : inferEffects (parseSurface surface) = some Weft.EffectSet.empty)
    (hExec : Exec oracle code [] [value] trace) :
    (∀ effect : Weft.EffectName, effect ∉ trace) ∧
      ∃ expectedCore : Weft.CoreSetTy,
        Weft.CoreSetTy.ofTy expected = some expectedCore ∧
        expectedCore.denotes value.toCoreAtom := by
  have hEval : Eval oracle (parseSurface surface) value trace :=
    staged_compile_complete hCompile hExec
  have hCore :
      Exec oracle (compileClosed (parseSurface surface)) [] [value] trace ∧
        (∀ effect : Weft.EffectName, effect ∉ trace) ∧
        ∃ expectedCore : Weft.CoreSetTy,
          Weft.CoreSetTy.ofTy expected = some expectedCore ∧
          expectedCore.denotes value.toCoreAtom :=
    compiled_pure_result_respects_expected_type hCheck hPure hEval
  exact ⟨hCore.2.1, hCore.2.2⟩

theorem staged_machine_result_respects_effects_and_expected_type
    {oracle : Oracle}
    {surface : SurfaceExpr}
    {expected : Weft.Ty}
    {effects : Weft.EffectSet}
    {code : Code}
    {value : RuntimeVal}
    {trace : List Weft.EffectName}
    (hCompile : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile surface = .ok code)
    (hCheck : checkAgainst (parseSurface surface) expected = true)
    (hEffects : inferEffects (parseSurface surface) = some effects)
    (hExec : Exec oracle code [] [value] trace) :
    (∀ effect : Weft.EffectName, effect ∈ trace -> effect ∈ effects.elems) ∧
      ∃ expectedCore : Weft.CoreSetTy,
        Weft.CoreSetTy.ofTy expected = some expectedCore ∧
        expectedCore.denotes value.toCoreAtom := by
  have hEval : Eval oracle (parseSurface surface) value trace :=
    staged_compile_complete hCompile hExec
  have hCore :
      Exec oracle (compileClosed (parseSurface surface)) [] [value] trace ∧
        (∀ effect : Weft.EffectName, effect ∈ trace -> effect ∈ effects.elems) ∧
        ∃ expectedCore : Weft.CoreSetTy,
          Weft.CoreSetTy.ofTy expected = some expectedCore ∧
          expectedCore.denotes value.toCoreAtom :=
    compiled_result_respects_effects_and_expected_type hCheck hEffects hEval
  exact ⟨hCore.2.1, hCore.2.2⟩

theorem staged_machine_behavior_respects_inferred_effects
    {oracle : Oracle}
    {surface : SurfaceExpr}
    {effects : Weft.EffectSet}
    {code : Code}
    {input : Weft.Input}
    {behavior : EffectBehavior}
    (hCompile : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile surface = .ok code)
    (hEffects : inferEffects (parseSurface surface) = some effects)
    (hMachine : machineSem oracle code input behavior) :
    ∀ effect : Weft.EffectName, effect ∈ behavior.trace -> effect ∈ effects.elems := by
  rcases hMachine with ⟨value, trace, hExec, hBehavior⟩
  have hEval : Eval oracle (parseSurface surface) value trace :=
    staged_compile_complete hCompile hExec
  rcases inferEffects_sound hEffects with ⟨ty, hTy⟩
  cases hBehavior
  exact trace_subset_of_typed_effects hTy hEval

theorem staged_machine_behavior_trace_free_when_pure
    {oracle : Oracle}
    {surface : SurfaceExpr}
    {code : Code}
    {input : Weft.Input}
    {behavior : EffectBehavior}
    (hCompile : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile surface = .ok code)
    (hPure : inferEffects (parseSurface surface) = some Weft.EffectSet.empty)
    (hMachine : machineSem oracle code input behavior) :
    ∀ effect : Weft.EffectName, effect ∉ behavior.trace := by
  rcases hMachine with ⟨value, trace, hExec, hBehavior⟩
  have hEval : Eval oracle (parseSurface surface) value trace :=
    staged_compile_complete hCompile hExec
  rcases inferEffects_sound hPure with ⟨ty, hTy⟩
  cases hBehavior
  exact empty_effects_have_empty_trace hTy hEval

theorem staged_result_behavior_respects_effects_and_expected_type
    {oracle : Oracle}
    {surface : SurfaceExpr}
    {expected : Weft.Ty}
    {effects : Weft.EffectSet}
    {code : Code}
    {input : Weft.Input}
    {behavior : ResultBehavior}
    (hCompile : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile surface = .ok code)
    (hCheck : checkAgainst (parseSurface surface) expected = true)
    (hEffects : inferEffects (parseSurface surface) = some effects)
    (hMachine : machineResultSem oracle code input behavior) :
    (∀ effect : Weft.EffectName, effect ∈ behavior.trace -> effect ∈ effects.elems) ∧
      ∃ expectedCore : Weft.CoreSetTy,
        Weft.CoreSetTy.ofTy expected = some expectedCore ∧
        expectedCore.denotes behavior.result.toCoreAtom := by
  rcases hMachine with ⟨value, trace, hExec, hBehavior⟩
  have hConforms :
      (∀ effect : Weft.EffectName, effect ∈ trace -> effect ∈ effects.elems) ∧
        ∃ expectedCore : Weft.CoreSetTy,
          Weft.CoreSetTy.ofTy expected = some expectedCore ∧
          expectedCore.denotes value.toCoreAtom :=
    staged_machine_result_respects_effects_and_expected_type hCompile hCheck hEffects hExec
  cases hBehavior
  exact hConforms

theorem staged_machine_pure_result_respects_expected_type_tag
    {oracle : Oracle}
    {surface : SurfaceExpr}
    {expected : Weft.Ty}
    {code : Code}
    {value : RuntimeVal}
    {trace : List Weft.EffectName}
    (hCompile : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile surface = .ok code)
    (hCheck : checkAgainst (parseSurface surface) expected = true)
    (hPure : inferEffects (parseSurface surface) = some Weft.EffectSet.empty)
    (hExec : Exec oracle code [] [value] trace) :
    (∀ effect : Weft.EffectName, effect ∉ trace) ∧
      Weft.Ty.denotesTag value.toKernelTag expected := by
  have hEval : Eval oracle (parseSurface surface) value trace :=
    staged_compile_complete hCompile hExec
  have hConforms :
      Exec oracle (compileClosed (parseSurface surface)) [] [value] trace ∧
        (∀ effect : Weft.EffectName, effect ∉ trace) ∧
        Weft.Ty.denotesTag value.toKernelTag expected :=
    compiled_pure_result_respects_expected_type_tag hCheck hPure hEval
  exact ⟨hConforms.2.1, hConforms.2.2⟩

theorem staged_machine_result_respects_effects_and_expected_type_tag
    {oracle : Oracle}
    {surface : SurfaceExpr}
    {expected : Weft.Ty}
    {effects : Weft.EffectSet}
    {code : Code}
    {value : RuntimeVal}
    {trace : List Weft.EffectName}
    (hCompile : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile surface = .ok code)
    (hCheck : checkAgainst (parseSurface surface) expected = true)
    (hEffects : inferEffects (parseSurface surface) = some effects)
    (hExec : Exec oracle code [] [value] trace) :
    (∀ effect : Weft.EffectName, effect ∈ trace -> effect ∈ effects.elems) ∧
      Weft.Ty.denotesTag value.toKernelTag expected := by
  have hEval : Eval oracle (parseSurface surface) value trace :=
    staged_compile_complete hCompile hExec
  have hConforms :
      Exec oracle (compileClosed (parseSurface surface)) [] [value] trace ∧
        (∀ effect : Weft.EffectName, effect ∈ trace -> effect ∈ effects.elems) ∧
        Weft.Ty.denotesTag value.toKernelTag expected :=
    compiled_result_respects_effects_and_expected_type_tag hCheck hEffects hEval
  exact ⟨hConforms.2.1, hConforms.2.2⟩

theorem staged_result_behavior_trace_free_and_typed_when_pure
    {oracle : Oracle}
    {surface : SurfaceExpr}
    {expected : Weft.Ty}
    {code : Code}
    {input : Weft.Input}
    {behavior : ResultBehavior}
    (hCompile : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile surface = .ok code)
    (hCheck : checkAgainst (parseSurface surface) expected = true)
    (hPure : inferEffects (parseSurface surface) = some Weft.EffectSet.empty)
    (hMachine : machineResultSem oracle code input behavior) :
    (∀ effect : Weft.EffectName, effect ∉ behavior.trace) ∧
      ∃ expectedCore : Weft.CoreSetTy,
        Weft.CoreSetTy.ofTy expected = some expectedCore ∧
        expectedCore.denotes behavior.result.toCoreAtom := by
  rcases hMachine with ⟨value, trace, hExec, hBehavior⟩
  have hConforms :
      (∀ effect : Weft.EffectName, effect ∉ trace) ∧
        ∃ expectedCore : Weft.CoreSetTy,
          Weft.CoreSetTy.ofTy expected = some expectedCore ∧
          expectedCore.denotes value.toCoreAtom :=
    staged_machine_pure_result_respects_expected_type hCompile hCheck hPure hExec
  cases hBehavior
  exact hConforms

theorem staged_result_behavior_respects_effects_and_expected_type_tag
    {oracle : Oracle}
    {surface : SurfaceExpr}
    {expected : Weft.Ty}
    {effects : Weft.EffectSet}
    {code : Code}
    {input : Weft.Input}
    {behavior : ResultBehavior}
    (hCompile : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile surface = .ok code)
    (hCheck : checkAgainst (parseSurface surface) expected = true)
    (hEffects : inferEffects (parseSurface surface) = some effects)
    (hMachine : machineResultSem oracle code input behavior) :
    (∀ effect : Weft.EffectName, effect ∈ behavior.trace -> effect ∈ effects.elems) ∧
      Weft.Ty.denotesTag behavior.result.toKernelTag expected := by
  rcases hMachine with ⟨value, trace, hExec, hBehavior⟩
  have hConforms :
      (∀ effect : Weft.EffectName, effect ∈ trace -> effect ∈ effects.elems) ∧
        Weft.Ty.denotesTag value.toKernelTag expected :=
    staged_machine_result_respects_effects_and_expected_type_tag hCompile hCheck hEffects hExec
  cases hBehavior
  exact hConforms

theorem staged_result_behavior_trace_free_and_typed_when_pure_tag
    {oracle : Oracle}
    {surface : SurfaceExpr}
    {expected : Weft.Ty}
    {code : Code}
    {input : Weft.Input}
    {behavior : ResultBehavior}
    (hCompile : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile surface = .ok code)
    (hCheck : checkAgainst (parseSurface surface) expected = true)
    (hPure : inferEffects (parseSurface surface) = some Weft.EffectSet.empty)
    (hMachine : machineResultSem oracle code input behavior) :
    (∀ effect : Weft.EffectName, effect ∉ behavior.trace) ∧
      Weft.Ty.denotesTag behavior.result.toKernelTag expected := by
  rcases hMachine with ⟨value, trace, hExec, hBehavior⟩
  have hConforms :
      (∀ effect : Weft.EffectName, effect ∉ trace) ∧
        Weft.Ty.denotesTag value.toKernelTag expected :=
    staged_machine_pure_result_respects_expected_type_tag hCompile hCheck hPure hExec
  cases hBehavior
  exact hConforms

end Weft.CoreEffects
