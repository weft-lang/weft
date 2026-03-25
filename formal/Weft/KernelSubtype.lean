import Weft.Properties.TyTheorySoundness

namespace Weft

namespace TyClause

theorem kernelDisjoint_symm
    {lhs rhs : TyAtom}
    (hDisjoint : KernelTheory.Disjoint lhs rhs) :
    KernelTheory.Disjoint rhs lhs := by
  cases lhs <;> cases rhs <;> simp [KernelTheory.Disjoint] at hDisjoint ⊢

def anyDisjointWith (lhs : TyAtom) : List TyAtom -> Bool
  | [] => false
  | rhs :: rest => KernelTheory.disjointb lhs rhs || anyDisjointWith lhs rest

def hasDisjointPosPairb : List TyAtom -> Bool
  | [] => false
  | lhs :: rest => anyDisjointWith lhs (lhs :: rest) || hasDisjointPosPairb rest

def anyImpliesNeg (pos : List TyAtom) : List TyAtom -> Bool
  | [] => false
  | rhs :: rest =>
      pos.any (fun lhs => KernelTheory.impliesb lhs rhs) || anyImpliesNeg pos rest

def kernelUnsatb (clause : TyClause) : Bool :=
  hasDisjointPosPairb clause.pos || anyImpliesNeg clause.pos clause.neg

theorem anyDisjointWith_spec
    (lhs : TyAtom)
    (atoms : List TyAtom) :
    anyDisjointWith lhs atoms = true ↔
      ∃ rhs, rhs ∈ atoms ∧ KernelTheory.Disjoint lhs rhs := by
  induction atoms with
  | nil =>
      simp [anyDisjointWith]
  | cons rhs rest ih =>
      simp [anyDisjointWith, KernelTheory.disjointb_spec, ih]

theorem hasDisjointPosPairb_spec
    (atoms : List TyAtom) :
    hasDisjointPosPairb atoms = true ↔
      ∃ lhs, lhs ∈ atoms ∧ ∃ rhs, rhs ∈ atoms ∧ KernelTheory.Disjoint lhs rhs := by
  induction atoms with
  | nil =>
      simp [hasDisjointPosPairb]
  | cons lhs rest ih =>
      constructor
      · intro h
        simp [hasDisjointPosPairb] at h
        rcases h with hHead | hTail
        · rcases (anyDisjointWith_spec lhs (lhs :: rest)).1 hHead with ⟨rhs, hMem, hDisjoint⟩
          exact ⟨lhs, List.mem_cons.mpr (Or.inl rfl), rhs, hMem, hDisjoint⟩
        · rcases ih.1 hTail with ⟨lhs', hMemL, rhs, hMemR, hDisjoint⟩
          exact ⟨lhs', List.mem_cons_of_mem _ hMemL, rhs, List.mem_cons_of_mem _ hMemR, hDisjoint⟩
      · rintro ⟨lhs, hMemL, rhs, hMemR, hDisjoint⟩
        simp [hasDisjointPosPairb]
        rcases List.mem_cons.mp hMemL with rfl | hMemTail
        · left
          exact (anyDisjointWith_spec lhs (lhs :: rest)).2 ⟨rhs, hMemR, hDisjoint⟩
        · rcases List.mem_cons.mp hMemR with hEq | hMemRTail
          · left
            subst hEq
            exact (anyDisjointWith_spec _ (_ :: _)).2
              ⟨lhs, List.mem_cons_of_mem _ hMemTail, kernelDisjoint_symm hDisjoint⟩
          · right
            exact ih.2 ⟨lhs, hMemTail, rhs, hMemRTail, hDisjoint⟩

theorem anyImpliesNeg_spec
    (pos neg : List TyAtom) :
    anyImpliesNeg pos neg = true ↔
      ∃ lhs, lhs ∈ pos ∧ ∃ rhs, rhs ∈ neg ∧ KernelTheory.Implies lhs rhs := by
  induction neg with
  | nil =>
      simp [anyImpliesNeg]
  | cons rhs rest ih =>
      constructor
      · intro h
        simp [anyImpliesNeg, List.any_eq_true, KernelTheory.impliesb_spec] at h
        rcases h with hHead | hTail
        · rcases hHead with ⟨lhs, hMem, hImplies⟩
          exact ⟨lhs, hMem, rhs, List.mem_cons.mpr (Or.inl rfl), hImplies⟩
        · rcases ih.1 hTail with ⟨lhs, hMem, rhs', hMemR, hImplies⟩
          exact ⟨lhs, hMem, rhs', List.mem_cons.mpr (Or.inr hMemR), hImplies⟩
      · rintro ⟨lhs, hMem, rhs', hMemR, hImplies⟩
        simp [anyImpliesNeg, List.any_eq_true, KernelTheory.impliesb_spec]
        rcases List.mem_cons.mp hMemR with rfl | hMemRTail
        · exact Or.inl ⟨lhs, hMem, hImplies⟩
        · exact Or.inr ((ih).2 ⟨lhs, hMem, rhs', hMemRTail, hImplies⟩)

theorem kernelUnsatb_spec
    (clause : TyClause) :
    clause.kernelUnsatb = true ↔ clause.Unsat KernelTheory.theory := by
  simpa [kernelUnsatb, TyClause.Unsat, KernelTheory.theory] using
    (show hasDisjointPosPairb clause.pos = true ∨ anyImpliesNeg clause.pos clause.neg = true ↔
      clause.Unsat KernelTheory.theory by
        simp [hasDisjointPosPairb_spec, anyImpliesNeg_spec, TyClause.Unsat, KernelTheory.theory])

end TyClause

namespace TyDNF

def kernelUnsatb : TyDNF -> Bool
  | [] => true
  | clause :: rest => clause.kernelUnsatb && kernelUnsatb rest

theorem kernelUnsatb_spec
    (dnf : TyDNF) :
    dnf.kernelUnsatb = true ↔ dnf.Unsat KernelTheory.theory := by
  induction dnf with
  | nil =>
      simp [kernelUnsatb, TyDNF.Unsat]
  | cons clause rest ih =>
      constructor
      · intro h clause' hMem
        simp [kernelUnsatb] at h
        rcases List.mem_cons.mp hMem with rfl | hMemRest
        · exact (TyClause.kernelUnsatb_spec _).1 h.1
        · exact (ih.1 h.2) clause' hMemRest
      · intro h
        have hClause : clause.kernelUnsatb = true :=
          (TyClause.kernelUnsatb_spec clause).2 (h clause (List.mem_cons.mpr (Or.inl rfl)))
        have hRest : kernelUnsatb rest = true :=
          (ih).2 (fun clause' hMem => h clause' (List.mem_cons.mpr (Or.inr hMem)))
        simpa [kernelUnsatb, Bool.and_eq_true] using And.intro hClause hRest

end TyDNF

namespace Ty

def kernelSubtypeb (lhs rhs : Ty) : Bool :=
  (Ty.normalizeTyDNF (Ty.inter lhs (Ty.compl rhs))).kernelUnsatb

theorem kernelSubtypeb_spec
    (lhs rhs : Ty) :
    lhs.kernelSubtypeb rhs = true ↔
      (Ty.normalizeTyDNF (Ty.inter lhs (Ty.compl rhs))).Unsat KernelTheory.theory := by
  simp [kernelSubtypeb, TyDNF.kernelUnsatb_spec]

theorem kernelSubtypeb_sound
    {lhs rhs : Ty}
    (hSubtype : lhs.kernelSubtypeb rhs = true) :
    lhs.SubtypeIn KernelTheory.theory rhs := by
  exact Ty.unsat_normalize_implies_subtypeIn ((kernelSubtypeb_spec lhs rhs).1 hSubtype)

theorem kernelSubtypeb_rc_ptr
    (inner : Ty) :
    (Ty.rc inner).kernelSubtypeb (Ty.ptr inner) = true := by
  exact (kernelSubtypeb_spec (Ty.rc inner) (Ty.ptr inner)).2
    (kernel_rc_ptr_diff_unsat inner)

theorem kernelSubtypeb_fn_effect_subset
    (arg ret : Ty)
    (eff eff' : EffectSet)
    (hSubset : EffectSet.subset eff eff') :
    (Ty.fn arg eff ret).kernelSubtypeb (Ty.fn arg eff' ret) = true := by
  exact (kernelSubtypeb_spec (Ty.fn arg eff ret) (Ty.fn arg eff' ret)).2
    (kernel_fn_effect_subset_diff_unsat arg ret eff eff' hSubset)

theorem kernelSubtypeb_pure_fn_effectful
    (arg ret : Ty)
    (effects : EffectSet) :
    (Ty.fn arg Weft.EffectSet.empty ret).kernelSubtypeb (Ty.fn arg effects ret) = true := by
  exact kernelSubtypeb_fn_effect_subset arg ret Weft.EffectSet.empty effects
    (Weft.EffectSet.subset_empty effects)

theorem kernelSubtypeb_mptr_ptr
    (inner : Ty) :
    (Ty.mptr inner).kernelSubtypeb (Ty.ptr inner) = true := by
  exact (kernelSubtypeb_spec (Ty.mptr inner) (Ty.ptr inner)).2
    (kernel_mptr_ptr_diff_unsat inner)

theorem kernelUnsatb_rc_mptr_inter
    (rcInner mptrInner : Ty) :
    (Ty.normalizeTyDNF (Ty.inter (Ty.rc rcInner) (Ty.mptr mptrInner))).kernelUnsatb = true := by
  exact (TyDNF.kernelUnsatb_spec
    (Ty.normalizeTyDNF (Ty.inter (Ty.rc rcInner) (Ty.mptr mptrInner)))).2
      (kernel_rc_mptr_inter_unsat rcInner mptrInner)

end Ty

end Weft
