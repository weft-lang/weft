import Weft.CoreMachine
import Weft.Properties.CompilerCorrectness

namespace Weft.SafetyCore

theorem compile_correct_aux
    (expr : Expr)
    (value : RuntimeVal)
    (k : Code)
    (stack out : List RuntimeVal)
    (hEval : Eval expr value)
    (hExecK : Exec k (value :: stack) out) :
    Exec (compile expr k) stack out := by
  induction hEval generalizing k stack out with
  | bool b =>
      simpa [compile] using Exec.pushBool b k stack out hExecK
  | int n =>
      simpa [compile] using Exec.pushInt n k stack out hExecK
  | nil =>
      simpa [compile] using Exec.pushNil k stack out hExecK
  | add lhs rhs lhsVal rhsVal hL hR ihL ihR =>
      have hAdd : Exec (.add k) (.int rhsVal :: .int lhsVal :: stack) out :=
        Exec.add k stack out lhsVal rhsVal hExecK
      have hRight : Exec (compile rhs (.add k)) (.int lhsVal :: stack) out :=
        ihR (.add k) (.int lhsVal :: stack) out hAdd
      exact ihL (compile rhs (.add k)) stack out hRight
  | ifTrue cond thenBranch elseBranch value hCond hThen ihCond ihThen =>
      have hThenExec : Exec (compile thenBranch k) stack out :=
        ihThen k stack out hExecK
      have hBranch : Exec (.branch (compile thenBranch k) (compile elseBranch k))
          (.bool true :: stack) out :=
        Exec.branchTrue (compile thenBranch k) (compile elseBranch k) stack out hThenExec
      exact ihCond (.branch (compile thenBranch k) (compile elseBranch k)) stack out hBranch
  | ifFalse cond thenBranch elseBranch value hCond hElse ihCond ihElse =>
      have hElseExec : Exec (compile elseBranch k) stack out :=
        ihElse k stack out hExecK
      have hBranch : Exec (.branch (compile thenBranch k) (compile elseBranch k))
          (.bool false :: stack) out :=
        Exec.branchFalse (compile thenBranch k) (compile elseBranch k) stack out hElseExec
      exact ihCond (.branch (compile thenBranch k) (compile elseBranch k)) stack out hBranch

theorem compile_correct
    (expr : Expr)
    (value : RuntimeVal)
    (hEval : Eval expr value) :
    Exec (compileClosed expr) [] [value] := by
  exact compile_correct_aux expr value .halt [] [value] hEval (Exec.halt [value])

def sourceSem (expr : Expr) (_input : Weft.Input) (behavior : Weft.Behavior) : Prop :=
  ∃ value, Eval expr value ∧ behavior = { trace := [], exitCode := exitCode value }

def machineSem (code : Code) (_input : Weft.Input) (behavior : Weft.Behavior) : Prop :=
  ∃ value, Exec code [] [value] ∧ behavior = { trace := [], exitCode := exitCode value }

def compileStage : Weft.Stage Expr Code where
  compile expr := .ok (compileClosed expr)

def idStage {α : Type} : Weft.Stage α α where
  compile artifact := .ok artifact

theorem id_stage_preserves
    {α : Type}
    (sem : Weft.Semantics α) :
    Weft.SemanticsPreserving sem sem idStage := by
  intro source artifact input behavior hCompile hSem
  simp [idStage] at hCompile
  subst artifact
  exact hSem

theorem compile_stage_preserves :
    Weft.SemanticsPreserving sourceSem machineSem compileStage := by
  intro expr artifact input behavior hCompile hSource
  rcases hSource with ⟨value, hEval, hBehavior⟩
  simp [compileStage, compileClosed] at hCompile
  subst artifact
  refine ⟨value, compile_correct expr value hEval, ?_⟩
  exact hBehavior

def compilerPipeline : Weft.CompilerPipeline where
  Source := Expr
  Parsed := Expr
  Typed := Expr
  IR := Expr
  Native := Code
  parse := idStage
  typecheck := idStage
  lower := idStage
  emit := compileStage

theorem safety_core_whole_compiler_theorem :
    Weft.SemanticsPreserving sourceSem machineSem (Weft.CompilerPipeline.compile compilerPipeline) := by
  simpa using
    (Weft.whole_compiler_theorem
      compilerPipeline
      sourceSem
      sourceSem
      sourceSem
      sourceSem
      machineSem
      (id_stage_preserves sourceSem)
      (id_stage_preserves sourceSem)
      (id_stage_preserves sourceSem)
      compile_stage_preserves)

end Weft.SafetyCore
