import Weft.CoreEffects

namespace Weft.CoreEffects

open Weft.SafetyCore

inductive Code : Type where
  | halt : Code
  | pushBool : Bool -> Code -> Code
  | pushInt : Int -> Code -> Code
  | pushNil : Code -> Code
  | add : Code -> Code
  | branch : Code -> Code -> Code
  | performBool : Weft.EffectName -> Code -> Code
  | handleBool : Weft.EffectName -> Bool -> Code -> Code -> Code
  deriving Repr, DecidableEq

inductive Exec : Oracle -> Code -> List RuntimeVal -> List RuntimeVal -> List Weft.EffectName -> Prop where
  | halt (oracle : Oracle) (stack : List RuntimeVal) :
      Exec oracle .halt stack stack []
  | pushBool (oracle : Oracle) (b : Bool) (k : Code) (stack out : List RuntimeVal)
      (trace : List Weft.EffectName) :
      Exec oracle k (.bool b :: stack) out trace ->
      Exec oracle (.pushBool b k) stack out trace
  | pushInt (oracle : Oracle) (n : Int) (k : Code) (stack out : List RuntimeVal)
      (trace : List Weft.EffectName) :
      Exec oracle k (.int n :: stack) out trace ->
      Exec oracle (.pushInt n k) stack out trace
  | pushNil (oracle : Oracle) (k : Code) (stack out : List RuntimeVal)
      (trace : List Weft.EffectName) :
      Exec oracle k (.nil :: stack) out trace ->
      Exec oracle (.pushNil k) stack out trace
  | add (oracle : Oracle) (k : Code) (stack out : List RuntimeVal)
      (trace : List Weft.EffectName) (lhs rhs : Int) :
      Exec oracle k (.int (lhs + rhs) :: stack) out trace ->
      Exec oracle (.add k) (.int rhs :: .int lhs :: stack) out trace
  | branchTrue (oracle : Oracle) (thenCode elseCode : Code) (stack out : List RuntimeVal)
      (trace : List Weft.EffectName) :
      Exec oracle thenCode stack out trace ->
      Exec oracle (.branch thenCode elseCode) (.bool true :: stack) out trace
  | branchFalse (oracle : Oracle) (thenCode elseCode : Code) (stack out : List RuntimeVal)
      (trace : List Weft.EffectName) :
      Exec oracle elseCode stack out trace ->
      Exec oracle (.branch thenCode elseCode) (.bool false :: stack) out trace
  | performBool (oracle : Oracle) (effect : Weft.EffectName) (k : Code) (stack out : List RuntimeVal)
      (trace : List Weft.EffectName) :
      Exec oracle k (.bool (oracle effect) :: stack) out trace ->
      Exec oracle (.performBool effect k) stack out (effect :: trace)
  | handleBool (oracle : Oracle) (effect : Weft.EffectName) (value : Bool)
      (body k : Code) (stack mid out : List RuntimeVal)
      (traceBody traceK : List Weft.EffectName) :
      Exec (fun effect' => if effect' = effect then value else oracle effect') body stack mid traceBody ->
      Exec oracle k mid out traceK ->
      Exec oracle (.handleBool effect value body k) stack out
        (traceBody.filter (fun effect' => effect' != effect) ++ traceK)

def compile : Expr -> Code -> Code
  | .bool b, k => .pushBool b k
  | .int n, k => .pushInt n k
  | .nil, k => .pushNil k
  | .add lhs rhs, k => compile lhs (compile rhs (.add k))
  | .ifThenElse cond thenBranch elseBranch, k =>
      compile cond (.branch (compile thenBranch k) (compile elseBranch k))
  | .performBool effect, k => .performBool effect k
  | .handleBool effect value body, k =>
      .handleBool effect value (compile body .halt) k

def compileClosed (expr : Expr) : Code :=
  compile expr .halt

end Weft.CoreEffects
