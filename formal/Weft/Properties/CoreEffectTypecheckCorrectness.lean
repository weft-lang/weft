import Weft.CoreEffectPipeline

namespace Weft.CoreEffects

open Weft.SafetyCore

theorem typed_ty_cases
    {expr : Expr}
    {ty : Weft.Ty}
    {effects : Weft.EffectSet}
    (hTy : HasType expr ty effects) :
    ty = Weft.Ty.bool ∨ ty = Weft.Ty.int ∨ ty = Weft.Ty.nil := by
  induction hTy with
  | bool _ =>
      exact Or.inl rfl
  | int _ =>
      exact Or.inr (Or.inl rfl)
  | nil =>
      exact Or.inr (Or.inr rfl)
  | add _ _ _ _ _ _ =>
      exact Or.inr (Or.inl rfl)
  | ifThenElse _ _ _ _ _ _ _ _ _ _ _ ihThen _ =>
      exact ihThen
  | performBool _ =>
      exact Or.inl rfl
  | handleBool _ _ _ _ _ _ ihBody =>
      exact ihBody

theorem check_sound
    {expr : Expr}
    {checked : CheckedTy expr}
    (_hCheck : check expr = some checked) :
    HasType expr checked.ty checked.effects := by
  exact checked.typed

theorem inferType_sound
    {expr : Expr}
    {ty : Weft.Ty}
    (hInfer : inferType expr = some ty) :
    ∃ effects : Weft.EffectSet, HasType expr ty effects := by
  unfold inferType at hInfer
  cases hCheck : check expr with
  | none =>
      simp [hCheck] at hInfer
  | some checked =>
      simp [hCheck] at hInfer
      cases hInfer
      exact ⟨checked.effects, checked.typed⟩

theorem inferEffects_sound
    {expr : Expr}
    {effects : Weft.EffectSet}
    (hInfer : inferEffects expr = some effects) :
    ∃ ty : Weft.Ty, HasType expr ty effects := by
  unfold inferEffects at hInfer
  cases hCheck : check expr with
  | none =>
      simp [hCheck] at hInfer
  | some checked =>
      simp [hCheck] at hInfer
      cases hInfer
      exact ⟨checked.ty, checked.typed⟩

theorem check_complete
    {expr : Expr}
    {ty : Weft.Ty}
    {effects : Weft.EffectSet}
    (hTy : HasType expr ty effects) :
    ∃ checked : CheckedTy expr,
      check expr = some checked ∧ checked.ty = ty ∧ checked.effects = effects := by
  induction hTy with
  | bool b =>
      refine ⟨{
        ty := Weft.Ty.bool
        effects := Weft.EffectSet.empty
        typed := HasType.bool b
      }, ?_, rfl, rfl⟩
      simp [check]
  | int n =>
      refine ⟨{
        ty := Weft.Ty.int
        effects := Weft.EffectSet.empty
        typed := HasType.int n
      }, ?_, rfl, rfl⟩
      simp [check]
  | nil =>
      refine ⟨{
        ty := Weft.Ty.nil
        effects := Weft.EffectSet.empty
        typed := HasType.nil
      }, ?_, rfl, rfl⟩
      simp [check]
  | add lhs rhs eL eR hL hR ihL ihR =>
      rcases ihL with ⟨checkedL, hCheckL, hTyL, hEffL⟩
      rcases ihR with ⟨checkedR, hCheckR, hTyR, hEffR⟩
      cases checkedL with
      | mk tyL effectsL typedL =>
          cases checkedR with
          | mk tyR effectsR typedR =>
              cases hTyL
              cases hEffL
              cases hTyR
              cases hEffR
              refine ⟨{
                ty := Weft.Ty.int
                effects := Weft.EffectSet.union effectsL effectsR
                typed := HasType.add lhs rhs effectsL effectsR typedL typedR
              }, ?_, rfl, rfl⟩
              simp [check, hCheckL, hCheckR]
  | ifThenElse cond thenBranch elseBranch ty eCond eThen eElse hCond hThen hElse ihCond ihThen ihElse =>
      rcases ihCond with ⟨checkedCond, hCheckCond, hTyCond, hEffCond⟩
      rcases ihThen with ⟨checkedThen, hCheckThen, hTyThen, hEffThen⟩
      rcases ihElse with ⟨checkedElse, hCheckElse, hTyElse, hEffElse⟩
      cases checkedCond with
      | mk tyCond effectsCond typedCond =>
          cases checkedThen with
          | mk tyThen effectsThen typedThen =>
              cases checkedElse with
              | mk tyElse effectsElse typedElse =>
                  rcases typed_ty_cases hThen with hBool | hInt | hNil
                  · cases hBool
                    cases hTyCond
                    cases hEffCond
                    cases hTyThen
                    cases hEffThen
                    cases hTyElse
                    cases hEffElse
                    refine ⟨{
                      ty := Weft.Ty.bool
                      effects := Weft.EffectSet.union effectsCond (Weft.EffectSet.union effectsThen effectsElse)
                      typed := HasType.ifThenElse cond thenBranch elseBranch Weft.Ty.bool
                        effectsCond effectsThen effectsElse typedCond typedThen typedElse
                    }, ?_, rfl, rfl⟩
                    simp [check, hCheckCond, hCheckThen, hCheckElse]
                  · cases hInt
                    cases hTyCond
                    cases hEffCond
                    cases hTyThen
                    cases hEffThen
                    cases hTyElse
                    cases hEffElse
                    refine ⟨{
                      ty := Weft.Ty.int
                      effects := Weft.EffectSet.union effectsCond (Weft.EffectSet.union effectsThen effectsElse)
                      typed := HasType.ifThenElse cond thenBranch elseBranch Weft.Ty.int
                        effectsCond effectsThen effectsElse typedCond typedThen typedElse
                    }, ?_, rfl, rfl⟩
                    simp [check, hCheckCond, hCheckThen, hCheckElse]
                  · cases hNil
                    cases hTyCond
                    cases hEffCond
                    cases hTyThen
                    cases hEffThen
                    cases hTyElse
                    cases hEffElse
                    refine ⟨{
                      ty := Weft.Ty.nil
                      effects := Weft.EffectSet.union effectsCond (Weft.EffectSet.union effectsThen effectsElse)
                      typed := HasType.ifThenElse cond thenBranch elseBranch Weft.Ty.nil
                        effectsCond effectsThen effectsElse typedCond typedThen typedElse
                    }, ?_, rfl, rfl⟩
                    simp [check, hCheckCond, hCheckThen, hCheckElse]
  | performBool effect =>
      refine ⟨{
        ty := Weft.Ty.bool
        effects := Weft.EffectSet.singleton effect
        typed := HasType.performBool effect
      }, ?_, rfl, rfl⟩
      simp [check]
  | handleBool effect value body ty bodyEffects hBody ihBody =>
      rcases ihBody with ⟨checkedBody, hCheckBody, hTyBody, hEffBody⟩
      cases checkedBody with
      | mk tyBody effectsBody typedBody =>
          cases hTyBody
          cases hEffBody
          refine ⟨{
            ty := tyBody
            effects := Weft.EffectSet.handle effectsBody (Weft.EffectSet.singleton effect)
            typed := HasType.handleBool effect value body tyBody effectsBody typedBody
          }, ?_, rfl, rfl⟩
          simp [check, hCheckBody]

theorem inferType_complete
    {expr : Expr}
    {ty : Weft.Ty}
    {effects : Weft.EffectSet}
    (hTy : HasType expr ty effects) :
    inferType expr = some ty := by
  rcases check_complete hTy with ⟨checked, hCheck, hTyEq, _⟩
  simp [inferType, hCheck, hTyEq]

theorem inferEffects_complete
    {expr : Expr}
    {ty : Weft.Ty}
    {effects : Weft.EffectSet}
    (hTy : HasType expr ty effects) :
    inferEffects expr = some effects := by
  rcases check_complete hTy with ⟨checked, hCheck, _, hEffEq⟩
  simp [inferEffects, hCheck, hEffEq]

theorem inferType_iff_hasType
    {expr : Expr}
    {ty : Weft.Ty} :
    inferType expr = some ty ↔ ∃ effects : Weft.EffectSet, HasType expr ty effects := by
  constructor
  · exact inferType_sound
  · intro hTy
    rcases hTy with ⟨effects, hTy⟩
    exact inferType_complete hTy

theorem inferEffects_iff_hasType
    {expr : Expr}
    {effects : Weft.EffectSet} :
    inferEffects expr = some effects ↔ ∃ ty : Weft.Ty, HasType expr ty effects := by
  constructor
  · exact inferEffects_sound
  · intro hTy
    rcases hTy with ⟨ty, hTy⟩
    exact inferEffects_complete hTy

end Weft.CoreEffects
