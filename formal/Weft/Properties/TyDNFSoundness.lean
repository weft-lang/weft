import Weft.TyDNF

namespace Weft

private theorem and_or_distrib_left {A B C : Prop} :
    (A ∧ B) ∨ (A ∧ C) ↔ A ∧ (B ∨ C) := by
  constructor
  · intro h
    cases h with
    | inl hAB => exact ⟨hAB.1, .inl hAB.2⟩
    | inr hAC => exact ⟨hAC.1, .inr hAC.2⟩
  · intro h
    cases h.2 with
    | inl hB => exact .inl ⟨h.1, hB⟩
    | inr hC => exact .inr ⟨h.1, hC⟩

private theorem or_and_distrib_right {A B C : Prop} :
    (A ∧ C) ∨ (B ∧ C) ↔ (A ∨ B) ∧ C := by
  constructor
  · intro h
    cases h with
    | inl hAC => exact ⟨.inl hAC.1, hAC.2⟩
    | inr hBC => exact ⟨.inr hBC.1, hBC.2⟩
  · intro h
    cases h.1 with
    | inl hA => exact .inl ⟨hA, h.2⟩
    | inr hB => exact .inr ⟨hB, h.2⟩

private theorem exists_mem_of_not_forall_mem
    {α : Type}
    {xs : List α}
    {P : α -> Prop}
    (hNot : ¬ (∀ x, x ∈ xs -> P x)) :
    ∃ x, x ∈ xs ∧ ¬ P x := by
  classical
  by_cases hExists : ∃ x, x ∈ xs ∧ ¬ P x
  · exact hExists
  · exact False.elim (hNot (by
      intro x hx
      by_cases hPx : P x
      · exact hPx
      · exact False.elim (hExists ⟨x, hx, hPx⟩)))

@[simp] theorem TyAtom.toTy_spec
    (ν : TyAtom -> Prop)
    (atom : TyAtom) :
    atom.toTy.denotesUnder ν ↔ ν atom := by
  cases atom <;> simp [TyAtom.toTy, Ty.denotesUnder]

theorem TyClause.posTy_spec
    (ν : TyAtom -> Prop)
    (atoms : List TyAtom) :
    (TyClause.posTy atoms).denotesUnder ν ↔
      ∀ atom, atom ∈ atoms -> ν atom := by
  induction atoms with
  | nil =>
      simp [TyClause.posTy, Ty.denotesUnder]
  | cons atom rest ih =>
      simp [TyClause.posTy, Ty.denotesUnder, ih, List.mem_cons]

theorem TyClause.negTy_spec
    (ν : TyAtom -> Prop)
    (atoms : List TyAtom) :
    (TyClause.negTy atoms).denotesUnder ν ↔
      ∀ atom, atom ∈ atoms -> ¬ ν atom := by
  induction atoms with
  | nil =>
      simp [TyClause.negTy, Ty.denotesUnder]
  | cons atom rest ih =>
      simp [TyClause.negTy, Ty.denotesUnder, ih, List.mem_cons]

theorem TyClause.toTy_spec
    (ν : TyAtom -> Prop)
    (clause : TyClause) :
    clause.toTy.denotesUnder ν ↔ clause.denotes ν := by
  simp [TyClause.toTy, TyClause.denotes, Ty.denotesUnder,
    TyClause.posTy_spec, TyClause.negTy_spec]

theorem TyClause.merge_spec
    (ν : TyAtom -> Prop)
    (lhs rhs : TyClause) :
    (lhs.merge rhs).denotes ν ↔ lhs.denotes ν ∧ rhs.denotes ν := by
  constructor
  · intro h
    refine ⟨?_, ?_⟩
    · exact ⟨
        (fun atom hMem => h.1 atom (List.mem_append.mpr (.inl hMem))),
        (fun atom hMem => h.2 atom (List.mem_append.mpr (.inl hMem)))⟩
    · exact ⟨
        (fun atom hMem => h.1 atom (List.mem_append.mpr (.inr hMem))),
        (fun atom hMem => h.2 atom (List.mem_append.mpr (.inr hMem)))⟩
  · rintro ⟨hL, hR⟩
    refine ⟨?_, ?_⟩
    · intro atom hMem
      rcases List.mem_append.mp hMem with hMemL | hMemR
      · exact hL.1 atom hMemL
      · exact hR.1 atom hMemR
    · intro atom hMem
      rcases List.mem_append.mp hMem with hMemL | hMemR
      · exact hL.2 atom hMemL
      · exact hR.2 atom hMemR

theorem TyDNF.ofAtom_spec
    (ν : TyAtom -> Prop)
    (atom : TyAtom) :
    TyDNF.denotes ν (TyDNF.ofAtom atom) ↔ ν atom := by
  simp [TyDNF.ofAtom, TyDNF.denotes, TyClause.ofPos, TyClause.denotes]

theorem TyDNF.append_spec
    (ν : TyAtom -> Prop)
    (lhs rhs : TyDNF) :
    TyDNF.denotes ν (lhs ++ rhs) ↔ TyDNF.denotes ν lhs ∨ TyDNF.denotes ν rhs := by
  induction lhs with
  | nil =>
      simp [TyDNF.denotes]
  | cons clause rest ih =>
      simp [TyDNF.denotes, ih, or_assoc]

theorem TyDNF.interWith_spec
    (ν : TyAtom -> Prop)
    (clause : TyClause)
    (rhs : TyDNF) :
    TyDNF.denotes ν (TyDNF.interWith clause rhs) ↔
      clause.denotes ν ∧ TyDNF.denotes ν rhs := by
  induction rhs with
  | nil =>
      simp [TyDNF.interWith, TyDNF.denotes]
  | cons other rest ih =>
      calc
        TyDNF.denotes ν (TyDNF.interWith clause (other :: rest))
            ↔ (clause.merge other).denotes ν ∨ TyDNF.denotes ν (TyDNF.interWith clause rest) := by
                simp [TyDNF.interWith, TyDNF.denotes]
        _ ↔ (clause.denotes ν ∧ other.denotes ν) ∨
              (clause.denotes ν ∧ TyDNF.denotes ν rest) := by
                simp [TyClause.merge_spec, ih]
        _ ↔ clause.denotes ν ∧ (other.denotes ν ∨ TyDNF.denotes ν rest) := and_or_distrib_left
        _ ↔ clause.denotes ν ∧ TyDNF.denotes ν (other :: rest) := by
                simp [TyDNF.denotes]

theorem TyDNF.inter_spec
    (ν : TyAtom -> Prop)
    (lhs rhs : TyDNF) :
    TyDNF.denotes ν (TyDNF.inter lhs rhs) ↔
      TyDNF.denotes ν lhs ∧ TyDNF.denotes ν rhs := by
  induction lhs with
  | nil =>
      simp [TyDNF.inter, TyDNF.denotes]
  | cons clause rest ih =>
      calc
        TyDNF.denotes ν (TyDNF.inter (clause :: rest) rhs)
            ↔ TyDNF.denotes ν (TyDNF.interWith clause rhs ++ TyDNF.inter rest rhs) := by
                rfl
        _ ↔ TyDNF.denotes ν (TyDNF.interWith clause rhs) ∨ TyDNF.denotes ν (TyDNF.inter rest rhs) := by
                exact TyDNF.append_spec ν _ _
        _ ↔ (clause.denotes ν ∧ TyDNF.denotes ν rhs) ∨
              (TyDNF.denotes ν rest ∧ TyDNF.denotes ν rhs) := by
                simp [TyDNF.interWith_spec, ih]
        _ ↔ (clause.denotes ν ∨ TyDNF.denotes ν rest) ∧ TyDNF.denotes ν rhs := or_and_distrib_right
        _ ↔ TyDNF.denotes ν (clause :: rest) ∧ TyDNF.denotes ν rhs := by
                simp [TyDNF.denotes]

theorem TyDNF.map_ofNeg_spec
    (ν : TyAtom -> Prop)
    (atoms : List TyAtom) :
    TyDNF.denotes ν (atoms.map TyClause.ofNeg) ↔
      ∃ atom, atom ∈ atoms ∧ ¬ ν atom := by
  induction atoms with
  | nil =>
      simp [TyDNF.denotes]
  | cons atom rest ih =>
      simp [TyDNF.denotes, TyClause.ofNeg, TyClause.denotes, ih]

theorem TyDNF.map_ofPos_spec
    (ν : TyAtom -> Prop)
    (atoms : List TyAtom) :
    TyDNF.denotes ν (atoms.map TyClause.ofPos) ↔
      ∃ atom, atom ∈ atoms ∧ ν atom := by
  induction atoms with
  | nil =>
      simp [TyDNF.denotes]
  | cons atom rest ih =>
      simp [TyDNF.denotes, TyClause.ofPos, TyClause.denotes, ih]

theorem TyDNF.complClause_spec
    (ν : TyAtom -> Prop)
    (clause : TyClause) :
    TyDNF.denotes ν (TyDNF.complClause clause) ↔ ¬ clause.denotes ν := by
  constructor
  · intro hComp hDen
    have hParts :
        (∃ atom, atom ∈ clause.pos ∧ ¬ ν atom) ∨
          ∃ atom, atom ∈ clause.neg ∧ ν atom := by
      simpa [TyDNF.complClause, TyDNF.append_spec, TyDNF.map_ofNeg_spec, TyDNF.map_ofPos_spec] using hComp
    cases hParts with
    | inl hPos =>
        rcases hPos with ⟨atom, hMem, hNot⟩
        exact hNot (hDen.1 atom hMem)
    | inr hNeg =>
        rcases hNeg with ⟨atom, hMem, hVal⟩
        exact (hDen.2 atom hMem) hVal
  · intro hNot
    classical
    by_cases hPos : ∀ atom, atom ∈ clause.pos -> ν atom
    · by_cases hNeg : ∀ atom, atom ∈ clause.neg -> ¬ ν atom
      · exact False.elim (hNot ⟨hPos, hNeg⟩)
      · rcases exists_mem_of_not_forall_mem hNeg with ⟨atom, hMem, hPosVal⟩
        have : ∃ atom, atom ∈ clause.neg ∧ ν atom := ⟨atom, hMem, by simpa using hPosVal⟩
        simpa [TyDNF.complClause, TyDNF.append_spec, TyDNF.map_ofNeg_spec, TyDNF.map_ofPos_spec] using Or.inr this
    · rcases exists_mem_of_not_forall_mem hPos with ⟨atom, hMem, hNegVal⟩
      have : ∃ atom, atom ∈ clause.pos ∧ ¬ ν atom := ⟨atom, hMem, by simpa using hNegVal⟩
      simpa [TyDNF.complClause, TyDNF.append_spec, TyDNF.map_ofNeg_spec, TyDNF.map_ofPos_spec] using Or.inl this

theorem TyDNF.compl_spec
    (ν : TyAtom -> Prop)
    (dnf : TyDNF) :
    TyDNF.denotes ν (TyDNF.compl dnf) ↔ ¬ TyDNF.denotes ν dnf := by
  induction dnf with
  | nil =>
      simp [TyDNF.compl, TyDNF.top, TyDNF.denotes, TyClause.top, TyClause.denotes]
  | cons clause rest ih =>
      calc
        TyDNF.denotes ν (TyDNF.compl (clause :: rest))
            ↔ TyDNF.denotes ν (TyDNF.inter (TyDNF.complClause clause) (TyDNF.compl rest)) := by
                rfl
        _ ↔ TyDNF.denotes ν (TyDNF.complClause clause) ∧ TyDNF.denotes ν (TyDNF.compl rest) := TyDNF.inter_spec ν _ _
        _ ↔ ¬ clause.denotes ν ∧ ¬ TyDNF.denotes ν rest := by
                simp [TyDNF.complClause_spec, ih]
        _ ↔ ¬ (clause.denotes ν ∨ TyDNF.denotes ν rest) := by
                simp
        _ ↔ ¬ TyDNF.denotes ν (clause :: rest) := by
                simp [TyDNF.denotes]

theorem TyDNF.toTy_spec
    (ν : TyAtom -> Prop)
    (dnf : TyDNF) :
    dnf.toTy.denotesUnder ν ↔ TyDNF.denotes ν dnf := by
  induction dnf with
  | nil =>
      simp [TyDNF.toTy, TyDNF.denotes, Ty.denotesUnder]
  | cons clause rest ih =>
      simp [TyDNF.toTy, TyDNF.denotes, Ty.denotesUnder, TyClause.toTy_spec, ih]

theorem Ty.normalizeTyDNF_spec
    (ν : TyAtom -> Prop) :
    (ty : Ty) -> TyDNF.denotes ν ty.normalizeTyDNF ↔ ty.denotesUnder ν
  | .bool =>
      by simpa [Ty.normalizeTyDNF, Ty.denotesUnder] using TyDNF.ofAtom_spec ν TyAtom.bool
  | .int =>
      by simpa [Ty.normalizeTyDNF, Ty.denotesUnder] using TyDNF.ofAtom_spec ν TyAtom.int
  | .nil =>
      by simpa [Ty.normalizeTyDNF, Ty.denotesUnder] using TyDNF.ofAtom_spec ν TyAtom.nil
  | .never =>
      by simp [Ty.normalizeTyDNF, TyDNF.denotes, Ty.denotesUnder]
  | .any =>
      by simp [Ty.normalizeTyDNF, TyDNF.top, TyDNF.denotes, TyClause.top, TyClause.denotes, Ty.denotesUnder]
  | .union lhs rhs =>
      by simp [Ty.normalizeTyDNF, TyDNF.union, TyDNF.append_spec, Ty.denotesUnder,
          Ty.normalizeTyDNF_spec ν lhs, Ty.normalizeTyDNF_spec ν rhs]
  | .inter lhs rhs =>
      by simp [Ty.normalizeTyDNF, TyDNF.inter_spec, Ty.denotesUnder,
          Ty.normalizeTyDNF_spec ν lhs, Ty.normalizeTyDNF_spec ν rhs]
  | .compl inner =>
      by simp [Ty.normalizeTyDNF, TyDNF.compl_spec, Ty.denotesUnder, Ty.normalizeTyDNF_spec ν inner]
  | .fn arg eff ret =>
      by simpa [Ty.normalizeTyDNF, Ty.denotesUnder] using TyDNF.ofAtom_spec ν (.fn arg eff ret)
  | .record fields =>
      by simpa [Ty.normalizeTyDNF, Ty.denotesUnder] using TyDNF.ofAtom_spec ν (.record fields)
  | .ptr inner =>
      by simpa [Ty.normalizeTyDNF, Ty.denotesUnder] using TyDNF.ofAtom_spec ν (.ptr inner)
  | .mptr inner =>
      by simpa [Ty.normalizeTyDNF, Ty.denotesUnder] using TyDNF.ofAtom_spec ν (.mptr inner)
  | .rc inner =>
      by simpa [Ty.normalizeTyDNF, Ty.denotesUnder] using TyDNF.ofAtom_spec ν (.rc inner)
  | .nominal name args =>
      by simpa [Ty.normalizeTyDNF, Ty.denotesUnder] using TyDNF.ofAtom_spec ν (.nominal name args)

theorem Ty.normalizeTyDNF_roundtrip
    (ν : TyAtom -> Prop)
    (dnf : TyDNF) :
    TyDNF.denotes ν dnf.toTy.normalizeTyDNF ↔ TyDNF.denotes ν dnf := by
  rw [Ty.normalizeTyDNF_spec, TyDNF.toTy_spec]

theorem Ty.normalizeTyDNF_idempotent_semantics
    (ν : TyAtom -> Prop)
    (ty : Ty) :
    TyDNF.denotes ν ty.normalizeTyDNF.toTy.normalizeTyDNF ↔
      TyDNF.denotes ν ty.normalizeTyDNF := by
  exact Ty.normalizeTyDNF_roundtrip ν ty.normalizeTyDNF

theorem Ty.subtypeUnder_iff_unsat_normalizeTyDNF_diff
    (lhs rhs : Ty) :
    lhs.SubtypeUnder rhs ↔
      ∀ ν : TyAtom -> Prop,
        ¬ TyDNF.denotes ν (Ty.normalizeTyDNF (Ty.inter lhs (Ty.compl rhs))) := by
  constructor
  · intro hSubtype
    intro ν hDiff
    have hDiffTy : (Ty.inter lhs (Ty.compl rhs)).denotesUnder ν :=
      (Ty.normalizeTyDNF_spec ν (Ty.inter lhs (Ty.compl rhs))).1 hDiff
    have hParts : lhs.denotesUnder ν ∧ ¬ rhs.denotesUnder ν := by
      simpa [Ty.denotesUnder] using hDiffTy
    exact hParts.2 (hSubtype ν hParts.1)
  · intro hEmpty ν hLhs
    by_cases hRhs : rhs.denotesUnder ν
    · exact hRhs
    · have hNoDiff : ¬ TyDNF.denotes ν (Ty.normalizeTyDNF (Ty.inter lhs (Ty.compl rhs))) :=
        hEmpty ν
      have hDiff : TyDNF.denotes ν (Ty.normalizeTyDNF (Ty.inter lhs (Ty.compl rhs))) :=
        (Ty.normalizeTyDNF_spec ν (Ty.inter lhs (Ty.compl rhs))).2 (by
          simpa [Ty.denotesUnder] using And.intro hLhs hRhs)
      exact False.elim (hNoDiff hDiff)

end Weft
