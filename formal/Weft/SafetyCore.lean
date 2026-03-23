import Weft.Types

namespace Weft.SafetyCore

inductive Expr : Type where
  | bool : Bool -> Expr
  | int : Int -> Expr
  | nil : Expr
  | add : Expr -> Expr -> Expr
  | ifThenElse : Expr -> Expr -> Expr -> Expr
  deriving Repr, DecidableEq

inductive Value : Expr -> Prop where
  | bool (b : Bool) : Value (.bool b)
  | int (n : Int) : Value (.int n)
  | nil : Value .nil

inductive HasType : Expr -> Weft.Ty -> Prop where
  | bool (b : Bool) : HasType (.bool b) Weft.Ty.bool
  | int (n : Int) : HasType (.int n) Weft.Ty.int
  | nil : HasType .nil Weft.Ty.nil
  | add (lhs rhs : Expr) :
      HasType lhs Weft.Ty.int ->
      HasType rhs Weft.Ty.int ->
      HasType (.add lhs rhs) Weft.Ty.int
  | ifThenElse (cond thenBranch elseBranch : Expr) (ty : Weft.Ty) :
      HasType cond Weft.Ty.bool ->
      HasType thenBranch ty ->
      HasType elseBranch ty ->
      HasType (.ifThenElse cond thenBranch elseBranch) ty

inductive Step : Expr -> Expr -> Prop where
  | addLeft (lhs lhs' rhs : Expr) :
      Step lhs lhs' ->
      Step (.add lhs rhs) (.add lhs' rhs)
  | addRight (lhs rhs rhs' : Expr) :
      Value lhs ->
      Step rhs rhs' ->
      Step (.add lhs rhs) (.add lhs rhs')
  | addInt (lhs rhs : Int) :
      Step (.add (.int lhs) (.int rhs)) (.int (lhs + rhs))
  | ifCond (cond cond' thenBranch elseBranch : Expr) :
      Step cond cond' ->
      Step (.ifThenElse cond thenBranch elseBranch) (.ifThenElse cond' thenBranch elseBranch)
  | ifTrue (thenBranch elseBranch : Expr) :
      Step (.ifThenElse (.bool true) thenBranch elseBranch) thenBranch
  | ifFalse (thenBranch elseBranch : Expr) :
      Step (.ifThenElse (.bool false) thenBranch elseBranch) elseBranch

inductive Steps : Expr -> Expr -> Prop where
  | refl (e : Expr) : Steps e e
  | tail (e e' e'' : Expr) :
      Step e e' ->
      Steps e' e'' ->
      Steps e e''

def NormalForm (e : Expr) : Prop :=
  ∀ e' : Expr, ¬ Step e e'

end Weft.SafetyCore
