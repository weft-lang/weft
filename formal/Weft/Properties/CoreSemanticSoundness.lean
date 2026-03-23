import Weft.Properties.CoreCompilerCorrectness

namespace Weft.SafetyCore

inductive RuntimeValHasType : RuntimeVal -> Weft.Ty -> Prop where
  | bool (b : Bool) : RuntimeValHasType (.bool b) Weft.Ty.bool
  | int (n : Int) : RuntimeValHasType (.int n) Weft.Ty.int
  | nil : RuntimeValHasType .nil Weft.Ty.nil

theorem eval_preserves_type
    {expr : Expr}
    {ty : Weft.Ty}
    {value : RuntimeVal}
    (hTy : HasType expr ty)
    (hEval : Eval expr value) :
    RuntimeValHasType value ty := by
  induction hEval generalizing ty with
  | bool b =>
      cases hTy with
      | bool _ =>
          exact RuntimeValHasType.bool b
  | int n =>
      cases hTy with
      | int _ =>
          exact RuntimeValHasType.int n
  | nil =>
      cases hTy with
      | nil =>
          exact RuntimeValHasType.nil
  | add lhs rhs lhsVal rhsVal hL hR ihL ihR =>
      cases hTy with
      | add _ _ _ _ =>
          exact RuntimeValHasType.int (lhsVal + rhsVal)
  | ifTrue cond thenBranch elseBranch value hCond hThen ihCond ihThen =>
      cases hTy with
      | ifThenElse _ _ _ _ _ hThenTy _ =>
          exact ihThen hThenTy
  | ifFalse cond thenBranch elseBranch value hCond hElse ihCond ihElse =>
      cases hTy with
      | ifThenElse _ _ _ _ _ _ hElseTy =>
          exact ihElse hElseTy

theorem compiled_result_preserves_type
    {expr : Expr}
    {ty : Weft.Ty}
    {value : RuntimeVal}
    (hTy : HasType expr ty)
    (hEval : Eval expr value) :
    Exec (compileClosed expr) [] [value] ∧ RuntimeValHasType value ty := by
  exact ⟨compile_correct expr value hEval, eval_preserves_type hTy hEval⟩

end Weft.SafetyCore
