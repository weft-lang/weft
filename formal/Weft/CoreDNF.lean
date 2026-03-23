import Weft.CoreSubtype

namespace Weft

inductive CoreReq : Type where
  | any : CoreReq
  | yes : CoreReq
  | no : CoreReq
  deriving Repr, DecidableEq

namespace CoreReq

def holds : CoreReq -> Bool -> Prop
  | .any, _ => True
  | .yes, present => present = true
  | .no, present => present = false

def holdsb : CoreReq -> Bool -> Bool
  | .any, _ => true
  | .yes, present => present
  | .no, present => !present

def meet : CoreReq -> CoreReq -> Option CoreReq
  | .any, rhs => some rhs
  | lhs, .any => some lhs
  | .yes, .yes => some .yes
  | .no, .no => some .no
  | .yes, .no => none
  | .no, .yes => none

def negate : CoreReq -> Option CoreReq
  | .any => none
  | .yes => some .no
  | .no => some .yes

end CoreReq

structure CoreCube : Type where
  boolReq : CoreReq
  intReq : CoreReq
  nilReq : CoreReq
  deriving Repr, DecidableEq

namespace CoreCube

def top : CoreCube :=
  { boolReq := .any, intReq := .any, nilReq := .any }

def atomReq (expected actual : CoreAtom) : Bool :=
  decide (actual = expected)

def denotes (cube : CoreCube) (atom : CoreAtom) : Prop :=
  cube.boolReq.holds (atomReq .bool atom) ∧
    cube.intReq.holds (atomReq .int atom) ∧
    cube.nilReq.holds (atomReq .nil atom)

def denotesb (cube : CoreCube) (atom : CoreAtom) : Bool :=
  cube.boolReq.holdsb (atomReq .bool atom) &&
    cube.intReq.holdsb (atomReq .int atom) &&
    cube.nilReq.holdsb (atomReq .nil atom)

def singleton (atom : CoreAtom) : CoreCube :=
  match atom with
  | .bool => { top with boolReq := .yes }
  | .int => { top with intReq := .yes }
  | .nil => { top with nilReq := .yes }

def meet (lhs rhs : CoreCube) : Option CoreCube := do
  let boolReq <- lhs.boolReq.meet rhs.boolReq
  let intReq <- lhs.intReq.meet rhs.intReq
  let nilReq <- lhs.nilReq.meet rhs.nilReq
  pure { boolReq, intReq, nilReq }

abbrev CoreDNF : Type := List CoreCube

def negateField
    (setReq : CoreReq)
    (setter : CoreCube -> CoreReq -> CoreCube) :
    CoreDNF :=
  match setReq.negate with
  | none => []
  | some req => [setter top req]

def compl (cube : CoreCube) : CoreDNF :=
  negateField cube.boolReq (fun c req => { c with boolReq := req }) ++
    negateField cube.intReq (fun c req => { c with intReq := req }) ++
    negateField cube.nilReq (fun c req => { c with nilReq := req })

def toTy (cube : CoreCube) : CoreSetTy :=
  let boolTy :=
    match cube.boolReq with
    | .any => .top
    | .yes => .atom .bool
    | .no => .compl (.atom .bool)
  let intTy :=
    match cube.intReq with
    | .any => .top
    | .yes => .atom .int
    | .no => .compl (.atom .int)
  let nilTy :=
    match cube.nilReq with
    | .any => .top
    | .yes => .atom .nil
    | .no => .compl (.atom .nil)
  .inter boolTy (.inter intTy nilTy)

end CoreCube

abbrev CoreDNF : Type := CoreCube.CoreDNF

namespace CoreDNF

def denotes : CoreDNF -> CoreAtom -> Prop
  | [], _ => False
  | cube :: rest, atom => cube.denotes atom ∨ denotes rest atom

def denotesb : CoreDNF -> CoreAtom -> Bool
  | [], _ => false
  | cube :: rest, atom => cube.denotesb atom || denotesb rest atom

def top : CoreDNF :=
  [CoreCube.top]

def union (lhs rhs : CoreDNF) : CoreDNF :=
  lhs ++ rhs

def meetCube (cube : CoreCube) : CoreDNF -> CoreDNF
  | [] => []
  | other :: rest =>
      match cube.meet other with
      | some merged => merged :: meetCube cube rest
      | none => meetCube cube rest

def inter : CoreDNF -> CoreDNF -> CoreDNF
  | [], _ => []
  | cube :: rest, rhs => meetCube cube rhs ++ inter rest rhs

def compl : CoreDNF -> CoreDNF
  | [] => top
  | cube :: rest => inter cube.compl (compl rest)

def emptyb (dnf : CoreDNF) : Bool :=
  !(dnf.denotesb .bool) && !(dnf.denotesb .int) && !(dnf.denotesb .nil)

def toTy : CoreDNF -> CoreSetTy
  | [] => .empty
  | cube :: rest => .union cube.toTy (toTy rest)

end CoreDNF

def CoreSetTy.normalizeDNF : CoreSetTy -> CoreDNF
  | .empty => []
  | .top => CoreDNF.top
  | .atom coreAtom => [CoreCube.singleton coreAtom]
  | .union lhs rhs => CoreDNF.union lhs.normalizeDNF rhs.normalizeDNF
  | .inter lhs rhs => CoreDNF.inter lhs.normalizeDNF rhs.normalizeDNF
  | .compl inner => CoreDNF.compl inner.normalizeDNF

end Weft
