import Weft.Effects

namespace Weft

abbrev Name : Type := String

inductive Ty : Type where
  | bool : Ty
  | int : Ty
  | nil : Ty
  | never : Ty
  | any : Ty
  | union : Ty -> Ty -> Ty
  | inter : Ty -> Ty -> Ty
  | compl : Ty -> Ty
  | fn : Ty -> EffectSet -> Ty -> Ty
  | record : List (Name × Ty) -> Ty
  | ptr : Ty -> Ty
  | mptr : Ty -> Ty
  | rc : Ty -> Ty
  | nominal : Name -> List Ty -> Ty
  deriving Repr

namespace Ty

def pureFn (arg ret : Ty) : Ty :=
  fn arg EffectSet.empty ret

def nullable (ty : Ty) : Ty :=
  union ty nil

end Ty

end Weft
