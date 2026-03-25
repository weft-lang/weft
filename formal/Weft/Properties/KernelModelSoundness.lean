import Weft.KernelModel
import Weft.KernelSubtype
import Weft.Properties.TyTheorySoundness

namespace Weft

theorem kernel_bool_int_empty_tag
    (tag : KernelTag) :
    ¬ Ty.denotesTag tag (Ty.inter Ty.bool Ty.int) := by
  intro hDen
  have hNorm :
      TyDNF.denotes (KernelTag.valuation tag) (Ty.normalizeTyDNF (Ty.inter Ty.bool Ty.int)) :=
    (Ty.normalizeTyDNF_spec (KernelTag.valuation tag) (Ty.inter Ty.bool Ty.int)).2 hDen
  exact TyDNF.unsat_sound (KernelTag.soundValuation tag) kernel_bool_int_inter_unsat hNorm

theorem kernel_subtypeIn_implies_tag_subtype
    {lhs rhs : Ty}
    (hSubtype : lhs.SubtypeIn KernelTheory.theory rhs) :
    ∀ tag : KernelTag, Ty.denotesTag tag lhs -> Ty.denotesTag tag rhs := by
  intro tag hDen
  exact hSubtype _ (KernelTag.soundValuation tag) hDen

theorem kernel_subtypeb_implies_tag_subtype
    {lhs rhs : Ty}
    (hSubtype : lhs.kernelSubtypeb rhs = true) :
    ∀ tag : KernelTag, Ty.denotesTag tag lhs -> Ty.denotesTag tag rhs := by
  exact kernel_subtypeIn_implies_tag_subtype (Ty.kernelSubtypeb_sound hSubtype)

theorem kernel_rc_ptr_tag
    (tag : KernelTag)
    (inner : Ty) :
    Ty.denotesTag tag (Ty.rc inner) ->
      Ty.denotesTag tag (Ty.ptr inner) := by
  intro hRc
  exact kernel_rc_subtype_ptr inner (KernelTag.valuation tag) (KernelTag.soundValuation tag) hRc

theorem kernel_ptr_covariant_tag
    (tag : KernelTag)
    (inner₁ inner₂ : Ty)
    (hSubtype : inner₁.SubtypeIn KernelTheory.theory inner₂) :
    Ty.denotesTag tag (Ty.ptr inner₁) ->
      Ty.denotesTag tag (Ty.ptr inner₂) := by
  intro hPtr
  cases tag <;> simp [Ty.denotesTag, Ty.denotesUnder, KernelTag.valuation, TyAtom.denotesTag] at hPtr ⊢
  case ptr kind innerTag =>
    exact Ty.subtypeIn_trans hPtr hSubtype

theorem kernel_rc_covariant_tag
    (tag : KernelTag)
    (inner₁ inner₂ : Ty)
    (hSubtype : inner₁.SubtypeIn KernelTheory.theory inner₂) :
    Ty.denotesTag tag (Ty.rc inner₁) ->
      Ty.denotesTag tag (Ty.rc inner₂) := by
  intro hRc
  cases tag <;> simp [Ty.denotesTag, Ty.denotesUnder, KernelTag.valuation, TyAtom.denotesTag] at hRc ⊢
  case ptr kind innerTag =>
    cases kind <;> simp at hRc ⊢
    case rc =>
      exact Ty.subtypeIn_trans hRc hSubtype

theorem kernel_fn_effect_subset_tag
    (tag : KernelTag)
    (arg ret : Ty)
    (eff eff' : EffectSet)
    (hSubset : EffectSet.subset eff eff') :
    Ty.denotesTag tag (Ty.fn arg eff ret) ->
      Ty.denotesTag tag (Ty.fn arg eff' ret) := by
  intro hFn
  exact kernel_fn_effect_subset_subtype arg ret eff eff' hSubset
    (KernelTag.valuation tag) (KernelTag.soundValuation tag) hFn

theorem kernel_fn_subtype_tag
    (tag : KernelTag)
    (arg₁ ret₁ arg₂ ret₂ : Ty)
    (eff₁ eff₂ : EffectSet)
    (hArg : arg₂.SubtypeIn KernelTheory.theory arg₁)
    (hEff : EffectSet.subset eff₁ eff₂)
    (hRet : ret₁.SubtypeIn KernelTheory.theory ret₂) :
    Ty.denotesTag tag (Ty.fn arg₁ eff₁ ret₁) ->
      Ty.denotesTag tag (Ty.fn arg₂ eff₂ ret₂) := by
  intro hFn
  cases tag <;> simp [Ty.denotesTag, Ty.denotesUnder, KernelTag.valuation, TyAtom.denotesTag] at hFn ⊢
  case fn argTag effTag retTag =>
    rcases hFn with ⟨hArgTag, hEffTag, hRetTag⟩
    exact ⟨Ty.subtypeIn_trans hArg hArgTag, EffectSet.subset_trans hEffTag hEff, Ty.subtypeIn_trans hRetTag hRet⟩

theorem kernel_mptr_ptr_tag
    (tag : KernelTag)
    (inner : Ty) :
    Ty.denotesTag tag (Ty.mptr inner) ->
      Ty.denotesTag tag (Ty.ptr inner) := by
  intro hMPtr
  exact kernel_mptr_subtype_ptr inner (KernelTag.valuation tag) (KernelTag.soundValuation tag) hMPtr

theorem kernel_rc_ptr_runtime
    (inner : Ty) :
    Ty.denotesTag (.ptr .rc inner) (Ty.ptr inner) := by
  simp [Ty.denotesTag, Ty.denotesUnder, KernelTag.valuation, TyAtom.denotesTag, Ty.subtypeIn_refl]

theorem kernel_pure_fn_tag
    (tag : KernelTag)
    (arg ret : Ty)
    (effects : EffectSet) :
    Ty.denotesTag tag (Ty.fn arg Weft.EffectSet.empty ret) ->
      Ty.denotesTag tag (Ty.fn arg effects ret) := by
  intro hFn
  exact kernel_fn_subtype_tag tag arg ret arg ret Weft.EffectSet.empty effects
    (Ty.subtypeIn_refl KernelTheory.theory arg)
    (Weft.EffectSet.subset_empty effects)
    (Ty.subtypeIn_refl KernelTheory.theory ret)
    hFn

theorem kernel_rc_mptr_empty_tag
    (tag : KernelTag)
    (rcInner mptrInner : Ty) :
    ¬ Ty.denotesTag tag (Ty.inter (Ty.rc rcInner) (Ty.mptr mptrInner)) := by
  intro hDen
  have hNorm :
      TyDNF.denotes (KernelTag.valuation tag)
        (Ty.normalizeTyDNF (Ty.inter (Ty.rc rcInner) (Ty.mptr mptrInner))) :=
    (Ty.normalizeTyDNF_spec (KernelTag.valuation tag)
      (Ty.inter (Ty.rc rcInner) (Ty.mptr mptrInner))).2 hDen
  exact TyDNF.unsat_sound (KernelTag.soundValuation tag)
    (kernel_rc_mptr_inter_unsat rcInner mptrInner) hNorm

theorem kernel_rc_runtime
    (inner : Ty) :
    Ty.denotesTag (.ptr .rc inner) (Ty.rc inner) := by
  simp [Ty.denotesTag, Ty.denotesUnder, KernelTag.valuation, TyAtom.denotesTag, Ty.subtypeIn_refl]

theorem kernel_pure_fn_runtime
    (arg ret : Ty)
    (effects : EffectSet) :
    Ty.denotesTag (.fn arg Weft.EffectSet.empty ret) (Ty.fn arg effects ret) := by
  simp [Ty.denotesTag, Ty.denotesUnder, KernelTag.valuation, TyAtom.denotesTag,
    Weft.EffectSet.subset_empty, Ty.subtypeIn_refl]

theorem kernel_mptr_ptr_runtime
    (inner : Ty) :
    Ty.denotesTag (.ptr .mut inner) (Ty.ptr inner) := by
  simp [Ty.denotesTag, Ty.denotesUnder, KernelTag.valuation, TyAtom.denotesTag, Ty.subtypeIn_refl]

theorem kernel_mptr_runtime
    (inner : Ty) :
    Ty.denotesTag (.ptr .mut inner) (Ty.mptr inner) := by
  simp [Ty.denotesTag, Ty.denotesUnder, KernelTag.valuation, TyAtom.denotesTag]

end Weft
