import Weft.SafetyCore

namespace Weft.SafetyCore

theorem bool_canonical
    (e : Expr)
    (hValue : Value e)
    (hTy : HasType e Weft.Ty.bool) :
    ∃ b : Bool, e = .bool b := by
  cases hValue with
  | bool b =>
      exact ⟨b, rfl⟩
  | int n =>
      cases hTy
  | nil =>
      cases hTy

theorem int_canonical
    (e : Expr)
    (hValue : Value e)
    (hTy : HasType e Weft.Ty.int) :
    ∃ n : Int, e = .int n := by
  cases hValue with
  | bool b =>
      cases hTy
  | int n =>
      exact ⟨n, rfl⟩
  | nil =>
      cases hTy

theorem progress
    (e : Expr)
    (ty : Weft.Ty)
    (hTy : HasType e ty) :
    Value e ∨ ∃ e' : Expr, Step e e' := by
  induction hTy with
  | bool b =>
      exact Or.inl (Value.bool b)
  | int n =>
      exact Or.inl (Value.int n)
  | nil =>
      exact Or.inl Value.nil
  | add lhs rhs hL hR ihL ihR =>
      cases ihL with
      | inl hValueL =>
          cases ihR with
          | inl hValueR =>
              rcases int_canonical lhs hValueL hL with ⟨ln, hEqL⟩
              rcases int_canonical rhs hValueR hR with ⟨rn, hEqR⟩
              right
              cases hEqL
              cases hEqR
              exact ⟨.int (ln + rn), Step.addInt ln rn⟩
          | inr hStepR =>
              rcases hStepR with ⟨rhs', hStepR⟩
              exact Or.inr ⟨.add lhs rhs', Step.addRight lhs rhs rhs' hValueL hStepR⟩
      | inr hStepL =>
          rcases hStepL with ⟨lhs', hStepL⟩
          exact Or.inr ⟨.add lhs' rhs, Step.addLeft lhs lhs' rhs hStepL⟩
  | ifThenElse cond thenBranch elseBranch ty hCond hThen hElse ihCond _ _ =>
      cases ihCond with
      | inl hValueCond =>
          rcases bool_canonical cond hValueCond hCond with ⟨b, hEqCond⟩
          cases hEqCond
          cases b with
          | false =>
              exact Or.inr ⟨elseBranch, Step.ifFalse thenBranch elseBranch⟩
          | true =>
              exact Or.inr ⟨thenBranch, Step.ifTrue thenBranch elseBranch⟩
      | inr hStepCond =>
          rcases hStepCond with ⟨cond', hStepCond⟩
          exact Or.inr ⟨.ifThenElse cond' thenBranch elseBranch,
            Step.ifCond cond cond' thenBranch elseBranch hStepCond⟩

theorem preservation
    (e e' : Expr)
    (ty : Weft.Ty)
    (hTy : HasType e ty)
    (hStep : Step e e') :
    HasType e' ty := by
  induction hStep generalizing ty with
  | addLeft lhs lhs' rhs hStep ih =>
      cases hTy with
      | add _ _ hL hR =>
          exact HasType.add lhs' rhs (ih Weft.Ty.int hL) hR
  | addRight lhs rhs rhs' hValue hStep ih =>
      cases hTy with
      | add _ _ hL hR =>
          exact HasType.add lhs rhs' hL (ih Weft.Ty.int hR)
  | addInt lhs rhs =>
      cases hTy with
      | add _ _ _ _ =>
          exact HasType.int (lhs + rhs)
  | ifCond cond cond' thenBranch elseBranch hStep ih =>
      cases hTy with
      | ifThenElse _ _ _ ty hCond hThen hElse =>
          exact HasType.ifThenElse cond' thenBranch elseBranch ty (ih Weft.Ty.bool hCond) hThen hElse
  | ifTrue thenBranch elseBranch =>
      cases hTy with
      | ifThenElse _ _ _ ty _ hThen _ =>
          exact hThen
  | ifFalse thenBranch elseBranch =>
      cases hTy with
      | ifThenElse _ _ _ ty _ _ hElse =>
          exact hElse

theorem preservation_many
    {e e' : Expr}
    {ty : Weft.Ty}
    (hSteps : Steps e e')
    (hTy : HasType e ty) :
    HasType e' ty := by
  induction hSteps generalizing ty with
  | refl _ =>
      exact hTy
  | tail e eMid e' hStep hTail ih =>
      have hMid : HasType eMid ty :=
        preservation e eMid ty hTy hStep
      exact ih hMid

theorem normal_form_of_typed_term_is_value
    (e : Expr)
    (ty : Weft.Ty)
    (hTy : HasType e ty)
    (hNormal : NormalForm e) :
    Value e := by
  cases progress e ty hTy with
  | inl hValue =>
      exact hValue
  | inr hStep =>
      rcases hStep with ⟨e', hStep⟩
      exact False.elim (hNormal e' hStep)

theorem type_safety
    (e e' : Expr)
    (ty : Weft.Ty)
    (hTy : HasType e ty)
    (hSteps : Steps e e')
    (hNormal : NormalForm e') :
    Value e' := by
  exact normal_form_of_typed_term_is_value e' ty (preservation_many hSteps hTy) hNormal

end Weft.SafetyCore
