import Weft.KernelModel
import Weft.KernelSubtype
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

theorem runtimeValHasType_denotesTag
    {value : RuntimeVal}
    {ty : Weft.Ty}
    (hTy : RuntimeValHasType value ty) :
    Weft.Ty.denotesTag value.toKernelTag ty := by
  cases hTy <;>
    simp [RuntimeVal.toKernelTag, Weft.Ty.denotesTag, Weft.Ty.denotesUnder,
      Weft.KernelTag.valuation, Weft.TyAtom.denotesTag]

theorem denotesTag_of_subtype
    {value : RuntimeVal}
    {lhs rhs : Weft.Ty}
    (hDen : Weft.Ty.denotesTag value.toKernelTag lhs)
    (hSubtype : lhs.SubtypeIn Weft.KernelTheory.theory rhs) :
    Weft.Ty.denotesTag value.toKernelTag rhs := by
  exact hSubtype _ (Weft.KernelTag.soundValuation value.toKernelTag) hDen

theorem denotesTag_of_tag_subtype
    {value : RuntimeVal}
    {lhs rhs : Weft.Ty}
    (hDen : Weft.Ty.denotesTag value.toKernelTag lhs)
    (hSubtype : ∀ tag : Weft.KernelTag, Weft.Ty.denotesTag tag lhs -> Weft.Ty.denotesTag tag rhs) :
    Weft.Ty.denotesTag value.toKernelTag rhs := by
  exact hSubtype value.toKernelTag hDen

theorem denotesTag_of_kernelSubtypeb
    {value : RuntimeVal}
    {lhs rhs : Weft.Ty}
    (hDen : Weft.Ty.denotesTag value.toKernelTag lhs)
    (hSubtype : lhs.kernelSubtypeb rhs = true) :
    Weft.Ty.denotesTag value.toKernelTag rhs := by
  exact denotesTag_of_subtype hDen (Weft.Ty.kernelSubtypeb_sound hSubtype)

def kernelCheckAgainst (expr : Expr) (expected : Weft.Ty) : Bool :=
  match inferType expr with
  | some inferred => inferred.kernelSubtypeb expected
  | none => false

theorem kernelCheckAgainst_semantic_soundness_tag
    {expr : Expr}
    {expected : Weft.Ty}
    {value : RuntimeVal}
    (hCheck : kernelCheckAgainst expr expected = true)
    (hEval : Eval expr value) :
    Weft.Ty.denotesTag value.toKernelTag expected := by
  unfold kernelCheckAgainst at hCheck
  cases hInfer : inferType expr with
  | none =>
      simp [hInfer] at hCheck
  | some inferred =>
      simp [hInfer] at hCheck
      have hSubtype : inferred.SubtypeIn Weft.KernelTheory.theory expected :=
        Weft.Ty.kernelSubtypeb_sound hCheck
      have hTy : HasType expr inferred :=
        inferType_sound hInfer
      have hValTy : RuntimeValHasType value inferred :=
        eval_preserves_type hTy hEval
      exact hSubtype _ (Weft.KernelTag.soundValuation value.toKernelTag)
        (runtimeValHasType_denotesTag hValTy)

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

def kernelCheckAgainst (expr : Expr) (expected : Weft.Ty) : Bool :=
  match inferType expr with
  | some inferred => inferred.kernelSubtypeb expected
  | none => false

theorem kernelCheckAgainst_semantic_soundness_tag
    {oracle : Oracle}
    {expr : Expr}
    {expected : Weft.Ty}
    {value : RuntimeVal}
    {trace : List Weft.EffectName}
    (hCheck : kernelCheckAgainst expr expected = true)
    (hEval : Eval oracle expr value trace) :
    Weft.Ty.denotesTag value.toKernelTag expected := by
  unfold kernelCheckAgainst at hCheck
  cases hInfer : inferType expr with
  | none =>
      simp [hInfer] at hCheck
  | some inferred =>
      simp [hInfer] at hCheck
      have hSubtype : inferred.SubtypeIn Weft.KernelTheory.theory expected :=
        Weft.Ty.kernelSubtypeb_sound hCheck
      rcases inferType_sound hInfer with ⟨effects, hTy⟩
      have hValTy : RuntimeValHasType value inferred :=
        eval_preserves_type hTy hEval
      exact hSubtype _ (Weft.KernelTag.soundValuation value.toKernelTag)
        (runtimeValHasType_denotesTag hValTy)

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

theorem compiled_pure_result_respects_kernel_expected_type_tag
    {oracle : Oracle}
    {expr : Expr}
    {expected : Weft.Ty}
    {value : RuntimeVal}
    {trace : List Weft.EffectName}
    (hCheck : kernelCheckAgainst expr expected = true)
    (hPure : inferEffects expr = some Weft.EffectSet.empty)
    (hEval : Eval oracle expr value trace) :
    Exec oracle (compileClosed expr) [] [value] trace ∧
      (∀ effect : Weft.EffectName, effect ∉ trace) ∧
      Weft.Ty.denotesTag value.toKernelTag expected := by
  have hExec : Exec oracle (compileClosed expr) [] [value] trace :=
    compile_correct oracle expr value trace hEval
  have hTraceFree : ∀ effect : Weft.EffectName, effect ∉ trace := by
    rcases inferEffects_sound hPure with ⟨ty, hTy⟩
    exact empty_effects_have_empty_trace hTy hEval
  exact ⟨hExec, hTraceFree, kernelCheckAgainst_semantic_soundness_tag hCheck hEval⟩

theorem compiled_result_respects_effects_and_kernel_expected_type_tag
    {oracle : Oracle}
    {expr : Expr}
    {expected : Weft.Ty}
    {effects : Weft.EffectSet}
    {value : RuntimeVal}
    {trace : List Weft.EffectName}
    (hCheck : kernelCheckAgainst expr expected = true)
    (hEffects : inferEffects expr = some effects)
    (hEval : Eval oracle expr value trace) :
    Exec oracle (compileClosed expr) [] [value] trace ∧
      (∀ effect : Weft.EffectName, effect ∈ trace -> effect ∈ effects.elems) ∧
      Weft.Ty.denotesTag value.toKernelTag expected := by
  have hExec : Exec oracle (compileClosed expr) [] [value] trace :=
    compile_correct oracle expr value trace hEval
  have hTrace :
      ∀ effect : Weft.EffectName, effect ∈ trace -> effect ∈ effects.elems := by
    rcases inferEffects_sound hEffects with ⟨ty, hTy⟩
    exact trace_subset_of_typed_effects hTy hEval
  exact ⟨hExec, hTrace, kernelCheckAgainst_semantic_soundness_tag hCheck hEval⟩

theorem compiled_pure_result_respects_weakened_kernel_expected_type_tag
    {oracle : Oracle}
    {expr : Expr}
    {expected widened : Weft.Ty}
    {value : RuntimeVal}
    {trace : List Weft.EffectName}
    (hCheck : kernelCheckAgainst expr expected = true)
    (hSubtype : expected.SubtypeIn Weft.KernelTheory.theory widened)
    (hPure : inferEffects expr = some Weft.EffectSet.empty)
    (hEval : Eval oracle expr value trace) :
    Exec oracle (compileClosed expr) [] [value] trace ∧
      (∀ effect : Weft.EffectName, effect ∉ trace) ∧
      Weft.Ty.denotesTag value.toKernelTag widened := by
  rcases compiled_pure_result_respects_kernel_expected_type_tag hCheck hPure hEval with
    ⟨hExec, hTrace, hTyped⟩
  exact ⟨hExec, hTrace, denotesTag_of_subtype hTyped hSubtype⟩

theorem compiled_result_respects_effects_and_weakened_kernel_expected_type_tag
    {oracle : Oracle}
    {expr : Expr}
    {expected widened : Weft.Ty}
    {effects : Weft.EffectSet}
    {value : RuntimeVal}
    {trace : List Weft.EffectName}
    (hCheck : kernelCheckAgainst expr expected = true)
    (hSubtype : expected.SubtypeIn Weft.KernelTheory.theory widened)
    (hEffects : inferEffects expr = some effects)
    (hEval : Eval oracle expr value trace) :
    Exec oracle (compileClosed expr) [] [value] trace ∧
      (∀ effect : Weft.EffectName, effect ∈ trace -> effect ∈ effects.elems) ∧
      Weft.Ty.denotesTag value.toKernelTag widened := by
  rcases compiled_result_respects_effects_and_kernel_expected_type_tag hCheck hEffects hEval with
    ⟨hExec, hTrace, hTyped⟩
  exact ⟨hExec, hTrace, denotesTag_of_subtype hTyped hSubtype⟩

theorem compiled_pure_result_respects_kernelSubtypeb_weakened_expected_type_tag
    {oracle : Oracle}
    {expr : Expr}
    {expected widened : Weft.Ty}
    {value : RuntimeVal}
    {trace : List Weft.EffectName}
    (hCheck : kernelCheckAgainst expr expected = true)
    (hSubtype : expected.kernelSubtypeb widened = true)
    (hPure : inferEffects expr = some Weft.EffectSet.empty)
    (hEval : Eval oracle expr value trace) :
    Exec oracle (compileClosed expr) [] [value] trace ∧
      (∀ effect : Weft.EffectName, effect ∉ trace) ∧
      Weft.Ty.denotesTag value.toKernelTag widened := by
  rcases compiled_pure_result_respects_kernel_expected_type_tag hCheck hPure hEval with
    ⟨hExec, hTrace, hTyped⟩
  exact ⟨hExec, hTrace, denotesTag_of_kernelSubtypeb hTyped hSubtype⟩

theorem compiled_result_respects_effects_and_kernelSubtypeb_weakened_expected_type_tag
    {oracle : Oracle}
    {expr : Expr}
    {expected widened : Weft.Ty}
    {effects : Weft.EffectSet}
    {value : RuntimeVal}
    {trace : List Weft.EffectName}
    (hCheck : kernelCheckAgainst expr expected = true)
    (hSubtype : expected.kernelSubtypeb widened = true)
    (hEffects : inferEffects expr = some effects)
    (hEval : Eval oracle expr value trace) :
    Exec oracle (compileClosed expr) [] [value] trace ∧
      (∀ effect : Weft.EffectName, effect ∈ trace -> effect ∈ effects.elems) ∧
      Weft.Ty.denotesTag value.toKernelTag widened := by
  rcases compiled_result_respects_effects_and_kernel_expected_type_tag hCheck hEffects hEval with
    ⟨hExec, hTrace, hTyped⟩
  exact ⟨hExec, hTrace, denotesTag_of_kernelSubtypeb hTyped hSubtype⟩

theorem compiled_pure_result_respects_tag_weakened_kernel_expected_type_tag
    {oracle : Oracle}
    {expr : Expr}
    {expected widened : Weft.Ty}
    {value : RuntimeVal}
    {trace : List Weft.EffectName}
    (hCheck : kernelCheckAgainst expr expected = true)
    (hSubtype : ∀ tag : Weft.KernelTag, Weft.Ty.denotesTag tag expected -> Weft.Ty.denotesTag tag widened)
    (hPure : inferEffects expr = some Weft.EffectSet.empty)
    (hEval : Eval oracle expr value trace) :
    Exec oracle (compileClosed expr) [] [value] trace ∧
      (∀ effect : Weft.EffectName, effect ∉ trace) ∧
      Weft.Ty.denotesTag value.toKernelTag widened := by
  rcases compiled_pure_result_respects_kernel_expected_type_tag hCheck hPure hEval with
    ⟨hExec, hTrace, hTyped⟩
  exact ⟨hExec, hTrace, denotesTag_of_tag_subtype hTyped hSubtype⟩

theorem compiled_result_respects_effects_and_tag_weakened_kernel_expected_type_tag
    {oracle : Oracle}
    {expr : Expr}
    {expected widened : Weft.Ty}
    {effects : Weft.EffectSet}
    {value : RuntimeVal}
    {trace : List Weft.EffectName}
    (hCheck : kernelCheckAgainst expr expected = true)
    (hSubtype : ∀ tag : Weft.KernelTag, Weft.Ty.denotesTag tag expected -> Weft.Ty.denotesTag tag widened)
    (hEffects : inferEffects expr = some effects)
    (hEval : Eval oracle expr value trace) :
    Exec oracle (compileClosed expr) [] [value] trace ∧
      (∀ effect : Weft.EffectName, effect ∈ trace -> effect ∈ effects.elems) ∧
      Weft.Ty.denotesTag value.toKernelTag widened := by
  rcases compiled_result_respects_effects_and_kernel_expected_type_tag hCheck hEffects hEval with
    ⟨hExec, hTrace, hTyped⟩
  exact ⟨hExec, hTrace, denotesTag_of_tag_subtype hTyped hSubtype⟩

end Weft.CoreEffects
