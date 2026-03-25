import Weft.CorePipeline
import Weft.Properties.CoreCompilerCorrectness

namespace Weft.SafetyCore

def surfaceSem (surface : SurfaceExpr) (input : Weft.Input) (behavior : Weft.Behavior) : Prop :=
  sourceSem (parseSurface surface) input behavior

def checkedSem (checked : CheckedExpr) (input : Weft.Input) (behavior : Weft.Behavior) : Prop :=
  sourceSem checked.expr input behavior

def irSem (ir : IRExpr) (_input : Weft.Input) (behavior : Weft.Behavior) : Prop :=
  ∃ value, IREval ir value ∧ behavior = { trace := [], exitCode := exitCode value }

theorem parse_stage_preserves :
    Weft.SemanticsPreserving surfaceSem sourceSem parseStage := by
  intro surface artifact input behavior hCompile hSurface
  simp [parseStage] at hCompile
  subst artifact
  exact hSurface

theorem parse_stage_reflects :
    Weft.SemanticsReflecting surfaceSem sourceSem parseStage := by
  intro surface artifact input behavior hCompile hSource
  simp [parseStage] at hCompile
  subst artifact
  exact hSource

theorem typecheck_stage_preserves :
    Weft.SemanticsPreserving sourceSem checkedSem typecheckStage := by
  intro expr artifact input behavior hCompile hSource
  cases hCheck : check expr with
  | none =>
      simp [typecheckStage, hCheck] at hCompile
  | some checked =>
      simp [typecheckStage, hCheck] at hCompile
      cases hCompile
      exact hSource

theorem typecheck_stage_reflects :
    Weft.SemanticsReflecting sourceSem checkedSem typecheckStage := by
  intro expr artifact input behavior hCompile hChecked
  cases hCheck : check expr with
  | none =>
      simp [typecheckStage, hCheck] at hCompile
  | some checked =>
      simp [typecheckStage, hCheck] at hCompile
      cases hCompile
      exact hChecked

theorem lower_eval_preserves
    {expr : Expr}
    {value : RuntimeVal}
    (hEval : Eval expr value) :
    IREval (lower expr) value := by
  induction hEval with
  | bool b =>
      simpa [lower] using IREval.const (.bool b)
  | int n =>
      simpa [lower] using IREval.const (.int n)
  | nil =>
      simpa [lower] using IREval.const RuntimeVal.nil
  | add lhs rhs lhsVal rhsVal hEvalLhs hEvalRhs ihLhs ihRhs =>
      simpa [lower] using IREval.add (lower lhs) (lower rhs) lhsVal rhsVal ihLhs ihRhs
  | ifTrue cond thenBranch elseBranch value hEvalCond hEvalThen ihCond ihThen =>
      simpa [lower] using IREval.ifTrue (lower cond) (lower thenBranch) (lower elseBranch) value ihCond ihThen
  | ifFalse cond thenBranch elseBranch value hEvalCond hEvalElse ihCond ihElse =>
      simpa [lower] using IREval.ifFalse (lower cond) (lower thenBranch) (lower elseBranch) value ihCond ihElse

theorem lower_stage_preserves :
    Weft.SemanticsPreserving checkedSem irSem lowerStage := by
  intro checked artifact input behavior hCompile hChecked
  simp [lowerStage] at hCompile
  subst artifact
  rcases hChecked with ⟨value, hEval, hBehavior⟩
  exact ⟨value, lower_eval_preserves hEval, hBehavior⟩

@[simp] theorem lower_toExpr
    (expr : Expr) :
    (lower expr).toExpr = expr := by
  induction expr <;> simp [lower, IRExpr.toExpr, *]

theorem irEval_to_source
    {ir : IRExpr}
    {value : RuntimeVal}
    (hEval : IREval ir value) :
    Eval ir.toExpr value := by
  induction hEval with
  | const value =>
      cases value with
      | bool b =>
          simpa [IRExpr.toExpr] using Eval.bool b
      | int n =>
          simpa [IRExpr.toExpr] using Eval.int n
      | nil =>
          simpa [IRExpr.toExpr] using Eval.nil
  | add lhs rhs lhsVal rhsVal hL hR ihL ihR =>
      simpa [IRExpr.toExpr] using Eval.add lhs.toExpr rhs.toExpr lhsVal rhsVal ihL ihR
  | ifTrue cond thenBranch elseBranch value hCond hThen ihCond ihThen =>
      simpa [IRExpr.toExpr] using
        Eval.ifTrue cond.toExpr thenBranch.toExpr elseBranch.toExpr value ihCond ihThen
  | ifFalse cond thenBranch elseBranch value hCond hElse ihCond ihElse =>
      simpa [IRExpr.toExpr] using
        Eval.ifFalse cond.toExpr thenBranch.toExpr elseBranch.toExpr value ihCond ihElse

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

theorem emit_correct_aux
    (ir : IRExpr)
    (value : RuntimeVal)
    (k : Code)
    (stack out : List RuntimeVal)
    (hEval : IREval ir value)
    (hExecK : Exec k (value :: stack) out) :
    Exec (emitIR ir k) stack out := by
  induction hEval generalizing k stack out with
  | const value =>
      cases value with
      | bool b =>
          simpa [emitIR] using Exec.pushBool b k stack out hExecK
      | int n =>
          simpa [emitIR] using Exec.pushInt n k stack out hExecK
      | nil =>
          simpa [emitIR] using Exec.pushNil k stack out hExecK
  | add lhs rhs lhsVal rhsVal hLhs hRhs ihLhs ihRhs =>
      have hAdd : Exec (.add k) (.int rhsVal :: .int lhsVal :: stack) out :=
        Exec.add k stack out lhsVal rhsVal hExecK
      have hRight : Exec (emitIR rhs (.add k)) (.int lhsVal :: stack) out :=
        ihRhs (.add k) (.int lhsVal :: stack) out hAdd
      exact ihLhs (emitIR rhs (.add k)) stack out hRight
  | ifTrue cond thenBranch elseBranch value hCond hThen ihCond ihThen =>
      have hThenExec : Exec (emitIR thenBranch k) stack out :=
        ihThen k stack out hExecK
      have hBranch : Exec (.branch (emitIR thenBranch k) (emitIR elseBranch k))
          (.bool true :: stack) out :=
        Exec.branchTrue (emitIR thenBranch k) (emitIR elseBranch k) stack out hThenExec
      exact ihCond (.branch (emitIR thenBranch k) (emitIR elseBranch k)) stack out hBranch
  | ifFalse cond thenBranch elseBranch value hCond hElse ihCond ihElse =>
      have hElseExec : Exec (emitIR elseBranch k) stack out :=
        ihElse k stack out hExecK
      have hBranch : Exec (.branch (emitIR thenBranch k) (emitIR elseBranch k))
          (.bool false :: stack) out :=
        Exec.branchFalse (emitIR thenBranch k) (emitIR elseBranch k) stack out hElseExec
      exact ihCond (.branch (emitIR thenBranch k) (emitIR elseBranch k)) stack out hBranch

theorem emit_correct
    (ir : IRExpr)
    (value : RuntimeVal)
    (hEval : IREval ir value) :
    Exec (emitClosed ir) [] [value] := by
  exact emit_correct_aux ir value .halt [] [value] hEval (Exec.halt [value])

theorem sourceEval_to_irEval
    {ir : IRExpr}
    {value : RuntimeVal}
    (hEval : Eval ir.toExpr value) :
    IREval ir value := by
  induction ir generalizing value with
  | const runtime =>
      cases runtime <;> cases hEval <;> simpa [IRExpr.toExpr] using IREval.const _
  | add lhs rhs ihL ihR =>
      cases hEval with
      | add lhsExpr rhsExpr lhsVal rhsVal hL hR =>
          simpa [IRExpr.toExpr] using IREval.add lhs rhs lhsVal rhsVal (ihL hL) (ihR hR)
  | ite cond thenBranch elseBranch ihCond ihThen ihElse =>
      cases hEval with
      | ifTrue condExpr thenExpr elseExpr value hCond hThen =>
          simpa [IRExpr.toExpr] using
            IREval.ifTrue cond thenBranch elseBranch value (ihCond hCond) (ihThen hThen)
      | ifFalse condExpr thenExpr elseExpr value hCond hElse =>
          simpa [IRExpr.toExpr] using
            IREval.ifFalse cond thenBranch elseBranch value (ihCond hCond) (ihElse hElse)

theorem emit_stage_preserves :
    Weft.SemanticsPreserving irSem machineSem emitStage := by
  intro ir artifact input behavior hCompile hIr
  simp [emitStage, emitClosed] at hCompile
  subst artifact
  rcases hIr with ⟨value, hEval, hBehavior⟩
  exact ⟨value, emit_correct ir value hEval, hBehavior⟩

theorem lower_stage_reflects :
    Weft.SemanticsReflecting checkedSem irSem lowerStage := by
  intro checked artifact input behavior hCompile hIr
  simp [lowerStage] at hCompile
  subst artifact
  rcases hIr with ⟨value, hEval, hBehavior⟩
  exact ⟨value, by
    simpa [lower_toExpr] using (irEval_to_source hEval : Eval (lower checked.expr).toExpr value), hBehavior⟩

theorem emit_stage_reflects :
    Weft.SemanticsReflecting irSem machineSem emitStage := by
  intro ir artifact input behavior hCompile hMachine
  simp [emitStage, emitClosed] at hCompile
  subst artifact
  rcases hMachine with ⟨value, hExec, hBehavior⟩
  have hExecCompile : Exec (compileClosed ir.toExpr) [] [value] := by
    simpa [compileClosed] using
      (show Exec (compile ir.toExpr .halt) [] [value] from by
        simpa [emitIR_eq_compile_toExpr] using hExec)
  have hSource : Eval ir.toExpr value :=
    compile_complete ir.toExpr value hExecCompile
  exact ⟨value, sourceEval_to_irEval hSource, hBehavior⟩

theorem staged_whole_compiler_theorem :
    Weft.SemanticsPreserving surfaceSem machineSem (Weft.CompilerPipeline.compile stagedCompilerPipeline) := by
  simpa using
    (Weft.whole_compiler_theorem
      stagedCompilerPipeline
      surfaceSem
      sourceSem
      checkedSem
      irSem
      machineSem
      parse_stage_preserves
      typecheck_stage_preserves
      lower_stage_preserves
      emit_stage_preserves)

theorem staged_whole_compiler_reflection_theorem :
    Weft.SemanticsReflecting surfaceSem machineSem (Weft.CompilerPipeline.compile stagedCompilerPipeline) := by
  simpa using
    (Weft.whole_compiler_reflection_theorem
      stagedCompilerPipeline
      surfaceSem
      sourceSem
      checkedSem
      irSem
      machineSem
      parse_stage_reflects
      typecheck_stage_reflects
      lower_stage_reflects
      emit_stage_reflects)

theorem staged_compile_complete
    {surface : SurfaceExpr}
    {code : Code}
    {value : RuntimeVal}
    (hCompile : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile surface = .ok code)
    (hExec : Exec code [] [value]) :
    Eval (parseSurface surface) value := by
  have hCode : code = emitClosed (lower (parseSurface surface)) := by
    unfold Weft.CompilerPipeline.compile Weft.Stage.comp stagedCompilerPipeline at hCompile
    cases hCheck : check (parseSurface surface) with
    | none =>
        simp [parseStage, typecheckStage, lowerStage, emitStage, hCheck] at hCompile
    | some checked =>
        simp [parseStage, typecheckStage, lowerStage, emitStage, hCheck] at hCompile
        exact hCompile.symm
  subst code
  have hExecCompile : Exec (compileClosed (parseSurface surface)) [] [value] := by
    simpa [compileClosed, lower_toExpr] using
      (show Exec (compile (lower (parseSurface surface)).toExpr .halt) [] [value] from by
        simpa [emitClosed, emitIR_eq_compile_toExpr] using hExec)
  exact compile_complete (parseSurface surface) value hExecCompile

theorem staged_semantics_iff
    {surface : SurfaceExpr}
    {code : Code}
    {input : Weft.Input}
    {behavior : Weft.Behavior}
    (hCompile : (Weft.CompilerPipeline.compile stagedCompilerPipeline).compile surface = .ok code) :
    surfaceSem surface input behavior ↔ machineSem code input behavior := by
  exact Weft.whole_compiler_semantics_iff
    stagedCompilerPipeline
    surfaceSem
    sourceSem
    checkedSem
    irSem
    machineSem
    parse_stage_preserves
    typecheck_stage_preserves
    lower_stage_preserves
    emit_stage_preserves
    parse_stage_reflects
    typecheck_stage_reflects
    lower_stage_reflects
    emit_stage_reflects
    hCompile

end Weft.SafetyCore
