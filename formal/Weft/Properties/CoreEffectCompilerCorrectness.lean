import Weft.CoreEffectMachine
import Weft.Properties.CoreEffectSoundness

namespace Weft.CoreEffects

open Weft.SafetyCore

theorem compile_correct_aux
    (oracle : Oracle)
    (expr : Expr)
    (value : RuntimeVal)
    (trace : List Weft.EffectName)
    (k : Code)
    (stack out : List RuntimeVal)
    (traceK : List Weft.EffectName)
    (hEval : Eval oracle expr value trace)
    (hExecK : Exec oracle k (value :: stack) out traceK) :
    Exec oracle (compile expr k) stack out (trace ++ traceK) := by
  induction hEval generalizing k stack out traceK with
  | bool oracle b =>
      simpa [compile] using Exec.pushBool oracle b k stack out traceK hExecK
  | int oracle n =>
      simpa [compile] using Exec.pushInt oracle n k stack out traceK hExecK
  | nil oracle =>
      simpa [compile] using Exec.pushNil oracle k stack out traceK hExecK
  | add oracle lhs rhs lhsVal rhsVal traceL traceR hEvalL hEvalR ihL ihR =>
      have hAdd : Exec oracle (.add k) (.int rhsVal :: .int lhsVal :: stack) out traceK :=
        Exec.add oracle k stack out traceK lhsVal rhsVal hExecK
      have hRight : Exec oracle (compile rhs (.add k)) (.int lhsVal :: stack) out (traceR ++ traceK) :=
        ihR (.add k) (.int lhsVal :: stack) out traceK hAdd
      have hLeft : Exec oracle (compile lhs (compile rhs (.add k))) stack out (traceL ++ (traceR ++ traceK)) :=
        ihL (compile rhs (.add k)) stack out (traceR ++ traceK) hRight
      simpa [compile, List.append_assoc] using hLeft
  | ifTrue oracle cond thenBranch elseBranch result traceCond traceThen hEvalCond hEvalThen ihCond ihThen =>
      have hThenExec : Exec oracle (compile thenBranch k) stack out (traceThen ++ traceK) :=
        ihThen k stack out traceK hExecK
      have hBranch : Exec oracle (.branch (compile thenBranch k) (compile elseBranch k))
          (.bool true :: stack) out (traceThen ++ traceK) :=
        Exec.branchTrue oracle (compile thenBranch k) (compile elseBranch k) stack out (traceThen ++ traceK) hThenExec
      have hCondExec : Exec oracle (compile cond (.branch (compile thenBranch k) (compile elseBranch k)))
          stack out (traceCond ++ (traceThen ++ traceK)) :=
        ihCond (.branch (compile thenBranch k) (compile elseBranch k)) stack out (traceThen ++ traceK) hBranch
      simpa [compile, List.append_assoc] using hCondExec
  | ifFalse oracle cond thenBranch elseBranch result traceCond traceElse hEvalCond hEvalElse ihCond ihElse =>
      have hElseExec : Exec oracle (compile elseBranch k) stack out (traceElse ++ traceK) :=
        ihElse k stack out traceK hExecK
      have hBranch : Exec oracle (.branch (compile thenBranch k) (compile elseBranch k))
          (.bool false :: stack) out (traceElse ++ traceK) :=
        Exec.branchFalse oracle (compile thenBranch k) (compile elseBranch k) stack out (traceElse ++ traceK) hElseExec
      have hCondExec : Exec oracle (compile cond (.branch (compile thenBranch k) (compile elseBranch k)))
          stack out (traceCond ++ (traceElse ++ traceK)) :=
        ihCond (.branch (compile thenBranch k) (compile elseBranch k)) stack out (traceElse ++ traceK) hBranch
      simpa [compile, List.append_assoc] using hCondExec
  | performBool oracle effect =>
      simpa [compile] using Exec.performBool oracle effect k stack out traceK hExecK
  | handleBool oracle effect value body result traceBody hEvalBody ihBody =>
      have hBodyExec : Exec
          (fun effect' => if effect' = effect then value else oracle effect')
          (compile body .halt)
          stack
          (result :: stack)
          traceBody := by
        simpa [compile] using
          ihBody .halt stack (result :: stack) [] (Exec.halt _ (result :: stack))
      have hHandle : Exec oracle (.handleBool effect value (compile body .halt) k)
          stack out (traceBody.filter (fun effect' => effect' != effect) ++ traceK) :=
        Exec.handleBool oracle effect value (compile body .halt) k stack (result :: stack) out
          traceBody traceK hBodyExec hExecK
      simpa [compile] using hHandle

theorem compile_correct
    (oracle : Oracle)
    (expr : Expr)
    (value : RuntimeVal)
    (trace : List Weft.EffectName)
    (hEval : Eval oracle expr value trace) :
    Exec oracle (compileClosed expr) [] [value] trace := by
  simpa [compileClosed] using
    compile_correct_aux oracle expr value trace .halt [] [value] [] hEval (Exec.halt oracle [value])

theorem compiled_trace_subset_of_typed_effects
    {oracle : Oracle}
    {expr : Expr}
    {ty : Weft.Ty}
    {effects : Weft.EffectSet}
    {value : RuntimeVal}
    {trace : List Weft.EffectName}
    (hTy : HasType expr ty effects)
    (hEval : Eval oracle expr value trace) :
    Exec oracle (compileClosed expr) [] [value] trace ∧
      ∀ effect : Weft.EffectName, effect ∈ trace -> effect ∈ effects.elems := by
  exact ⟨compile_correct oracle expr value trace hEval,
    fun effect hMem => trace_subset_of_typed_effects hTy hEval effect hMem⟩

theorem compiled_empty_effects_have_empty_trace
    {oracle : Oracle}
    {expr : Expr}
    {ty : Weft.Ty}
    {value : RuntimeVal}
    {trace : List Weft.EffectName}
    (hTy : HasType expr ty Weft.EffectSet.empty)
    (hEval : Eval oracle expr value trace) :
    Exec oracle (compileClosed expr) [] [value] trace ∧
      ∀ effect : Weft.EffectName, effect ∉ trace := by
  exact ⟨compile_correct oracle expr value trace hEval,
    empty_effects_have_empty_trace hTy hEval⟩

end Weft.CoreEffects
