import Weft.Properties.TyTheorySoundness

namespace Weft

namespace TyClause

noncomputable def kernelUnsatb (clause : TyClause) : Bool := by
  classical
  exact decide (clause.Unsat KernelTheory.theory)

theorem kernelUnsatb_spec
    (clause : TyClause) :
    clause.kernelUnsatb = true ↔ clause.Unsat KernelTheory.theory := by
  classical
  simp [kernelUnsatb]

end TyClause

namespace TyDNF

noncomputable def kernelUnsatb (dnf : TyDNF) : Bool := by
  classical
  exact decide (dnf.Unsat KernelTheory.theory)

theorem kernelUnsatb_spec
    (dnf : TyDNF) :
    dnf.kernelUnsatb = true ↔ dnf.Unsat KernelTheory.theory := by
  classical
  simp [kernelUnsatb]

end TyDNF

namespace Ty

noncomputable def kernelSubtypeb (lhs rhs : Ty) : Bool := by
  classical
  exact decide ((Ty.normalizeTyDNF (Ty.inter lhs (Ty.compl rhs))).Unsat KernelTheory.theory)

theorem kernelSubtypeb_spec
    (lhs rhs : Ty) :
    lhs.kernelSubtypeb rhs = true ↔
      (Ty.normalizeTyDNF (Ty.inter lhs (Ty.compl rhs))).Unsat KernelTheory.theory := by
  classical
  simp [kernelSubtypeb]

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
