import Weft.Types

namespace Weft

inductive CoreAtom : Type where
  | bool : CoreAtom
  | int : CoreAtom
  | nil : CoreAtom
  deriving Repr, DecidableEq

def coreUniverse : List CoreAtom :=
  [.bool, .int, .nil]

inductive CoreSetTy : Type where
  | empty : CoreSetTy
  | top : CoreSetTy
  | atom : CoreAtom -> CoreSetTy
  | union : CoreSetTy -> CoreSetTy -> CoreSetTy
  | inter : CoreSetTy -> CoreSetTy -> CoreSetTy
  | compl : CoreSetTy -> CoreSetTy
  deriving Repr, DecidableEq

def CoreSetTy.denotes : CoreSetTy -> CoreAtom -> Prop
  | .empty, _ => False
  | .top, _ => True
  | .atom expected, a => a = expected
  | .union lhs rhs, a => CoreSetTy.denotes lhs a ∨ CoreSetTy.denotes rhs a
  | .inter lhs rhs, a => CoreSetTy.denotes lhs a ∧ CoreSetTy.denotes rhs a
  | .compl inner, a => ¬ CoreSetTy.denotes inner a

def CoreSetTy.denotesb : CoreSetTy -> CoreAtom -> Bool
  | .empty, _ => false
  | .top, _ => true
  | .atom expected, a => decide (a = expected)
  | .union lhs rhs, a => lhs.denotesb a || rhs.denotesb a
  | .inter lhs rhs, a => lhs.denotesb a && rhs.denotesb a
  | .compl inner, a => !(inner.denotesb a)

def CoreSetTy.normalize (ty : CoreSetTy) : List CoreAtom :=
  coreUniverse.filter (fun atom => ty.denotesb atom)

def CoreSetTy.emptyb (ty : CoreSetTy) : Bool :=
  !(ty.denotesb .bool) && !(ty.denotesb .int) && !(ty.denotesb .nil)

def CoreSetTy.impliesb (lhs rhs : Bool) : Bool :=
  (!lhs) || rhs

def CoreSetTy.subtypeb (lhs rhs : CoreSetTy) : Bool :=
  impliesb (lhs.denotesb .bool) (rhs.denotesb .bool) &&
    impliesb (lhs.denotesb .int) (rhs.denotesb .int) &&
    impliesb (lhs.denotesb .nil) (rhs.denotesb .nil)

def CoreSetTy.Subtype (lhs rhs : CoreSetTy) : Prop :=
  ∀ atom : CoreAtom, lhs.denotes atom -> rhs.denotes atom

def CoreSetTy.ofTy : Ty -> Option CoreSetTy
  | .bool => some (.atom .bool)
  | .int => some (.atom .int)
  | .nil => some (.atom .nil)
  | .never => some .empty
  | .any => some .top
  | .union lhs rhs => do
      let lhs' <- ofTy lhs
      let rhs' <- ofTy rhs
      pure (.union lhs' rhs')
  | .inter lhs rhs => do
      let lhs' <- ofTy lhs
      let rhs' <- ofTy rhs
      pure (.inter lhs' rhs')
  | .compl inner => do
      let inner' <- ofTy inner
      pure (.compl inner')
  | _ => none

end Weft
