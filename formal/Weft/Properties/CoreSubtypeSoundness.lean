import Weft.CoreSubtype

namespace Weft

theorem core_atom_mem_universe (atom : CoreAtom) :
    atom ∈ coreUniverse := by
  cases atom <;> simp [coreUniverse]

theorem denotesb_spec
    (ty : CoreSetTy)
    (atom : CoreAtom) :
    ty.denotesb atom = true ↔ ty.denotes atom := by
  induction ty generalizing atom with
  | empty =>
      simp [CoreSetTy.denotes, CoreSetTy.denotesb]
  | top =>
      simp [CoreSetTy.denotes, CoreSetTy.denotesb]
  | atom expected =>
      simp [CoreSetTy.denotes, CoreSetTy.denotesb]
  | union lhs rhs ihL ihR =>
      simp [CoreSetTy.denotes, CoreSetTy.denotesb, ihL, ihR]
  | inter lhs rhs ihL ihR =>
      simp [CoreSetTy.denotes, CoreSetTy.denotesb, ihL, ihR]
  | compl inner ih =>
      by_cases hDen : inner.denotes atom
      · have hTrue : inner.denotesb atom = true := (ih atom).2 hDen
        simp [CoreSetTy.denotes, CoreSetTy.denotesb, hDen, hTrue]
      · have hFalse : inner.denotesb atom = false := by
          cases hBool : inner.denotesb atom with
          | false =>
              rfl
          | true =>
              exact False.elim (hDen ((ih atom).1 hBool))
        simp [CoreSetTy.denotes, CoreSetTy.denotesb, hDen, hFalse]

theorem denotesb_false_spec
    (ty : CoreSetTy)
    (atom : CoreAtom) :
    ty.denotesb atom = false ↔ ¬ ty.denotes atom := by
  constructor
  · intro hFalse hDen
    have hTrue : ty.denotesb atom = true := (denotesb_spec ty atom).2 hDen
    simp [hFalse] at hTrue
  · intro hNot
    cases hBool : ty.denotesb atom with
    | false =>
        rfl
    | true =>
        exact False.elim (hNot ((denotesb_spec ty atom).1 hBool))

theorem mem_normalize_iff
    (ty : CoreSetTy)
    (atom : CoreAtom) :
    atom ∈ ty.normalize ↔ ty.denotes atom := by
  have hUniverse : atom ∈ coreUniverse := core_atom_mem_universe atom
  simp [CoreSetTy.normalize, denotesb_spec, hUniverse]

theorem emptyb_spec
    (ty : CoreSetTy) :
    ty.emptyb = true ↔ ∀ atom : CoreAtom, ¬ ty.denotes atom := by
  constructor
  · intro hEmpty atom
    have hParts : (ty.denotesb .bool = false ∧ ty.denotesb .int = false) ∧
        ty.denotesb .nil = false := by
      simpa [CoreSetTy.emptyb] using hEmpty
    cases atom with
    | bool =>
        exact (denotesb_false_spec ty .bool).1 hParts.1.1
    | int =>
        exact (denotesb_false_spec ty .int).1 hParts.1.2
    | nil =>
        exact (denotesb_false_spec ty .nil).1 hParts.2
  · intro hEmpty
    have hBool : ty.denotesb .bool = false :=
      (denotesb_false_spec ty .bool).2 (hEmpty .bool)
    have hInt : ty.denotesb .int = false :=
      (denotesb_false_spec ty .int).2 (hEmpty .int)
    have hNil : ty.denotesb .nil = false :=
      (denotesb_false_spec ty .nil).2 (hEmpty .nil)
    simp [CoreSetTy.emptyb, hBool, hInt, hNil]

theorem impliesb_spec
    (lhs rhs : Bool) :
    CoreSetTy.impliesb lhs rhs = true ↔ (lhs = true → rhs = true) := by
  cases lhs <;> cases rhs <;> simp [CoreSetTy.impliesb]

theorem subtypeb_spec
    (lhs rhs : CoreSetTy) :
    lhs.subtypeb rhs = true ↔ lhs.Subtype rhs := by
  constructor
  · intro hSubtype atom hMem
    have hParts :
        (CoreSetTy.impliesb (lhs.denotesb .bool) (rhs.denotesb .bool) = true ∧
          CoreSetTy.impliesb (lhs.denotesb .int) (rhs.denotesb .int) = true) ∧
        CoreSetTy.impliesb (lhs.denotesb .nil) (rhs.denotesb .nil) = true := by
      simpa [CoreSetTy.subtypeb] using hSubtype
    cases atom with
    | bool =>
        have hStep : lhs.denotesb .bool = true → rhs.denotesb .bool = true :=
          (impliesb_spec _ _).1 hParts.1.1
        exact (denotesb_spec rhs .bool).1 (hStep ((denotesb_spec lhs .bool).2 hMem))
    | int =>
        have hStep : lhs.denotesb .int = true → rhs.denotesb .int = true :=
          (impliesb_spec _ _).1 hParts.1.2
        exact (denotesb_spec rhs .int).1 (hStep ((denotesb_spec lhs .int).2 hMem))
    | nil =>
        have hStep : lhs.denotesb .nil = true → rhs.denotesb .nil = true :=
          (impliesb_spec _ _).1 hParts.2
        exact (denotesb_spec rhs .nil).1 (hStep ((denotesb_spec lhs .nil).2 hMem))
  · intro hSubtype
    have hBool : CoreSetTy.impliesb (lhs.denotesb .bool) (rhs.denotesb .bool) = true := by
      apply (impliesb_spec _ _).2
      intro hL
      exact (denotesb_spec rhs .bool).2 (hSubtype .bool ((denotesb_spec lhs .bool).1 hL))
    have hInt : CoreSetTy.impliesb (lhs.denotesb .int) (rhs.denotesb .int) = true := by
      apply (impliesb_spec _ _).2
      intro hL
      exact (denotesb_spec rhs .int).2 (hSubtype .int ((denotesb_spec lhs .int).1 hL))
    have hNil : CoreSetTy.impliesb (lhs.denotesb .nil) (rhs.denotesb .nil) = true := by
      apply (impliesb_spec _ _).2
      intro hL
      exact (denotesb_spec rhs .nil).2 (hSubtype .nil ((denotesb_spec lhs .nil).1 hL))
    simp [CoreSetTy.subtypeb, hBool, hInt, hNil]

theorem subtype_iff_empty_diff
    (lhs rhs : CoreSetTy) :
    lhs.Subtype rhs ↔ (CoreSetTy.inter lhs (CoreSetTy.compl rhs)).emptyb = true := by
  constructor
  · intro hSubtype
    apply (emptyb_spec _).2
    intro atom hWitness
    have hParts : lhs.denotes atom ∧ ¬ rhs.denotes atom := by
      simpa [CoreSetTy.denotes] using hWitness
    exact hParts.2 (hSubtype atom hParts.1)
  · intro hEmpty atom hLhs
    by_cases hRhs : rhs.denotes atom
    · exact hRhs
    · have hNoWitness : ¬ (CoreSetTy.inter lhs (CoreSetTy.compl rhs)).denotes atom :=
        (emptyb_spec _).1 hEmpty atom
      have hWitness : (CoreSetTy.inter lhs (CoreSetTy.compl rhs)).denotes atom := by
        simpa [CoreSetTy.denotes] using And.intro hLhs hRhs
      exact False.elim (hNoWitness hWitness)

theorem subtypeb_iff_emptyb_diff
    (lhs rhs : CoreSetTy) :
    lhs.subtypeb rhs = true ↔ (CoreSetTy.inter lhs (CoreSetTy.compl rhs)).emptyb = true := by
  rw [subtypeb_spec, subtype_iff_empty_diff]

end Weft
