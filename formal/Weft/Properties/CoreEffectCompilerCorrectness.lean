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

theorem compile_complete_aux
    (oracle : Oracle)
    (expr : Expr)
    (k : Code)
    (stack out : List RuntimeVal)
    (trace : List Weft.EffectName)
    (hExec : Exec oracle (compile expr k) stack out trace) :
    ∃ value traceExpr traceK,
      Eval oracle expr value traceExpr ∧
      Exec oracle k (value :: stack) out traceK ∧
      trace = traceExpr ++ traceK := by
  induction expr generalizing oracle k stack out trace with
  | bool b =>
      cases hExec with
      | pushBool =>
          rename_i hExecK
          exact ⟨.bool b, [], trace, Eval.bool oracle b, hExecK, by simp⟩
  | int n =>
      cases hExec with
      | pushInt =>
          rename_i hExecK
          exact ⟨.int n, [], trace, Eval.int oracle n, hExecK, by simp⟩
  | nil =>
      cases hExec with
      | pushNil =>
          rename_i hExecK
          exact ⟨.nil, [], trace, Eval.nil oracle, hExecK, by simp⟩
  | add lhs rhs ihL ihR =>
      rcases ihL oracle (compile rhs (.add k)) stack out trace hExec with
        ⟨lhsVal, traceL, traceRest, hEvalL, hExecRest, hTrace⟩
      rcases ihR oracle (.add k) (lhsVal :: stack) out traceRest hExecRest with
        ⟨rhsVal, traceR, traceK, hEvalR, hExecAdd, hTraceRest⟩
      cases hExecAdd with
      | add =>
          rename_i lhsInt rhsInt hExecK
          exact ⟨.int (lhsInt + rhsInt), traceL ++ traceR, traceK,
            Eval.add oracle lhs rhs lhsInt rhsInt traceL traceR hEvalL hEvalR,
            hExecK,
            by simp [hTrace, hTraceRest, List.append_assoc]⟩
  | ifThenElse cond thenBranch elseBranch ihCond ihThen ihElse =>
      rcases ihCond oracle (.branch (compile thenBranch k) (compile elseBranch k)) stack out trace hExec with
        ⟨condVal, traceCond, traceBranch, hEvalCond, hExecBranch, hTrace⟩
      cases hExecBranch with
      | branchTrue =>
          rename_i hExecThen
          rcases ihThen oracle k stack out traceBranch hExecThen with
            ⟨value, traceThenEval, traceK, hEvalThen, hExecK, hTraceThen⟩
          exact ⟨value, traceCond ++ traceThenEval, traceK,
            Eval.ifTrue oracle cond thenBranch elseBranch value traceCond traceThenEval hEvalCond hEvalThen,
            hExecK,
            by simp [hTrace, hTraceThen, List.append_assoc]⟩
      | branchFalse =>
          rename_i hExecElse
          rcases ihElse oracle k stack out traceBranch hExecElse with
            ⟨value, traceElseEval, traceK, hEvalElse, hExecK, hTraceElse⟩
          exact ⟨value, traceCond ++ traceElseEval, traceK,
            Eval.ifFalse oracle cond thenBranch elseBranch value traceCond traceElseEval hEvalCond hEvalElse,
            hExecK,
            by simp [hTrace, hTraceElse, List.append_assoc]⟩
  | performBool effect =>
      cases hExec with
      | performBool =>
          rename_i traceK hExecK
          exact ⟨.bool (oracle effect), [effect], traceK,
            Eval.performBool oracle effect,
            hExecK,
            by simp⟩
  | handleBool effect value body ihBody =>
      cases hExec with
      | handleBool =>
          rename_i mid traceBody traceK hExecBody hExecK
          rcases ihBody (fun effect' => if effect' = effect then value else oracle effect')
              .halt stack mid traceBody hExecBody with
            ⟨result, traceEval, traceHalt, hEvalBody, hExecHalt, hTraceBody⟩
          cases hExecHalt with
          | halt _ _ =>
              exact ⟨result, traceEval.filter (fun effect' => effect' != effect), traceK,
                Eval.handleBool oracle effect value body result traceEval hEvalBody,
                hExecK,
                by simp [hTraceBody]⟩

theorem compile_complete
    (oracle : Oracle)
    (expr : Expr)
    (value : RuntimeVal)
    (trace : List Weft.EffectName)
    (hExec : Exec oracle (compileClosed expr) [] [value] trace) :
    Eval oracle expr value trace := by
  rcases compile_complete_aux oracle expr .halt [] [value] trace hExec with
    ⟨value', traceExpr, traceHalt, hEval, hExecHalt, hTrace⟩
  cases hExecHalt with
  | halt _ _ =>
      simpa [hTrace] using hEval

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
