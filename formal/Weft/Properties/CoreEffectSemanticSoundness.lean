import Weft.Properties.CoreEffectCompilerCorrectness
import Weft.Properties.CoreSemanticSoundness

namespace Weft.CoreEffects

open Weft.SafetyCore

theorem eval_preserves_type
    {oracle : Oracle}
    {expr : Expr}
    {ty : Weft.Ty}
    {effects : Weft.EffectSet}
    {value : RuntimeVal}
    {trace : List Weft.EffectName}
    (hTy : HasType expr ty effects)
    (hEval : Eval oracle expr value trace) :
    RuntimeValHasType value ty := by
  induction hEval generalizing ty effects with
  | bool oracle b =>
      cases hTy with
      | bool _ =>
          exact RuntimeValHasType.bool b
  | int oracle n =>
      cases hTy with
      | int _ =>
          exact RuntimeValHasType.int n
  | nil oracle =>
      cases hTy with
      | nil =>
          exact RuntimeValHasType.nil
  | add oracle lhs rhs lhsVal rhsVal traceL traceR hEvalL hEvalR ihL ihR =>
      cases hTy with
      | add _ _ _ _ _ _ =>
          exact RuntimeValHasType.int (lhsVal + rhsVal)
  | ifTrue oracle cond thenBranch elseBranch value traceCond traceThen hEvalCond hEvalThen ihCond ihThen =>
      cases hTy with
      | ifThenElse _ _ _ _ _ _ _ _ hThenTy _ =>
          exact ihThen hThenTy
  | ifFalse oracle cond thenBranch elseBranch value traceCond traceElse hEvalCond hEvalElse ihCond ihElse =>
      cases hTy with
      | ifThenElse _ _ _ _ _ _ _ _ _ hElseTy =>
          exact ihElse hElseTy
  | performBool oracle effect =>
      cases hTy with
      | performBool _ =>
          exact RuntimeValHasType.bool (oracle effect)
  | handleBool oracle effect handledValue body result traceInner hEvalBody ihBody =>
      cases hTy with
      | handleBool _ _ _ _ _ hBody =>
          exact ihBody hBody

theorem compiled_result_preserves_type_and_trace
    {oracle : Oracle}
    {expr : Expr}
    {ty : Weft.Ty}
    {effects : Weft.EffectSet}
    {value : RuntimeVal}
    {trace : List Weft.EffectName}
    (hTy : HasType expr ty effects)
    (hEval : Eval oracle expr value trace) :
    Exec oracle (compileClosed expr) [] [value] trace ∧ RuntimeValHasType value ty := by
  exact ⟨compile_correct oracle expr value trace hEval, eval_preserves_type hTy hEval⟩

end Weft.CoreEffects
