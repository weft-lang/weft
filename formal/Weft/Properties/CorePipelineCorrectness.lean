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

theorem emit_stage_preserves :
    Weft.SemanticsPreserving irSem machineSem emitStage := by
  intro ir artifact input behavior hCompile hIr
  simp [emitStage, emitClosed] at hCompile
  subst artifact
  rcases hIr with ⟨value, hEval, hBehavior⟩
  exact ⟨value, emit_correct ir value hEval, hBehavior⟩

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

end Weft.SafetyCore
