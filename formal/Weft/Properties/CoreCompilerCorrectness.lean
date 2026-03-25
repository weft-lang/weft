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

theorem compile_complete_aux
    (expr : Expr)
    (k : Code)
    (stack out : List RuntimeVal)
    (hExec : Exec (compile expr k) stack out) :
    ∃ value,
      Eval expr value ∧
      Exec k (value :: stack) out := by
  induction expr generalizing k stack out with
  | bool b =>
      cases hExec with
      | pushBool =>
          rename_i hExecK
          exact ⟨.bool b, Eval.bool b, hExecK⟩
  | int n =>
      cases hExec with
      | pushInt =>
          rename_i hExecK
          exact ⟨.int n, Eval.int n, hExecK⟩
  | nil =>
      cases hExec with
      | pushNil =>
          rename_i hExecK
          exact ⟨.nil, Eval.nil, hExecK⟩
  | add lhs rhs ihL ihR =>
      rcases ihL (compile rhs (.add k)) stack out hExec with ⟨lhsVal, hEvalL, hExecRest⟩
      rcases ihR (.add k) (lhsVal :: stack) out hExecRest with ⟨rhsVal, hEvalR, hExecAdd⟩
      cases hExecAdd with
      | add =>
          rename_i lhsInt rhsInt hExecK
          exact ⟨.int (lhsInt + rhsInt), Eval.add lhs rhs lhsInt rhsInt hEvalL hEvalR, hExecK⟩
  | ifThenElse cond thenBranch elseBranch ihCond ihThen ihElse =>
      rcases ihCond (.branch (compile thenBranch k) (compile elseBranch k)) stack out hExec with
        ⟨condVal, hEvalCond, hExecBranch⟩
      cases hExecBranch with
      | branchTrue =>
          rename_i hExecThen
          rcases ihThen k stack out hExecThen with ⟨value, hEvalThen, hExecK⟩
          exact ⟨value, Eval.ifTrue cond thenBranch elseBranch value hEvalCond hEvalThen, hExecK⟩
      | branchFalse =>
          rename_i hExecElse
          rcases ihElse k stack out hExecElse with ⟨value, hEvalElse, hExecK⟩
          exact ⟨value, Eval.ifFalse cond thenBranch elseBranch value hEvalCond hEvalElse, hExecK⟩

theorem compile_complete
    (expr : Expr)
    (value : RuntimeVal)
    (hExec : Exec (compileClosed expr) [] [value]) :
    Eval expr value := by
  rcases compile_complete_aux expr .halt [] [value] hExec with ⟨value', hEval, hExecHalt⟩
  cases hExecHalt with
  | halt =>
      simpa using hEval

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

theorem id_stage_reflects
    {α : Type}
    (sem : Weft.Semantics α) :
    Weft.SemanticsReflecting sem sem idStage := by
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

theorem compile_stage_reflects :
    Weft.SemanticsReflecting sourceSem machineSem compileStage := by
  intro expr artifact input behavior hCompile hMachine
  simp [compileStage, compileClosed] at hCompile
  subst artifact
  rcases hMachine with ⟨value, hExec, hBehavior⟩
  exact ⟨value, compile_complete expr value hExec, hBehavior⟩

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

theorem safety_core_whole_compiler_reflection_theorem :
    Weft.SemanticsReflecting sourceSem machineSem (Weft.CompilerPipeline.compile compilerPipeline) := by
  simpa using
    (Weft.whole_compiler_reflection_theorem
      compilerPipeline
      sourceSem
      sourceSem
      sourceSem
      sourceSem
      machineSem
      (id_stage_reflects sourceSem)
      (id_stage_reflects sourceSem)
      (id_stage_reflects sourceSem)
      compile_stage_reflects)

theorem safety_core_compile_semantics_iff
    {expr : Expr}
    {code : Code}
    {input : Weft.Input}
    {behavior : Weft.Behavior}
    (hCompile : (Weft.CompilerPipeline.compile compilerPipeline).compile expr = .ok code) :
    sourceSem expr input behavior ↔ machineSem code input behavior := by
  exact Weft.whole_compiler_semantics_iff
    compilerPipeline
    sourceSem
    sourceSem
    sourceSem
    sourceSem
    machineSem
    (id_stage_preserves sourceSem)
    (id_stage_preserves sourceSem)
    (id_stage_preserves sourceSem)
    compile_stage_preserves
    (id_stage_reflects sourceSem)
    (id_stage_reflects sourceSem)
    (id_stage_reflects sourceSem)
    compile_stage_reflects
    hCompile

end Weft.SafetyCore
