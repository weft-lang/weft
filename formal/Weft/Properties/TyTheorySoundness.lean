import Weft.TyTheory
import Weft.Properties.TyDNFSoundness

namespace Weft

theorem TyClause.unsat_sound
    {theory : TyTheory}
    {ν : TyAtom -> Prop}
    (hSound : theory.SoundValuation ν)
    {clause : TyClause}
    (hUnsat : clause.Unsat theory) :
    ¬ clause.denotes ν := by
  intro hDen
  cases hUnsat with
  | inl hDis =>
      rcases hDis with ⟨lhs, hLhs, rhs, hRhs, hDisjoint⟩
      exact hSound.disjoint_sound hDisjoint ⟨hDen.1 lhs hLhs, hDen.1 rhs hRhs⟩
  | inr hImp =>
      rcases hImp with ⟨lhs, hLhs, rhs, hRhs, hImplies⟩
      exact (hDen.2 rhs hRhs) (hSound.implies_sound hImplies (hDen.1 lhs hLhs))

theorem TyDNF.unsat_sound
    {theory : TyTheory}
    {ν : TyAtom -> Prop}
    (hSound : theory.SoundValuation ν)
    {dnf : TyDNF}
    (hUnsat : dnf.Unsat theory) :
    ¬ TyDNF.denotes ν dnf := by
  intro hDen
  induction dnf with
  | nil =>
      cases hDen
  | cons clause rest ih =>
      cases hDen with
      | inl hClause =>
          exact TyClause.unsat_sound hSound (hUnsat clause (by simp)) hClause
      | inr hRest =>
          exact ih (fun clause' hMem => hUnsat clause' (by simp [hMem])) hRest

theorem Ty.unsat_normalize_implies_subtypeIn
    {theory : TyTheory}
    {lhs rhs : Ty}
    (hUnsat : (Ty.normalizeTyDNF (Ty.inter lhs (Ty.compl rhs))).Unsat theory) :
    lhs.SubtypeIn theory rhs := by
  intro ν hSound hLhs
  by_cases hRhs : rhs.denotesUnder ν
  · exact hRhs
  · have hDiff : TyDNF.denotes ν (Ty.normalizeTyDNF (Ty.inter lhs (Ty.compl rhs))) :=
      (Ty.normalizeTyDNF_spec ν (Ty.inter lhs (Ty.compl rhs))).2 (by
        simpa [Ty.denotesUnder] using And.intro hLhs hRhs)
    exact False.elim (TyDNF.unsat_sound hSound hUnsat hDiff)

theorem kernel_bool_int_inter_unsat :
    (Ty.normalizeTyDNF (Ty.inter Ty.bool Ty.int)).Unsat KernelTheory.theory := by
  intro clause hMem
  have hClause : clause = { pos := [TyAtom.bool, TyAtom.int], neg := [] } := by
    simpa [Ty.normalizeTyDNF, TyDNF.inter, TyDNF.interWith, TyDNF.ofAtom,
      TyClause.ofPos, TyClause.merge] using hMem
  subst clause
  refine Or.inl ⟨TyAtom.bool, by simp, TyAtom.int, by simp, ?_⟩
  change True
  trivial

theorem kernel_rc_ptr_diff_unsat
    (inner : Ty) :
    (Ty.normalizeTyDNF (Ty.inter (Ty.rc inner) (Ty.compl (Ty.ptr inner)))).Unsat KernelTheory.theory := by
  intro clause hMem
  have hClause : clause = { pos := [TyAtom.rc inner], neg := [TyAtom.ptr inner] } := by
    simpa [Ty.normalizeTyDNF, TyDNF.inter, TyDNF.interWith, TyDNF.ofAtom, TyDNF.compl,
      TyDNF.complClause, TyDNF.top, TyClause.ofPos, TyClause.ofNeg, TyClause.merge,
      TyClause.top] using hMem
  subst clause
  refine Or.inr ⟨TyAtom.rc inner, by simp, TyAtom.ptr inner, by simp, ?_⟩
  change inner = inner
  rfl

theorem kernel_mptr_ptr_diff_unsat
    (inner : Ty) :
    (Ty.normalizeTyDNF (Ty.inter (Ty.mptr inner) (Ty.compl (Ty.ptr inner)))).Unsat KernelTheory.theory := by
  intro clause hMem
  have hClause : clause = { pos := [TyAtom.mptr inner], neg := [TyAtom.ptr inner] } := by
    simpa [Ty.normalizeTyDNF, TyDNF.inter, TyDNF.interWith, TyDNF.ofAtom, TyDNF.compl,
      TyDNF.complClause, TyDNF.top, TyClause.ofPos, TyClause.ofNeg, TyClause.merge,
      TyClause.top] using hMem
  subst clause
  refine Or.inr ⟨TyAtom.mptr inner, by simp, TyAtom.ptr inner, by simp, ?_⟩
  change inner = inner
  rfl

theorem kernel_rc_subtype_ptr
    (inner : Ty) :
    (Ty.rc inner).SubtypeIn KernelTheory.theory (Ty.ptr inner) := by
  exact Ty.unsat_normalize_implies_subtypeIn (kernel_rc_ptr_diff_unsat inner)

theorem kernel_mptr_subtype_ptr
    (inner : Ty) :
    (Ty.mptr inner).SubtypeIn KernelTheory.theory (Ty.ptr inner) := by
  exact Ty.unsat_normalize_implies_subtypeIn (kernel_mptr_ptr_diff_unsat inner)

end Weft
