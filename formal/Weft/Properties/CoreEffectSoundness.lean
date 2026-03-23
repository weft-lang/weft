import Weft.CoreEffects

namespace Weft.CoreEffects

open Weft.SafetyCore

theorem mem_remove_of_mem_of_ne
    {effects : Weft.EffectSet}
    {effect removed : Weft.EffectName}
    (hMem : effect ∈ effects.elems)
    (hNe : effect ≠ removed) :
    effect ∈ (Weft.EffectSet.remove effects removed).elems := by
  simpa [Weft.EffectSet.remove, hNe] using hMem

theorem trace_subset_of_typed_effects
    {oracle : Oracle}
    {expr : Expr}
    {value : RuntimeVal}
    {trace : List Weft.EffectName}
    {ty : Weft.Ty}
    {effects : Weft.EffectSet}
    (hTy : HasType expr ty effects)
    (hEval : Eval oracle expr value trace)
    (effect : Weft.EffectName)
    (hMem : effect ∈ trace) :
    effect ∈ effects.elems := by
  induction hEval generalizing ty effects effect with
  | bool oracle b =>
      cases hTy
      cases hMem
  | int oracle n =>
      cases hTy
      cases hMem
  | nil oracle =>
      cases hTy
      cases hMem
  | add oracle lhs rhs lhsVal rhsVal traceL traceR hEvalL hEvalR ihL ihR =>
      cases hTy with
      | add _ _ eL eR hL hR =>
          rcases List.mem_append.mp hMem with hMemL | hMemR
          · exact List.mem_append.mpr (Or.inl (ihL hL effect hMemL))
          · exact List.mem_append.mpr (Or.inr (ihR hR effect hMemR))
  | ifTrue oracle cond thenBranch elseBranch value traceCond traceThen hEvalCond hEvalThen ihCond ihThen =>
      cases hTy with
      | ifThenElse _ _ _ ty eCond eThen eElse hTyCond hTyThen hTyElse =>
          rcases List.mem_append.mp hMem with hMemCond | hMemThen
          · exact List.mem_append.mpr (Or.inl (ihCond hTyCond effect hMemCond))
          · exact List.mem_append.mpr (Or.inr (List.mem_append.mpr (Or.inl (ihThen hTyThen effect hMemThen))))
  | ifFalse oracle cond thenBranch elseBranch value traceCond traceElse hEvalCond hEvalElse ihCond ihElse =>
      cases hTy with
      | ifThenElse _ _ _ ty eCond eThen eElse hTyCond hTyThen hTyElse =>
          rcases List.mem_append.mp hMem with hMemCond | hMemElse
          · exact List.mem_append.mpr (Or.inl (ihCond hTyCond effect hMemCond))
          · exact List.mem_append.mpr (Or.inr (List.mem_append.mpr (Or.inr (ihElse hTyElse effect hMemElse))))
  | performBool oracle declaredEffect =>
      cases hTy with
      | performBool _ =>
          simp [Weft.EffectSet.singleton] at hMem ⊢
          exact hMem
  | handleBool oracle handled handledValue body result traceInner hEvalBody ihBody =>
      cases hTy with
      | handleBool _ _ _ ty bodyEffects hTyBody =>
          have hFiltered : effect ∈ traceInner.filter (fun effect' => effect' != handled) := hMem
          have hParts : effect ∈ traceInner ∧ effect != handled := by
            simpa using List.mem_filter.mp hFiltered
          have hBodyMem : effect ∈ bodyEffects.elems :=
            ihBody hTyBody effect hParts.1
          have hRemoved : effect ∈ (Weft.EffectSet.remove bodyEffects handled).elems :=
            mem_remove_of_mem_of_ne hBodyMem (by
              intro hEq
              simp [hEq] at hParts)
          simpa [Weft.EffectSet.handle, Weft.EffectSet.singleton, Weft.EffectSet.removeAll] using hRemoved

theorem handled_effect_confined
    {oracle : Oracle}
    {effect : Weft.EffectName}
    {value : Bool}
    {body : Expr}
    {result : RuntimeVal}
    {trace : List Weft.EffectName}
    (hEval : Eval oracle (.handleBool effect value body) result trace) :
    effect ∉ trace := by
  cases hEval with
  | handleBool _ handled _ _ _ traceInner hEvalBody =>
      intro hMem
      have hFiltered : effect ∈ traceInner.filter (fun effect' => effect' != effect) := hMem
      have hImpossible : False := by
        simpa using (List.mem_filter.mp hFiltered).2
      exact hImpossible.elim

theorem empty_effects_have_empty_trace
    {oracle : Oracle}
    {expr : Expr}
    {value : RuntimeVal}
    {trace : List Weft.EffectName}
    {ty : Weft.Ty}
    (hTy : HasType expr ty Weft.EffectSet.empty)
    (hEval : Eval oracle expr value trace) :
    ∀ effect : Weft.EffectName, effect ∉ trace := by
  intro effect hMem
  have hSubset : effect ∈ Weft.EffectSet.empty.elems :=
    trace_subset_of_typed_effects hTy hEval effect hMem
  simp [Weft.EffectSet.empty] at hSubset

theorem fully_handled_perform_is_pure
    {oracle : Oracle}
    {effect : Weft.EffectName}
    {value : Bool}
    {result : RuntimeVal}
    {trace : List Weft.EffectName}
    (hTy : HasType (.handleBool effect value (.performBool effect)) Weft.Ty.bool Weft.EffectSet.empty)
    (hEval : Eval oracle (.handleBool effect value (.performBool effect)) result trace) :
    ∀ escaped : Weft.EffectName, escaped ∉ trace := by
  exact empty_effects_have_empty_trace hTy hEval

end Weft.CoreEffects
