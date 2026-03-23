import Weft.Compiler
import Weft.SafetyCore

namespace Weft.SafetyCore

inductive RuntimeVal : Type where
  | bool : Bool -> RuntimeVal
  | int : Int -> RuntimeVal
  | nil : RuntimeVal
  deriving Repr, DecidableEq

def exitCode : RuntimeVal -> Int
  | .bool true => 1
  | .bool false => 0
  | .int n => n
  | .nil => 0

inductive Eval : Expr -> RuntimeVal -> Prop where
  | bool (b : Bool) : Eval (.bool b) (.bool b)
  | int (n : Int) : Eval (.int n) (.int n)
  | nil : Eval .nil .nil
  | add (lhs rhs : Expr) (lhsVal rhsVal : Int) :
      Eval lhs (.int lhsVal) ->
      Eval rhs (.int rhsVal) ->
      Eval (.add lhs rhs) (.int (lhsVal + rhsVal))
  | ifTrue (cond thenBranch elseBranch : Expr) (v : RuntimeVal) :
      Eval cond (.bool true) ->
      Eval thenBranch v ->
      Eval (.ifThenElse cond thenBranch elseBranch) v
  | ifFalse (cond thenBranch elseBranch : Expr) (v : RuntimeVal) :
      Eval cond (.bool false) ->
      Eval elseBranch v ->
      Eval (.ifThenElse cond thenBranch elseBranch) v

inductive Code : Type where
  | halt : Code
  | pushBool : Bool -> Code -> Code
  | pushInt : Int -> Code -> Code
  | pushNil : Code -> Code
  | add : Code -> Code
  | branch : Code -> Code -> Code
  deriving Repr, DecidableEq

inductive Exec : Code -> List RuntimeVal -> List RuntimeVal -> Prop where
  | halt (stack : List RuntimeVal) :
      Exec .halt stack stack
  | pushBool (b : Bool) (k : Code) (stack out : List RuntimeVal) :
      Exec k (.bool b :: stack) out ->
      Exec (.pushBool b k) stack out
  | pushInt (n : Int) (k : Code) (stack out : List RuntimeVal) :
      Exec k (.int n :: stack) out ->
      Exec (.pushInt n k) stack out
  | pushNil (k : Code) (stack out : List RuntimeVal) :
      Exec k (.nil :: stack) out ->
      Exec (.pushNil k) stack out
  | add (k : Code) (stack out : List RuntimeVal) (lhs rhs : Int) :
      Exec k (.int (lhs + rhs) :: stack) out ->
      Exec (.add k) (.int rhs :: .int lhs :: stack) out
  | branchTrue (thenCode elseCode : Code) (stack out : List RuntimeVal) :
      Exec thenCode stack out ->
      Exec (.branch thenCode elseCode) (.bool true :: stack) out
  | branchFalse (thenCode elseCode : Code) (stack out : List RuntimeVal) :
      Exec elseCode stack out ->
      Exec (.branch thenCode elseCode) (.bool false :: stack) out

def compile : Expr -> Code -> Code
  | .bool b, k => .pushBool b k
  | .int n, k => .pushInt n k
  | .nil, k => .pushNil k
  | .add lhs rhs, k => compile lhs (compile rhs (.add k))
  | .ifThenElse cond thenBranch elseBranch, k =>
      compile cond (.branch (compile thenBranch k) (compile elseBranch k))

def compileClosed (expr : Expr) : Code :=
  compile expr .halt

end Weft.SafetyCore
