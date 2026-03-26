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

theorem staged_machine_pure_result_respects_kernel_expected_type_tag
    {oracle : Oracle}
    {surface : SurfaceExpr}
    {expected : Weft.Ty}
    {code : Code}
    {value : RuntimeVal}
    {trace : List Weft.EffectName}
    (hCompile : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile surface = .ok code)
    (hCheck : kernelCheckAgainst (parseSurface surface) expected = true)
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
    compiled_pure_result_respects_kernel_expected_type_tag hCheck hPure hEval
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

theorem staged_machine_result_respects_effects_and_kernel_expected_type_tag
    {oracle : Oracle}
    {surface : SurfaceExpr}
    {expected : Weft.Ty}
    {effects : Weft.EffectSet}
    {code : Code}
    {value : RuntimeVal}
    {trace : List Weft.EffectName}
    (hCompile : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile surface = .ok code)
    (hCheck : kernelCheckAgainst (parseSurface surface) expected = true)
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
    compiled_result_respects_effects_and_kernel_expected_type_tag hCheck hEffects hEval
  exact ⟨hConforms.2.1, hConforms.2.2⟩

theorem staged_machine_pure_result_respects_weakened_kernel_expected_type_tag
    {oracle : Oracle}
    {surface : SurfaceExpr}
    {expected widened : Weft.Ty}
    {code : Code}
    {value : RuntimeVal}
    {trace : List Weft.EffectName}
    (hCompile : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile surface = .ok code)
    (hCheck : kernelCheckAgainst (parseSurface surface) expected = true)
    (hSubtype : expected.SubtypeIn Weft.KernelTheory.theory widened)
    (hPure : inferEffects (parseSurface surface) = some Weft.EffectSet.empty)
    (hExec : Exec oracle code [] [value] trace) :
    (∀ effect : Weft.EffectName, effect ∉ trace) ∧
      Weft.Ty.denotesTag value.toKernelTag widened := by
  have hEval : Eval oracle (parseSurface surface) value trace :=
    staged_compile_complete hCompile hExec
  have hConforms :
      Exec oracle (compileClosed (parseSurface surface)) [] [value] trace ∧
        (∀ effect : Weft.EffectName, effect ∉ trace) ∧
        Weft.Ty.denotesTag value.toKernelTag widened :=
    compiled_pure_result_respects_weakened_kernel_expected_type_tag hCheck hSubtype hPure hEval
  exact ⟨hConforms.2.1, hConforms.2.2⟩

theorem staged_machine_result_respects_effects_and_weakened_kernel_expected_type_tag
    {oracle : Oracle}
    {surface : SurfaceExpr}
    {expected widened : Weft.Ty}
    {effects : Weft.EffectSet}
    {code : Code}
    {value : RuntimeVal}
    {trace : List Weft.EffectName}
    (hCompile : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile surface = .ok code)
    (hCheck : kernelCheckAgainst (parseSurface surface) expected = true)
    (hSubtype : expected.SubtypeIn Weft.KernelTheory.theory widened)
    (hEffects : inferEffects (parseSurface surface) = some effects)
    (hExec : Exec oracle code [] [value] trace) :
    (∀ effect : Weft.EffectName, effect ∈ trace -> effect ∈ effects.elems) ∧
      Weft.Ty.denotesTag value.toKernelTag widened := by
  have hEval : Eval oracle (parseSurface surface) value trace :=
    staged_compile_complete hCompile hExec
  have hConforms :
      Exec oracle (compileClosed (parseSurface surface)) [] [value] trace ∧
        (∀ effect : Weft.EffectName, effect ∈ trace -> effect ∈ effects.elems) ∧
        Weft.Ty.denotesTag value.toKernelTag widened :=
    compiled_result_respects_effects_and_weakened_kernel_expected_type_tag
      hCheck hSubtype hEffects hEval
  exact ⟨hConforms.2.1, hConforms.2.2⟩

theorem staged_machine_pure_result_respects_kernelSubtypeb_weakened_expected_type_tag
    {oracle : Oracle}
    {surface : SurfaceExpr}
    {expected widened : Weft.Ty}
    {code : Code}
    {value : RuntimeVal}
    {trace : List Weft.EffectName}
    (hCompile : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile surface = .ok code)
    (hCheck : kernelCheckAgainst (parseSurface surface) expected = true)
    (hSubtype : expected.kernelSubtypeb widened = true)
    (hPure : inferEffects (parseSurface surface) = some Weft.EffectSet.empty)
    (hExec : Exec oracle code [] [value] trace) :
    (∀ effect : Weft.EffectName, effect ∉ trace) ∧
      Weft.Ty.denotesTag value.toKernelTag widened := by
  have hEval : Eval oracle (parseSurface surface) value trace :=
    staged_compile_complete hCompile hExec
  have hConforms :
      Exec oracle (compileClosed (parseSurface surface)) [] [value] trace ∧
        (∀ effect : Weft.EffectName, effect ∉ trace) ∧
        Weft.Ty.denotesTag value.toKernelTag widened :=
    compiled_pure_result_respects_kernelSubtypeb_weakened_expected_type_tag
      hCheck hSubtype hPure hEval
  exact ⟨hConforms.2.1, hConforms.2.2⟩

theorem staged_machine_result_respects_effects_and_kernelSubtypeb_weakened_expected_type_tag
    {oracle : Oracle}
    {surface : SurfaceExpr}
    {expected widened : Weft.Ty}
    {effects : Weft.EffectSet}
    {code : Code}
    {value : RuntimeVal}
    {trace : List Weft.EffectName}
    (hCompile : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile surface = .ok code)
    (hCheck : kernelCheckAgainst (parseSurface surface) expected = true)
    (hSubtype : expected.kernelSubtypeb widened = true)
    (hEffects : inferEffects (parseSurface surface) = some effects)
    (hExec : Exec oracle code [] [value] trace) :
    (∀ effect : Weft.EffectName, effect ∈ trace -> effect ∈ effects.elems) ∧
      Weft.Ty.denotesTag value.toKernelTag widened := by
  have hEval : Eval oracle (parseSurface surface) value trace :=
    staged_compile_complete hCompile hExec
  have hConforms :
      Exec oracle (compileClosed (parseSurface surface)) [] [value] trace ∧
        (∀ effect : Weft.EffectName, effect ∈ trace -> effect ∈ effects.elems) ∧
        Weft.Ty.denotesTag value.toKernelTag widened :=
    compiled_result_respects_effects_and_kernelSubtypeb_weakened_expected_type_tag
      hCheck hSubtype hEffects hEval
  exact ⟨hConforms.2.1, hConforms.2.2⟩

theorem staged_machine_pure_result_respects_tag_weakened_kernel_expected_type_tag
    {oracle : Oracle}
    {surface : SurfaceExpr}
    {expected widened : Weft.Ty}
    {code : Code}
    {value : RuntimeVal}
    {trace : List Weft.EffectName}
    (hCompile : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile surface = .ok code)
    (hCheck : kernelCheckAgainst (parseSurface surface) expected = true)
    (hSubtype : ∀ tag : Weft.KernelTag, Weft.Ty.denotesTag tag expected -> Weft.Ty.denotesTag tag widened)
    (hPure : inferEffects (parseSurface surface) = some Weft.EffectSet.empty)
    (hExec : Exec oracle code [] [value] trace) :
    (∀ effect : Weft.EffectName, effect ∉ trace) ∧
      Weft.Ty.denotesTag value.toKernelTag widened := by
  have hEval : Eval oracle (parseSurface surface) value trace :=
    staged_compile_complete hCompile hExec
  have hConforms :
      Exec oracle (compileClosed (parseSurface surface)) [] [value] trace ∧
        (∀ effect : Weft.EffectName, effect ∉ trace) ∧
        Weft.Ty.denotesTag value.toKernelTag widened :=
    compiled_pure_result_respects_tag_weakened_kernel_expected_type_tag hCheck hSubtype hPure hEval
  exact ⟨hConforms.2.1, hConforms.2.2⟩

theorem staged_machine_result_respects_effects_and_tag_weakened_kernel_expected_type_tag
    {oracle : Oracle}
    {surface : SurfaceExpr}
    {expected widened : Weft.Ty}
    {effects : Weft.EffectSet}
    {code : Code}
    {value : RuntimeVal}
    {trace : List Weft.EffectName}
    (hCompile : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile surface = .ok code)
    (hCheck : kernelCheckAgainst (parseSurface surface) expected = true)
    (hSubtype : ∀ tag : Weft.KernelTag, Weft.Ty.denotesTag tag expected -> Weft.Ty.denotesTag tag widened)
    (hEffects : inferEffects (parseSurface surface) = some effects)
    (hExec : Exec oracle code [] [value] trace) :
    (∀ effect : Weft.EffectName, effect ∈ trace -> effect ∈ effects.elems) ∧
      Weft.Ty.denotesTag value.toKernelTag widened := by
  have hEval : Eval oracle (parseSurface surface) value trace :=
    staged_compile_complete hCompile hExec
  have hConforms :
      Exec oracle (compileClosed (parseSurface surface)) [] [value] trace ∧
        (∀ effect : Weft.EffectName, effect ∈ trace -> effect ∈ effects.elems) ∧
        Weft.Ty.denotesTag value.toKernelTag widened :=
    compiled_result_respects_effects_and_tag_weakened_kernel_expected_type_tag
      hCheck hSubtype hEffects hEval
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

theorem staged_result_behavior_respects_effects_and_kernel_expected_type_tag
    {oracle : Oracle}
    {surface : SurfaceExpr}
    {expected : Weft.Ty}
    {effects : Weft.EffectSet}
    {code : Code}
    {input : Weft.Input}
    {behavior : ResultBehavior}
    (hCompile : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile surface = .ok code)
    (hCheck : kernelCheckAgainst (parseSurface surface) expected = true)
    (hEffects : inferEffects (parseSurface surface) = some effects)
    (hMachine : machineResultSem oracle code input behavior) :
    (∀ effect : Weft.EffectName, effect ∈ behavior.trace -> effect ∈ effects.elems) ∧
      Weft.Ty.denotesTag behavior.result.toKernelTag expected := by
  rcases hMachine with ⟨value, trace, hExec, hBehavior⟩
  have hConforms :
      (∀ effect : Weft.EffectName, effect ∈ trace -> effect ∈ effects.elems) ∧
        Weft.Ty.denotesTag value.toKernelTag expected :=
    staged_machine_result_respects_effects_and_kernel_expected_type_tag
      hCompile hCheck hEffects hExec
  cases hBehavior
  exact hConforms

theorem staged_result_behavior_respects_effects_and_weakened_kernel_expected_type_tag
    {oracle : Oracle}
    {surface : SurfaceExpr}
    {expected widened : Weft.Ty}
    {effects : Weft.EffectSet}
    {code : Code}
    {input : Weft.Input}
    {behavior : ResultBehavior}
    (hCompile : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile surface = .ok code)
    (hCheck : kernelCheckAgainst (parseSurface surface) expected = true)
    (hSubtype : expected.SubtypeIn Weft.KernelTheory.theory widened)
    (hEffects : inferEffects (parseSurface surface) = some effects)
    (hMachine : machineResultSem oracle code input behavior) :
    (∀ effect : Weft.EffectName, effect ∈ behavior.trace -> effect ∈ effects.elems) ∧
      Weft.Ty.denotesTag behavior.result.toKernelTag widened := by
  rcases hMachine with ⟨value, trace, hExec, hBehavior⟩
  have hConforms :
      (∀ effect : Weft.EffectName, effect ∈ trace -> effect ∈ effects.elems) ∧
        Weft.Ty.denotesTag value.toKernelTag widened :=
    staged_machine_result_respects_effects_and_weakened_kernel_expected_type_tag
      hCompile hCheck hSubtype hEffects hExec
  cases hBehavior
  exact hConforms

theorem staged_result_behavior_respects_effects_and_tag_weakened_kernel_expected_type_tag
    {oracle : Oracle}
    {surface : SurfaceExpr}
    {expected widened : Weft.Ty}
    {effects : Weft.EffectSet}
    {code : Code}
    {input : Weft.Input}
    {behavior : ResultBehavior}
    (hCompile : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile surface = .ok code)
    (hCheck : kernelCheckAgainst (parseSurface surface) expected = true)
    (hSubtype : ∀ tag : Weft.KernelTag, Weft.Ty.denotesTag tag expected -> Weft.Ty.denotesTag tag widened)
    (hEffects : inferEffects (parseSurface surface) = some effects)
    (hMachine : machineResultSem oracle code input behavior) :
    (∀ effect : Weft.EffectName, effect ∈ behavior.trace -> effect ∈ effects.elems) ∧
      Weft.Ty.denotesTag behavior.result.toKernelTag widened := by
  rcases hMachine with ⟨value, trace, hExec, hBehavior⟩
  have hConforms :
      (∀ effect : Weft.EffectName, effect ∈ trace -> effect ∈ effects.elems) ∧
        Weft.Ty.denotesTag value.toKernelTag widened :=
    staged_machine_result_respects_effects_and_tag_weakened_kernel_expected_type_tag
      hCompile hCheck hSubtype hEffects hExec
  cases hBehavior
  exact hConforms

theorem staged_result_behavior_respects_effects_and_kernelSubtypeb_weakened_expected_type_tag
    {oracle : Oracle}
    {surface : SurfaceExpr}
    {expected widened : Weft.Ty}
    {effects : Weft.EffectSet}
    {code : Code}
    {input : Weft.Input}
    {behavior : ResultBehavior}
    (hCompile : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile surface = .ok code)
    (hCheck : kernelCheckAgainst (parseSurface surface) expected = true)
    (hSubtype : expected.kernelSubtypeb widened = true)
    (hEffects : inferEffects (parseSurface surface) = some effects)
    (hMachine : machineResultSem oracle code input behavior) :
    (∀ effect : Weft.EffectName, effect ∈ behavior.trace -> effect ∈ effects.elems) ∧
      Weft.Ty.denotesTag behavior.result.toKernelTag widened := by
  rcases hMachine with ⟨value, trace, hExec, hBehavior⟩
  have hConforms :
      (∀ effect : Weft.EffectName, effect ∈ trace -> effect ∈ effects.elems) ∧
        Weft.Ty.denotesTag value.toKernelTag widened :=
    staged_machine_result_respects_effects_and_kernelSubtypeb_weakened_expected_type_tag
      hCompile hCheck hSubtype hEffects hExec
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

theorem staged_result_behavior_trace_free_and_kernel_typed_when_pure_tag
    {oracle : Oracle}
    {surface : SurfaceExpr}
    {expected : Weft.Ty}
    {code : Code}
    {input : Weft.Input}
    {behavior : ResultBehavior}
    (hCompile : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile surface = .ok code)
    (hCheck : kernelCheckAgainst (parseSurface surface) expected = true)
    (hPure : inferEffects (parseSurface surface) = some Weft.EffectSet.empty)
    (hMachine : machineResultSem oracle code input behavior) :
    (∀ effect : Weft.EffectName, effect ∉ behavior.trace) ∧
      Weft.Ty.denotesTag behavior.result.toKernelTag expected := by
  rcases hMachine with ⟨value, trace, hExec, hBehavior⟩
  have hConforms :
      (∀ effect : Weft.EffectName, effect ∉ trace) ∧
        Weft.Ty.denotesTag value.toKernelTag expected :=
    staged_machine_pure_result_respects_kernel_expected_type_tag
      hCompile hCheck hPure hExec
  cases hBehavior
  exact hConforms

theorem staged_result_behavior_trace_free_and_weakened_kernel_typed_when_pure_tag
    {oracle : Oracle}
    {surface : SurfaceExpr}
    {expected widened : Weft.Ty}
    {code : Code}
    {input : Weft.Input}
    {behavior : ResultBehavior}
    (hCompile : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile surface = .ok code)
    (hCheck : kernelCheckAgainst (parseSurface surface) expected = true)
    (hSubtype : expected.SubtypeIn Weft.KernelTheory.theory widened)
    (hPure : inferEffects (parseSurface surface) = some Weft.EffectSet.empty)
    (hMachine : machineResultSem oracle code input behavior) :
    (∀ effect : Weft.EffectName, effect ∉ behavior.trace) ∧
      Weft.Ty.denotesTag behavior.result.toKernelTag widened := by
  rcases hMachine with ⟨value, trace, hExec, hBehavior⟩
  have hConforms :
      (∀ effect : Weft.EffectName, effect ∉ trace) ∧
        Weft.Ty.denotesTag value.toKernelTag widened :=
    staged_machine_pure_result_respects_weakened_kernel_expected_type_tag
      hCompile hCheck hSubtype hPure hExec
  cases hBehavior
  exact hConforms

theorem staged_result_behavior_trace_free_and_tag_weakened_kernel_typed_when_pure_tag
    {oracle : Oracle}
    {surface : SurfaceExpr}
    {expected widened : Weft.Ty}
    {code : Code}
    {input : Weft.Input}
    {behavior : ResultBehavior}
    (hCompile : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile surface = .ok code)
    (hCheck : kernelCheckAgainst (parseSurface surface) expected = true)
    (hSubtype : ∀ tag : Weft.KernelTag, Weft.Ty.denotesTag tag expected -> Weft.Ty.denotesTag tag widened)
    (hPure : inferEffects (parseSurface surface) = some Weft.EffectSet.empty)
    (hMachine : machineResultSem oracle code input behavior) :
    (∀ effect : Weft.EffectName, effect ∉ behavior.trace) ∧
      Weft.Ty.denotesTag behavior.result.toKernelTag widened := by
  rcases hMachine with ⟨value, trace, hExec, hBehavior⟩
  have hConforms :
      (∀ effect : Weft.EffectName, effect ∉ trace) ∧
        Weft.Ty.denotesTag value.toKernelTag widened :=
    staged_machine_pure_result_respects_tag_weakened_kernel_expected_type_tag
      hCompile hCheck hSubtype hPure hExec
  cases hBehavior
  exact hConforms

theorem staged_result_behavior_trace_free_and_kernelSubtypeb_weakened_typed_when_pure_tag
    {oracle : Oracle}
    {surface : SurfaceExpr}
    {expected widened : Weft.Ty}
    {code : Code}
    {input : Weft.Input}
    {behavior : ResultBehavior}
    (hCompile : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile surface = .ok code)
    (hCheck : kernelCheckAgainst (parseSurface surface) expected = true)
    (hSubtype : expected.kernelSubtypeb widened = true)
    (hPure : inferEffects (parseSurface surface) = some Weft.EffectSet.empty)
    (hMachine : machineResultSem oracle code input behavior) :
    (∀ effect : Weft.EffectName, effect ∉ behavior.trace) ∧
      Weft.Ty.denotesTag behavior.result.toKernelTag widened := by
  rcases hMachine with ⟨value, trace, hExec, hBehavior⟩
  have hConforms :
      (∀ effect : Weft.EffectName, effect ∉ trace) ∧
        Weft.Ty.denotesTag value.toKernelTag widened :=
    staged_machine_pure_result_respects_kernelSubtypeb_weakened_expected_type_tag
      hCompile hCheck hSubtype hPure hExec
  cases hBehavior
  exact hConforms

theorem staged_result_behavior_respects_effects_and_ptr_covariant_kernel_expected_type_tag
    {oracle : Oracle}
    {surface : SurfaceExpr}
    {inner₁ inner₂ : Weft.Ty}
    {effects : Weft.EffectSet}
    {code : Code}
    {input : Weft.Input}
    {behavior : ResultBehavior}
    (hCompile : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile surface = .ok code)
    (hCheck : kernelCheckAgainst (parseSurface surface) (Weft.Ty.ptr inner₁) = true)
    (hSubtype : inner₁.kernelSubtypeb inner₂ = true)
    (hEffects : inferEffects (parseSurface surface) = some effects)
    (hMachine : machineResultSem oracle code input behavior) :
    (∀ effect : Weft.EffectName, effect ∈ behavior.trace -> effect ∈ effects.elems) ∧
      Weft.Ty.denotesTag behavior.result.toKernelTag (Weft.Ty.ptr inner₂) := by
  exact staged_result_behavior_respects_effects_and_tag_weakened_kernel_expected_type_tag
    hCompile hCheck (tag_subtype_of_ptr_covariant_kernelSubtypeb hSubtype) hEffects hMachine

theorem staged_result_behavior_trace_free_and_ptr_covariant_kernel_typed_when_pure_tag
    {oracle : Oracle}
    {surface : SurfaceExpr}
    {inner₁ inner₂ : Weft.Ty}
    {code : Code}
    {input : Weft.Input}
    {behavior : ResultBehavior}
    (hCompile : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile surface = .ok code)
    (hCheck : kernelCheckAgainst (parseSurface surface) (Weft.Ty.ptr inner₁) = true)
    (hSubtype : inner₁.kernelSubtypeb inner₂ = true)
    (hPure : inferEffects (parseSurface surface) = some Weft.EffectSet.empty)
    (hMachine : machineResultSem oracle code input behavior) :
    (∀ effect : Weft.EffectName, effect ∉ behavior.trace) ∧
      Weft.Ty.denotesTag behavior.result.toKernelTag (Weft.Ty.ptr inner₂) := by
  exact staged_result_behavior_trace_free_and_tag_weakened_kernel_typed_when_pure_tag
    hCompile hCheck (tag_subtype_of_ptr_covariant_kernelSubtypeb hSubtype) hPure hMachine

theorem staged_result_behavior_respects_effects_and_rc_covariant_kernel_expected_type_tag
    {oracle : Oracle}
    {surface : SurfaceExpr}
    {inner₁ inner₂ : Weft.Ty}
    {effects : Weft.EffectSet}
    {code : Code}
    {input : Weft.Input}
    {behavior : ResultBehavior}
    (hCompile : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile surface = .ok code)
    (hCheck : kernelCheckAgainst (parseSurface surface) (Weft.Ty.rc inner₁) = true)
    (hSubtype : inner₁.kernelSubtypeb inner₂ = true)
    (hEffects : inferEffects (parseSurface surface) = some effects)
    (hMachine : machineResultSem oracle code input behavior) :
    (∀ effect : Weft.EffectName, effect ∈ behavior.trace -> effect ∈ effects.elems) ∧
      Weft.Ty.denotesTag behavior.result.toKernelTag (Weft.Ty.rc inner₂) := by
  exact staged_result_behavior_respects_effects_and_tag_weakened_kernel_expected_type_tag
    hCompile hCheck (tag_subtype_of_rc_covariant_kernelSubtypeb hSubtype) hEffects hMachine

theorem staged_result_behavior_trace_free_and_rc_covariant_kernel_typed_when_pure_tag
    {oracle : Oracle}
    {surface : SurfaceExpr}
    {inner₁ inner₂ : Weft.Ty}
    {code : Code}
    {input : Weft.Input}
    {behavior : ResultBehavior}
    (hCompile : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile surface = .ok code)
    (hCheck : kernelCheckAgainst (parseSurface surface) (Weft.Ty.rc inner₁) = true)
    (hSubtype : inner₁.kernelSubtypeb inner₂ = true)
    (hPure : inferEffects (parseSurface surface) = some Weft.EffectSet.empty)
    (hMachine : machineResultSem oracle code input behavior) :
    (∀ effect : Weft.EffectName, effect ∉ behavior.trace) ∧
      Weft.Ty.denotesTag behavior.result.toKernelTag (Weft.Ty.rc inner₂) := by
  exact staged_result_behavior_trace_free_and_tag_weakened_kernel_typed_when_pure_tag
    hCompile hCheck (tag_subtype_of_rc_covariant_kernelSubtypeb hSubtype) hPure hMachine

theorem staged_result_behavior_respects_effects_and_fn_subtype_kernel_expected_type_tag
    {oracle : Oracle}
    {surface : SurfaceExpr}
    {arg₁ ret₁ arg₂ ret₂ : Weft.Ty}
    {eff₁ eff₂ : Weft.EffectSet}
    {effects : Weft.EffectSet}
    {code : Code}
    {input : Weft.Input}
    {behavior : ResultBehavior}
    (hCompile : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile surface = .ok code)
    (hCheck : kernelCheckAgainst (parseSurface surface) (Weft.Ty.fn arg₁ eff₁ ret₁) = true)
    (hArg : arg₂.kernelSubtypeb arg₁ = true)
    (hEff : Weft.EffectSet.subsetb eff₁ eff₂ = true)
    (hRet : ret₁.kernelSubtypeb ret₂ = true)
    (hEffects : inferEffects (parseSurface surface) = some effects)
    (hMachine : machineResultSem oracle code input behavior) :
    (∀ effect : Weft.EffectName, effect ∈ behavior.trace -> effect ∈ effects.elems) ∧
      Weft.Ty.denotesTag behavior.result.toKernelTag (Weft.Ty.fn arg₂ eff₂ ret₂) := by
  exact staged_result_behavior_respects_effects_and_tag_weakened_kernel_expected_type_tag
    hCompile hCheck (tag_subtype_of_fn_subtype_kernelSubtypeb hArg hEff hRet) hEffects hMachine

theorem staged_result_behavior_trace_free_and_fn_subtype_kernel_typed_when_pure_tag
    {oracle : Oracle}
    {surface : SurfaceExpr}
    {arg₁ ret₁ arg₂ ret₂ : Weft.Ty}
    {eff₁ eff₂ : Weft.EffectSet}
    {code : Code}
    {input : Weft.Input}
    {behavior : ResultBehavior}
    (hCompile : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile surface = .ok code)
    (hCheck : kernelCheckAgainst (parseSurface surface) (Weft.Ty.fn arg₁ eff₁ ret₁) = true)
    (hArg : arg₂.kernelSubtypeb arg₁ = true)
    (hEff : Weft.EffectSet.subsetb eff₁ eff₂ = true)
    (hRet : ret₁.kernelSubtypeb ret₂ = true)
    (hPure : inferEffects (parseSurface surface) = some Weft.EffectSet.empty)
    (hMachine : machineResultSem oracle code input behavior) :
    (∀ effect : Weft.EffectName, effect ∉ behavior.trace) ∧
      Weft.Ty.denotesTag behavior.result.toKernelTag (Weft.Ty.fn arg₂ eff₂ ret₂) := by
  exact staged_result_behavior_trace_free_and_tag_weakened_kernel_typed_when_pure_tag
    hCompile hCheck (tag_subtype_of_fn_subtype_kernelSubtypeb hArg hEff hRet) hPure hMachine

end Weft.CoreEffects
