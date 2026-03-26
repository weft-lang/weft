import Weft.Properties.CoreEffectIOObservations
import Weft.Properties.CompilerCorrectness

namespace Weft.CoreEffects

theorem machine_io_semanticEq_of_surfaceEq
    (oracle : Oracle)
    {surface₁ surface₂ : SurfaceExpr}
    {code₁ code₂ : Code}
    (hCompile₁ : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile surface₁ = .ok code₁)
    (hCompile₂ : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile surface₂ = .ok code₂)
    (hEq : Weft.SemanticEq (surfaceIOSem oracle) surface₁ surface₂) :
    Weft.SemanticEq (machineIOSem oracle) code₁ code₂ :=
  Weft.compiled_semanticEq_of_sourceEq
    (staged_whole_io_compiler_theorem oracle)
    (staged_whole_io_compiler_reflection_theorem oracle)
    hCompile₁ hCompile₂ hEq

theorem machine_io_result_semanticEq_of_surfaceEq
    (oracle : Oracle)
    {surface₁ surface₂ : SurfaceExpr}
    {code₁ code₂ : Code}
    (hCompile₁ : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile surface₁ = .ok code₁)
    (hCompile₂ : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile surface₂ = .ok code₂)
    (hEq : Weft.SemanticEq (surfaceIOResultSem oracle) surface₁ surface₂) :
    Weft.SemanticEq (machineIOResultSem oracle) code₁ code₂ :=
  Weft.compiled_semanticEq_of_sourceEq
    (staged_whole_io_result_compiler_theorem oracle)
    (staged_whole_io_result_compiler_reflection_theorem oracle)
    hCompile₁ hCompile₂ hEq

theorem machine_semanticEq_of_surfaceEq
    (oracle : Oracle)
    {surface₁ surface₂ : SurfaceExpr}
    {code₁ code₂ : Code}
    (hCompile₁ : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile surface₁ = .ok code₁)
    (hCompile₂ : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile surface₂ = .ok code₂)
    (hEq : Weft.SemanticEq (surfaceSem oracle) surface₁ surface₂) :
    Weft.SemanticEq (machineSem oracle) code₁ code₂ :=
  Weft.compiled_semanticEq_of_sourceEq
    (staged_whole_compiler_theorem oracle)
    (staged_whole_compiler_reflection_theorem oracle)
    hCompile₁ hCompile₂ hEq

theorem machine_result_semanticEq_of_surfaceEq
    (oracle : Oracle)
    {surface₁ surface₂ : SurfaceExpr}
    {code₁ code₂ : Code}
    (hCompile₁ : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile surface₁ = .ok code₁)
    (hCompile₂ : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile surface₂ = .ok code₂)
    (hEq : Weft.SemanticEq (surfaceResultSem oracle) surface₁ surface₂) :
    Weft.SemanticEq (machineResultSem oracle) code₁ code₂ :=
  Weft.compiled_semanticEq_of_sourceEq
    (staged_whole_result_compiler_theorem oracle)
    (staged_whole_result_compiler_reflection_theorem oracle)
    hCompile₁ hCompile₂ hEq

theorem staged_bootstrap_surface_io_semantics_stable
    (oracle : Oracle)
    {compiler₁ compiler₂ compiler₃ : SurfaceExpr}
    (h₁₂ : Weft.SemanticEq (surfaceIOSem oracle) compiler₁ compiler₂)
    (h₂₃ : Weft.SemanticEq (surfaceIOSem oracle) compiler₂ compiler₃) :
    Weft.SemanticEq (surfaceIOSem oracle) compiler₁ compiler₃ :=
  Weft.bootstrap_semantics_stable (surfaceIOSem oracle) h₁₂ h₂₃

theorem staged_bootstrap_surface_io_result_semantics_stable
    (oracle : Oracle)
    {compiler₁ compiler₂ compiler₃ : SurfaceExpr}
    (h₁₂ : Weft.SemanticEq (surfaceIOResultSem oracle) compiler₁ compiler₂)
    (h₂₃ : Weft.SemanticEq (surfaceIOResultSem oracle) compiler₂ compiler₃) :
    Weft.SemanticEq (surfaceIOResultSem oracle) compiler₁ compiler₃ :=
  Weft.bootstrap_semantics_stable (surfaceIOResultSem oracle) h₁₂ h₂₃

theorem staged_bootstrap_machine_io_semantics_stable
    (oracle : Oracle)
    {compiler₁ compiler₂ compiler₃ : SurfaceExpr}
    {code₁ code₂ code₃ : Code}
    (hCompile₁ : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile compiler₁ = .ok code₁)
    (_hCompile₂ : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile compiler₂ = .ok code₂)
    (hCompile₃ : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile compiler₃ = .ok code₃)
    (h₁₂ : Weft.SemanticEq (surfaceIOSem oracle) compiler₁ compiler₂)
    (h₂₃ : Weft.SemanticEq (surfaceIOSem oracle) compiler₂ compiler₃) :
    Weft.SemanticEq (machineIOSem oracle) code₁ code₃ :=
  Weft.compiled_bootstrap_semantics_stable
    (staged_whole_io_compiler_theorem oracle)
    (staged_whole_io_compiler_reflection_theorem oracle)
    hCompile₁ _hCompile₂ hCompile₃ h₁₂ h₂₃

theorem staged_bootstrap_surface_semantics_stable
    (oracle : Oracle)
    {compiler₁ compiler₂ compiler₃ : SurfaceExpr}
    (h₁₂ : Weft.SemanticEq (surfaceSem oracle) compiler₁ compiler₂)
    (h₂₃ : Weft.SemanticEq (surfaceSem oracle) compiler₂ compiler₃) :
    Weft.SemanticEq (surfaceSem oracle) compiler₁ compiler₃ :=
  Weft.bootstrap_semantics_stable (surfaceSem oracle) h₁₂ h₂₃

theorem staged_bootstrap_surface_result_semantics_stable
    (oracle : Oracle)
    {compiler₁ compiler₂ compiler₃ : SurfaceExpr}
    (h₁₂ : Weft.SemanticEq (surfaceResultSem oracle) compiler₁ compiler₂)
    (h₂₃ : Weft.SemanticEq (surfaceResultSem oracle) compiler₂ compiler₃) :
    Weft.SemanticEq (surfaceResultSem oracle) compiler₁ compiler₃ :=
  Weft.bootstrap_semantics_stable (surfaceResultSem oracle) h₁₂ h₂₃

theorem staged_bootstrap_machine_io_result_semantics_stable
    (oracle : Oracle)
    {compiler₁ compiler₂ compiler₃ : SurfaceExpr}
    {code₁ code₂ code₃ : Code}
    (hCompile₁ : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile compiler₁ = .ok code₁)
    (_hCompile₂ : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile compiler₂ = .ok code₂)
    (hCompile₃ : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile compiler₃ = .ok code₃)
    (h₁₂ : Weft.SemanticEq (surfaceIOResultSem oracle) compiler₁ compiler₂)
    (h₂₃ : Weft.SemanticEq (surfaceIOResultSem oracle) compiler₂ compiler₃) :
    Weft.SemanticEq (machineIOResultSem oracle) code₁ code₃ :=
  Weft.compiled_bootstrap_semantics_stable
    (staged_whole_io_result_compiler_theorem oracle)
    (staged_whole_io_result_compiler_reflection_theorem oracle)
    hCompile₁ _hCompile₂ hCompile₃ h₁₂ h₂₃

theorem staged_bootstrap_machine_semantics_stable
    (oracle : Oracle)
    {compiler₁ compiler₂ compiler₃ : SurfaceExpr}
    {code₁ code₂ code₃ : Code}
    (hCompile₁ : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile compiler₁ = .ok code₁)
    (_hCompile₂ : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile compiler₂ = .ok code₂)
    (hCompile₃ : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile compiler₃ = .ok code₃)
    (h₁₂ : Weft.SemanticEq (surfaceSem oracle) compiler₁ compiler₂)
    (h₂₃ : Weft.SemanticEq (surfaceSem oracle) compiler₂ compiler₃) :
    Weft.SemanticEq (machineSem oracle) code₁ code₃ :=
  Weft.compiled_bootstrap_semantics_stable
    (staged_whole_compiler_theorem oracle)
    (staged_whole_compiler_reflection_theorem oracle)
    hCompile₁ _hCompile₂ hCompile₃ h₁₂ h₂₃

theorem staged_bootstrap_machine_result_semantics_stable
    (oracle : Oracle)
    {compiler₁ compiler₂ compiler₃ : SurfaceExpr}
    {code₁ code₂ code₃ : Code}
    (hCompile₁ : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile compiler₁ = .ok code₁)
    (_hCompile₂ : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile compiler₂ = .ok code₂)
    (hCompile₃ : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile compiler₃ = .ok code₃)
    (h₁₂ : Weft.SemanticEq (surfaceResultSem oracle) compiler₁ compiler₂)
    (h₂₃ : Weft.SemanticEq (surfaceResultSem oracle) compiler₂ compiler₃) :
    Weft.SemanticEq (machineResultSem oracle) code₁ code₃ :=
  Weft.compiled_bootstrap_semantics_stable
    (staged_whole_result_compiler_theorem oracle)
    (staged_whole_result_compiler_reflection_theorem oracle)
    hCompile₁ _hCompile₂ hCompile₃ h₁₂ h₂₃

theorem machine_io_result_behavior_only_reports_inferred_effects_and_kernel_expected_type_tag_of_surfaceEq
    (oracle : Oracle)
    {surface₁ surface₂ : SurfaceExpr}
    {code₁ code₂ : Code}
    {expected : Weft.Ty}
    {effects : Weft.EffectSet}
    {input : Weft.Input}
    {behavior : IOResultBehavior}
    (hCompile₁ : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile surface₁ = .ok code₁)
    (hCompile₂ : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile surface₂ = .ok code₂)
    (hEq : Weft.SemanticEq (surfaceIOResultSem oracle) surface₁ surface₂)
    (hCheck₁ : kernelCheckAgainst (parseSurface surface₁) expected = true)
    (hEffects₁ : inferEffects (parseSurface surface₁) = some effects)
    (hMachine₂ : machineIOResultSem oracle code₂ input behavior) :
    (∀ event, event ∈ behavior.trace ->
      ∃ effect : Weft.EffectName,
        effect ∈ effects.elems ∧ event = Weft.IOEvent.effectQuery effect (oracle effect)) ∧
      Weft.Ty.denotesTag behavior.result.toKernelTag expected := by
  have hMachine₁ : machineIOResultSem oracle code₁ input behavior :=
    (machine_io_result_semanticEq_of_surfaceEq oracle hCompile₁ hCompile₂ hEq input behavior).2 hMachine₂
  exact staged_io_result_behavior_only_reports_inferred_effects_and_kernel_expected_type_tag
    hCompile₁ hCheck₁ hEffects₁ hMachine₁

theorem machine_io_result_behavior_trace_free_and_kernel_typed_when_pure_of_surfaceEq
    (oracle : Oracle)
    {surface₁ surface₂ : SurfaceExpr}
    {code₁ code₂ : Code}
    {expected : Weft.Ty}
    {input : Weft.Input}
    {behavior : IOResultBehavior}
    (hCompile₁ : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile surface₁ = .ok code₁)
    (hCompile₂ : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile surface₂ = .ok code₂)
    (hEq : Weft.SemanticEq (surfaceIOResultSem oracle) surface₁ surface₂)
    (hCheck₁ : kernelCheckAgainst (parseSurface surface₁) expected = true)
    (hPure₁ : inferEffects (parseSurface surface₁) = some Weft.EffectSet.empty)
    (hMachine₂ : machineIOResultSem oracle code₂ input behavior) :
    behavior.trace = [] ∧
      Weft.Ty.denotesTag behavior.result.toKernelTag expected := by
  have hMachine₁ : machineIOResultSem oracle code₁ input behavior :=
    (machine_io_result_semanticEq_of_surfaceEq oracle hCompile₁ hCompile₂ hEq input behavior).2 hMachine₂
  exact staged_io_result_behavior_trace_free_and_kernel_typed_when_pure_tag
    hCompile₁ hCheck₁ hPure₁ hMachine₁

theorem machine_io_result_behavior_only_reports_inferred_effects_and_ptr_covariant_kernel_expected_type_tag_of_surfaceEq
    (oracle : Oracle)
    {surface₁ surface₂ : SurfaceExpr}
    {code₁ code₂ : Code}
    {inner₁ inner₂ : Weft.Ty}
    {effects : Weft.EffectSet}
    {input : Weft.Input}
    {behavior : IOResultBehavior}
    (hCompile₁ : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile surface₁ = .ok code₁)
    (hCompile₂ : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile surface₂ = .ok code₂)
    (hEq : Weft.SemanticEq (surfaceIOResultSem oracle) surface₁ surface₂)
    (hCheck₁ : kernelCheckAgainst (parseSurface surface₁) (Weft.Ty.ptr inner₁) = true)
    (hSubtype : inner₁.kernelSubtypeb inner₂ = true)
    (hEffects₁ : inferEffects (parseSurface surface₁) = some effects)
    (hMachine₂ : machineIOResultSem oracle code₂ input behavior) :
    (∀ event, event ∈ behavior.trace ->
      ∃ effect : Weft.EffectName,
        effect ∈ effects.elems ∧ event = Weft.IOEvent.effectQuery effect (oracle effect)) ∧
      Weft.Ty.denotesTag behavior.result.toKernelTag (Weft.Ty.ptr inner₂) := by
  have hMachine₁ : machineIOResultSem oracle code₁ input behavior :=
    (machine_io_result_semanticEq_of_surfaceEq oracle hCompile₁ hCompile₂ hEq input behavior).2 hMachine₂
  exact staged_io_result_behavior_only_reports_inferred_effects_and_ptr_covariant_kernel_expected_type_tag
    hCompile₁ hCheck₁ hSubtype hEffects₁ hMachine₁

theorem machine_io_result_behavior_trace_free_and_ptr_covariant_kernel_typed_when_pure_of_surfaceEq
    (oracle : Oracle)
    {surface₁ surface₂ : SurfaceExpr}
    {code₁ code₂ : Code}
    {inner₁ inner₂ : Weft.Ty}
    {input : Weft.Input}
    {behavior : IOResultBehavior}
    (hCompile₁ : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile surface₁ = .ok code₁)
    (hCompile₂ : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile surface₂ = .ok code₂)
    (hEq : Weft.SemanticEq (surfaceIOResultSem oracle) surface₁ surface₂)
    (hCheck₁ : kernelCheckAgainst (parseSurface surface₁) (Weft.Ty.ptr inner₁) = true)
    (hSubtype : inner₁.kernelSubtypeb inner₂ = true)
    (hPure₁ : inferEffects (parseSurface surface₁) = some Weft.EffectSet.empty)
    (hMachine₂ : machineIOResultSem oracle code₂ input behavior) :
    behavior.trace = [] ∧
      Weft.Ty.denotesTag behavior.result.toKernelTag (Weft.Ty.ptr inner₂) := by
  have hMachine₁ : machineIOResultSem oracle code₁ input behavior :=
    (machine_io_result_semanticEq_of_surfaceEq oracle hCompile₁ hCompile₂ hEq input behavior).2 hMachine₂
  exact staged_io_result_behavior_trace_free_and_ptr_covariant_kernel_typed_when_pure_tag
    hCompile₁ hCheck₁ hSubtype hPure₁ hMachine₁

theorem machine_io_result_behavior_only_reports_inferred_effects_and_rc_covariant_kernel_expected_type_tag_of_surfaceEq
    (oracle : Oracle)
    {surface₁ surface₂ : SurfaceExpr}
    {code₁ code₂ : Code}
    {inner₁ inner₂ : Weft.Ty}
    {effects : Weft.EffectSet}
    {input : Weft.Input}
    {behavior : IOResultBehavior}
    (hCompile₁ : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile surface₁ = .ok code₁)
    (hCompile₂ : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile surface₂ = .ok code₂)
    (hEq : Weft.SemanticEq (surfaceIOResultSem oracle) surface₁ surface₂)
    (hCheck₁ : kernelCheckAgainst (parseSurface surface₁) (Weft.Ty.rc inner₁) = true)
    (hSubtype : inner₁.kernelSubtypeb inner₂ = true)
    (hEffects₁ : inferEffects (parseSurface surface₁) = some effects)
    (hMachine₂ : machineIOResultSem oracle code₂ input behavior) :
    (∀ event, event ∈ behavior.trace ->
      ∃ effect : Weft.EffectName,
        effect ∈ effects.elems ∧ event = Weft.IOEvent.effectQuery effect (oracle effect)) ∧
      Weft.Ty.denotesTag behavior.result.toKernelTag (Weft.Ty.rc inner₂) := by
  have hMachine₁ : machineIOResultSem oracle code₁ input behavior :=
    (machine_io_result_semanticEq_of_surfaceEq oracle hCompile₁ hCompile₂ hEq input behavior).2 hMachine₂
  exact staged_io_result_behavior_only_reports_inferred_effects_and_rc_covariant_kernel_expected_type_tag
    hCompile₁ hCheck₁ hSubtype hEffects₁ hMachine₁

theorem machine_io_result_behavior_trace_free_and_rc_covariant_kernel_typed_when_pure_of_surfaceEq
    (oracle : Oracle)
    {surface₁ surface₂ : SurfaceExpr}
    {code₁ code₂ : Code}
    {inner₁ inner₂ : Weft.Ty}
    {input : Weft.Input}
    {behavior : IOResultBehavior}
    (hCompile₁ : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile surface₁ = .ok code₁)
    (hCompile₂ : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile surface₂ = .ok code₂)
    (hEq : Weft.SemanticEq (surfaceIOResultSem oracle) surface₁ surface₂)
    (hCheck₁ : kernelCheckAgainst (parseSurface surface₁) (Weft.Ty.rc inner₁) = true)
    (hSubtype : inner₁.kernelSubtypeb inner₂ = true)
    (hPure₁ : inferEffects (parseSurface surface₁) = some Weft.EffectSet.empty)
    (hMachine₂ : machineIOResultSem oracle code₂ input behavior) :
    behavior.trace = [] ∧
      Weft.Ty.denotesTag behavior.result.toKernelTag (Weft.Ty.rc inner₂) := by
  have hMachine₁ : machineIOResultSem oracle code₁ input behavior :=
    (machine_io_result_semanticEq_of_surfaceEq oracle hCompile₁ hCompile₂ hEq input behavior).2 hMachine₂
  exact staged_io_result_behavior_trace_free_and_rc_covariant_kernel_typed_when_pure_tag
    hCompile₁ hCheck₁ hSubtype hPure₁ hMachine₁

theorem machine_io_result_behavior_only_reports_inferred_effects_and_fn_subtype_kernel_expected_type_tag_of_surfaceEq
    (oracle : Oracle)
    {surface₁ surface₂ : SurfaceExpr}
    {code₁ code₂ : Code}
    {arg₁ ret₁ arg₂ ret₂ : Weft.Ty}
    {eff₁ eff₂ : Weft.EffectSet}
    {effects : Weft.EffectSet}
    {input : Weft.Input}
    {behavior : IOResultBehavior}
    (hCompile₁ : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile surface₁ = .ok code₁)
    (hCompile₂ : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile surface₂ = .ok code₂)
    (hEq : Weft.SemanticEq (surfaceIOResultSem oracle) surface₁ surface₂)
    (hCheck₁ : kernelCheckAgainst (parseSurface surface₁) (Weft.Ty.fn arg₁ eff₁ ret₁) = true)
    (hArg : arg₂.kernelSubtypeb arg₁ = true)
    (hEff : Weft.EffectSet.subsetb eff₁ eff₂ = true)
    (hRet : ret₁.kernelSubtypeb ret₂ = true)
    (hEffects₁ : inferEffects (parseSurface surface₁) = some effects)
    (hMachine₂ : machineIOResultSem oracle code₂ input behavior) :
    (∀ event, event ∈ behavior.trace ->
      ∃ effect : Weft.EffectName,
        effect ∈ effects.elems ∧ event = Weft.IOEvent.effectQuery effect (oracle effect)) ∧
      Weft.Ty.denotesTag behavior.result.toKernelTag (Weft.Ty.fn arg₂ eff₂ ret₂) := by
  have hMachine₁ : machineIOResultSem oracle code₁ input behavior :=
    (machine_io_result_semanticEq_of_surfaceEq oracle hCompile₁ hCompile₂ hEq input behavior).2 hMachine₂
  exact staged_io_result_behavior_only_reports_inferred_effects_and_fn_subtype_kernel_expected_type_tag
    hCompile₁ hCheck₁ hArg hEff hRet hEffects₁ hMachine₁

theorem machine_io_result_behavior_trace_free_and_fn_subtype_kernel_typed_when_pure_of_surfaceEq
    (oracle : Oracle)
    {surface₁ surface₂ : SurfaceExpr}
    {code₁ code₂ : Code}
    {arg₁ ret₁ arg₂ ret₂ : Weft.Ty}
    {eff₁ eff₂ : Weft.EffectSet}
    {input : Weft.Input}
    {behavior : IOResultBehavior}
    (hCompile₁ : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile surface₁ = .ok code₁)
    (hCompile₂ : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile surface₂ = .ok code₂)
    (hEq : Weft.SemanticEq (surfaceIOResultSem oracle) surface₁ surface₂)
    (hCheck₁ : kernelCheckAgainst (parseSurface surface₁) (Weft.Ty.fn arg₁ eff₁ ret₁) = true)
    (hArg : arg₂.kernelSubtypeb arg₁ = true)
    (hEff : Weft.EffectSet.subsetb eff₁ eff₂ = true)
    (hRet : ret₁.kernelSubtypeb ret₂ = true)
    (hPure₁ : inferEffects (parseSurface surface₁) = some Weft.EffectSet.empty)
    (hMachine₂ : machineIOResultSem oracle code₂ input behavior) :
    behavior.trace = [] ∧
      Weft.Ty.denotesTag behavior.result.toKernelTag (Weft.Ty.fn arg₂ eff₂ ret₂) := by
  have hMachine₁ : machineIOResultSem oracle code₁ input behavior :=
    (machine_io_result_semanticEq_of_surfaceEq oracle hCompile₁ hCompile₂ hEq input behavior).2 hMachine₂
  exact staged_io_result_behavior_trace_free_and_fn_subtype_kernel_typed_when_pure_tag
    hCompile₁ hCheck₁ hArg hEff hRet hPure₁ hMachine₁

theorem machine_io_behavior_has_no_non_effect_events_of_surfaceEq
    (oracle : Oracle)
    {surface₁ surface₂ : SurfaceExpr}
    {code₁ code₂ : Code}
    {input : Weft.Input}
    {behavior : Weft.Behavior}
    (hCompile₁ : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile surface₁ = .ok code₁)
    (hCompile₂ : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile surface₂ = .ok code₂)
    (hEq : Weft.SemanticEq (surfaceIOSem oracle) surface₁ surface₂)
    (hMachine₂ : machineIOSem oracle code₂ input behavior) :
    ∀ event, event ∈ behavior.trace ->
      ∃ effect : Weft.EffectName,
        event = Weft.IOEvent.effectQuery effect (oracle effect) := by
  have hMachine₁ : machineIOSem oracle code₁ input behavior :=
    (machine_io_semanticEq_of_surfaceEq oracle hCompile₁ hCompile₂ hEq input behavior).2 hMachine₂
  exact staged_io_behavior_has_no_non_effect_events hCompile₁ hMachine₁

theorem machine_behavior_respects_inferred_effects_of_surfaceEq
    (oracle : Oracle)
    {surface₁ surface₂ : SurfaceExpr}
    {code₁ code₂ : Code}
    {effects : Weft.EffectSet}
    {input : Weft.Input}
    {behavior : EffectBehavior}
    (hCompile₁ : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile surface₁ = .ok code₁)
    (hCompile₂ : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile surface₂ = .ok code₂)
    (hEq : Weft.SemanticEq (surfaceSem oracle) surface₁ surface₂)
    (hEffects₁ : inferEffects (parseSurface surface₁) = some effects)
    (hMachine₂ : machineSem oracle code₂ input behavior) :
    ∀ effect : Weft.EffectName, effect ∈ behavior.trace -> effect ∈ effects.elems := by
  have hMachine₁ : machineSem oracle code₁ input behavior :=
    (machine_semanticEq_of_surfaceEq oracle hCompile₁ hCompile₂ hEq input behavior).2 hMachine₂
  exact staged_machine_behavior_respects_inferred_effects hCompile₁ hEffects₁ hMachine₁

theorem machine_io_behavior_only_reports_inferred_effects_of_surfaceEq
    (oracle : Oracle)
    {surface₁ surface₂ : SurfaceExpr}
    {code₁ code₂ : Code}
    {effects : Weft.EffectSet}
    {input : Weft.Input}
    {behavior : Weft.Behavior}
    (hCompile₁ : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile surface₁ = .ok code₁)
    (hCompile₂ : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile surface₂ = .ok code₂)
    (hEq : Weft.SemanticEq (surfaceIOSem oracle) surface₁ surface₂)
    (hEffects₁ : inferEffects (parseSurface surface₁) = some effects)
    (hMachine₂ : machineIOSem oracle code₂ input behavior) :
    ∀ event, event ∈ behavior.trace ->
      ∃ effect : Weft.EffectName,
        effect ∈ effects.elems ∧ event = Weft.IOEvent.effectQuery effect (oracle effect) := by
  have hMachine₁ : machineIOSem oracle code₁ input behavior :=
    (machine_io_semanticEq_of_surfaceEq oracle hCompile₁ hCompile₂ hEq input behavior).2 hMachine₂
  exact staged_io_behavior_only_reports_inferred_effects hCompile₁ hEffects₁ hMachine₁

theorem machine_io_result_behavior_has_no_non_effect_events_of_surfaceEq
    (oracle : Oracle)
    {surface₁ surface₂ : SurfaceExpr}
    {code₁ code₂ : Code}
    {input : Weft.Input}
    {behavior : IOResultBehavior}
    (hCompile₁ : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile surface₁ = .ok code₁)
    (hCompile₂ : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile surface₂ = .ok code₂)
    (hEq : Weft.SemanticEq (surfaceIOResultSem oracle) surface₁ surface₂)
    (hMachine₂ : machineIOResultSem oracle code₂ input behavior) :
    ∀ event, event ∈ behavior.trace ->
      ∃ effect : Weft.EffectName,
        event = Weft.IOEvent.effectQuery effect (oracle effect) := by
  have hMachine₁ : machineIOResultSem oracle code₁ input behavior :=
    (machine_io_result_semanticEq_of_surfaceEq oracle hCompile₁ hCompile₂ hEq input behavior).2 hMachine₂
  exact staged_io_result_behavior_has_no_non_effect_events hCompile₁ hMachine₁

theorem machine_behavior_trace_free_when_pure_of_surfaceEq
    (oracle : Oracle)
    {surface₁ surface₂ : SurfaceExpr}
    {code₁ code₂ : Code}
    {input : Weft.Input}
    {behavior : EffectBehavior}
    (hCompile₁ : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile surface₁ = .ok code₁)
    (hCompile₂ : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile surface₂ = .ok code₂)
    (hEq : Weft.SemanticEq (surfaceSem oracle) surface₁ surface₂)
    (hPure₁ : inferEffects (parseSurface surface₁) = some Weft.EffectSet.empty)
    (hMachine₂ : machineSem oracle code₂ input behavior) :
    ∀ effect : Weft.EffectName, effect ∉ behavior.trace := by
  have hMachine₁ : machineSem oracle code₁ input behavior :=
    (machine_semanticEq_of_surfaceEq oracle hCompile₁ hCompile₂ hEq input behavior).2 hMachine₂
  exact staged_machine_behavior_trace_free_when_pure hCompile₁ hPure₁ hMachine₁

theorem machine_io_behavior_trace_free_when_pure_of_surfaceEq
    (oracle : Oracle)
    {surface₁ surface₂ : SurfaceExpr}
    {code₁ code₂ : Code}
    {input : Weft.Input}
    {behavior : Weft.Behavior}
    (hCompile₁ : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile surface₁ = .ok code₁)
    (hCompile₂ : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile surface₂ = .ok code₂)
    (hEq : Weft.SemanticEq (surfaceIOSem oracle) surface₁ surface₂)
    (hPure₁ : inferEffects (parseSurface surface₁) = some Weft.EffectSet.empty)
    (hMachine₂ : machineIOSem oracle code₂ input behavior) :
    behavior.trace = [] := by
  have hMachine₁ : machineIOSem oracle code₁ input behavior :=
    (machine_io_semanticEq_of_surfaceEq oracle hCompile₁ hCompile₂ hEq input behavior).2 hMachine₂
  exact staged_io_behavior_trace_free_when_pure hCompile₁ hPure₁ hMachine₁

theorem machine_result_respects_effects_and_kernel_expected_type_tag_of_surfaceEq
    (oracle : Oracle)
    {surface₁ surface₂ : SurfaceExpr}
    {code₁ code₂ : Code}
    {expected : Weft.Ty}
    {effects : Weft.EffectSet}
    {input : Weft.Input}
    {behavior : ResultBehavior}
    (hCompile₁ : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile surface₁ = .ok code₁)
    (hCompile₂ : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile surface₂ = .ok code₂)
    (hEq : Weft.SemanticEq (surfaceResultSem oracle) surface₁ surface₂)
    (hCheck₁ : kernelCheckAgainst (parseSurface surface₁) expected = true)
    (hEffects₁ : inferEffects (parseSurface surface₁) = some effects)
    (hMachine₂ : machineResultSem oracle code₂ input behavior) :
    (∀ effect : Weft.EffectName, effect ∈ behavior.trace -> effect ∈ effects.elems) ∧
      Weft.Ty.denotesTag behavior.result.toKernelTag expected := by
  have hMachine₁ : machineResultSem oracle code₁ input behavior :=
    (machine_result_semanticEq_of_surfaceEq oracle hCompile₁ hCompile₂ hEq input behavior).2 hMachine₂
  exact staged_result_behavior_respects_effects_and_kernel_expected_type_tag
    hCompile₁ hCheck₁ hEffects₁ hMachine₁

theorem machine_result_respects_effects_and_expected_type_of_surfaceEq
    (oracle : Oracle)
    {surface₁ surface₂ : SurfaceExpr}
    {code₁ code₂ : Code}
    {expected : Weft.Ty}
    {effects : Weft.EffectSet}
    {input : Weft.Input}
    {behavior : ResultBehavior}
    (hCompile₁ : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile surface₁ = .ok code₁)
    (hCompile₂ : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile surface₂ = .ok code₂)
    (hEq : Weft.SemanticEq (surfaceResultSem oracle) surface₁ surface₂)
    (hCheck₁ : checkAgainst (parseSurface surface₁) expected = true)
    (hEffects₁ : inferEffects (parseSurface surface₁) = some effects)
    (hMachine₂ : machineResultSem oracle code₂ input behavior) :
    (∀ effect : Weft.EffectName, effect ∈ behavior.trace -> effect ∈ effects.elems) ∧
      ∃ expectedCore : Weft.CoreSetTy,
        Weft.CoreSetTy.ofTy expected = some expectedCore ∧
        expectedCore.denotes behavior.result.toCoreAtom := by
  have hMachine₁ : machineResultSem oracle code₁ input behavior :=
    (machine_result_semanticEq_of_surfaceEq oracle hCompile₁ hCompile₂ hEq input behavior).2 hMachine₂
  exact staged_result_behavior_respects_effects_and_expected_type
    hCompile₁ hCheck₁ hEffects₁ hMachine₁

theorem machine_result_trace_free_and_kernel_typed_when_pure_of_surfaceEq
    (oracle : Oracle)
    {surface₁ surface₂ : SurfaceExpr}
    {code₁ code₂ : Code}
    {expected : Weft.Ty}
    {input : Weft.Input}
    {behavior : ResultBehavior}
    (hCompile₁ : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile surface₁ = .ok code₁)
    (hCompile₂ : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile surface₂ = .ok code₂)
    (hEq : Weft.SemanticEq (surfaceResultSem oracle) surface₁ surface₂)
    (hCheck₁ : kernelCheckAgainst (parseSurface surface₁) expected = true)
    (hPure₁ : inferEffects (parseSurface surface₁) = some Weft.EffectSet.empty)
    (hMachine₂ : machineResultSem oracle code₂ input behavior) :
    (∀ effect : Weft.EffectName, effect ∉ behavior.trace) ∧
      Weft.Ty.denotesTag behavior.result.toKernelTag expected := by
  have hMachine₁ : machineResultSem oracle code₁ input behavior :=
    (machine_result_semanticEq_of_surfaceEq oracle hCompile₁ hCompile₂ hEq input behavior).2 hMachine₂
  exact staged_result_behavior_trace_free_and_kernel_typed_when_pure_tag
    hCompile₁ hCheck₁ hPure₁ hMachine₁

theorem machine_result_respects_effects_and_weakened_kernel_expected_type_tag_of_surfaceEq
    (oracle : Oracle)
    {surface₁ surface₂ : SurfaceExpr}
    {code₁ code₂ : Code}
    {expected widened : Weft.Ty}
    {effects : Weft.EffectSet}
    {input : Weft.Input}
    {behavior : ResultBehavior}
    (hCompile₁ : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile surface₁ = .ok code₁)
    (hCompile₂ : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile surface₂ = .ok code₂)
    (hEq : Weft.SemanticEq (surfaceResultSem oracle) surface₁ surface₂)
    (hCheck₁ : kernelCheckAgainst (parseSurface surface₁) expected = true)
    (hSubtype : expected.SubtypeIn Weft.KernelTheory.theory widened)
    (hEffects₁ : inferEffects (parseSurface surface₁) = some effects)
    (hMachine₂ : machineResultSem oracle code₂ input behavior) :
    (∀ effect : Weft.EffectName, effect ∈ behavior.trace -> effect ∈ effects.elems) ∧
      Weft.Ty.denotesTag behavior.result.toKernelTag widened := by
  have hMachine₁ : machineResultSem oracle code₁ input behavior :=
    (machine_result_semanticEq_of_surfaceEq oracle hCompile₁ hCompile₂ hEq input behavior).2 hMachine₂
  exact staged_result_behavior_respects_effects_and_weakened_kernel_expected_type_tag
    hCompile₁ hCheck₁ hSubtype hEffects₁ hMachine₁

theorem machine_result_trace_free_and_typed_when_pure_of_surfaceEq
    (oracle : Oracle)
    {surface₁ surface₂ : SurfaceExpr}
    {code₁ code₂ : Code}
    {expected : Weft.Ty}
    {input : Weft.Input}
    {behavior : ResultBehavior}
    (hCompile₁ : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile surface₁ = .ok code₁)
    (hCompile₂ : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile surface₂ = .ok code₂)
    (hEq : Weft.SemanticEq (surfaceResultSem oracle) surface₁ surface₂)
    (hCheck₁ : checkAgainst (parseSurface surface₁) expected = true)
    (hPure₁ : inferEffects (parseSurface surface₁) = some Weft.EffectSet.empty)
    (hMachine₂ : machineResultSem oracle code₂ input behavior) :
    (∀ effect : Weft.EffectName, effect ∉ behavior.trace) ∧
      ∃ expectedCore : Weft.CoreSetTy,
        Weft.CoreSetTy.ofTy expected = some expectedCore ∧
        expectedCore.denotes behavior.result.toCoreAtom := by
  have hMachine₁ : machineResultSem oracle code₁ input behavior :=
    (machine_result_semanticEq_of_surfaceEq oracle hCompile₁ hCompile₂ hEq input behavior).2 hMachine₂
  exact staged_result_behavior_trace_free_and_typed_when_pure
    hCompile₁ hCheck₁ hPure₁ hMachine₁

theorem machine_result_trace_free_and_weakened_kernel_typed_when_pure_of_surfaceEq
    (oracle : Oracle)
    {surface₁ surface₂ : SurfaceExpr}
    {code₁ code₂ : Code}
    {expected widened : Weft.Ty}
    {input : Weft.Input}
    {behavior : ResultBehavior}
    (hCompile₁ : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile surface₁ = .ok code₁)
    (hCompile₂ : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile surface₂ = .ok code₂)
    (hEq : Weft.SemanticEq (surfaceResultSem oracle) surface₁ surface₂)
    (hCheck₁ : kernelCheckAgainst (parseSurface surface₁) expected = true)
    (hSubtype : expected.SubtypeIn Weft.KernelTheory.theory widened)
    (hPure₁ : inferEffects (parseSurface surface₁) = some Weft.EffectSet.empty)
    (hMachine₂ : machineResultSem oracle code₂ input behavior) :
    (∀ effect : Weft.EffectName, effect ∉ behavior.trace) ∧
      Weft.Ty.denotesTag behavior.result.toKernelTag widened := by
  have hMachine₁ : machineResultSem oracle code₁ input behavior :=
    (machine_result_semanticEq_of_surfaceEq oracle hCompile₁ hCompile₂ hEq input behavior).2 hMachine₂
  exact staged_result_behavior_trace_free_and_weakened_kernel_typed_when_pure_tag
    hCompile₁ hCheck₁ hSubtype hPure₁ hMachine₁

theorem machine_result_respects_effects_and_tag_weakened_kernel_expected_type_tag_of_surfaceEq
    (oracle : Oracle)
    {surface₁ surface₂ : SurfaceExpr}
    {code₁ code₂ : Code}
    {expected widened : Weft.Ty}
    {effects : Weft.EffectSet}
    {input : Weft.Input}
    {behavior : ResultBehavior}
    (hCompile₁ : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile surface₁ = .ok code₁)
    (hCompile₂ : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile surface₂ = .ok code₂)
    (hEq : Weft.SemanticEq (surfaceResultSem oracle) surface₁ surface₂)
    (hCheck₁ : kernelCheckAgainst (parseSurface surface₁) expected = true)
    (hSubtype : ∀ tag : Weft.KernelTag, Weft.Ty.denotesTag tag expected -> Weft.Ty.denotesTag tag widened)
    (hEffects₁ : inferEffects (parseSurface surface₁) = some effects)
    (hMachine₂ : machineResultSem oracle code₂ input behavior) :
    (∀ effect : Weft.EffectName, effect ∈ behavior.trace -> effect ∈ effects.elems) ∧
      Weft.Ty.denotesTag behavior.result.toKernelTag widened := by
  have hMachine₁ : machineResultSem oracle code₁ input behavior :=
    (machine_result_semanticEq_of_surfaceEq oracle hCompile₁ hCompile₂ hEq input behavior).2 hMachine₂
  exact staged_result_behavior_respects_effects_and_tag_weakened_kernel_expected_type_tag
    hCompile₁ hCheck₁ hSubtype hEffects₁ hMachine₁

theorem machine_result_trace_free_and_tag_weakened_kernel_typed_when_pure_of_surfaceEq
    (oracle : Oracle)
    {surface₁ surface₂ : SurfaceExpr}
    {code₁ code₂ : Code}
    {expected widened : Weft.Ty}
    {input : Weft.Input}
    {behavior : ResultBehavior}
    (hCompile₁ : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile surface₁ = .ok code₁)
    (hCompile₂ : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile surface₂ = .ok code₂)
    (hEq : Weft.SemanticEq (surfaceResultSem oracle) surface₁ surface₂)
    (hCheck₁ : kernelCheckAgainst (parseSurface surface₁) expected = true)
    (hSubtype : ∀ tag : Weft.KernelTag, Weft.Ty.denotesTag tag expected -> Weft.Ty.denotesTag tag widened)
    (hPure₁ : inferEffects (parseSurface surface₁) = some Weft.EffectSet.empty)
    (hMachine₂ : machineResultSem oracle code₂ input behavior) :
    (∀ effect : Weft.EffectName, effect ∉ behavior.trace) ∧
      Weft.Ty.denotesTag behavior.result.toKernelTag widened := by
  have hMachine₁ : machineResultSem oracle code₁ input behavior :=
    (machine_result_semanticEq_of_surfaceEq oracle hCompile₁ hCompile₂ hEq input behavior).2 hMachine₂
  exact staged_result_behavior_trace_free_and_tag_weakened_kernel_typed_when_pure_tag
    hCompile₁ hCheck₁ hSubtype hPure₁ hMachine₁

theorem machine_result_respects_effects_and_kernelSubtypeb_weakened_expected_type_tag_of_surfaceEq
    (oracle : Oracle)
    {surface₁ surface₂ : SurfaceExpr}
    {code₁ code₂ : Code}
    {expected widened : Weft.Ty}
    {effects : Weft.EffectSet}
    {input : Weft.Input}
    {behavior : ResultBehavior}
    (hCompile₁ : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile surface₁ = .ok code₁)
    (hCompile₂ : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile surface₂ = .ok code₂)
    (hEq : Weft.SemanticEq (surfaceResultSem oracle) surface₁ surface₂)
    (hCheck₁ : kernelCheckAgainst (parseSurface surface₁) expected = true)
    (hSubtype : expected.kernelSubtypeb widened = true)
    (hEffects₁ : inferEffects (parseSurface surface₁) = some effects)
    (hMachine₂ : machineResultSem oracle code₂ input behavior) :
    (∀ effect : Weft.EffectName, effect ∈ behavior.trace -> effect ∈ effects.elems) ∧
      Weft.Ty.denotesTag behavior.result.toKernelTag widened := by
  have hMachine₁ : machineResultSem oracle code₁ input behavior :=
    (machine_result_semanticEq_of_surfaceEq oracle hCompile₁ hCompile₂ hEq input behavior).2 hMachine₂
  exact staged_result_behavior_respects_effects_and_kernelSubtypeb_weakened_expected_type_tag
    hCompile₁ hCheck₁ hSubtype hEffects₁ hMachine₁

theorem machine_result_trace_free_and_kernelSubtypeb_weakened_typed_when_pure_of_surfaceEq
    (oracle : Oracle)
    {surface₁ surface₂ : SurfaceExpr}
    {code₁ code₂ : Code}
    {expected widened : Weft.Ty}
    {input : Weft.Input}
    {behavior : ResultBehavior}
    (hCompile₁ : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile surface₁ = .ok code₁)
    (hCompile₂ : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile surface₂ = .ok code₂)
    (hEq : Weft.SemanticEq (surfaceResultSem oracle) surface₁ surface₂)
    (hCheck₁ : kernelCheckAgainst (parseSurface surface₁) expected = true)
    (hSubtype : expected.kernelSubtypeb widened = true)
    (hPure₁ : inferEffects (parseSurface surface₁) = some Weft.EffectSet.empty)
    (hMachine₂ : machineResultSem oracle code₂ input behavior) :
    (∀ effect : Weft.EffectName, effect ∉ behavior.trace) ∧
      Weft.Ty.denotesTag behavior.result.toKernelTag widened := by
  have hMachine₁ : machineResultSem oracle code₁ input behavior :=
    (machine_result_semanticEq_of_surfaceEq oracle hCompile₁ hCompile₂ hEq input behavior).2 hMachine₂
  exact staged_result_behavior_trace_free_and_kernelSubtypeb_weakened_typed_when_pure_tag
    hCompile₁ hCheck₁ hSubtype hPure₁ hMachine₁

theorem staged_bootstrap_machine_io_result_behavior_only_reports_inferred_effects_and_kernel_expected_type_tag
    (oracle : Oracle)
    {compiler₁ compiler₂ compiler₃ : SurfaceExpr}
    {code₁ code₂ code₃ : Code}
    {expected : Weft.Ty}
    {effects : Weft.EffectSet}
    {input : Weft.Input}
    {behavior : IOResultBehavior}
    (hCompile₁ : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile compiler₁ = .ok code₁)
    (_hCompile₂ : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile compiler₂ = .ok code₂)
    (hCompile₃ : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile compiler₃ = .ok code₃)
    (h₁₂ : Weft.SemanticEq (surfaceIOResultSem oracle) compiler₁ compiler₂)
    (h₂₃ : Weft.SemanticEq (surfaceIOResultSem oracle) compiler₂ compiler₃)
    (hCheck₁ : kernelCheckAgainst (parseSurface compiler₁) expected = true)
    (hEffects₁ : inferEffects (parseSurface compiler₁) = some effects)
    (hMachine₃ : machineIOResultSem oracle code₃ input behavior) :
    (∀ event, event ∈ behavior.trace ->
      ∃ effect : Weft.EffectName,
        effect ∈ effects.elems ∧ event = Weft.IOEvent.effectQuery effect (oracle effect)) ∧
      Weft.Ty.denotesTag behavior.result.toKernelTag expected := by
  have hSurface : Weft.SemanticEq (surfaceIOResultSem oracle) compiler₁ compiler₃ :=
    staged_bootstrap_surface_io_result_semantics_stable oracle h₁₂ h₂₃
  exact machine_io_result_behavior_only_reports_inferred_effects_and_kernel_expected_type_tag_of_surfaceEq
    oracle hCompile₁ hCompile₃ hSurface hCheck₁ hEffects₁ hMachine₃

theorem staged_bootstrap_machine_io_result_behavior_only_reports_inferred_effects_and_ptr_covariant_kernel_expected_type_tag
    (oracle : Oracle)
    {compiler₁ compiler₂ compiler₃ : SurfaceExpr}
    {code₁ code₂ code₃ : Code}
    {inner₁ inner₂ : Weft.Ty}
    {effects : Weft.EffectSet}
    {input : Weft.Input}
    {behavior : IOResultBehavior}
    (hCompile₁ : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile compiler₁ = .ok code₁)
    (_hCompile₂ : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile compiler₂ = .ok code₂)
    (hCompile₃ : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile compiler₃ = .ok code₃)
    (h₁₂ : Weft.SemanticEq (surfaceIOResultSem oracle) compiler₁ compiler₂)
    (h₂₃ : Weft.SemanticEq (surfaceIOResultSem oracle) compiler₂ compiler₃)
    (hCheck₁ : kernelCheckAgainst (parseSurface compiler₁) (Weft.Ty.ptr inner₁) = true)
    (hSubtype : inner₁.kernelSubtypeb inner₂ = true)
    (hEffects₁ : inferEffects (parseSurface compiler₁) = some effects)
    (hMachine₃ : machineIOResultSem oracle code₃ input behavior) :
    (∀ event, event ∈ behavior.trace ->
      ∃ effect : Weft.EffectName,
        effect ∈ effects.elems ∧ event = Weft.IOEvent.effectQuery effect (oracle effect)) ∧
      Weft.Ty.denotesTag behavior.result.toKernelTag (Weft.Ty.ptr inner₂) := by
  have hSurface : Weft.SemanticEq (surfaceIOResultSem oracle) compiler₁ compiler₃ :=
    staged_bootstrap_surface_io_result_semantics_stable oracle h₁₂ h₂₃
  exact machine_io_result_behavior_only_reports_inferred_effects_and_ptr_covariant_kernel_expected_type_tag_of_surfaceEq
    oracle hCompile₁ hCompile₃ hSurface hCheck₁ hSubtype hEffects₁ hMachine₃

theorem staged_bootstrap_machine_io_result_behavior_trace_free_and_ptr_covariant_kernel_typed_when_pure
    (oracle : Oracle)
    {compiler₁ compiler₂ compiler₃ : SurfaceExpr}
    {code₁ code₂ code₃ : Code}
    {inner₁ inner₂ : Weft.Ty}
    {input : Weft.Input}
    {behavior : IOResultBehavior}
    (hCompile₁ : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile compiler₁ = .ok code₁)
    (_hCompile₂ : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile compiler₂ = .ok code₂)
    (hCompile₃ : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile compiler₃ = .ok code₃)
    (h₁₂ : Weft.SemanticEq (surfaceIOResultSem oracle) compiler₁ compiler₂)
    (h₂₃ : Weft.SemanticEq (surfaceIOResultSem oracle) compiler₂ compiler₃)
    (hCheck₁ : kernelCheckAgainst (parseSurface compiler₁) (Weft.Ty.ptr inner₁) = true)
    (hSubtype : inner₁.kernelSubtypeb inner₂ = true)
    (hPure₁ : inferEffects (parseSurface compiler₁) = some Weft.EffectSet.empty)
    (hMachine₃ : machineIOResultSem oracle code₃ input behavior) :
    behavior.trace = [] ∧
      Weft.Ty.denotesTag behavior.result.toKernelTag (Weft.Ty.ptr inner₂) := by
  have hSurface : Weft.SemanticEq (surfaceIOResultSem oracle) compiler₁ compiler₃ :=
    staged_bootstrap_surface_io_result_semantics_stable oracle h₁₂ h₂₃
  exact machine_io_result_behavior_trace_free_and_ptr_covariant_kernel_typed_when_pure_of_surfaceEq
    oracle hCompile₁ hCompile₃ hSurface hCheck₁ hSubtype hPure₁ hMachine₃

theorem staged_bootstrap_machine_io_result_behavior_only_reports_inferred_effects_and_rc_covariant_kernel_expected_type_tag
    (oracle : Oracle)
    {compiler₁ compiler₂ compiler₃ : SurfaceExpr}
    {code₁ code₂ code₃ : Code}
    {inner₁ inner₂ : Weft.Ty}
    {effects : Weft.EffectSet}
    {input : Weft.Input}
    {behavior : IOResultBehavior}
    (hCompile₁ : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile compiler₁ = .ok code₁)
    (_hCompile₂ : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile compiler₂ = .ok code₂)
    (hCompile₃ : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile compiler₃ = .ok code₃)
    (h₁₂ : Weft.SemanticEq (surfaceIOResultSem oracle) compiler₁ compiler₂)
    (h₂₃ : Weft.SemanticEq (surfaceIOResultSem oracle) compiler₂ compiler₃)
    (hCheck₁ : kernelCheckAgainst (parseSurface compiler₁) (Weft.Ty.rc inner₁) = true)
    (hSubtype : inner₁.kernelSubtypeb inner₂ = true)
    (hEffects₁ : inferEffects (parseSurface compiler₁) = some effects)
    (hMachine₃ : machineIOResultSem oracle code₃ input behavior) :
    (∀ event, event ∈ behavior.trace ->
      ∃ effect : Weft.EffectName,
        effect ∈ effects.elems ∧ event = Weft.IOEvent.effectQuery effect (oracle effect)) ∧
      Weft.Ty.denotesTag behavior.result.toKernelTag (Weft.Ty.rc inner₂) := by
  have hSurface : Weft.SemanticEq (surfaceIOResultSem oracle) compiler₁ compiler₃ :=
    staged_bootstrap_surface_io_result_semantics_stable oracle h₁₂ h₂₃
  exact machine_io_result_behavior_only_reports_inferred_effects_and_rc_covariant_kernel_expected_type_tag_of_surfaceEq
    oracle hCompile₁ hCompile₃ hSurface hCheck₁ hSubtype hEffects₁ hMachine₃

theorem staged_bootstrap_machine_io_result_behavior_trace_free_and_rc_covariant_kernel_typed_when_pure
    (oracle : Oracle)
    {compiler₁ compiler₂ compiler₃ : SurfaceExpr}
    {code₁ code₂ code₃ : Code}
    {inner₁ inner₂ : Weft.Ty}
    {input : Weft.Input}
    {behavior : IOResultBehavior}
    (hCompile₁ : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile compiler₁ = .ok code₁)
    (_hCompile₂ : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile compiler₂ = .ok code₂)
    (hCompile₃ : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile compiler₃ = .ok code₃)
    (h₁₂ : Weft.SemanticEq (surfaceIOResultSem oracle) compiler₁ compiler₂)
    (h₂₃ : Weft.SemanticEq (surfaceIOResultSem oracle) compiler₂ compiler₃)
    (hCheck₁ : kernelCheckAgainst (parseSurface compiler₁) (Weft.Ty.rc inner₁) = true)
    (hSubtype : inner₁.kernelSubtypeb inner₂ = true)
    (hPure₁ : inferEffects (parseSurface compiler₁) = some Weft.EffectSet.empty)
    (hMachine₃ : machineIOResultSem oracle code₃ input behavior) :
    behavior.trace = [] ∧
      Weft.Ty.denotesTag behavior.result.toKernelTag (Weft.Ty.rc inner₂) := by
  have hSurface : Weft.SemanticEq (surfaceIOResultSem oracle) compiler₁ compiler₃ :=
    staged_bootstrap_surface_io_result_semantics_stable oracle h₁₂ h₂₃
  exact machine_io_result_behavior_trace_free_and_rc_covariant_kernel_typed_when_pure_of_surfaceEq
    oracle hCompile₁ hCompile₃ hSurface hCheck₁ hSubtype hPure₁ hMachine₃

theorem staged_bootstrap_machine_io_result_behavior_only_reports_inferred_effects_and_fn_subtype_kernel_expected_type_tag
    (oracle : Oracle)
    {compiler₁ compiler₂ compiler₃ : SurfaceExpr}
    {code₁ code₂ code₃ : Code}
    {arg₁ ret₁ arg₂ ret₂ : Weft.Ty}
    {eff₁ eff₂ : Weft.EffectSet}
    {effects : Weft.EffectSet}
    {input : Weft.Input}
    {behavior : IOResultBehavior}
    (hCompile₁ : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile compiler₁ = .ok code₁)
    (_hCompile₂ : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile compiler₂ = .ok code₂)
    (hCompile₃ : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile compiler₃ = .ok code₃)
    (h₁₂ : Weft.SemanticEq (surfaceIOResultSem oracle) compiler₁ compiler₂)
    (h₂₃ : Weft.SemanticEq (surfaceIOResultSem oracle) compiler₂ compiler₃)
    (hCheck₁ : kernelCheckAgainst (parseSurface compiler₁) (Weft.Ty.fn arg₁ eff₁ ret₁) = true)
    (hArg : arg₂.kernelSubtypeb arg₁ = true)
    (hEff : Weft.EffectSet.subsetb eff₁ eff₂ = true)
    (hRet : ret₁.kernelSubtypeb ret₂ = true)
    (hEffects₁ : inferEffects (parseSurface compiler₁) = some effects)
    (hMachine₃ : machineIOResultSem oracle code₃ input behavior) :
    (∀ event, event ∈ behavior.trace ->
      ∃ effect : Weft.EffectName,
        effect ∈ effects.elems ∧ event = Weft.IOEvent.effectQuery effect (oracle effect)) ∧
      Weft.Ty.denotesTag behavior.result.toKernelTag (Weft.Ty.fn arg₂ eff₂ ret₂) := by
  have hSurface : Weft.SemanticEq (surfaceIOResultSem oracle) compiler₁ compiler₃ :=
    staged_bootstrap_surface_io_result_semantics_stable oracle h₁₂ h₂₃
  exact machine_io_result_behavior_only_reports_inferred_effects_and_fn_subtype_kernel_expected_type_tag_of_surfaceEq
    oracle hCompile₁ hCompile₃ hSurface hCheck₁ hArg hEff hRet hEffects₁ hMachine₃

theorem staged_bootstrap_machine_io_result_behavior_trace_free_and_fn_subtype_kernel_typed_when_pure
    (oracle : Oracle)
    {compiler₁ compiler₂ compiler₃ : SurfaceExpr}
    {code₁ code₂ code₃ : Code}
    {arg₁ ret₁ arg₂ ret₂ : Weft.Ty}
    {eff₁ eff₂ : Weft.EffectSet}
    {input : Weft.Input}
    {behavior : IOResultBehavior}
    (hCompile₁ : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile compiler₁ = .ok code₁)
    (_hCompile₂ : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile compiler₂ = .ok code₂)
    (hCompile₃ : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile compiler₃ = .ok code₃)
    (h₁₂ : Weft.SemanticEq (surfaceIOResultSem oracle) compiler₁ compiler₂)
    (h₂₃ : Weft.SemanticEq (surfaceIOResultSem oracle) compiler₂ compiler₃)
    (hCheck₁ : kernelCheckAgainst (parseSurface compiler₁) (Weft.Ty.fn arg₁ eff₁ ret₁) = true)
    (hArg : arg₂.kernelSubtypeb arg₁ = true)
    (hEff : Weft.EffectSet.subsetb eff₁ eff₂ = true)
    (hRet : ret₁.kernelSubtypeb ret₂ = true)
    (hPure₁ : inferEffects (parseSurface compiler₁) = some Weft.EffectSet.empty)
    (hMachine₃ : machineIOResultSem oracle code₃ input behavior) :
    behavior.trace = [] ∧
      Weft.Ty.denotesTag behavior.result.toKernelTag (Weft.Ty.fn arg₂ eff₂ ret₂) := by
  have hSurface : Weft.SemanticEq (surfaceIOResultSem oracle) compiler₁ compiler₃ :=
    staged_bootstrap_surface_io_result_semantics_stable oracle h₁₂ h₂₃
  exact machine_io_result_behavior_trace_free_and_fn_subtype_kernel_typed_when_pure_of_surfaceEq
    oracle hCompile₁ hCompile₃ hSurface hCheck₁ hArg hEff hRet hPure₁ hMachine₃

theorem staged_bootstrap_machine_io_behavior_has_no_non_effect_events
    (oracle : Oracle)
    {compiler₁ compiler₂ compiler₃ : SurfaceExpr}
    {code₁ code₂ code₃ : Code}
    {input : Weft.Input}
    {behavior : Weft.Behavior}
    (hCompile₁ : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile compiler₁ = .ok code₁)
    (_hCompile₂ : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile compiler₂ = .ok code₂)
    (hCompile₃ : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile compiler₃ = .ok code₃)
    (h₁₂ : Weft.SemanticEq (surfaceIOSem oracle) compiler₁ compiler₂)
    (h₂₃ : Weft.SemanticEq (surfaceIOSem oracle) compiler₂ compiler₃)
    (hMachine₃ : machineIOSem oracle code₃ input behavior) :
    ∀ event, event ∈ behavior.trace ->
      ∃ effect : Weft.EffectName,
        event = Weft.IOEvent.effectQuery effect (oracle effect) := by
  have hSurface : Weft.SemanticEq (surfaceIOSem oracle) compiler₁ compiler₃ :=
    staged_bootstrap_surface_io_semantics_stable oracle h₁₂ h₂₃
  exact machine_io_behavior_has_no_non_effect_events_of_surfaceEq
    oracle hCompile₁ hCompile₃ hSurface hMachine₃

theorem staged_bootstrap_machine_behavior_respects_inferred_effects
    (oracle : Oracle)
    {compiler₁ compiler₂ compiler₃ : SurfaceExpr}
    {code₁ code₂ code₃ : Code}
    {effects : Weft.EffectSet}
    {input : Weft.Input}
    {behavior : EffectBehavior}
    (hCompile₁ : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile compiler₁ = .ok code₁)
    (_hCompile₂ : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile compiler₂ = .ok code₂)
    (hCompile₃ : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile compiler₃ = .ok code₃)
    (h₁₂ : Weft.SemanticEq (surfaceSem oracle) compiler₁ compiler₂)
    (h₂₃ : Weft.SemanticEq (surfaceSem oracle) compiler₂ compiler₃)
    (hEffects₁ : inferEffects (parseSurface compiler₁) = some effects)
    (hMachine₃ : machineSem oracle code₃ input behavior) :
    ∀ effect : Weft.EffectName, effect ∈ behavior.trace -> effect ∈ effects.elems := by
  have hSurface : Weft.SemanticEq (surfaceSem oracle) compiler₁ compiler₃ :=
    staged_bootstrap_surface_semantics_stable oracle h₁₂ h₂₃
  exact machine_behavior_respects_inferred_effects_of_surfaceEq
    oracle hCompile₁ hCompile₃ hSurface hEffects₁ hMachine₃

theorem staged_bootstrap_machine_io_behavior_only_reports_inferred_effects
    (oracle : Oracle)
    {compiler₁ compiler₂ compiler₃ : SurfaceExpr}
    {code₁ code₂ code₃ : Code}
    {effects : Weft.EffectSet}
    {input : Weft.Input}
    {behavior : Weft.Behavior}
    (hCompile₁ : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile compiler₁ = .ok code₁)
    (_hCompile₂ : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile compiler₂ = .ok code₂)
    (hCompile₃ : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile compiler₃ = .ok code₃)
    (h₁₂ : Weft.SemanticEq (surfaceIOSem oracle) compiler₁ compiler₂)
    (h₂₃ : Weft.SemanticEq (surfaceIOSem oracle) compiler₂ compiler₃)
    (hEffects₁ : inferEffects (parseSurface compiler₁) = some effects)
    (hMachine₃ : machineIOSem oracle code₃ input behavior) :
    ∀ event, event ∈ behavior.trace ->
      ∃ effect : Weft.EffectName,
        effect ∈ effects.elems ∧ event = Weft.IOEvent.effectQuery effect (oracle effect) := by
  have hSurface : Weft.SemanticEq (surfaceIOSem oracle) compiler₁ compiler₃ :=
    staged_bootstrap_surface_io_semantics_stable oracle h₁₂ h₂₃
  exact machine_io_behavior_only_reports_inferred_effects_of_surfaceEq
    oracle hCompile₁ hCompile₃ hSurface hEffects₁ hMachine₃

theorem staged_bootstrap_machine_behavior_trace_free_when_pure
    (oracle : Oracle)
    {compiler₁ compiler₂ compiler₃ : SurfaceExpr}
    {code₁ code₂ code₃ : Code}
    {input : Weft.Input}
    {behavior : EffectBehavior}
    (hCompile₁ : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile compiler₁ = .ok code₁)
    (_hCompile₂ : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile compiler₂ = .ok code₂)
    (hCompile₃ : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile compiler₃ = .ok code₃)
    (h₁₂ : Weft.SemanticEq (surfaceSem oracle) compiler₁ compiler₂)
    (h₂₃ : Weft.SemanticEq (surfaceSem oracle) compiler₂ compiler₃)
    (hPure₁ : inferEffects (parseSurface compiler₁) = some Weft.EffectSet.empty)
    (hMachine₃ : machineSem oracle code₃ input behavior) :
    ∀ effect : Weft.EffectName, effect ∉ behavior.trace := by
  have hSurface : Weft.SemanticEq (surfaceSem oracle) compiler₁ compiler₃ :=
    staged_bootstrap_surface_semantics_stable oracle h₁₂ h₂₃
  exact machine_behavior_trace_free_when_pure_of_surfaceEq
    oracle hCompile₁ hCompile₃ hSurface hPure₁ hMachine₃

theorem staged_bootstrap_machine_io_result_behavior_has_no_non_effect_events
    (oracle : Oracle)
    {compiler₁ compiler₂ compiler₃ : SurfaceExpr}
    {code₁ code₂ code₃ : Code}
    {input : Weft.Input}
    {behavior : IOResultBehavior}
    (hCompile₁ : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile compiler₁ = .ok code₁)
    (_hCompile₂ : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile compiler₂ = .ok code₂)
    (hCompile₃ : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile compiler₃ = .ok code₃)
    (h₁₂ : Weft.SemanticEq (surfaceIOResultSem oracle) compiler₁ compiler₂)
    (h₂₃ : Weft.SemanticEq (surfaceIOResultSem oracle) compiler₂ compiler₃)
    (hMachine₃ : machineIOResultSem oracle code₃ input behavior) :
    ∀ event, event ∈ behavior.trace ->
      ∃ effect : Weft.EffectName,
        event = Weft.IOEvent.effectQuery effect (oracle effect) := by
  have hSurface : Weft.SemanticEq (surfaceIOResultSem oracle) compiler₁ compiler₃ :=
    staged_bootstrap_surface_io_result_semantics_stable oracle h₁₂ h₂₃
  exact machine_io_result_behavior_has_no_non_effect_events_of_surfaceEq
    oracle hCompile₁ hCompile₃ hSurface hMachine₃

theorem staged_bootstrap_machine_result_respects_effects_and_kernel_expected_type_tag
    (oracle : Oracle)
    {compiler₁ compiler₂ compiler₃ : SurfaceExpr}
    {code₁ code₂ code₃ : Code}
    {expected : Weft.Ty}
    {effects : Weft.EffectSet}
    {input : Weft.Input}
    {behavior : ResultBehavior}
    (hCompile₁ : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile compiler₁ = .ok code₁)
    (_hCompile₂ : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile compiler₂ = .ok code₂)
    (hCompile₃ : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile compiler₃ = .ok code₃)
    (h₁₂ : Weft.SemanticEq (surfaceResultSem oracle) compiler₁ compiler₂)
    (h₂₃ : Weft.SemanticEq (surfaceResultSem oracle) compiler₂ compiler₃)
    (hCheck₁ : kernelCheckAgainst (parseSurface compiler₁) expected = true)
    (hEffects₁ : inferEffects (parseSurface compiler₁) = some effects)
    (hMachine₃ : machineResultSem oracle code₃ input behavior) :
    (∀ effect : Weft.EffectName, effect ∈ behavior.trace -> effect ∈ effects.elems) ∧
      Weft.Ty.denotesTag behavior.result.toKernelTag expected := by
  have hSurface : Weft.SemanticEq (surfaceResultSem oracle) compiler₁ compiler₃ :=
    staged_bootstrap_surface_result_semantics_stable oracle h₁₂ h₂₃
  exact machine_result_respects_effects_and_kernel_expected_type_tag_of_surfaceEq
    oracle hCompile₁ hCompile₃ hSurface hCheck₁ hEffects₁ hMachine₃

theorem staged_bootstrap_machine_result_respects_effects_and_weakened_kernel_expected_type_tag
    (oracle : Oracle)
    {compiler₁ compiler₂ compiler₃ : SurfaceExpr}
    {code₁ code₂ code₃ : Code}
    {expected widened : Weft.Ty}
    {effects : Weft.EffectSet}
    {input : Weft.Input}
    {behavior : ResultBehavior}
    (hCompile₁ : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile compiler₁ = .ok code₁)
    (_hCompile₂ : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile compiler₂ = .ok code₂)
    (hCompile₃ : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile compiler₃ = .ok code₃)
    (h₁₂ : Weft.SemanticEq (surfaceResultSem oracle) compiler₁ compiler₂)
    (h₂₃ : Weft.SemanticEq (surfaceResultSem oracle) compiler₂ compiler₃)
    (hCheck₁ : kernelCheckAgainst (parseSurface compiler₁) expected = true)
    (hSubtype : expected.SubtypeIn Weft.KernelTheory.theory widened)
    (hEffects₁ : inferEffects (parseSurface compiler₁) = some effects)
    (hMachine₃ : machineResultSem oracle code₃ input behavior) :
    (∀ effect : Weft.EffectName, effect ∈ behavior.trace -> effect ∈ effects.elems) ∧
      Weft.Ty.denotesTag behavior.result.toKernelTag widened := by
  have hSurface : Weft.SemanticEq (surfaceResultSem oracle) compiler₁ compiler₃ :=
    staged_bootstrap_surface_result_semantics_stable oracle h₁₂ h₂₃
  exact machine_result_respects_effects_and_weakened_kernel_expected_type_tag_of_surfaceEq
    oracle hCompile₁ hCompile₃ hSurface hCheck₁ hSubtype hEffects₁ hMachine₃

theorem staged_bootstrap_machine_result_respects_effects_and_expected_type
    (oracle : Oracle)
    {compiler₁ compiler₂ compiler₃ : SurfaceExpr}
    {code₁ code₂ code₃ : Code}
    {expected : Weft.Ty}
    {effects : Weft.EffectSet}
    {input : Weft.Input}
    {behavior : ResultBehavior}
    (hCompile₁ : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile compiler₁ = .ok code₁)
    (_hCompile₂ : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile compiler₂ = .ok code₂)
    (hCompile₃ : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile compiler₃ = .ok code₃)
    (h₁₂ : Weft.SemanticEq (surfaceResultSem oracle) compiler₁ compiler₂)
    (h₂₃ : Weft.SemanticEq (surfaceResultSem oracle) compiler₂ compiler₃)
    (hCheck₁ : checkAgainst (parseSurface compiler₁) expected = true)
    (hEffects₁ : inferEffects (parseSurface compiler₁) = some effects)
    (hMachine₃ : machineResultSem oracle code₃ input behavior) :
    (∀ effect : Weft.EffectName, effect ∈ behavior.trace -> effect ∈ effects.elems) ∧
      ∃ expectedCore : Weft.CoreSetTy,
        Weft.CoreSetTy.ofTy expected = some expectedCore ∧
        expectedCore.denotes behavior.result.toCoreAtom := by
  have hSurface : Weft.SemanticEq (surfaceResultSem oracle) compiler₁ compiler₃ :=
    staged_bootstrap_surface_result_semantics_stable oracle h₁₂ h₂₃
  exact machine_result_respects_effects_and_expected_type_of_surfaceEq
    oracle hCompile₁ hCompile₃ hSurface hCheck₁ hEffects₁ hMachine₃

theorem staged_bootstrap_machine_result_trace_free_and_kernel_typed_when_pure
    (oracle : Oracle)
    {compiler₁ compiler₂ compiler₃ : SurfaceExpr}
    {code₁ code₂ code₃ : Code}
    {expected : Weft.Ty}
    {input : Weft.Input}
    {behavior : ResultBehavior}
    (hCompile₁ : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile compiler₁ = .ok code₁)
    (_hCompile₂ : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile compiler₂ = .ok code₂)
    (hCompile₃ : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile compiler₃ = .ok code₃)
    (h₁₂ : Weft.SemanticEq (surfaceResultSem oracle) compiler₁ compiler₂)
    (h₂₃ : Weft.SemanticEq (surfaceResultSem oracle) compiler₂ compiler₃)
    (hCheck₁ : kernelCheckAgainst (parseSurface compiler₁) expected = true)
    (hPure₁ : inferEffects (parseSurface compiler₁) = some Weft.EffectSet.empty)
    (hMachine₃ : machineResultSem oracle code₃ input behavior) :
    (∀ effect : Weft.EffectName, effect ∉ behavior.trace) ∧
      Weft.Ty.denotesTag behavior.result.toKernelTag expected := by
  have hSurface : Weft.SemanticEq (surfaceResultSem oracle) compiler₁ compiler₃ :=
    staged_bootstrap_surface_result_semantics_stable oracle h₁₂ h₂₃
  exact machine_result_trace_free_and_kernel_typed_when_pure_of_surfaceEq
    oracle hCompile₁ hCompile₃ hSurface hCheck₁ hPure₁ hMachine₃

theorem staged_bootstrap_machine_result_trace_free_and_weakened_kernel_typed_when_pure
    (oracle : Oracle)
    {compiler₁ compiler₂ compiler₃ : SurfaceExpr}
    {code₁ code₂ code₃ : Code}
    {expected widened : Weft.Ty}
    {input : Weft.Input}
    {behavior : ResultBehavior}
    (hCompile₁ : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile compiler₁ = .ok code₁)
    (_hCompile₂ : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile compiler₂ = .ok code₂)
    (hCompile₃ : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile compiler₃ = .ok code₃)
    (h₁₂ : Weft.SemanticEq (surfaceResultSem oracle) compiler₁ compiler₂)
    (h₂₃ : Weft.SemanticEq (surfaceResultSem oracle) compiler₂ compiler₃)
    (hCheck₁ : kernelCheckAgainst (parseSurface compiler₁) expected = true)
    (hSubtype : expected.SubtypeIn Weft.KernelTheory.theory widened)
    (hPure₁ : inferEffects (parseSurface compiler₁) = some Weft.EffectSet.empty)
    (hMachine₃ : machineResultSem oracle code₃ input behavior) :
    (∀ effect : Weft.EffectName, effect ∉ behavior.trace) ∧
      Weft.Ty.denotesTag behavior.result.toKernelTag widened := by
  have hSurface : Weft.SemanticEq (surfaceResultSem oracle) compiler₁ compiler₃ :=
    staged_bootstrap_surface_result_semantics_stable oracle h₁₂ h₂₃
  exact machine_result_trace_free_and_weakened_kernel_typed_when_pure_of_surfaceEq
    oracle hCompile₁ hCompile₃ hSurface hCheck₁ hSubtype hPure₁ hMachine₃

theorem staged_bootstrap_machine_result_respects_effects_and_tag_weakened_kernel_expected_type_tag
    (oracle : Oracle)
    {compiler₁ compiler₂ compiler₃ : SurfaceExpr}
    {code₁ code₂ code₃ : Code}
    {expected widened : Weft.Ty}
    {effects : Weft.EffectSet}
    {input : Weft.Input}
    {behavior : ResultBehavior}
    (hCompile₁ : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile compiler₁ = .ok code₁)
    (_hCompile₂ : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile compiler₂ = .ok code₂)
    (hCompile₃ : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile compiler₃ = .ok code₃)
    (h₁₂ : Weft.SemanticEq (surfaceResultSem oracle) compiler₁ compiler₂)
    (h₂₃ : Weft.SemanticEq (surfaceResultSem oracle) compiler₂ compiler₃)
    (hCheck₁ : kernelCheckAgainst (parseSurface compiler₁) expected = true)
    (hSubtype : ∀ tag : Weft.KernelTag, Weft.Ty.denotesTag tag expected -> Weft.Ty.denotesTag tag widened)
    (hEffects₁ : inferEffects (parseSurface compiler₁) = some effects)
    (hMachine₃ : machineResultSem oracle code₃ input behavior) :
    (∀ effect : Weft.EffectName, effect ∈ behavior.trace -> effect ∈ effects.elems) ∧
      Weft.Ty.denotesTag behavior.result.toKernelTag widened := by
  have hSurface : Weft.SemanticEq (surfaceResultSem oracle) compiler₁ compiler₃ :=
    staged_bootstrap_surface_result_semantics_stable oracle h₁₂ h₂₃
  exact machine_result_respects_effects_and_tag_weakened_kernel_expected_type_tag_of_surfaceEq
    oracle hCompile₁ hCompile₃ hSurface hCheck₁ hSubtype hEffects₁ hMachine₃

theorem staged_bootstrap_machine_result_trace_free_and_tag_weakened_kernel_typed_when_pure
    (oracle : Oracle)
    {compiler₁ compiler₂ compiler₃ : SurfaceExpr}
    {code₁ code₂ code₃ : Code}
    {expected widened : Weft.Ty}
    {input : Weft.Input}
    {behavior : ResultBehavior}
    (hCompile₁ : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile compiler₁ = .ok code₁)
    (_hCompile₂ : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile compiler₂ = .ok code₂)
    (hCompile₃ : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile compiler₃ = .ok code₃)
    (h₁₂ : Weft.SemanticEq (surfaceResultSem oracle) compiler₁ compiler₂)
    (h₂₃ : Weft.SemanticEq (surfaceResultSem oracle) compiler₂ compiler₃)
    (hCheck₁ : kernelCheckAgainst (parseSurface compiler₁) expected = true)
    (hSubtype : ∀ tag : Weft.KernelTag, Weft.Ty.denotesTag tag expected -> Weft.Ty.denotesTag tag widened)
    (hPure₁ : inferEffects (parseSurface compiler₁) = some Weft.EffectSet.empty)
    (hMachine₃ : machineResultSem oracle code₃ input behavior) :
    (∀ effect : Weft.EffectName, effect ∉ behavior.trace) ∧
      Weft.Ty.denotesTag behavior.result.toKernelTag widened := by
  have hSurface : Weft.SemanticEq (surfaceResultSem oracle) compiler₁ compiler₃ :=
    staged_bootstrap_surface_result_semantics_stable oracle h₁₂ h₂₃
  exact machine_result_trace_free_and_tag_weakened_kernel_typed_when_pure_of_surfaceEq
    oracle hCompile₁ hCompile₃ hSurface hCheck₁ hSubtype hPure₁ hMachine₃

theorem staged_bootstrap_machine_result_respects_effects_and_kernelSubtypeb_weakened_expected_type_tag
    (oracle : Oracle)
    {compiler₁ compiler₂ compiler₃ : SurfaceExpr}
    {code₁ code₂ code₃ : Code}
    {expected widened : Weft.Ty}
    {effects : Weft.EffectSet}
    {input : Weft.Input}
    {behavior : ResultBehavior}
    (hCompile₁ : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile compiler₁ = .ok code₁)
    (_hCompile₂ : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile compiler₂ = .ok code₂)
    (hCompile₃ : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile compiler₃ = .ok code₃)
    (h₁₂ : Weft.SemanticEq (surfaceResultSem oracle) compiler₁ compiler₂)
    (h₂₃ : Weft.SemanticEq (surfaceResultSem oracle) compiler₂ compiler₃)
    (hCheck₁ : kernelCheckAgainst (parseSurface compiler₁) expected = true)
    (hSubtype : expected.kernelSubtypeb widened = true)
    (hEffects₁ : inferEffects (parseSurface compiler₁) = some effects)
    (hMachine₃ : machineResultSem oracle code₃ input behavior) :
    (∀ effect : Weft.EffectName, effect ∈ behavior.trace -> effect ∈ effects.elems) ∧
      Weft.Ty.denotesTag behavior.result.toKernelTag widened := by
  have hSurface : Weft.SemanticEq (surfaceResultSem oracle) compiler₁ compiler₃ :=
    staged_bootstrap_surface_result_semantics_stable oracle h₁₂ h₂₃
  exact machine_result_respects_effects_and_kernelSubtypeb_weakened_expected_type_tag_of_surfaceEq
    oracle hCompile₁ hCompile₃ hSurface hCheck₁ hSubtype hEffects₁ hMachine₃

theorem staged_bootstrap_machine_result_trace_free_and_kernelSubtypeb_weakened_typed_when_pure
    (oracle : Oracle)
    {compiler₁ compiler₂ compiler₃ : SurfaceExpr}
    {code₁ code₂ code₃ : Code}
    {expected widened : Weft.Ty}
    {input : Weft.Input}
    {behavior : ResultBehavior}
    (hCompile₁ : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile compiler₁ = .ok code₁)
    (_hCompile₂ : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile compiler₂ = .ok code₂)
    (hCompile₃ : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile compiler₃ = .ok code₃)
    (h₁₂ : Weft.SemanticEq (surfaceResultSem oracle) compiler₁ compiler₂)
    (h₂₃ : Weft.SemanticEq (surfaceResultSem oracle) compiler₂ compiler₃)
    (hCheck₁ : kernelCheckAgainst (parseSurface compiler₁) expected = true)
    (hSubtype : expected.kernelSubtypeb widened = true)
    (hPure₁ : inferEffects (parseSurface compiler₁) = some Weft.EffectSet.empty)
    (hMachine₃ : machineResultSem oracle code₃ input behavior) :
    (∀ effect : Weft.EffectName, effect ∉ behavior.trace) ∧
      Weft.Ty.denotesTag behavior.result.toKernelTag widened := by
  have hSurface : Weft.SemanticEq (surfaceResultSem oracle) compiler₁ compiler₃ :=
    staged_bootstrap_surface_result_semantics_stable oracle h₁₂ h₂₃
  exact machine_result_trace_free_and_kernelSubtypeb_weakened_typed_when_pure_of_surfaceEq
    oracle hCompile₁ hCompile₃ hSurface hCheck₁ hSubtype hPure₁ hMachine₃

theorem staged_bootstrap_machine_result_respects_effects_and_ptr_covariant_kernel_expected_type_tag
    (oracle : Oracle)
    {compiler₁ compiler₂ compiler₃ : SurfaceExpr}
    {code₁ code₂ code₃ : Code}
    {inner₁ inner₂ : Weft.Ty}
    {effects : Weft.EffectSet}
    {input : Weft.Input}
    {behavior : ResultBehavior}
    (hCompile₁ : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile compiler₁ = .ok code₁)
    (_hCompile₂ : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile compiler₂ = .ok code₂)
    (hCompile₃ : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile compiler₃ = .ok code₃)
    (h₁₂ : Weft.SemanticEq (surfaceResultSem oracle) compiler₁ compiler₂)
    (h₂₃ : Weft.SemanticEq (surfaceResultSem oracle) compiler₂ compiler₃)
    (hCheck₁ : kernelCheckAgainst (parseSurface compiler₁) (Weft.Ty.ptr inner₁) = true)
    (hSubtype : inner₁.kernelSubtypeb inner₂ = true)
    (hEffects₁ : inferEffects (parseSurface compiler₁) = some effects)
    (hMachine₃ : machineResultSem oracle code₃ input behavior) :
    (∀ effect : Weft.EffectName, effect ∈ behavior.trace -> effect ∈ effects.elems) ∧
      Weft.Ty.denotesTag behavior.result.toKernelTag (Weft.Ty.ptr inner₂) := by
  have hSurface : Weft.SemanticEq (surfaceResultSem oracle) compiler₁ compiler₃ :=
    staged_bootstrap_surface_result_semantics_stable oracle h₁₂ h₂₃
  exact machine_result_respects_effects_and_tag_weakened_kernel_expected_type_tag_of_surfaceEq
    oracle hCompile₁ hCompile₃ hSurface hCheck₁
    (Weft.SafetyCore.tag_subtype_of_ptr_covariant_kernelSubtypeb hSubtype) hEffects₁ hMachine₃

theorem staged_bootstrap_machine_result_trace_free_and_ptr_covariant_kernel_typed_when_pure
    (oracle : Oracle)
    {compiler₁ compiler₂ compiler₃ : SurfaceExpr}
    {code₁ code₂ code₃ : Code}
    {inner₁ inner₂ : Weft.Ty}
    {input : Weft.Input}
    {behavior : ResultBehavior}
    (hCompile₁ : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile compiler₁ = .ok code₁)
    (_hCompile₂ : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile compiler₂ = .ok code₂)
    (hCompile₃ : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile compiler₃ = .ok code₃)
    (h₁₂ : Weft.SemanticEq (surfaceResultSem oracle) compiler₁ compiler₂)
    (h₂₃ : Weft.SemanticEq (surfaceResultSem oracle) compiler₂ compiler₃)
    (hCheck₁ : kernelCheckAgainst (parseSurface compiler₁) (Weft.Ty.ptr inner₁) = true)
    (hSubtype : inner₁.kernelSubtypeb inner₂ = true)
    (hPure₁ : inferEffects (parseSurface compiler₁) = some Weft.EffectSet.empty)
    (hMachine₃ : machineResultSem oracle code₃ input behavior) :
    (∀ effect : Weft.EffectName, effect ∉ behavior.trace) ∧
      Weft.Ty.denotesTag behavior.result.toKernelTag (Weft.Ty.ptr inner₂) := by
  have hSurface : Weft.SemanticEq (surfaceResultSem oracle) compiler₁ compiler₃ :=
    staged_bootstrap_surface_result_semantics_stable oracle h₁₂ h₂₃
  exact machine_result_trace_free_and_tag_weakened_kernel_typed_when_pure_of_surfaceEq
    oracle hCompile₁ hCompile₃ hSurface hCheck₁
    (Weft.SafetyCore.tag_subtype_of_ptr_covariant_kernelSubtypeb hSubtype) hPure₁ hMachine₃

theorem staged_bootstrap_machine_result_respects_effects_and_rc_covariant_kernel_expected_type_tag
    (oracle : Oracle)
    {compiler₁ compiler₂ compiler₃ : SurfaceExpr}
    {code₁ code₂ code₃ : Code}
    {inner₁ inner₂ : Weft.Ty}
    {effects : Weft.EffectSet}
    {input : Weft.Input}
    {behavior : ResultBehavior}
    (hCompile₁ : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile compiler₁ = .ok code₁)
    (_hCompile₂ : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile compiler₂ = .ok code₂)
    (hCompile₃ : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile compiler₃ = .ok code₃)
    (h₁₂ : Weft.SemanticEq (surfaceResultSem oracle) compiler₁ compiler₂)
    (h₂₃ : Weft.SemanticEq (surfaceResultSem oracle) compiler₂ compiler₃)
    (hCheck₁ : kernelCheckAgainst (parseSurface compiler₁) (Weft.Ty.rc inner₁) = true)
    (hSubtype : inner₁.kernelSubtypeb inner₂ = true)
    (hEffects₁ : inferEffects (parseSurface compiler₁) = some effects)
    (hMachine₃ : machineResultSem oracle code₃ input behavior) :
    (∀ effect : Weft.EffectName, effect ∈ behavior.trace -> effect ∈ effects.elems) ∧
      Weft.Ty.denotesTag behavior.result.toKernelTag (Weft.Ty.rc inner₂) := by
  have hSurface : Weft.SemanticEq (surfaceResultSem oracle) compiler₁ compiler₃ :=
    staged_bootstrap_surface_result_semantics_stable oracle h₁₂ h₂₃
  exact machine_result_respects_effects_and_tag_weakened_kernel_expected_type_tag_of_surfaceEq
    oracle hCompile₁ hCompile₃ hSurface hCheck₁
    (Weft.SafetyCore.tag_subtype_of_rc_covariant_kernelSubtypeb hSubtype) hEffects₁ hMachine₃

theorem staged_bootstrap_machine_result_trace_free_and_rc_covariant_kernel_typed_when_pure
    (oracle : Oracle)
    {compiler₁ compiler₂ compiler₃ : SurfaceExpr}
    {code₁ code₂ code₃ : Code}
    {inner₁ inner₂ : Weft.Ty}
    {input : Weft.Input}
    {behavior : ResultBehavior}
    (hCompile₁ : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile compiler₁ = .ok code₁)
    (_hCompile₂ : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile compiler₂ = .ok code₂)
    (hCompile₃ : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile compiler₃ = .ok code₃)
    (h₁₂ : Weft.SemanticEq (surfaceResultSem oracle) compiler₁ compiler₂)
    (h₂₃ : Weft.SemanticEq (surfaceResultSem oracle) compiler₂ compiler₃)
    (hCheck₁ : kernelCheckAgainst (parseSurface compiler₁) (Weft.Ty.rc inner₁) = true)
    (hSubtype : inner₁.kernelSubtypeb inner₂ = true)
    (hPure₁ : inferEffects (parseSurface compiler₁) = some Weft.EffectSet.empty)
    (hMachine₃ : machineResultSem oracle code₃ input behavior) :
    (∀ effect : Weft.EffectName, effect ∉ behavior.trace) ∧
      Weft.Ty.denotesTag behavior.result.toKernelTag (Weft.Ty.rc inner₂) := by
  have hSurface : Weft.SemanticEq (surfaceResultSem oracle) compiler₁ compiler₃ :=
    staged_bootstrap_surface_result_semantics_stable oracle h₁₂ h₂₃
  exact machine_result_trace_free_and_tag_weakened_kernel_typed_when_pure_of_surfaceEq
    oracle hCompile₁ hCompile₃ hSurface hCheck₁
    (Weft.SafetyCore.tag_subtype_of_rc_covariant_kernelSubtypeb hSubtype) hPure₁ hMachine₃

theorem staged_bootstrap_machine_result_respects_effects_and_fn_subtype_kernel_expected_type_tag
    (oracle : Oracle)
    {compiler₁ compiler₂ compiler₃ : SurfaceExpr}
    {code₁ code₂ code₃ : Code}
    {arg₁ ret₁ arg₂ ret₂ : Weft.Ty}
    {eff₁ eff₂ : Weft.EffectSet}
    {effects : Weft.EffectSet}
    {input : Weft.Input}
    {behavior : ResultBehavior}
    (hCompile₁ : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile compiler₁ = .ok code₁)
    (_hCompile₂ : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile compiler₂ = .ok code₂)
    (hCompile₃ : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile compiler₃ = .ok code₃)
    (h₁₂ : Weft.SemanticEq (surfaceResultSem oracle) compiler₁ compiler₂)
    (h₂₃ : Weft.SemanticEq (surfaceResultSem oracle) compiler₂ compiler₃)
    (hCheck₁ : kernelCheckAgainst (parseSurface compiler₁) (Weft.Ty.fn arg₁ eff₁ ret₁) = true)
    (hArg : arg₂.kernelSubtypeb arg₁ = true)
    (hEff : Weft.EffectSet.subsetb eff₁ eff₂ = true)
    (hRet : ret₁.kernelSubtypeb ret₂ = true)
    (hEffects₁ : inferEffects (parseSurface compiler₁) = some effects)
    (hMachine₃ : machineResultSem oracle code₃ input behavior) :
    (∀ effect : Weft.EffectName, effect ∈ behavior.trace -> effect ∈ effects.elems) ∧
      Weft.Ty.denotesTag behavior.result.toKernelTag (Weft.Ty.fn arg₂ eff₂ ret₂) := by
  have hSurface : Weft.SemanticEq (surfaceResultSem oracle) compiler₁ compiler₃ :=
    staged_bootstrap_surface_result_semantics_stable oracle h₁₂ h₂₃
  exact machine_result_respects_effects_and_tag_weakened_kernel_expected_type_tag_of_surfaceEq
    oracle hCompile₁ hCompile₃ hSurface hCheck₁
    (Weft.SafetyCore.tag_subtype_of_fn_subtype_kernelSubtypeb hArg hEff hRet) hEffects₁ hMachine₃

theorem staged_bootstrap_machine_result_trace_free_and_fn_subtype_kernel_typed_when_pure
    (oracle : Oracle)
    {compiler₁ compiler₂ compiler₃ : SurfaceExpr}
    {code₁ code₂ code₃ : Code}
    {arg₁ ret₁ arg₂ ret₂ : Weft.Ty}
    {eff₁ eff₂ : Weft.EffectSet}
    {input : Weft.Input}
    {behavior : ResultBehavior}
    (hCompile₁ : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile compiler₁ = .ok code₁)
    (_hCompile₂ : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile compiler₂ = .ok code₂)
    (hCompile₃ : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile compiler₃ = .ok code₃)
    (h₁₂ : Weft.SemanticEq (surfaceResultSem oracle) compiler₁ compiler₂)
    (h₂₃ : Weft.SemanticEq (surfaceResultSem oracle) compiler₂ compiler₃)
    (hCheck₁ : kernelCheckAgainst (parseSurface compiler₁) (Weft.Ty.fn arg₁ eff₁ ret₁) = true)
    (hArg : arg₂.kernelSubtypeb arg₁ = true)
    (hEff : Weft.EffectSet.subsetb eff₁ eff₂ = true)
    (hRet : ret₁.kernelSubtypeb ret₂ = true)
    (hPure₁ : inferEffects (parseSurface compiler₁) = some Weft.EffectSet.empty)
    (hMachine₃ : machineResultSem oracle code₃ input behavior) :
    (∀ effect : Weft.EffectName, effect ∉ behavior.trace) ∧
      Weft.Ty.denotesTag behavior.result.toKernelTag (Weft.Ty.fn arg₂ eff₂ ret₂) := by
  have hSurface : Weft.SemanticEq (surfaceResultSem oracle) compiler₁ compiler₃ :=
    staged_bootstrap_surface_result_semantics_stable oracle h₁₂ h₂₃
  exact machine_result_trace_free_and_tag_weakened_kernel_typed_when_pure_of_surfaceEq
    oracle hCompile₁ hCompile₃ hSurface hCheck₁
    (Weft.SafetyCore.tag_subtype_of_fn_subtype_kernelSubtypeb hArg hEff hRet) hPure₁ hMachine₃

theorem staged_bootstrap_machine_result_trace_free_and_typed_when_pure
    (oracle : Oracle)
    {compiler₁ compiler₂ compiler₃ : SurfaceExpr}
    {code₁ code₂ code₃ : Code}
    {expected : Weft.Ty}
    {input : Weft.Input}
    {behavior : ResultBehavior}
    (hCompile₁ : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile compiler₁ = .ok code₁)
    (_hCompile₂ : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile compiler₂ = .ok code₂)
    (hCompile₃ : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile compiler₃ = .ok code₃)
    (h₁₂ : Weft.SemanticEq (surfaceResultSem oracle) compiler₁ compiler₂)
    (h₂₃ : Weft.SemanticEq (surfaceResultSem oracle) compiler₂ compiler₃)
    (hCheck₁ : checkAgainst (parseSurface compiler₁) expected = true)
    (hPure₁ : inferEffects (parseSurface compiler₁) = some Weft.EffectSet.empty)
    (hMachine₃ : machineResultSem oracle code₃ input behavior) :
    (∀ effect : Weft.EffectName, effect ∉ behavior.trace) ∧
      ∃ expectedCore : Weft.CoreSetTy,
        Weft.CoreSetTy.ofTy expected = some expectedCore ∧
        expectedCore.denotes behavior.result.toCoreAtom := by
  have hSurface : Weft.SemanticEq (surfaceResultSem oracle) compiler₁ compiler₃ :=
    staged_bootstrap_surface_result_semantics_stable oracle h₁₂ h₂₃
  exact machine_result_trace_free_and_typed_when_pure_of_surfaceEq
    oracle hCompile₁ hCompile₃ hSurface hCheck₁ hPure₁ hMachine₃

theorem staged_bootstrap_machine_io_behavior_trace_free_when_pure
    (oracle : Oracle)
    {compiler₁ compiler₂ compiler₃ : SurfaceExpr}
    {code₁ code₂ code₃ : Code}
    {input : Weft.Input}
    {behavior : Weft.Behavior}
    (hCompile₁ : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile compiler₁ = .ok code₁)
    (_hCompile₂ : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile compiler₂ = .ok code₂)
    (hCompile₃ : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile compiler₃ = .ok code₃)
    (h₁₂ : Weft.SemanticEq (surfaceIOSem oracle) compiler₁ compiler₂)
    (h₂₃ : Weft.SemanticEq (surfaceIOSem oracle) compiler₂ compiler₃)
    (hPure₁ : inferEffects (parseSurface compiler₁) = some Weft.EffectSet.empty)
    (hMachine₃ : machineIOSem oracle code₃ input behavior) :
    behavior.trace = [] := by
  have hSurface : Weft.SemanticEq (surfaceIOSem oracle) compiler₁ compiler₃ :=
    staged_bootstrap_surface_io_semantics_stable oracle h₁₂ h₂₃
  exact machine_io_behavior_trace_free_when_pure_of_surfaceEq
    oracle hCompile₁ hCompile₃ hSurface hPure₁ hMachine₃

theorem staged_bootstrap_machine_io_result_behavior_trace_free_and_kernel_typed_when_pure
    (oracle : Oracle)
    {compiler₁ compiler₂ compiler₃ : SurfaceExpr}
    {code₁ code₂ code₃ : Code}
    {expected : Weft.Ty}
    {input : Weft.Input}
    {behavior : IOResultBehavior}
    (hCompile₁ : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile compiler₁ = .ok code₁)
    (_hCompile₂ : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile compiler₂ = .ok code₂)
    (hCompile₃ : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile compiler₃ = .ok code₃)
    (h₁₂ : Weft.SemanticEq (surfaceIOResultSem oracle) compiler₁ compiler₂)
    (h₂₃ : Weft.SemanticEq (surfaceIOResultSem oracle) compiler₂ compiler₃)
    (hCheck₁ : kernelCheckAgainst (parseSurface compiler₁) expected = true)
    (hPure₁ : inferEffects (parseSurface compiler₁) = some Weft.EffectSet.empty)
    (hMachine₃ : machineIOResultSem oracle code₃ input behavior) :
    behavior.trace = [] ∧
      Weft.Ty.denotesTag behavior.result.toKernelTag expected := by
  have hSurface : Weft.SemanticEq (surfaceIOResultSem oracle) compiler₁ compiler₃ :=
    staged_bootstrap_surface_io_result_semantics_stable oracle h₁₂ h₂₃
  exact machine_io_result_behavior_trace_free_and_kernel_typed_when_pure_of_surfaceEq
    oracle hCompile₁ hCompile₃ hSurface hCheck₁ hPure₁ hMachine₃

end Weft.CoreEffects
