namespace Weft

abbrev EffectName : Type := String

structure EffectSet : Type where
  elems : List EffectName
  deriving Repr, DecidableEq

namespace EffectSet

def empty : EffectSet :=
  { elems := [] }

def singleton (name : EffectName) : EffectSet :=
  { elems := [name] }

def union (lhs rhs : EffectSet) : EffectSet :=
  { elems := lhs.elems ++ rhs.elems }

def remove (s : EffectSet) (name : EffectName) : EffectSet :=
  { elems := s.elems.erase name }

def removeAll : EffectSet -> EffectSet -> EffectSet
  | available, { elems := [] } => available
  | available, { elems := eff :: effs } =>
      removeAll (remove available eff) { elems := effs }

def handle (available handled : EffectSet) : EffectSet :=
  removeAll available handled

def subset (lhs rhs : EffectSet) : Prop :=
  ∀ effect : EffectName, effect ∈ lhs.elems -> effect ∈ rhs.elems

def subsetbList (lhs : List EffectName) (rhs : EffectSet) : Bool :=
  match lhs with
  | [] => true
  | effect :: rest => decide (effect ∈ rhs.elems) && subsetbList rest rhs

def subsetb (lhs rhs : EffectSet) : Bool :=
  subsetbList lhs.elems rhs

def disjoint (lhs rhs : EffectSet) : Prop :=
  ∀ effect : EffectName, effect ∈ lhs.elems -> effect ∉ rhs.elems

theorem subset_refl (s : EffectSet) : subset s s := by
  intro effect hMem
  exact hMem

theorem subset_trans {a b c : EffectSet} :
    subset a b -> subset b c -> subset a c := by
  intro hab hbc effect hMem
  exact hbc effect (hab effect hMem)

theorem subset_empty (s : EffectSet) : subset empty s := by
  intro effect hMem
  cases hMem

theorem subsetbList_spec
    (lhs : List EffectName)
    (rhs : EffectSet) :
    subsetbList lhs rhs = true ↔
      ∀ effect : EffectName, effect ∈ lhs -> effect ∈ rhs.elems := by
  induction lhs with
  | nil =>
      simp [subsetbList]
  | cons effect rest ih =>
      constructor
      · intro h target hMem
        simp [subsetbList, Bool.and_eq_true] at h
        rcases List.mem_cons.mp hMem with rfl | hMemRest
        · simpa using h.1
        · exact (ih.1 h.2) target hMemRest
      · intro h
        have hHead : decide (effect ∈ rhs.elems) = true :=
          decide_eq_true (h effect (List.mem_cons.mpr (Or.inl rfl)))
        have hTail : subsetbList rest rhs = true :=
          (ih.2 (fun target hMem => h target (List.mem_cons.mpr (Or.inr hMem))))
        simpa [subsetbList, Bool.and_eq_true] using And.intro hHead hTail

theorem subsetb_spec
    (lhs rhs : EffectSet) :
    subsetb lhs rhs = true ↔ subset lhs rhs := by
  cases lhs with
  | mk elems =>
      simpa [subsetb, subset] using subsetbList_spec elems rhs

theorem subset_union_left (lhs rhs : EffectSet) : subset lhs (union lhs rhs) := by
  intro effect hMem
  exact List.mem_append.mpr (Or.inl hMem)

theorem subset_union_right (lhs rhs : EffectSet) : subset rhs (union lhs rhs) := by
  intro effect hMem
  exact List.mem_append.mpr (Or.inr hMem)

theorem remove_subset (s : EffectSet) (name : EffectName) :
    subset (remove s name) s := by
  intro effect hMem
  exact List.mem_of_mem_erase hMem

theorem removeAll_subset (available handled : EffectSet) :
    subset (removeAll available handled) available := by
  cases handled with
  | mk elems =>
      induction elems generalizing available with
      | nil =>
          simpa [removeAll] using subset_refl available
      | cons eff effs ih =>
          have hStep : subset (removeAll (remove available eff) { elems := effs }) (remove available eff) :=
            ih (remove available eff)
          have hTrans : subset (removeAll (remove available eff) { elems := effs }) available :=
            subset_trans hStep (remove_subset available eff)
          simpa [removeAll] using hTrans

theorem handle_subset (available handled : EffectSet) :
    subset (handle available handled) available := by
  simpa [handle] using removeAll_subset available handled

end EffectSet

end Weft
