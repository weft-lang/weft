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
    Weft.SemanticEq (machineIOSem oracle) code₁ code₂ := by
  intro input behavior
  constructor
  · intro hMachine
    have hSurface₁ : surfaceIOSem oracle surface₁ input behavior :=
      (staged_io_semantics_iff oracle hCompile₁).2 hMachine
    have hSurface₂ : surfaceIOSem oracle surface₂ input behavior :=
      (hEq input behavior).1 hSurface₁
    exact (staged_io_semantics_iff oracle hCompile₂).1 hSurface₂
  · intro hMachine
    have hSurface₂ : surfaceIOSem oracle surface₂ input behavior :=
      (staged_io_semantics_iff oracle hCompile₂).2 hMachine
    have hSurface₁ : surfaceIOSem oracle surface₁ input behavior :=
      (hEq input behavior).2 hSurface₂
    exact (staged_io_semantics_iff oracle hCompile₁).1 hSurface₁

theorem machine_io_result_semanticEq_of_surfaceEq
    (oracle : Oracle)
    {surface₁ surface₂ : SurfaceExpr}
    {code₁ code₂ : Code}
    (hCompile₁ : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile surface₁ = .ok code₁)
    (hCompile₂ : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile surface₂ = .ok code₂)
    (hEq : Weft.SemanticEq (surfaceIOResultSem oracle) surface₁ surface₂) :
    Weft.SemanticEq (machineIOResultSem oracle) code₁ code₂ := by
  intro input behavior
  constructor
  · intro hMachine
    have hSurface₁ : surfaceIOResultSem oracle surface₁ input behavior :=
      (staged_io_result_semantics_iff oracle hCompile₁).2 hMachine
    have hSurface₂ : surfaceIOResultSem oracle surface₂ input behavior :=
      (hEq input behavior).1 hSurface₁
    exact (staged_io_result_semantics_iff oracle hCompile₂).1 hSurface₂
  · intro hMachine
    have hSurface₂ : surfaceIOResultSem oracle surface₂ input behavior :=
      (staged_io_result_semantics_iff oracle hCompile₂).2 hMachine
    have hSurface₁ : surfaceIOResultSem oracle surface₁ input behavior :=
      (hEq input behavior).2 hSurface₂
    exact (staged_io_result_semantics_iff oracle hCompile₁).1 hSurface₁

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
    Weft.SemanticEq (machineIOSem oracle) code₁ code₃ := by
  have hSurface : Weft.SemanticEq (surfaceIOSem oracle) compiler₁ compiler₃ :=
    staged_bootstrap_surface_io_semantics_stable oracle h₁₂ h₂₃
  exact machine_io_semanticEq_of_surfaceEq oracle hCompile₁ hCompile₃ hSurface

theorem staged_bootstrap_machine_io_result_semantics_stable
    (oracle : Oracle)
    {compiler₁ compiler₂ compiler₃ : SurfaceExpr}
    {code₁ code₂ code₃ : Code}
    (hCompile₁ : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile compiler₁ = .ok code₁)
    (_hCompile₂ : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile compiler₂ = .ok code₂)
    (hCompile₃ : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile compiler₃ = .ok code₃)
    (h₁₂ : Weft.SemanticEq (surfaceIOResultSem oracle) compiler₁ compiler₂)
    (h₂₃ : Weft.SemanticEq (surfaceIOResultSem oracle) compiler₂ compiler₃) :
    Weft.SemanticEq (machineIOResultSem oracle) code₁ code₃ := by
  have hSurface : Weft.SemanticEq (surfaceIOResultSem oracle) compiler₁ compiler₃ :=
    staged_bootstrap_surface_io_result_semantics_stable oracle h₁₂ h₂₃
  exact machine_io_result_semanticEq_of_surfaceEq oracle hCompile₁ hCompile₃ hSurface

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
