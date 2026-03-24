import Weft.Properties.CoreEffectPipelineSemanticSoundness

namespace Weft.CoreEffects

open Weft.SafetyCore

def sourceIOSem (oracle : Oracle) : Weft.Semantics Expr Weft.Behavior :=
  fun expr _input behavior =>
    ∃ value trace, Eval oracle expr value trace ∧
      behavior = { trace := observeIOTrace oracle trace, exitCode := exitCode value }

def surfaceIOSem (oracle : Oracle) : Weft.Semantics SurfaceExpr Weft.Behavior :=
  fun surface input behavior =>
    sourceIOSem oracle (parseSurface surface) input behavior

def checkedIOSem (oracle : Oracle) : Weft.Semantics CheckedExpr Weft.Behavior :=
  fun checked input behavior =>
    sourceIOSem oracle checked.expr input behavior

def irIOSem (oracle : Oracle) : Weft.Semantics IRExpr Weft.Behavior :=
  fun ir _input behavior =>
    ∃ value trace, IREval oracle ir value trace ∧
      behavior = { trace := observeIOTrace oracle trace, exitCode := exitCode value }

def machineIOSem (oracle : Oracle) : Weft.Semantics Code Weft.Behavior :=
  fun code _input behavior =>
    ∃ value trace, Exec oracle code [] [value] trace ∧
      behavior = { trace := observeIOTrace oracle trace, exitCode := exitCode value }

structure IOResultBehavior : Type where
  result : RuntimeVal
  trace : List Weft.IOEvent
  exitCode : Int
  deriving Repr, DecidableEq

def sourceIOResultSem (oracle : Oracle) : Weft.Semantics Expr IOResultBehavior :=
  fun expr _input behavior =>
    ∃ value trace, Eval oracle expr value trace ∧
      behavior = { result := value, trace := observeIOTrace oracle trace, exitCode := exitCode value }

def surfaceIOResultSem (oracle : Oracle) : Weft.Semantics SurfaceExpr IOResultBehavior :=
  fun surface input behavior =>
    sourceIOResultSem oracle (parseSurface surface) input behavior

def checkedIOResultSem (oracle : Oracle) : Weft.Semantics CheckedExpr IOResultBehavior :=
  fun checked input behavior =>
    sourceIOResultSem oracle checked.expr input behavior

def irIOResultSem (oracle : Oracle) : Weft.Semantics IRExpr IOResultBehavior :=
  fun ir _input behavior =>
    ∃ value trace, IREval oracle ir value trace ∧
      behavior = { result := value, trace := observeIOTrace oracle trace, exitCode := exitCode value }

def machineIOResultSem (oracle : Oracle) : Weft.Semantics Code IOResultBehavior :=
  fun code _input behavior =>
    ∃ value trace, Exec oracle code [] [value] trace ∧
      behavior = { result := value, trace := observeIOTrace oracle trace, exitCode := exitCode value }

theorem staged_whole_io_compiler_theorem
    (oracle : Oracle) :
    Weft.SemanticsPreserving (surfaceIOSem oracle) (machineIOSem oracle)
      (Weft.CompilerPipeline.compile stagedCompilerPipeline) := by
  intro surface code input behavior hCompile hSurface
  rcases hSurface with ⟨value, trace, hEval, hBehavior⟩
  exact ⟨value, trace, staged_compile_correct hCompile hEval, hBehavior⟩

theorem staged_whole_io_result_compiler_theorem
    (oracle : Oracle) :
    Weft.SemanticsPreserving (surfaceIOResultSem oracle) (machineIOResultSem oracle)
      (Weft.CompilerPipeline.compile stagedCompilerPipeline) := by
  intro surface code input behavior hCompile hSurface
  rcases hSurface with ⟨value, trace, hEval, hBehavior⟩
  exact ⟨value, trace, staged_compile_correct hCompile hEval, hBehavior⟩

theorem staged_io_semantics_iff
    (oracle : Oracle)
    {surface : SurfaceExpr}
    {code : Code}
    {input : Weft.Input}
    {behavior : Weft.Behavior}
    (hCompile : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile surface = .ok code) :
    surfaceIOSem oracle surface input behavior ↔ machineIOSem oracle code input behavior := by
  constructor
  · intro hSurface
    exact staged_whole_io_compiler_theorem oracle surface code input behavior hCompile hSurface
  · intro hMachine
    rcases hMachine with ⟨value, trace, hExec, hBehavior⟩
    exact ⟨value, trace, staged_compile_complete hCompile hExec, hBehavior⟩

theorem staged_io_result_semantics_iff
    (oracle : Oracle)
    {surface : SurfaceExpr}
    {code : Code}
    {input : Weft.Input}
    {behavior : IOResultBehavior}
    (hCompile : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile surface = .ok code) :
    surfaceIOResultSem oracle surface input behavior ↔
      machineIOResultSem oracle code input behavior := by
  constructor
  · intro hSurface
    exact staged_whole_io_result_compiler_theorem oracle surface code input behavior hCompile hSurface
  · intro hMachine
    rcases hMachine with ⟨value, trace, hExec, hBehavior⟩
    exact ⟨value, trace, staged_compile_complete hCompile hExec, hBehavior⟩

theorem staged_io_behavior_respects_inferred_effects
    {oracle : Oracle}
    {surface : SurfaceExpr}
    {effects : Weft.EffectSet}
    {code : Code}
    {input : Weft.Input}
    {behavior : Weft.Behavior}
    (hCompile : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile surface = .ok code)
    (hEffects : inferEffects (parseSurface surface) = some effects)
    (hMachine : machineIOSem oracle code input behavior) :
    ∀ effect response,
      Weft.IOEvent.effectQuery effect response ∈ behavior.trace ->
        effect ∈ effects.elems ∧ response = oracle effect := by
  rcases hMachine with ⟨value, trace, hExec, hBehavior⟩
  have hEval : Eval oracle (parseSurface surface) value trace :=
    staged_compile_complete hCompile hExec
  rcases inferEffects_sound hEffects with ⟨ty, hTy⟩
  intro effect response hMem
  have hObserved : effect ∈ trace ∧ response = oracle effect := by
    cases hBehavior
    exact observeIOTrace_query_mem_iff.mp hMem
  exact ⟨trace_subset_of_typed_effects hTy hEval effect hObserved.1, hObserved.2⟩

theorem staged_io_behavior_only_reports_inferred_effects
    {oracle : Oracle}
    {surface : SurfaceExpr}
    {effects : Weft.EffectSet}
    {code : Code}
    {input : Weft.Input}
    {behavior : Weft.Behavior}
    (hCompile : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile surface = .ok code)
    (hEffects : inferEffects (parseSurface surface) = some effects)
    (hMachine : machineIOSem oracle code input behavior) :
    ∀ event, event ∈ behavior.trace ->
      ∃ effect : Weft.EffectName,
        effect ∈ effects.elems ∧ event = Weft.IOEvent.effectQuery effect (oracle effect) := by
  rcases hMachine with ⟨value, trace, hExec, hBehavior⟩
  have hEval : Eval oracle (parseSurface surface) value trace :=
    staged_compile_complete hCompile hExec
  rcases inferEffects_sound hEffects with ⟨ty, hTy⟩
  intro event hMem
  have hObserved :
      ∃ effect : Weft.EffectName,
        effect ∈ trace ∧ event = Weft.IOEvent.effectQuery effect (oracle effect) := by
    cases hBehavior
    exact mem_observeIOTrace_iff.mp hMem
  rcases hObserved with ⟨effect, hInTrace, rfl⟩
  exact ⟨effect, trace_subset_of_typed_effects hTy hEval effect hInTrace, rfl⟩

theorem staged_io_behavior_trace_free_when_pure
    {oracle : Oracle}
    {surface : SurfaceExpr}
    {code : Code}
    {input : Weft.Input}
    {behavior : Weft.Behavior}
    (hCompile : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile surface = .ok code)
    (hPure : inferEffects (parseSurface surface) = some Weft.EffectSet.empty)
    (hMachine : machineIOSem oracle code input behavior) :
    behavior.trace = [] := by
  rcases hMachine with ⟨value, trace, hExec, hBehavior⟩
  have hEval : Eval oracle (parseSurface surface) value trace :=
    staged_compile_complete hCompile hExec
  rcases inferEffects_sound hPure with ⟨ty, hTy⟩
  have hTraceFree : ∀ effect : Weft.EffectName, effect ∉ trace :=
    empty_effects_have_empty_trace hTy hEval
  have hTraceNil : trace = [] :=
    trace_eq_nil_of_forall_not_mem hTraceFree
  cases hBehavior
  simp [hTraceNil, observeIOTrace]

theorem staged_io_result_behavior_respects_effects_and_expected_type_tag
    {oracle : Oracle}
    {surface : SurfaceExpr}
    {expected : Weft.Ty}
    {effects : Weft.EffectSet}
    {code : Code}
    {input : Weft.Input}
    {behavior : IOResultBehavior}
    (hCompile : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile surface = .ok code)
    (hCheck : checkAgainst (parseSurface surface) expected = true)
    (hEffects : inferEffects (parseSurface surface) = some effects)
    (hMachine : machineIOResultSem oracle code input behavior) :
    (∀ effect response,
      Weft.IOEvent.effectQuery effect response ∈ behavior.trace ->
        effect ∈ effects.elems ∧ response = oracle effect) ∧
      Weft.Ty.denotesTag behavior.result.toKernelTag expected := by
  rcases hMachine with ⟨value, trace, hExec, hBehavior⟩
  have hConforms :
      (∀ effect : Weft.EffectName, effect ∈ trace -> effect ∈ effects.elems) ∧
        Weft.Ty.denotesTag value.toKernelTag expected :=
    staged_machine_result_respects_effects_and_expected_type_tag hCompile hCheck hEffects hExec
  cases hBehavior
  constructor
  · intro effect response hMem
    have hObserved : effect ∈ trace ∧ response = oracle effect :=
      observeIOTrace_query_mem_iff.mp hMem
    exact ⟨hConforms.1 effect hObserved.1, hObserved.2⟩
  · exact hConforms.2

theorem staged_io_result_behavior_only_reports_inferred_effects_and_expected_type_tag
    {oracle : Oracle}
    {surface : SurfaceExpr}
    {expected : Weft.Ty}
    {effects : Weft.EffectSet}
    {code : Code}
    {input : Weft.Input}
    {behavior : IOResultBehavior}
    (hCompile : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile surface = .ok code)
    (hCheck : checkAgainst (parseSurface surface) expected = true)
    (hEffects : inferEffects (parseSurface surface) = some effects)
    (hMachine : machineIOResultSem oracle code input behavior) :
    (∀ event, event ∈ behavior.trace ->
      ∃ effect : Weft.EffectName,
        effect ∈ effects.elems ∧ event = Weft.IOEvent.effectQuery effect (oracle effect)) ∧
      Weft.Ty.denotesTag behavior.result.toKernelTag expected := by
  rcases hMachine with ⟨value, trace, hExec, hBehavior⟩
  have hEval : Eval oracle (parseSurface surface) value trace :=
    staged_compile_complete hCompile hExec
  rcases inferEffects_sound hEffects with ⟨ty, hTy⟩
  have hTyped : Weft.Ty.denotesTag value.toKernelTag expected :=
    (staged_machine_result_respects_effects_and_expected_type_tag
      hCompile hCheck hEffects hExec).2
  cases hBehavior
  constructor
  · intro event hMem
    have hObserved :
        ∃ effect : Weft.EffectName,
          effect ∈ trace ∧ event = Weft.IOEvent.effectQuery effect (oracle effect) :=
      mem_observeIOTrace_iff.mp hMem
    rcases hObserved with ⟨effect, hInTrace, rfl⟩
    exact ⟨effect, trace_subset_of_typed_effects hTy hEval effect hInTrace, rfl⟩
  · exact hTyped

theorem staged_io_result_behavior_only_reports_inferred_effects_and_kernel_expected_type_tag
    {oracle : Oracle}
    {surface : SurfaceExpr}
    {expected : Weft.Ty}
    {effects : Weft.EffectSet}
    {code : Code}
    {input : Weft.Input}
    {behavior : IOResultBehavior}
    (hCompile : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile surface = .ok code)
    (hCheck : kernelCheckAgainst (parseSurface surface) expected = true)
    (hEffects : inferEffects (parseSurface surface) = some effects)
    (hMachine : machineIOResultSem oracle code input behavior) :
    (∀ event, event ∈ behavior.trace ->
      ∃ effect : Weft.EffectName,
        effect ∈ effects.elems ∧ event = Weft.IOEvent.effectQuery effect (oracle effect)) ∧
      Weft.Ty.denotesTag behavior.result.toKernelTag expected := by
  rcases hMachine with ⟨value, trace, hExec, hBehavior⟩
  have hEval : Eval oracle (parseSurface surface) value trace :=
    staged_compile_complete hCompile hExec
  rcases inferEffects_sound hEffects with ⟨ty, hTy⟩
  have hTyped : Weft.Ty.denotesTag value.toKernelTag expected :=
    (staged_machine_result_respects_effects_and_kernel_expected_type_tag
      hCompile hCheck hEffects hExec).2
  cases hBehavior
  constructor
  · intro event hMem
    have hObserved :
        ∃ effect : Weft.EffectName,
          effect ∈ trace ∧ event = Weft.IOEvent.effectQuery effect (oracle effect) :=
      mem_observeIOTrace_iff.mp hMem
    rcases hObserved with ⟨effect, hInTrace, rfl⟩
    exact ⟨effect, trace_subset_of_typed_effects hTy hEval effect hInTrace, rfl⟩
  · exact hTyped

theorem staged_io_result_behavior_trace_free_and_typed_when_pure_tag
    {oracle : Oracle}
    {surface : SurfaceExpr}
    {expected : Weft.Ty}
    {code : Code}
    {input : Weft.Input}
    {behavior : IOResultBehavior}
    (hCompile : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile surface = .ok code)
    (hCheck : checkAgainst (parseSurface surface) expected = true)
    (hPure : inferEffects (parseSurface surface) = some Weft.EffectSet.empty)
    (hMachine : machineIOResultSem oracle code input behavior) :
    behavior.trace = [] ∧
      Weft.Ty.denotesTag behavior.result.toKernelTag expected := by
  rcases hMachine with ⟨value, trace, hExec, hBehavior⟩
  have hConforms :
      (∀ effect : Weft.EffectName, effect ∉ trace) ∧
        Weft.Ty.denotesTag value.toKernelTag expected :=
    staged_machine_pure_result_respects_expected_type_tag hCompile hCheck hPure hExec
  have hTraceNil : trace = [] :=
    trace_eq_nil_of_forall_not_mem hConforms.1
  cases hBehavior
  exact ⟨by simp [hTraceNil, observeIOTrace], hConforms.2⟩

theorem staged_io_result_behavior_trace_free_and_kernel_typed_when_pure_tag
    {oracle : Oracle}
    {surface : SurfaceExpr}
    {expected : Weft.Ty}
    {code : Code}
    {input : Weft.Input}
    {behavior : IOResultBehavior}
    (hCompile : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile surface = .ok code)
    (hCheck : kernelCheckAgainst (parseSurface surface) expected = true)
    (hPure : inferEffects (parseSurface surface) = some Weft.EffectSet.empty)
    (hMachine : machineIOResultSem oracle code input behavior) :
    behavior.trace = [] ∧
      Weft.Ty.denotesTag behavior.result.toKernelTag expected := by
  rcases hMachine with ⟨value, trace, hExec, hBehavior⟩
  have hConforms :
      (∀ effect : Weft.EffectName, effect ∉ trace) ∧
        Weft.Ty.denotesTag value.toKernelTag expected :=
    staged_machine_pure_result_respects_kernel_expected_type_tag hCompile hCheck hPure hExec
  have hTraceNil : trace = [] :=
    trace_eq_nil_of_forall_not_mem hConforms.1
  cases hBehavior
  exact ⟨by simp [hTraceNil, observeIOTrace], hConforms.2⟩

end Weft.CoreEffects
