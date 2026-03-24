import Weft.KernelModel
import Weft.Properties.CoreEffectSubtypeChecking

namespace Weft.SafetyCore

def RuntimeVal.toKernelTag : RuntimeVal -> Weft.KernelTag
  | .bool _ => .bool
  | .int _ => .int
  | .nil => .nil

private theorem ofTy_denotes_iff_denotesTag'
    (value : RuntimeVal) :
    (ty : Weft.Ty) -> (core : Weft.CoreSetTy) ->
      Weft.CoreSetTy.ofTy ty = some core ->
      (core.denotes value.toCoreAtom ↔ Weft.Ty.denotesTag value.toKernelTag ty)
  | .bool, core, hCore => by
      simp [Weft.CoreSetTy.ofTy] at hCore
      cases hCore
      cases value <;>
        simp [Weft.CoreSetTy.denotes, RuntimeVal.toCoreAtom,
          RuntimeVal.toKernelTag, Weft.Ty.denotesTag, Weft.Ty.denotesUnder,
          Weft.KernelTag.valuation, Weft.TyAtom.denotesTag]
  | .int, core, hCore => by
      simp [Weft.CoreSetTy.ofTy] at hCore
      cases hCore
      cases value <;>
        simp [Weft.CoreSetTy.denotes, RuntimeVal.toCoreAtom,
          RuntimeVal.toKernelTag, Weft.Ty.denotesTag, Weft.Ty.denotesUnder,
          Weft.KernelTag.valuation, Weft.TyAtom.denotesTag]
  | .nil, core, hCore => by
      simp [Weft.CoreSetTy.ofTy] at hCore
      cases hCore
      cases value <;>
        simp [Weft.CoreSetTy.denotes, RuntimeVal.toCoreAtom,
          RuntimeVal.toKernelTag, Weft.Ty.denotesTag, Weft.Ty.denotesUnder,
          Weft.KernelTag.valuation, Weft.TyAtom.denotesTag]
  | .never, core, hCore => by
      simp [Weft.CoreSetTy.ofTy] at hCore
      cases hCore
      cases value <;>
        simp [Weft.CoreSetTy.denotes, Weft.Ty.denotesTag, Weft.Ty.denotesUnder]
  | .any, core, hCore => by
      simp [Weft.CoreSetTy.ofTy] at hCore
      cases hCore
      cases value <;>
        simp [Weft.CoreSetTy.denotes, Weft.Ty.denotesTag, Weft.Ty.denotesUnder]
  | .union lhs rhs, core, hCore => by
      cases hL : Weft.CoreSetTy.ofTy lhs <;> simp [Weft.CoreSetTy.ofTy, hL] at hCore
      cases hR : Weft.CoreSetTy.ofTy rhs <;> simp [hR] at hCore
      cases hCore
      simp [Weft.CoreSetTy.denotes, Weft.Ty.denotesTag, Weft.Ty.denotesUnder,
        ofTy_denotes_iff_denotesTag' value lhs _ hL,
        ofTy_denotes_iff_denotesTag' value rhs _ hR]
  | .inter lhs rhs, core, hCore => by
      cases hL : Weft.CoreSetTy.ofTy lhs <;> simp [Weft.CoreSetTy.ofTy, hL] at hCore
      cases hR : Weft.CoreSetTy.ofTy rhs <;> simp [hR] at hCore
      cases hCore
      simp [Weft.CoreSetTy.denotes, Weft.Ty.denotesTag, Weft.Ty.denotesUnder,
        ofTy_denotes_iff_denotesTag' value lhs _ hL,
        ofTy_denotes_iff_denotesTag' value rhs _ hR]
  | .compl inner, core, hCore => by
      cases hInner : Weft.CoreSetTy.ofTy inner <;> simp [Weft.CoreSetTy.ofTy, hInner] at hCore
      cases hCore
      simp [Weft.CoreSetTy.denotes, Weft.Ty.denotesTag, Weft.Ty.denotesUnder,
        ofTy_denotes_iff_denotesTag' value inner _ hInner]
  | .fn _ _ _, core, hCore => by
      simp [Weft.CoreSetTy.ofTy] at hCore
  | .record _, core, hCore => by
      simp [Weft.CoreSetTy.ofTy] at hCore
  | .ptr _, core, hCore => by
      simp [Weft.CoreSetTy.ofTy] at hCore
  | .mptr _, core, hCore => by
      simp [Weft.CoreSetTy.ofTy] at hCore
  | .rc _, core, hCore => by
      simp [Weft.CoreSetTy.ofTy] at hCore
  | .nominal _ _, core, hCore => by
      simp [Weft.CoreSetTy.ofTy] at hCore

theorem ofTy_denotes_iff_denotesTag
    {value : RuntimeVal}
    {ty : Weft.Ty}
    {core : Weft.CoreSetTy}
    (hCore : Weft.CoreSetTy.ofTy ty = some core) :
    (core.denotes value.toCoreAtom ↔ Weft.Ty.denotesTag value.toKernelTag ty) :=
  ofTy_denotes_iff_denotesTag' value ty core hCore

theorem checkAgainst_semantic_soundness_tag
    {expr : Expr}
    {expected : Weft.Ty}
    {value : RuntimeVal}
    (hCheck : checkAgainst expr expected = true)
    (hEval : Eval expr value) :
    Weft.Ty.denotesTag value.toKernelTag expected := by
  rcases checkAgainst_semantic_soundness hCheck hEval with ⟨expectedCore, hCore, hDen⟩
  exact (ofTy_denotes_iff_denotesTag hCore).1 hDen

end Weft.SafetyCore

namespace Weft.CoreEffects

open Weft.SafetyCore

theorem checkAgainst_semantic_soundness_tag
    {oracle : Oracle}
    {expr : Expr}
    {expected : Weft.Ty}
    {value : RuntimeVal}
    {trace : List Weft.EffectName}
    (hCheck : checkAgainst expr expected = true)
    (hEval : Eval oracle expr value trace) :
    Weft.Ty.denotesTag value.toKernelTag expected := by
  rcases checkAgainst_semantic_soundness hCheck hEval with ⟨expectedCore, hCore, hDen⟩
  exact (ofTy_denotes_iff_denotesTag hCore).1 hDen

theorem compiled_pure_result_respects_expected_type_tag
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
      Weft.Ty.denotesTag value.toKernelTag expected := by
  rcases compiled_pure_result_respects_expected_type hCheck hPure hEval with
    ⟨hExec, hTraceFree, expectedCore, hCore, hDen⟩
  exact ⟨hExec, hTraceFree, (ofTy_denotes_iff_denotesTag hCore).1 hDen⟩

theorem compiled_result_respects_effects_and_expected_type_tag
    {oracle : Oracle}
    {expr : Expr}
    {expected : Weft.Ty}
    {effects : Weft.EffectSet}
    {value : RuntimeVal}
    {trace : List Weft.EffectName}
    (hCheck : checkAgainst expr expected = true)
    (hEffects : inferEffects expr = some effects)
    (hEval : Eval oracle expr value trace) :
    Exec oracle (compileClosed expr) [] [value] trace ∧
      (∀ effect : Weft.EffectName, effect ∈ trace -> effect ∈ effects.elems) ∧
      Weft.Ty.denotesTag value.toKernelTag expected := by
  rcases compiled_result_respects_effects_and_expected_type hCheck hEffects hEval with
    ⟨hExec, hTrace, expectedCore, hCore, hDen⟩
  exact ⟨hExec, hTrace, (ofTy_denotes_iff_denotesTag hCore).1 hDen⟩

end Weft.CoreEffects
