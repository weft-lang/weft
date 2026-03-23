import Weft.CoreDNF
import Weft.Properties.CoreSubtypeSoundness

namespace Weft

theorem CoreReq.holdsb_spec
    (req : CoreReq)
    (present : Bool) :
    req.holdsb present = true ↔ req.holds present := by
  cases req <;> cases present <;> simp [CoreReq.holdsb, CoreReq.holds]

theorem CoreCube.denotesb_spec
    (cube : CoreCube)
    (atom : CoreAtom) :
    cube.denotesb atom = true ↔ cube.denotes atom := by
  cases atom <;>
    simp [CoreCube.denotesb, CoreCube.denotes, CoreCube.atomReq, CoreReq.holdsb_spec, and_assoc]

private theorem or_self_assoc {A B : Prop} :
    A ∨ A ∨ B ↔ A ∨ B := by
  constructor
  · intro h
    cases h with
    | inl hA => exact .inl hA
    | inr hRest =>
        cases hRest with
        | inl hA => exact .inl hA
        | inr hB => exact .inr hB
  · intro h
    cases h with
    | inl hA => exact .inl hA
    | inr hB => exact .inr (.inr hB)

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

theorem CoreCube.meet_spec
    (lhs rhs : CoreCube)
    (atom : CoreAtom) :
    match lhs.meet rhs with
    | some merged => merged.denotes atom ↔ lhs.denotes atom ∧ rhs.denotes atom
    | none => ¬ (lhs.denotes atom ∧ rhs.denotes atom) := by
  cases lhs with
  | mk lhsBool lhsInt lhsNil =>
      cases rhs with
      | mk rhsBool rhsInt rhsNil =>
          cases lhsBool <;> cases lhsInt <;> cases lhsNil <;>
            cases rhsBool <;> cases rhsInt <;> cases rhsNil <;>
            cases atom <;>
            simp [CoreCube.meet, CoreReq.meet, CoreCube.denotes, CoreCube.atomReq, CoreReq.holds]

theorem CoreCube.compl_spec
    (cube : CoreCube)
    (atom : CoreAtom) :
    CoreDNF.denotes cube.compl atom ↔ ¬ cube.denotes atom := by
  cases cube with
  | mk boolReq intReq nilReq =>
      cases boolReq <;> cases intReq <;> cases nilReq <;> cases atom <;>
        simp [CoreCube.compl, CoreCube.negateField, CoreDNF.denotes,
          CoreCube.denotes, CoreCube.atomReq, CoreReq.negate, CoreReq.holds, CoreCube.top]

theorem CoreCube.toTy_spec
    (cube : CoreCube)
    (atom : CoreAtom) :
    cube.toTy.denotes atom ↔ cube.denotes atom := by
  cases cube with
  | mk boolReq intReq nilReq =>
      cases boolReq <;> cases intReq <;> cases nilReq <;> cases atom <;>
        simp [CoreCube.toTy, CoreCube.denotes, CoreCube.atomReq, CoreReq.holds, CoreSetTy.denotes]

theorem CoreDNF.denotesb_spec
    (dnf : CoreDNF)
    (atom : CoreAtom) :
    dnf.denotesb atom = true ↔ dnf.denotes atom := by
  induction dnf with
  | nil =>
      simp [CoreDNF.denotesb, CoreDNF.denotes]
  | cons cube rest ih =>
      simp [CoreDNF.denotesb, CoreDNF.denotes, CoreCube.denotesb_spec, ih]

theorem CoreDNF.denotesb_false_spec
    (dnf : CoreDNF)
    (atom : CoreAtom) :
    dnf.denotesb atom = false ↔ ¬ dnf.denotes atom := by
  constructor
  · intro hFalse hDen
    have hTrue : dnf.denotesb atom = true := (CoreDNF.denotesb_spec dnf atom).2 hDen
    simp [hFalse] at hTrue
  · intro hNot
    cases hBool : dnf.denotesb atom with
    | false =>
        rfl
    | true =>
        exact False.elim (hNot ((CoreDNF.denotesb_spec dnf atom).1 hBool))

theorem CoreDNF.append_spec
    (lhs rhs : CoreDNF)
    (atom : CoreAtom) :
    CoreDNF.denotes (lhs ++ rhs) atom ↔ CoreDNF.denotes lhs atom ∨ CoreDNF.denotes rhs atom := by
  induction lhs with
  | nil =>
      simp [CoreDNF.denotes]
  | cons cube rest ih =>
      simp [CoreDNF.denotes, ih, or_assoc]

theorem CoreDNF.meetCube_spec
    (cube : CoreCube)
    (rhs : CoreDNF)
    (atom : CoreAtom) :
    CoreDNF.denotes (CoreDNF.meetCube cube rhs) atom ↔
      cube.denotes atom ∧ CoreDNF.denotes rhs atom := by
  induction rhs with
  | nil =>
      simp [CoreDNF.meetCube, CoreDNF.denotes]
  | cons other rest ih =>
      cases hMeet : cube.meet other with
      | none =>
          have hNo : ¬ (cube.denotes atom ∧ other.denotes atom) := by
            simpa [hMeet] using (CoreCube.meet_spec cube other atom)
          constructor
          · intro hDen
            have hMeetRest : CoreDNF.denotes (CoreDNF.meetCube cube rest) atom := by
              simpa [CoreDNF.meetCube, hMeet, CoreDNF.denotes] using hDen
            have hRest : cube.denotes atom ∧ CoreDNF.denotes rest atom :=
              (ih).1 hMeetRest
            exact ⟨hRest.1, .inr hRest.2⟩
          · intro hDen
            cases hDen.2 with
            | inl hOther =>
                exact False.elim (hNo ⟨hDen.1, hOther⟩)
            | inr hRest =>
                have hMeetRest : CoreDNF.denotes (CoreDNF.meetCube cube rest) atom :=
                  (ih).2 ⟨hDen.1, hRest⟩
                simpa [CoreDNF.meetCube, hMeet, CoreDNF.denotes] using hMeetRest
      | some merged =>
          have hSome : merged.denotes atom ↔ cube.denotes atom ∧ other.denotes atom := by
            simpa [hMeet] using (CoreCube.meet_spec cube other atom)
          calc
            CoreDNF.denotes (CoreDNF.meetCube cube (other :: rest)) atom
                ↔ merged.denotes atom ∨ CoreDNF.denotes (CoreDNF.meetCube cube rest) atom := by
                    simp [CoreDNF.meetCube, hMeet, CoreDNF.denotes]
            _ ↔ (cube.denotes atom ∧ other.denotes atom) ∨
                  (cube.denotes atom ∧ CoreDNF.denotes rest atom) := by
                    simp [hSome, ih]
            _ ↔ cube.denotes atom ∧ (other.denotes atom ∨ CoreDNF.denotes rest atom) := and_or_distrib_left
            _ ↔ cube.denotes atom ∧ CoreDNF.denotes (other :: rest) atom := by
                    simp [CoreDNF.denotes]

theorem CoreDNF.inter_spec
    (lhs rhs : CoreDNF)
    (atom : CoreAtom) :
    CoreDNF.denotes (CoreDNF.inter lhs rhs) atom ↔
      CoreDNF.denotes lhs atom ∧ CoreDNF.denotes rhs atom := by
  induction lhs with
  | nil =>
      simp [CoreDNF.inter, CoreDNF.denotes]
  | cons cube rest ih =>
      calc
        CoreDNF.denotes (CoreDNF.inter (cube :: rest) rhs) atom
            ↔ CoreDNF.denotes (CoreDNF.meetCube cube rhs ++ CoreDNF.inter rest rhs) atom := by
                rfl
        _ ↔ CoreDNF.denotes (CoreDNF.meetCube cube rhs) atom ∨ CoreDNF.denotes (CoreDNF.inter rest rhs) atom := by
                exact CoreDNF.append_spec _ _ _
        _ ↔ (cube.denotes atom ∧ CoreDNF.denotes rhs atom) ∨
              (CoreDNF.denotes rest atom ∧ CoreDNF.denotes rhs atom) := by
                simp [CoreDNF.meetCube_spec, ih]
        _ ↔ (cube.denotes atom ∨ CoreDNF.denotes rest atom) ∧ CoreDNF.denotes rhs atom := or_and_distrib_right
        _ ↔ CoreDNF.denotes (cube :: rest) atom ∧ CoreDNF.denotes rhs atom := by
                simp [CoreDNF.denotes]

theorem CoreDNF.compl_spec
    (dnf : CoreDNF)
    (atom : CoreAtom) :
    CoreDNF.denotes (CoreDNF.compl dnf) atom ↔ ¬ CoreDNF.denotes dnf atom := by
  induction dnf with
  | nil =>
      simp [CoreDNF.compl, CoreDNF.top, CoreDNF.denotes,
        CoreCube.denotes, CoreReq.holds, CoreCube.top]
  | cons cube rest ih =>
      calc
        CoreDNF.denotes (CoreDNF.compl (cube :: rest)) atom
            ↔ CoreDNF.denotes (CoreDNF.inter cube.compl (CoreDNF.compl rest)) atom := by
                rfl
        _ ↔ CoreDNF.denotes cube.compl atom ∧ CoreDNF.denotes (CoreDNF.compl rest) atom := CoreDNF.inter_spec _ _ _
        _ ↔ ¬ cube.denotes atom ∧ ¬ CoreDNF.denotes rest atom := by
                simp [CoreCube.compl_spec, ih]
        _ ↔ ¬ (cube.denotes atom ∨ CoreDNF.denotes rest atom) := by
                simp
        _ ↔ ¬ CoreDNF.denotes (cube :: rest) atom := by
                simp [CoreDNF.denotes]

theorem CoreDNF.emptyb_spec
    (dnf : CoreDNF) :
    dnf.emptyb = true ↔ ∀ atom : CoreAtom, ¬ dnf.denotes atom := by
  constructor
  · intro hEmpty atom
    have hParts : (dnf.denotesb .bool = false ∧ dnf.denotesb .int = false) ∧
        dnf.denotesb .nil = false := by
      simpa [CoreDNF.emptyb] using hEmpty
    cases atom with
    | bool =>
        exact (CoreDNF.denotesb_false_spec dnf .bool).1 hParts.1.1
    | int =>
        exact (CoreDNF.denotesb_false_spec dnf .int).1 hParts.1.2
    | nil =>
        exact (CoreDNF.denotesb_false_spec dnf .nil).1 hParts.2
  · intro hEmpty
    have hBool : dnf.denotesb .bool = false :=
      (CoreDNF.denotesb_false_spec dnf .bool).2 (hEmpty .bool)
    have hInt : dnf.denotesb .int = false :=
      (CoreDNF.denotesb_false_spec dnf .int).2 (hEmpty .int)
    have hNil : dnf.denotesb .nil = false :=
      (CoreDNF.denotesb_false_spec dnf .nil).2 (hEmpty .nil)
    simp [CoreDNF.emptyb, hBool, hInt, hNil]

theorem CoreDNF.toTy_spec
    (dnf : CoreDNF)
    (atom : CoreAtom) :
    dnf.toTy.denotes atom ↔ dnf.denotes atom := by
  induction dnf with
  | nil =>
      simp [CoreDNF.toTy, CoreDNF.denotes, CoreSetTy.denotes]
  | cons cube rest ih =>
      simp [CoreDNF.toTy, CoreDNF.denotes, CoreSetTy.denotes, CoreCube.toTy_spec, ih]

theorem CoreSetTy.normalizeDNF_spec
    (ty : CoreSetTy)
    (atom : CoreAtom) :
    CoreDNF.denotes ty.normalizeDNF atom ↔ ty.denotes atom := by
  induction ty generalizing atom with
  | empty =>
      simp [CoreSetTy.normalizeDNF, CoreDNF.denotes, CoreSetTy.denotes]
  | top =>
      cases atom <;>
        simp [CoreSetTy.normalizeDNF, CoreDNF.top, CoreDNF.denotes,
          CoreCube.denotes, CoreReq.holds, CoreCube.top, CoreSetTy.denotes]
  | atom expected =>
      cases expected <;> cases atom <;>
        simp [CoreSetTy.normalizeDNF, CoreDNF.denotes, CoreCube.denotes,
          CoreCube.singleton, CoreCube.atomReq, CoreReq.holds, CoreCube.top, CoreSetTy.denotes]
  | union lhs rhs ihL ihR =>
      simp [CoreSetTy.normalizeDNF, CoreDNF.union, CoreDNF.append_spec, CoreSetTy.denotes, ihL, ihR]
  | inter lhs rhs ihL ihR =>
      simp [CoreSetTy.normalizeDNF, CoreDNF.inter_spec, CoreSetTy.denotes, ihL, ihR]
  | compl inner ih =>
      simp [CoreSetTy.normalizeDNF, CoreDNF.compl_spec, CoreSetTy.denotes, ih]

theorem CoreSetTy.normalizeDNF_roundtrip
    (dnf : CoreDNF)
    (atom : CoreAtom) :
    CoreDNF.denotes dnf.toTy.normalizeDNF atom ↔ CoreDNF.denotes dnf atom := by
  rw [CoreSetTy.normalizeDNF_spec, CoreDNF.toTy_spec]

theorem CoreSetTy.normalizeDNF_idempotent
    (ty : CoreSetTy)
    (atom : CoreAtom) :
    CoreDNF.denotes ty.normalizeDNF.toTy.normalizeDNF atom ↔
      CoreDNF.denotes ty.normalizeDNF atom := by
  exact CoreSetTy.normalizeDNF_roundtrip ty.normalizeDNF atom

theorem CoreSetTy.subtype_iff_normalizeDNF_empty_diff
    (lhs rhs : CoreSetTy) :
    lhs.Subtype rhs ↔
      (CoreSetTy.normalizeDNF (CoreSetTy.inter lhs (CoreSetTy.compl rhs))).emptyb = true := by
  constructor
  · intro hSubtype
    apply (CoreDNF.emptyb_spec _).2
    intro atom hDnf
    have hWitness : (CoreSetTy.inter lhs (CoreSetTy.compl rhs)).denotes atom :=
      (CoreSetTy.normalizeDNF_spec (CoreSetTy.inter lhs (CoreSetTy.compl rhs)) atom).1 hDnf
    have hParts : lhs.denotes atom ∧ ¬ rhs.denotes atom := by
      simpa [CoreSetTy.denotes] using hWitness
    exact hParts.2 (hSubtype atom hParts.1)
  · intro hEmpty atom hLhs
    by_cases hRhs : rhs.denotes atom
    · exact hRhs
    · have hNoWitness :
          ¬ CoreDNF.denotes (CoreSetTy.normalizeDNF (CoreSetTy.inter lhs (CoreSetTy.compl rhs))) atom :=
        (CoreDNF.emptyb_spec _).1 hEmpty atom
      have hWitness :
          CoreDNF.denotes (CoreSetTy.normalizeDNF (CoreSetTy.inter lhs (CoreSetTy.compl rhs))) atom := by
        apply (CoreSetTy.normalizeDNF_spec (CoreSetTy.inter lhs (CoreSetTy.compl rhs)) atom).2
        simpa [CoreSetTy.denotes] using And.intro hLhs hRhs
      exact False.elim (hNoWitness hWitness)

theorem CoreSetTy.subtypeb_iff_normalizeDNF_empty_diff
    (lhs rhs : CoreSetTy) :
    lhs.subtypeb rhs = true ↔
      (CoreSetTy.normalizeDNF (CoreSetTy.inter lhs (CoreSetTy.compl rhs))).emptyb = true := by
  rw [subtypeb_spec, CoreSetTy.subtype_iff_normalizeDNF_empty_diff]

theorem CoreSetTy.subtypeb_eq_normalizeDNF_empty_diff
    (lhs rhs : CoreSetTy) :
    lhs.subtypeb rhs =
      (CoreSetTy.normalizeDNF (CoreSetTy.inter lhs (CoreSetTy.compl rhs))).emptyb := by
  cases hSubtype : lhs.subtypeb rhs <;>
    cases hEmpty : (CoreSetTy.normalizeDNF (CoreSetTy.inter lhs (CoreSetTy.compl rhs))).emptyb <;>
    try rfl
  · have h : lhs.subtypeb rhs = true :=
        (CoreSetTy.subtypeb_iff_normalizeDNF_empty_diff lhs rhs).2 hEmpty
    simp [hSubtype] at h
  · have h : (CoreSetTy.normalizeDNF (CoreSetTy.inter lhs (CoreSetTy.compl rhs))).emptyb = true :=
        (CoreSetTy.subtypeb_iff_normalizeDNF_empty_diff lhs rhs).1 hSubtype
    simp [hEmpty] at h

end Weft
