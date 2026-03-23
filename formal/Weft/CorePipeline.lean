import Weft.CoreMachine

namespace Weft.SafetyCore

inductive SurfaceExpr : Type where
  | bool : Bool -> SurfaceExpr
  | int : Int -> SurfaceExpr
  | nil : SurfaceExpr
  | add : SurfaceExpr -> SurfaceExpr -> SurfaceExpr
  | ifThenElse : SurfaceExpr -> SurfaceExpr -> SurfaceExpr -> SurfaceExpr
  deriving Repr, DecidableEq

def parseSurface : SurfaceExpr -> Expr
  | .bool b => .bool b
  | .int n => .int n
  | .nil => .nil
  | .add lhs rhs => .add (parseSurface lhs) (parseSurface rhs)
  | .ifThenElse cond thenBranch elseBranch =>
      .ifThenElse (parseSurface cond) (parseSurface thenBranch) (parseSurface elseBranch)

structure CheckedExpr : Type where
  expr : Expr
  ty : Weft.Ty
  typed : HasType expr ty

structure CheckedTy (expr : Expr) : Type where
  ty : Weft.Ty
  typed : HasType expr ty

def check : (expr : Expr) -> Option (CheckedTy expr)
  | .bool b => some { ty := Weft.Ty.bool, typed := HasType.bool b }
  | .int n => some { ty := Weft.Ty.int, typed := HasType.int n }
  | .nil => some { ty := Weft.Ty.nil, typed := HasType.nil }
  | .add lhs rhs =>
      match check lhs, check rhs with
      | some { ty := Weft.Ty.int, typed := hLhs }, some { ty := Weft.Ty.int, typed := hRhs } =>
          some { ty := Weft.Ty.int, typed := HasType.add lhs rhs hLhs hRhs }
      | _, _ => none
  | .ifThenElse cond thenBranch elseBranch =>
      match check cond, check thenBranch, check elseBranch with
      | some { ty := Weft.Ty.bool, typed := hCond },
        some { ty := Weft.Ty.bool, typed := hThen },
        some { ty := Weft.Ty.bool, typed := hElse } =>
          some { ty := Weft.Ty.bool, typed := HasType.ifThenElse cond thenBranch elseBranch Weft.Ty.bool hCond hThen hElse }
      | some { ty := Weft.Ty.bool, typed := hCond },
        some { ty := Weft.Ty.int, typed := hThen },
        some { ty := Weft.Ty.int, typed := hElse } =>
          some { ty := Weft.Ty.int, typed := HasType.ifThenElse cond thenBranch elseBranch Weft.Ty.int hCond hThen hElse }
      | some { ty := Weft.Ty.bool, typed := hCond },
        some { ty := Weft.Ty.nil, typed := hThen },
        some { ty := Weft.Ty.nil, typed := hElse } =>
          some { ty := Weft.Ty.nil, typed := HasType.ifThenElse cond thenBranch elseBranch Weft.Ty.nil hCond hThen hElse }
      | _, _, _ => none

def inferType (expr : Expr) : Option Weft.Ty :=
  match check expr with
  | some checked => some checked.ty
  | none => none

inductive IRExpr : Type where
  | const : RuntimeVal -> IRExpr
  | add : IRExpr -> IRExpr -> IRExpr
  | ite : IRExpr -> IRExpr -> IRExpr -> IRExpr
  deriving Repr, DecidableEq

inductive IREval : IRExpr -> RuntimeVal -> Prop where
  | const (value : RuntimeVal) :
      IREval (.const value) value
  | add (lhs rhs : IRExpr) (lhsVal rhsVal : Int) :
      IREval lhs (.int lhsVal) ->
      IREval rhs (.int rhsVal) ->
      IREval (.add lhs rhs) (.int (lhsVal + rhsVal))
  | ifTrue (cond thenBranch elseBranch : IRExpr) (value : RuntimeVal) :
      IREval cond (.bool true) ->
      IREval thenBranch value ->
      IREval (.ite cond thenBranch elseBranch) value
  | ifFalse (cond thenBranch elseBranch : IRExpr) (value : RuntimeVal) :
      IREval cond (.bool false) ->
      IREval elseBranch value ->
      IREval (.ite cond thenBranch elseBranch) value

def lower : Expr -> IRExpr
  | .bool b => .const (.bool b)
  | .int n => .const (.int n)
  | .nil => .const .nil
  | .add lhs rhs => .add (lower lhs) (lower rhs)
  | .ifThenElse cond thenBranch elseBranch =>
      .ite (lower cond) (lower thenBranch) (lower elseBranch)

def emitIR : IRExpr -> Code -> Code
  | .const (.bool b), k => .pushBool b k
  | .const (.int n), k => .pushInt n k
  | .const .nil, k => .pushNil k
  | .add lhs rhs, k => emitIR lhs (emitIR rhs (.add k))
  | .ite cond thenBranch elseBranch, k =>
      emitIR cond (.branch (emitIR thenBranch k) (emitIR elseBranch k))

def emitClosed (ir : IRExpr) : Code :=
  emitIR ir .halt

def parseStage : Weft.Stage SurfaceExpr Expr where
  compile surface := .ok (parseSurface surface)

def typecheckStage : Weft.Stage Expr CheckedExpr where
  compile expr :=
    match check expr with
    | some checked => .ok { expr := expr, ty := checked.ty, typed := checked.typed }
    | none => .error "type error"

def lowerStage : Weft.Stage CheckedExpr IRExpr where
  compile checked := .ok (lower checked.expr)

def emitStage : Weft.Stage IRExpr Code where
  compile ir := .ok (emitClosed ir)

def stagedCompilerPipeline : Weft.CompilerPipeline where
  Source := SurfaceExpr
  Parsed := Expr
  Typed := CheckedExpr
  IR := IRExpr
  Native := Code
  parse := parseStage
  typecheck := typecheckStage
  lower := lowerStage
  emit := emitStage

end Weft.SafetyCore
