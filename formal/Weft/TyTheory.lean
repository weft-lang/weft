import Weft.TyDNF

namespace Weft

structure TyTheory : Type where
  Implies : TyAtom -> TyAtom -> Prop
  Disjoint : TyAtom -> TyAtom -> Prop
  implies_refl : ∀ atom : TyAtom, Implies atom atom

namespace TyTheory

structure SoundValuation (theory : TyTheory) (ν : TyAtom -> Prop) : Prop where
  implies_sound : ∀ {lhs rhs : TyAtom}, theory.Implies lhs rhs -> ν lhs -> ν rhs
  disjoint_sound : ∀ {lhs rhs : TyAtom}, theory.Disjoint lhs rhs -> ¬ (ν lhs ∧ ν rhs)

end TyTheory

namespace TyClause

def Unsat (theory : TyTheory) (clause : TyClause) : Prop :=
  (∃ lhs, lhs ∈ clause.pos ∧ ∃ rhs, rhs ∈ clause.pos ∧ theory.Disjoint lhs rhs) ∨
    ∃ lhs, lhs ∈ clause.pos ∧ ∃ rhs, rhs ∈ clause.neg ∧ theory.Implies lhs rhs

end TyClause

namespace TyDNF

def Unsat (theory : TyTheory) (dnf : TyDNF) : Prop :=
  ∀ clause, clause ∈ dnf -> clause.Unsat theory

end TyDNF

namespace Ty

def SubtypeIn (theory : TyTheory) (lhs rhs : Ty) : Prop :=
  ∀ ν : TyAtom -> Prop, theory.SoundValuation ν -> lhs.denotesUnder ν -> rhs.denotesUnder ν

end Ty

namespace KernelTheory

def Implies : TyAtom -> TyAtom -> Prop
  | .fn arg eff ret, .fn arg' eff' ret' =>
      arg = arg' ∧ EffectSet.subset eff eff' ∧ ret = ret'
  | .rc inner, .ptr inner' => inner = inner'
  | .mptr inner, .ptr inner' => inner = inner'
  | lhs, rhs => lhs = rhs

def impliesb : TyAtom -> TyAtom -> Bool
  | .fn arg eff ret, .fn arg' eff' ret' =>
      Ty.eqb arg arg' && EffectSet.subsetb eff eff' && Ty.eqb ret ret'
  | .rc inner, .ptr inner' => Ty.eqb inner inner'
  | .mptr inner, .ptr inner' => Ty.eqb inner inner'
  | lhs, rhs => TyAtom.eqb lhs rhs

def Disjoint : TyAtom -> TyAtom -> Prop
  | .bool, .int => True
  | .int, .bool => True
  | .bool, .nil => True
  | .nil, .bool => True
  | .int, .nil => True
  | .nil, .int => True
  | .rc _, .mptr _ => True
  | .mptr _, .rc _ => True
  | _, _ => False

def disjointb : TyAtom -> TyAtom -> Bool
  | .bool, .int => true
  | .int, .bool => true
  | .bool, .nil => true
  | .nil, .bool => true
  | .int, .nil => true
  | .nil, .int => true
  | .rc _, .mptr _ => true
  | .mptr _, .rc _ => true
  | _, _ => false

theorem impliesb_spec
    (lhs rhs : TyAtom) :
    impliesb lhs rhs = true ↔ Implies lhs rhs := by
  cases lhs <;> cases rhs <;>
    simp [impliesb, Implies, Ty.eqb_spec, TyAtom.eqb_spec, EffectSet.subsetb_spec, and_assoc]

theorem disjointb_spec
    (lhs rhs : TyAtom) :
    disjointb lhs rhs = true ↔ Disjoint lhs rhs := by
  cases lhs <;> cases rhs <;> simp [disjointb, Disjoint]

def theory : TyTheory where
  Implies := Implies
  Disjoint := Disjoint
  implies_refl := by
    intro atom
    cases atom <;> simp [Implies, EffectSet.subset_refl]

end KernelTheory

end Weft
