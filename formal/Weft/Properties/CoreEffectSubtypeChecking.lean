import Weft.Properties.CoreEffectSemanticSoundness
import Weft.Properties.CoreEffectTypecheckCorrectness
import Weft.Properties.CoreSubtypeChecking
import Weft.Properties.CoreSubtypeSoundness

namespace Weft.CoreEffects

open Weft.SafetyCore

def AdmitsExpectedTy (expr : Expr) (expected : Weft.Ty) : Prop :=
  ∃ inferred : Weft.Ty,
    ∃ effects : Weft.EffectSet,
      ∃ inferredCore expectedCore : Weft.CoreSetTy,
        HasType expr inferred effects ∧
        Weft.CoreSetTy.ofTy inferred = some inferredCore ∧
        Weft.CoreSetTy.ofTy expected = some expectedCore ∧
        inferredCore.Subtype expectedCore

theorem eval_denotes_inferred_core_type
    {oracle : Oracle}
    {expr : Expr}
    {inferred : Weft.Ty}
    {effects : Weft.EffectSet}
    {inferredCore : Weft.CoreSetTy}
    {value : RuntimeVal}
    {trace : List Weft.EffectName}
    (hTy : HasType expr inferred effects)
    (hCore : Weft.CoreSetTy.ofTy inferred = some inferredCore)
    (hEval : Eval oracle expr value trace) :
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
                rcases inferType_sound hInfer with ⟨effects, hTy⟩
                exact ⟨inferred, effects, inferredCore, expectedCore,
                  hTy, hInferredCore, hExpected, hSubtype⟩
  · rintro ⟨inferred, effects, inferredCore, expectedCore, hTy, hInferredCore, hExpected, hSubtype⟩
    have hInfer : inferType expr = some inferred :=
      inferType_complete hTy
    have hSubtypeb : inferredCore.subtypeb expectedCore = true :=
      (Weft.subtypeb_spec inferredCore expectedCore).2 hSubtype
    simp [checkAgainst, hInfer, hExpected, hInferredCore, hSubtypeb]

theorem checkAgainst_semantic_soundness
    {oracle : Oracle}
    {expr : Expr}
    {expected : Weft.Ty}
    {value : RuntimeVal}
    {trace : List Weft.EffectName}
    (hCheck : checkAgainst expr expected = true)
    (hEval : Eval oracle expr value trace) :
    ∃ expectedCore : Weft.CoreSetTy,
      Weft.CoreSetTy.ofTy expected = some expectedCore ∧
      expectedCore.denotes value.toCoreAtom := by
  rcases (checkAgainst_iff_admitsExpectedTy).1 hCheck with
    ⟨inferred, effects, inferredCore, expectedCore, hTy, hInferredCore, hExpected, hSubtype⟩
  have hInferredDenotes : inferredCore.denotes value.toCoreAtom :=
    eval_denotes_inferred_core_type hTy hInferredCore hEval
  exact ⟨expectedCore, hExpected, hSubtype _ hInferredDenotes⟩

theorem checkAgainst_complete
    {expr : Expr}
    {expected : Weft.Ty}
    (hAdmits : AdmitsExpectedTy expr expected) :
    checkAgainst expr expected = true :=
  (checkAgainst_iff_admitsExpectedTy).2 hAdmits

theorem compiled_pure_result_respects_expected_type
    {oracle : Oracle}
    {expr : Expr}
    {expected : Weft.Ty}
    {value : RuntimeVal}
    {trace : List Weft.EffectName}
    (hCheck : checkAgainst expr expected = true)
    (hPure : inferEffects expr = some Weft.EffectSet.empty)
    (hEval : Eval oracle expr value trace) :
    Exec oracle (compileClosed expr) [] [value] trace ∧
      (∀ effect : Weft.EffectName, effect ∉ trace) ∧
      ∃ expectedCore : Weft.CoreSetTy,
        Weft.CoreSetTy.ofTy expected = some expectedCore ∧
        expectedCore.denotes value.toCoreAtom := by
  rcases inferEffects_sound hPure with ⟨ty, hTy⟩
  have hCompiledPure : Exec oracle (compileClosed expr) [] [value] trace ∧
      ∀ effect : Weft.EffectName, effect ∉ trace :=
    compiled_empty_effects_have_empty_trace hTy hEval
  have hExpectedSound :
      ∃ expectedCore : Weft.CoreSetTy,
        Weft.CoreSetTy.ofTy expected = some expectedCore ∧
        expectedCore.denotes value.toCoreAtom :=
    checkAgainst_semantic_soundness hCheck hEval
  exact ⟨hCompiledPure.1, hCompiledPure.2, hExpectedSound⟩

end Weft.CoreEffects
