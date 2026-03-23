import Weft.Properties.CoreSemanticSoundness
import Weft.Properties.CoreDNFSoundness
import Weft.Properties.CoreSubtypeSoundness
import Weft.Properties.CoreTypecheckCorrectness

namespace Weft.SafetyCore

def RuntimeVal.toCoreAtom : RuntimeVal -> Weft.CoreAtom
  | .bool _ => .bool
  | .int _ => .int
  | .nil => .nil

def AdmitsExpectedTy (expr : Expr) (expected : Weft.Ty) : Prop :=
  ∃ inferred : Weft.Ty,
    ∃ inferredCore expectedCore : Weft.CoreSetTy,
      HasType expr inferred ∧
      Weft.CoreSetTy.ofTy inferred = some inferredCore ∧
      Weft.CoreSetTy.ofTy expected = some expectedCore ∧
      inferredCore.Subtype expectedCore

theorem eval_denotes_inferred_core_type
    {expr : Expr}
    {inferred : Weft.Ty}
    {inferredCore : Weft.CoreSetTy}
    {value : RuntimeVal}
    (hTy : HasType expr inferred)
    (hCore : Weft.CoreSetTy.ofTy inferred = some inferredCore)
    (hEval : Eval expr value) :
    inferredCore.denotes value.toCoreAtom := by
  have hValueTy : RuntimeValHasType value inferred :=
    eval_preserves_type hTy hEval
  cases hValueTy with
  | bool b =>
      simp [Weft.CoreSetTy.ofTy] at hCore
      cases hCore
      simp [Weft.CoreSetTy.denotes, RuntimeVal.toCoreAtom]
  | int n =>
      simp [Weft.CoreSetTy.ofTy] at hCore
      cases hCore
      simp [Weft.CoreSetTy.denotes, RuntimeVal.toCoreAtom]
  | nil =>
      simp [Weft.CoreSetTy.ofTy] at hCore
      cases hCore
      simp [Weft.CoreSetTy.denotes, RuntimeVal.toCoreAtom]

theorem checkAgainst_iff_admitsExpectedTy
    {expr : Expr}
    {expected : Weft.Ty} :
    checkAgainst expr expected = true ↔ AdmitsExpectedTy expr expected := by
  constructor
  · intro hCheck
    unfold checkAgainst at hCheck
    cases hInfer : inferType expr with
    | none =>
        simp [hInfer] at hCheck
    | some inferred =>
        cases hExpected : Weft.CoreSetTy.ofTy expected with
        | none =>
            simp [hExpected] at hCheck
        | some expectedCore =>
            cases hInferredCore : Weft.CoreSetTy.ofTy inferred with
            | none =>
                simp [hInfer, hExpected, hInferredCore] at hCheck
            | some inferredCore =>
                have hSubtype : inferredCore.Subtype expectedCore :=
                  (Weft.subtypeb_spec inferredCore expectedCore).1 (by
                    simpa [hInfer, hExpected, hInferredCore] using hCheck)
                exact ⟨inferred, inferredCore, expectedCore,
                  inferType_sound hInfer, hInferredCore, hExpected, hSubtype⟩
  · rintro ⟨inferred, inferredCore, expectedCore, hTy, hInferredCore, hExpected, hSubtype⟩
    have hInfer : inferType expr = some inferred :=
      inferType_complete hTy
    have hSubtypeb : inferredCore.subtypeb expectedCore = true :=
      (Weft.subtypeb_spec inferredCore expectedCore).2 hSubtype
    simp [checkAgainst, hInfer, hExpected, hInferredCore, hSubtypeb]

theorem checkAgainst_semantic_soundness
    {expr : Expr}
    {expected : Weft.Ty}
    {value : RuntimeVal}
    (hCheck : checkAgainst expr expected = true)
    (hEval : Eval expr value) :
    ∃ expectedCore : Weft.CoreSetTy,
      Weft.CoreSetTy.ofTy expected = some expectedCore ∧
      expectedCore.denotes value.toCoreAtom := by
  rcases (checkAgainst_iff_admitsExpectedTy).1 hCheck with
    ⟨inferred, inferredCore, expectedCore, hTy, hInferredCore, hExpected, hSubtype⟩
  have hInferredDenotes : inferredCore.denotes value.toCoreAtom :=
    eval_denotes_inferred_core_type hTy hInferredCore hEval
  exact ⟨expectedCore, hExpected, hSubtype _ hInferredDenotes⟩

theorem checkAgainst_complete
    {expr : Expr}
    {expected : Weft.Ty}
    (hAdmits : AdmitsExpectedTy expr expected) :
    checkAgainst expr expected = true :=
  (checkAgainst_iff_admitsExpectedTy).2 hAdmits

theorem checkAgainst_iff_normalizeDNF_empty_diff
    {expr : Expr}
    {expected : Weft.Ty} :
    checkAgainst expr expected = true ↔
      ∃ inferred inferredCore expectedCore,
        inferType expr = some inferred ∧
        Weft.CoreSetTy.ofTy inferred = some inferredCore ∧
        Weft.CoreSetTy.ofTy expected = some expectedCore ∧
        (Weft.CoreSetTy.normalizeDNF
          (Weft.CoreSetTy.inter inferredCore (Weft.CoreSetTy.compl expectedCore))).emptyb = true := by
  unfold checkAgainst
  cases hInfer : inferType expr with
  | none =>
      simp
  | some inferred =>
      cases hExpected : Weft.CoreSetTy.ofTy expected with
      | none =>
          simp
      | some expectedCore =>
          cases hInferred : Weft.CoreSetTy.ofTy inferred with
          | none =>
              simp [hInferred]
          | some inferredCore =>
              simp [hInferred]
              exact Weft.CoreSetTy.subtypeb_eq_normalizeDNF_empty_diff inferredCore expectedCore

end Weft.SafetyCore
