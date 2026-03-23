import Weft.Types

namespace Weft

inductive Literal : Type where
  | bool : Bool -> Literal
  | int : Int -> Literal
  | nil : Literal
  deriving Repr, DecidableEq

inductive Pattern : Type where
  | wildcard : Pattern
  | binder : Name -> Pattern
  | lit : Literal -> Pattern
  | variant : Name -> Name -> List Pattern -> Pattern
  deriving Repr

inductive Term : Type where
  | var : Name -> Term
  | lit : Literal -> Term
  | lam : Name -> Ty -> EffectSet -> Ty -> Term -> Term
  | app : Term -> Term -> Term
  | letE : Name -> Option Ty -> Term -> Term -> Term
  | ifThenElse : Term -> Term -> Term -> Term
  | record : List (Name × Term) -> Term
  | field : Term -> Name -> Term
  | variant : Name -> Name -> List Term -> Term
  | matchE : Term -> List (Pattern × Term) -> Term
  | perform : EffectName -> Name -> List Term -> Term
  | handle : EffectName -> Term -> Term -> Term
  | resume : Term -> Term
  | whileE : Term -> Term -> Term
  | annotate : Term -> Ty -> Term
  deriving Repr

inductive Decl : Type where
  | fnDecl : Name -> List (Name × Ty) -> EffectSet -> Ty -> Term -> Decl
  | typeDecl : Name -> Ty -> Decl
  | effectDecl : EffectName -> List (Name × List Ty × Ty) -> Decl
  deriving Repr

structure Module : Type where
  decls : List Decl
  deriving Repr

end Weft
