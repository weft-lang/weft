import Weft.CoreEffectPipeline
import Weft.Properties.CoreEffectCompilerCorrectness
import Weft.Properties.CompilerCorrectness

namespace Weft.CoreEffects

open Weft.SafetyCore

structure EffectBehavior : Type where
  trace : List Weft.EffectName
  exitCode : Int
  deriving Repr, DecidableEq

def sourceSem (oracle : Oracle) : Weft.Semantics Expr EffectBehavior :=
  fun expr _input behavior =>
    ∃ value trace, Eval oracle expr value trace ∧
      behavior = { trace := trace, exitCode := exitCode value }

def surfaceSem (oracle : Oracle) : Weft.Semantics SurfaceExpr EffectBehavior :=
  fun surface input behavior =>
    sourceSem oracle (parseSurface surface) input behavior

def checkedSem (oracle : Oracle) : Weft.Semantics CheckedExpr EffectBehavior :=
  fun checked input behavior =>
    sourceSem oracle checked.expr input behavior

def irSem (oracle : Oracle) : Weft.Semantics IRExpr EffectBehavior :=
  fun ir _input behavior =>
    ∃ value trace, IREval oracle ir value trace ∧
      behavior = { trace := trace, exitCode := exitCode value }

def machineSem (oracle : Oracle) : Weft.Semantics Code EffectBehavior :=
  fun code _input behavior =>
    ∃ value trace, Exec oracle code [] [value] trace ∧
      behavior = { trace := trace, exitCode := exitCode value }

structure ResultBehavior : Type where
  result : RuntimeVal
  trace : List Weft.EffectName
  exitCode : Int
  deriving Repr, DecidableEq

def sourceResultSem (oracle : Oracle) : Weft.Semantics Expr ResultBehavior :=
  fun expr _input behavior =>
    ∃ value trace, Eval oracle expr value trace ∧
      behavior = { result := value, trace := trace, exitCode := exitCode value }

def surfaceResultSem (oracle : Oracle) : Weft.Semantics SurfaceExpr ResultBehavior :=
  fun surface input behavior =>
    sourceResultSem oracle (parseSurface surface) input behavior

def checkedResultSem (oracle : Oracle) : Weft.Semantics CheckedExpr ResultBehavior :=
  fun checked input behavior =>
    sourceResultSem oracle checked.expr input behavior

def irResultSem (oracle : Oracle) : Weft.Semantics IRExpr ResultBehavior :=
  fun ir _input behavior =>
    ∃ value trace, IREval oracle ir value trace ∧
      behavior = { result := value, trace := trace, exitCode := exitCode value }

def machineResultSem (oracle : Oracle) : Weft.Semantics Code ResultBehavior :=
  fun code _input behavior =>
    ∃ value trace, Exec oracle code [] [value] trace ∧
      behavior = { result := value, trace := trace, exitCode := exitCode value }

theorem parse_stage_preserves
    (oracle : Oracle) :
    Weft.SemanticsPreserving (surfaceSem oracle) (sourceSem oracle) parseStage := by
  intro surface artifact input behavior hCompile hSurface
  simp [parseStage] at hCompile
  subst artifact
  exact hSurface

theorem parse_stage_preserves_result
    (oracle : Oracle) :
    Weft.SemanticsPreserving (surfaceResultSem oracle) (sourceResultSem oracle) parseStage := by
  intro surface artifact input behavior hCompile hSurface
  simp [parseStage] at hCompile
  subst artifact
  exact hSurface

theorem parse_stage_reflects
    (oracle : Oracle) :
    Weft.SemanticsReflecting (surfaceSem oracle) (sourceSem oracle) parseStage := by
  intro surface artifact input behavior hCompile hSource
  simp [parseStage] at hCompile
  subst artifact
  exact hSource

theorem parse_stage_reflects_result
    (oracle : Oracle) :
    Weft.SemanticsReflecting (surfaceResultSem oracle) (sourceResultSem oracle) parseStage := by
  intro surface artifact input behavior hCompile hSource
  simp [parseStage] at hCompile
  subst artifact
  exact hSource

theorem typecheck_stage_preserves
    (oracle : Oracle) :
    Weft.SemanticsPreserving (sourceSem oracle) (checkedSem oracle) typecheckStage := by
  intro expr artifact input behavior hCompile hSource
  cases hCheck : check expr with
  | none =>
      simp [typecheckStage, hCheck] at hCompile
  | some checked =>
      simp [typecheckStage, hCheck] at hCompile
      cases hCompile
      exact hSource

theorem typecheck_stage_preserves_result
    (oracle : Oracle) :
    Weft.SemanticsPreserving (sourceResultSem oracle) (checkedResultSem oracle) typecheckStage := by
  intro expr artifact input behavior hCompile hSource
  cases hCheck : check expr with
  | none =>
      simp [typecheckStage, hCheck] at hCompile
  | some checked =>
      simp [typecheckStage, hCheck] at hCompile
      cases hCompile
      exact hSource

theorem typecheck_stage_reflects
    (oracle : Oracle) :
    Weft.SemanticsReflecting (sourceSem oracle) (checkedSem oracle) typecheckStage := by
  intro expr artifact input behavior hCompile hChecked
  cases hCheck : check expr with
  | none =>
      simp [typecheckStage, hCheck] at hCompile
  | some checked =>
      simp [typecheckStage, hCheck] at hCompile
      cases hCompile
      exact hChecked

theorem typecheck_stage_reflects_result
    (oracle : Oracle) :
    Weft.SemanticsReflecting (sourceResultSem oracle) (checkedResultSem oracle) typecheckStage := by
  intro expr artifact input behavior hCompile hChecked
  cases hCheck : check expr with
  | none =>
      simp [typecheckStage, hCheck] at hCompile
  | some checked =>
      simp [typecheckStage, hCheck] at hCompile
      cases hCompile
      exact hChecked

theorem lower_eval_preserves
    {oracle : Oracle}
    {expr : Expr}
    {value : RuntimeVal}
    {trace : List Weft.EffectName}
    (hEval : Eval oracle expr value trace) :
    IREval oracle (lower expr) value trace := by
  induction hEval with
  | bool oracle b =>
      simpa [lower] using IREval.const oracle (.bool b)
  | int oracle n =>
      simpa [lower] using IREval.const oracle (.int n)
  | nil oracle =>
      simpa [lower] using IREval.const oracle RuntimeVal.nil
  | add oracle lhs rhs lhsVal rhsVal traceL traceR hEvalL hEvalR ihL ihR =>
      simpa [lower] using IREval.add oracle (lower lhs) (lower rhs) lhsVal rhsVal traceL traceR ihL ihR
  | ifTrue oracle cond thenBranch elseBranch value traceCond traceThen hEvalCond hEvalThen ihCond ihThen =>
      simpa [lower] using
        IREval.ifTrue oracle (lower cond) (lower thenBranch) (lower elseBranch)
          value traceCond traceThen ihCond ihThen
  | ifFalse oracle cond thenBranch elseBranch value traceCond traceElse hEvalCond hEvalElse ihCond ihElse =>
      simpa [lower] using
        IREval.ifFalse oracle (lower cond) (lower thenBranch) (lower elseBranch)
          value traceCond traceElse ihCond ihElse
  | performBool oracle effect =>
      simpa [lower] using IREval.performBool oracle effect
  | handleBool oracle effect value body result trace hEvalBody ihBody =>
      simpa [lower] using
        IREval.handleBool oracle effect value (lower body) result trace ihBody

theorem lower_stage_preserves
    (oracle : Oracle) :
    Weft.SemanticsPreserving (checkedSem oracle) (irSem oracle) lowerStage := by
  intro checked artifact input behavior hCompile hChecked
  simp [lowerStage] at hCompile
  subst artifact
  rcases hChecked with ⟨value, trace, hEval, hBehavior⟩
  exact ⟨value, trace, lower_eval_preserves hEval, hBehavior⟩

theorem lower_stage_preserves_result
    (oracle : Oracle) :
    Weft.SemanticsPreserving (checkedResultSem oracle) (irResultSem oracle) lowerStage := by
  intro checked artifact input behavior hCompile hChecked
  simp [lowerStage] at hCompile
  subst artifact
  rcases hChecked with ⟨value, trace, hEval, hBehavior⟩
  exact ⟨value, trace, lower_eval_preserves hEval, hBehavior⟩

@[simp] theorem lower_toExpr
    (expr : Expr) :
    (lower expr).toExpr = expr := by
  induction expr <;> simp [lower, IRExpr.toExpr, *]

theorem irEval_to_source
    {oracle : Oracle}
    {ir : IRExpr}
    {value : RuntimeVal}
    {trace : List Weft.EffectName}
    (hEval : IREval oracle ir value trace) :
    Eval oracle ir.toExpr value trace := by
  induction hEval with
  | const oracle value =>
      cases value with
      | bool b =>
          simpa [IRExpr.toExpr] using Eval.bool oracle b
      | int n =>
          simpa [IRExpr.toExpr] using Eval.int oracle n
      | nil =>
          simpa [IRExpr.toExpr] using Eval.nil oracle
  | add oracle lhs rhs lhsVal rhsVal traceL traceR hL hR ihL ihR =>
      simpa [IRExpr.toExpr] using
        Eval.add oracle lhs.toExpr rhs.toExpr lhsVal rhsVal traceL traceR ihL ihR
  | ifTrue oracle cond thenBranch elseBranch value traceCond traceThen hCond hThen ihCond ihThen =>
      simpa [IRExpr.toExpr] using
        Eval.ifTrue oracle cond.toExpr thenBranch.toExpr elseBranch.toExpr value traceCond traceThen ihCond ihThen
  | ifFalse oracle cond thenBranch elseBranch value traceCond traceElse hCond hElse ihCond ihElse =>
      simpa [IRExpr.toExpr] using
        Eval.ifFalse oracle cond.toExpr thenBranch.toExpr elseBranch.toExpr value traceCond traceElse ihCond ihElse
  | performBool oracle effect =>
      simpa [IRExpr.toExpr] using Eval.performBool oracle effect
  | handleBool oracle effect value body result trace hBody ihBody =>
      simpa [IRExpr.toExpr] using
        Eval.handleBool oracle effect value body.toExpr result trace ihBody

theorem lower_stage_reflects
    (oracle : Oracle) :
    Weft.SemanticsReflecting (checkedSem oracle) (irSem oracle) lowerStage := by
  intro checked artifact input behavior hCompile hIr
  simp [lowerStage] at hCompile
  subst artifact
  rcases hIr with ⟨value, trace, hEval, hBehavior⟩
  exact ⟨value, trace, by
    simpa [lower_toExpr] using (irEval_to_source hEval : Eval oracle (lower checked.expr).toExpr value trace), hBehavior⟩

theorem lower_stage_reflects_result
    (oracle : Oracle) :
    Weft.SemanticsReflecting (checkedResultSem oracle) (irResultSem oracle) lowerStage := by
  intro checked artifact input behavior hCompile hIr
  simp [lowerStage] at hCompile
  subst artifact
  rcases hIr with ⟨value, trace, hEval, hBehavior⟩
  exact ⟨value, trace, by
    simpa [lower_toExpr] using (irEval_to_source hEval : Eval oracle (lower checked.expr).toExpr value trace), hBehavior⟩

theorem sourceEval_to_irEval
    {oracle : Oracle}
    {ir : IRExpr}
    {value : RuntimeVal}
    {trace : List Weft.EffectName}
    (hEval : Eval oracle ir.toExpr value trace) :
    IREval oracle ir value trace := by
  induction ir generalizing oracle value trace with
  | const runtime =>
      cases runtime <;> cases hEval <;> simpa [IRExpr.toExpr] using IREval.const oracle _
  | add lhs rhs ihL ihR =>
      cases hEval with
      | add oracle lhsExpr rhsExpr lhsVal rhsVal traceL traceR hL hR =>
          simpa [IRExpr.toExpr] using
            IREval.add oracle lhs rhs lhsVal rhsVal traceL traceR (ihL hL) (ihR hR)
  | ite cond thenBranch elseBranch ihCond ihThen ihElse =>
      cases hEval with
      | ifTrue oracle condExpr thenExpr elseExpr value traceCond traceThen hCond hThen =>
          simpa [IRExpr.toExpr] using
            IREval.ifTrue oracle cond thenBranch elseBranch value traceCond traceThen
              (ihCond hCond) (ihThen hThen)
      | ifFalse oracle condExpr thenExpr elseExpr value traceCond traceElse hCond hElse =>
          simpa [IRExpr.toExpr] using
            IREval.ifFalse oracle cond thenBranch elseBranch value traceCond traceElse
              (ihCond hCond) (ihElse hElse)
  | performBool effect =>
      cases hEval
      simpa [IRExpr.toExpr] using IREval.performBool oracle effect
  | handleBool effect handled body ihBody =>
      cases hEval with
      | handleBool oracle _ _ _ _ trace hBody =>
          simpa [IRExpr.toExpr] using
            IREval.handleBool oracle effect handled body value trace (ihBody hBody)

theorem emitIR_eq_compile_toExpr
    (ir : IRExpr)
    (k : Code) :
    emitIR ir k = compile ir.toExpr k := by
  induction ir generalizing k with
  | const value =>
      cases value <;> rfl
  | add lhs rhs ihL ihR =>
      simp [emitIR, IRExpr.toExpr, compile, ihL, ihR]
  | ite cond thenBranch elseBranch ihCond ihThen ihElse =>
      simp [emitIR, IRExpr.toExpr, compile, ihCond, ihThen, ihElse]
  | performBool effect =>
      rfl
  | handleBool effect value body ihBody =>
      simp [emitIR, IRExpr.toExpr, compile, ihBody]

theorem emit_correct_aux
    (oracle : Oracle)
    (ir : IRExpr)
    (value : RuntimeVal)
    (trace : List Weft.EffectName)
    (k : Code)
    (stack out : List RuntimeVal)
    (traceK : List Weft.EffectName)
    (hEval : IREval oracle ir value trace)
    (hExecK : Exec oracle k (value :: stack) out traceK) :
    Exec oracle (emitIR ir k) stack out (trace ++ traceK) := by
  have hSourceEval : Eval oracle ir.toExpr value trace :=
    irEval_to_source hEval
  have hCompiled : Exec oracle (compile ir.toExpr k) stack out (trace ++ traceK) :=
    compile_correct_aux oracle ir.toExpr value trace k stack out traceK hSourceEval hExecK
  simpa [emitIR_eq_compile_toExpr ir k] using hCompiled

theorem emit_correct
    (oracle : Oracle)
    (ir : IRExpr)
    (value : RuntimeVal)
    (trace : List Weft.EffectName)
    (hEval : IREval oracle ir value trace) :
    Exec oracle (emitClosed ir) [] [value] trace := by
  simpa [emitClosed] using
    emit_correct_aux oracle ir value trace .halt [] [value] [] hEval (Exec.halt oracle [value])

theorem emitClosed_eq_compileClosed
    (expr : Expr) :
    emitClosed (lower expr) = compileClosed expr := by
  simpa [emitClosed, compileClosed, lower_toExpr] using
    emitIR_eq_compile_toExpr (lower expr) .halt

theorem emit_stage_preserves
    (oracle : Oracle) :
    Weft.SemanticsPreserving (irSem oracle) (machineSem oracle) emitStage := by
  intro ir artifact input behavior hCompile hIr
  simp [emitStage, emitClosed] at hCompile
  subst artifact
  rcases hIr with ⟨value, trace, hEval, hBehavior⟩
  exact ⟨value, trace, emit_correct oracle ir value trace hEval, hBehavior⟩

theorem emit_stage_preserves_result
    (oracle : Oracle) :
    Weft.SemanticsPreserving (irResultSem oracle) (machineResultSem oracle) emitStage := by
  intro ir artifact input behavior hCompile hIr
  simp [emitStage, emitClosed] at hCompile
  subst artifact
  rcases hIr with ⟨value, trace, hEval, hBehavior⟩
  exact ⟨value, trace, emit_correct oracle ir value trace hEval, hBehavior⟩

theorem emit_stage_reflects
    (oracle : Oracle) :
    Weft.SemanticsReflecting (irSem oracle) (machineSem oracle) emitStage := by
  intro ir artifact input behavior hCompile hMachine
  simp [emitStage, emitClosed] at hCompile
  subst artifact
  rcases hMachine with ⟨value, trace, hExec, hBehavior⟩
  have hExecCompile : Exec oracle (compileClosed ir.toExpr) [] [value] trace := by
    simpa [compileClosed] using
      (show Exec oracle (compile ir.toExpr .halt) [] [value] trace from by
        simpa [emitIR_eq_compile_toExpr] using hExec)
  have hSource : Eval oracle ir.toExpr value trace :=
    compile_complete oracle ir.toExpr value trace hExecCompile
  exact ⟨value, trace, sourceEval_to_irEval hSource, hBehavior⟩

theorem emit_stage_reflects_result
    (oracle : Oracle) :
    Weft.SemanticsReflecting (irResultSem oracle) (machineResultSem oracle) emitStage := by
  intro ir artifact input behavior hCompile hMachine
  simp [emitStage, emitClosed] at hCompile
  subst artifact
  rcases hMachine with ⟨value, trace, hExec, hBehavior⟩
  have hExecCompile : Exec oracle (compileClosed ir.toExpr) [] [value] trace := by
    simpa [compileClosed] using
      (show Exec oracle (compile ir.toExpr .halt) [] [value] trace from by
        simpa [emitIR_eq_compile_toExpr] using hExec)
  have hSource : Eval oracle ir.toExpr value trace :=
    compile_complete oracle ir.toExpr value trace hExecCompile
  exact ⟨value, trace, sourceEval_to_irEval hSource, hBehavior⟩

theorem staged_whole_compiler_theorem
    (oracle : Oracle) :
    Weft.SemanticsPreserving (surfaceSem oracle) (machineSem oracle)
      (Weft.CompilerPipeline.compile stagedCompilerPipeline) := by
  simpa using
    (Weft.whole_compiler_theorem
      stagedCompilerPipeline
      (surfaceSem oracle)
      (sourceSem oracle)
      (checkedSem oracle)
      (irSem oracle)
      (machineSem oracle)
      (parse_stage_preserves oracle)
      (typecheck_stage_preserves oracle)
      (lower_stage_preserves oracle)
      (emit_stage_preserves oracle))

theorem staged_whole_result_compiler_theorem
    (oracle : Oracle) :
    Weft.SemanticsPreserving (surfaceResultSem oracle) (machineResultSem oracle)
      (Weft.CompilerPipeline.compile stagedCompilerPipeline) := by
  simpa using
    (Weft.whole_compiler_theorem
      stagedCompilerPipeline
      (surfaceResultSem oracle)
      (sourceResultSem oracle)
      (checkedResultSem oracle)
      (irResultSem oracle)
      (machineResultSem oracle)
      (parse_stage_preserves_result oracle)
      (typecheck_stage_preserves_result oracle)
      (lower_stage_preserves_result oracle)
      (emit_stage_preserves_result oracle))

theorem staged_whole_compiler_reflection_theorem
    (oracle : Oracle) :
    Weft.SemanticsReflecting (surfaceSem oracle) (machineSem oracle)
      (Weft.CompilerPipeline.compile stagedCompilerPipeline) := by
  simpa using
    (Weft.whole_compiler_reflection_theorem
      stagedCompilerPipeline
      (surfaceSem oracle)
      (sourceSem oracle)
      (checkedSem oracle)
      (irSem oracle)
      (machineSem oracle)
      (parse_stage_reflects oracle)
      (typecheck_stage_reflects oracle)
      (lower_stage_reflects oracle)
      (emit_stage_reflects oracle))

theorem staged_whole_result_compiler_reflection_theorem
    (oracle : Oracle) :
    Weft.SemanticsReflecting (surfaceResultSem oracle) (machineResultSem oracle)
      (Weft.CompilerPipeline.compile stagedCompilerPipeline) := by
  simpa using
    (Weft.whole_compiler_reflection_theorem
      stagedCompilerPipeline
      (surfaceResultSem oracle)
      (sourceResultSem oracle)
      (checkedResultSem oracle)
      (irResultSem oracle)
      (machineResultSem oracle)
      (parse_stage_reflects_result oracle)
      (typecheck_stage_reflects_result oracle)
      (lower_stage_reflects_result oracle)
      (emit_stage_reflects_result oracle))

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

theorem staged_compile_complete
    {oracle : Oracle}
    {surface : SurfaceExpr}
    {code : Code}
    {value : RuntimeVal}
    {trace : List Weft.EffectName}
    (hCompile : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile surface = .ok code)
    (hExec : Exec oracle code [] [value] trace) :
    Eval oracle (parseSurface surface) value trace := by
  have hCode : code = emitClosed (lower (parseSurface surface)) :=
    staged_compile_eq_emitClosed hCompile
  subst code
  rw [emitClosed_eq_compileClosed] at hExec
  exact compile_complete oracle (parseSurface surface) value trace hExec

theorem staged_semantics_iff
    (oracle : Oracle)
    {surface : SurfaceExpr}
    {code : Code}
    {input : Weft.Input}
    {behavior : EffectBehavior}
    (hCompile : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile surface = .ok code) :
    surfaceSem oracle surface input behavior ↔ machineSem oracle code input behavior := by
  exact Weft.whole_compiler_semantics_iff
    stagedCompilerPipeline
    (surfaceSem oracle)
    (sourceSem oracle)
    (checkedSem oracle)
    (irSem oracle)
    (machineSem oracle)
    (parse_stage_preserves oracle)
    (typecheck_stage_preserves oracle)
    (lower_stage_preserves oracle)
    (emit_stage_preserves oracle)
    (parse_stage_reflects oracle)
    (typecheck_stage_reflects oracle)
    (lower_stage_reflects oracle)
    (emit_stage_reflects oracle)
    hCompile

theorem staged_result_semantics_iff
    (oracle : Oracle)
    {surface : SurfaceExpr}
    {code : Code}
    {input : Weft.Input}
    {behavior : ResultBehavior}
    (hCompile : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile surface = .ok code) :
    surfaceResultSem oracle surface input behavior ↔ machineResultSem oracle code input behavior := by
  exact Weft.whole_compiler_semantics_iff
    stagedCompilerPipeline
    (surfaceResultSem oracle)
    (sourceResultSem oracle)
    (checkedResultSem oracle)
    (irResultSem oracle)
    (machineResultSem oracle)
    (parse_stage_preserves_result oracle)
    (typecheck_stage_preserves_result oracle)
    (lower_stage_preserves_result oracle)
    (emit_stage_preserves_result oracle)
    (parse_stage_reflects_result oracle)
    (typecheck_stage_reflects_result oracle)
    (lower_stage_reflects_result oracle)
    (emit_stage_reflects_result oracle)
    hCompile

end Weft.CoreEffects
