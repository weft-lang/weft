import Weft.Types

namespace Weft

inductive TyAtom : Type where
  | bool : TyAtom
  | int : TyAtom
  | nil : TyAtom
  | fn : Ty -> EffectSet -> Ty -> TyAtom
  | record : List (Name × Ty) -> TyAtom
  | ptr : Ty -> TyAtom
  | mptr : Ty -> TyAtom
  | rc : Ty -> TyAtom
  | nominal : Name -> List Ty -> TyAtom
  deriving Repr

namespace TyAtom

def toTy : TyAtom -> Ty
  | .bool => .bool
  | .int => .int
  | .nil => .nil
  | .fn arg eff ret => .fn arg eff ret
  | .record fields => .record fields
  | .ptr inner => .ptr inner
  | .mptr inner => .mptr inner
  | .rc inner => .rc inner
  | .nominal name args => .nominal name args

end TyAtom

structure TyClause : Type where
  pos : List TyAtom
  neg : List TyAtom
  deriving Repr

namespace TyClause

def top : TyClause :=
  { pos := [], neg := [] }

def ofPos (atom : TyAtom) : TyClause :=
  { pos := [atom], neg := [] }

def ofNeg (atom : TyAtom) : TyClause :=
  { pos := [], neg := [atom] }

def merge (lhs rhs : TyClause) : TyClause :=
  { pos := lhs.pos ++ rhs.pos, neg := lhs.neg ++ rhs.neg }

def denotes (ν : TyAtom -> Prop) (clause : TyClause) : Prop :=
  (∀ atom, atom ∈ clause.pos -> ν atom) ∧
    (∀ atom, atom ∈ clause.neg -> ¬ ν atom)

def posTy : List TyAtom -> Ty
  | [] => .any
  | atom :: rest => .inter atom.toTy (posTy rest)

def negTy : List TyAtom -> Ty
  | [] => .any
  | atom :: rest => .inter (.compl atom.toTy) (negTy rest)

def toTy (clause : TyClause) : Ty :=
  .inter (posTy clause.pos) (negTy clause.neg)

end TyClause

abbrev TyDNF : Type := List TyClause

namespace TyDNF

def top : TyDNF :=
  [TyClause.top]

def ofAtom (atom : TyAtom) : TyDNF :=
  [TyClause.ofPos atom]

def denotes (ν : TyAtom -> Prop) : TyDNF -> Prop
  | [] => False
  | clause :: rest => clause.denotes ν ∨ denotes ν rest

def union (lhs rhs : TyDNF) : TyDNF :=
  lhs ++ rhs

def interWith (clause : TyClause) : TyDNF -> TyDNF
  | [] => []
  | other :: rest => clause.merge other :: interWith clause rest

def inter : TyDNF -> TyDNF -> TyDNF
  | [], _ => []
  | clause :: rest, rhs => interWith clause rhs ++ inter rest rhs

def complClause (clause : TyClause) : TyDNF :=
  clause.pos.map TyClause.ofNeg ++ clause.neg.map TyClause.ofPos

def compl : TyDNF -> TyDNF
  | [] => top
  | clause :: rest => inter (complClause clause) (compl rest)

def toTy : TyDNF -> Ty
  | [] => .never
  | clause :: rest => .union clause.toTy (toTy rest)

end TyDNF

namespace Ty

def denotesUnder (ν : TyAtom -> Prop) : Ty -> Prop
  | .bool => ν .bool
  | .int => ν .int
  | .nil => ν .nil
  | .never => False
  | .any => True
  | .union lhs rhs => denotesUnder ν lhs ∨ denotesUnder ν rhs
  | .inter lhs rhs => denotesUnder ν lhs ∧ denotesUnder ν rhs
  | .compl inner => ¬ denotesUnder ν inner
  | .fn arg eff ret => ν (.fn arg eff ret)
  | .record fields => ν (.record fields)
  | .ptr inner => ν (.ptr inner)
  | .mptr inner => ν (.mptr inner)
  | .rc inner => ν (.rc inner)
  | .nominal name args => ν (.nominal name args)

def normalizeTyDNF : Ty -> TyDNF
  | .bool => TyDNF.ofAtom .bool
  | .int => TyDNF.ofAtom .int
  | .nil => TyDNF.ofAtom .nil
  | .never => []
  | .any => TyDNF.top
  | .union lhs rhs => TyDNF.union lhs.normalizeTyDNF rhs.normalizeTyDNF
  | .inter lhs rhs => TyDNF.inter lhs.normalizeTyDNF rhs.normalizeTyDNF
  | .compl inner => TyDNF.compl inner.normalizeTyDNF
  | .fn arg eff ret => TyDNF.ofAtom (.fn arg eff ret)
  | .record fields => TyDNF.ofAtom (.record fields)
  | .ptr inner => TyDNF.ofAtom (.ptr inner)
  | .mptr inner => TyDNF.ofAtom (.mptr inner)
  | .rc inner => TyDNF.ofAtom (.rc inner)
  | .nominal name args => TyDNF.ofAtom (.nominal name args)

def SubtypeUnder (lhs rhs : Ty) : Prop :=
  ∀ ν : TyAtom -> Prop, lhs.denotesUnder ν -> rhs.denotesUnder ν

end Ty

end Weft
