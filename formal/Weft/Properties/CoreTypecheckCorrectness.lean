import Weft.CorePipeline

namespace Weft.SafetyCore

theorem typed_ty_cases
    {expr : Expr}
    {ty : Weft.Ty}
    (hTy : HasType expr ty) :
    ty = Weft.Ty.bool ∨ ty = Weft.Ty.int ∨ ty = Weft.Ty.nil := by
  induction hTy with
  | bool _ =>
      exact Or.inl rfl
  | int _ =>
      exact Or.inr (Or.inl rfl)
  | nil =>
      exact Or.inr (Or.inr rfl)
  | add _ _ _ _ =>
      exact Or.inr (Or.inl rfl)
  | ifThenElse _ _ _ _ _ _ _ _ ihThen _ =>
      exact ihThen

theorem type_uniqueness
    {expr : Expr}
    {ty₁ ty₂ : Weft.Ty}
    (hTy₁ : HasType expr ty₁)
    (hTy₂ : HasType expr ty₂) :
    ty₁ = ty₂ := by
  induction hTy₁ generalizing ty₂ with
  | bool b =>
      cases hTy₂ <;> rfl
  | int n =>
      cases hTy₂ <;> rfl
  | nil =>
      cases hTy₂ <;> rfl
  | add lhs rhs hL hR ihL ihR =>
      cases hTy₂
      rfl
  | ifThenElse cond thenBranch elseBranch ty hCond hThen hElse ihCond ihThen ihElse =>
      cases hTy₂ with
      | ifThenElse _ _ _ ty' _ hThen' _ =>
          exact ihThen hThen'

theorem check_sound
    {expr : Expr}
    {checked : CheckedTy expr}
    (_hCheck : check expr = some checked) :
    HasType expr checked.ty := by
  exact checked.typed

theorem inferType_sound
    {expr : Expr}
    {ty : Weft.Ty}
    (hInfer : inferType expr = some ty) :
    HasType expr ty := by
  unfold inferType at hInfer
  cases hCheck : check expr with
  | none =>
      simp [hCheck] at hInfer
  | some checked =>
      simp [hCheck] at hInfer
      cases hInfer
      exact checked.typed

theorem check_complete
    {expr : Expr}
    {ty : Weft.Ty}
    (hTy : HasType expr ty) :
    ∃ checked : CheckedTy expr, check expr = some checked ∧ checked.ty = ty := by
  induction hTy with
  | bool b =>
      refine ⟨{ ty := Weft.Ty.bool, typed := HasType.bool b }, ?_, rfl⟩
      simp [check]
  | int n =>
      refine ⟨{ ty := Weft.Ty.int, typed := HasType.int n }, ?_, rfl⟩
      simp [check]
  | nil =>
      refine ⟨{ ty := Weft.Ty.nil, typed := HasType.nil }, ?_, rfl⟩
      simp [check]
  | add lhs rhs hL hR ihL ihR =>
      rcases ihL with ⟨checkedL, hCheckL, hTyL⟩
      rcases ihR with ⟨checkedR, hCheckR, hTyR⟩
      cases checkedL with
      | mk tyL typedL =>
          cases checkedR with
          | mk tyR typedR =>
              cases hTyL
              cases hTyR
              refine ⟨{
                ty := Weft.Ty.int
                typed := HasType.add lhs rhs typedL typedR
              }, ?_, rfl⟩
              simp [check, hCheckL, hCheckR]
  | ifThenElse cond thenBranch elseBranch ty hCond hThen hElse ihCond ihThen ihElse =>
      rcases ihCond with ⟨checkedCond, hCheckCond, hTyCond⟩
      rcases ihThen with ⟨checkedThen, hCheckThen, hTyThen⟩
      rcases ihElse with ⟨checkedElse, hCheckElse, hTyElse⟩
      cases checkedCond with
      | mk tyCond typedCond =>
          cases checkedThen with
          | mk tyThen typedThen =>
              cases checkedElse with
              | mk tyElse typedElse =>
                  rcases typed_ty_cases hThen with hBool | hInt | hNil
                  · cases hBool
                    cases hTyCond
                    cases hTyThen
                    cases hTyElse
                    refine ⟨{
                      ty := Weft.Ty.bool
                      typed := HasType.ifThenElse cond thenBranch elseBranch Weft.Ty.bool
                        typedCond
                        typedThen
                        typedElse
                    }, ?_, rfl⟩
                    simp [check, hCheckCond, hCheckThen, hCheckElse]
                  · cases hInt
                    cases hTyCond
                    cases hTyThen
                    cases hTyElse
                    refine ⟨{
                      ty := Weft.Ty.int
                      typed := HasType.ifThenElse cond thenBranch elseBranch Weft.Ty.int
                        typedCond
                        typedThen
                        typedElse
                    }, ?_, rfl⟩
                    simp [check, hCheckCond, hCheckThen, hCheckElse]
                  · cases hNil
                    cases hTyCond
                    cases hTyThen
                    cases hTyElse
                    refine ⟨{
                      ty := Weft.Ty.nil
                      typed := HasType.ifThenElse cond thenBranch elseBranch Weft.Ty.nil
                        typedCond
                        typedThen
                        typedElse
                    }, ?_, rfl⟩
                    simp [check, hCheckCond, hCheckThen, hCheckElse]

theorem inferType_complete
    {expr : Expr}
    {ty : Weft.Ty}
    (hTy : HasType expr ty) :
    inferType expr = some ty := by
  rcases check_complete hTy with ⟨checked, hCheck, hTyEq⟩
  simp [inferType, hCheck, hTyEq]

theorem inferType_iff_hasType
    {expr : Expr}
    {ty : Weft.Ty} :
    inferType expr = some ty ↔ HasType expr ty := by
  constructor
  · exact inferType_sound
  · exact inferType_complete

end Weft.SafetyCore
