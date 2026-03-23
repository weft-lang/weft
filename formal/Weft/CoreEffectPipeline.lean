import Weft.CoreEffectMachine
import Weft.CoreSubtype

namespace Weft.CoreEffects

open Weft.SafetyCore

inductive SurfaceExpr : Type where
  | bool : Bool -> SurfaceExpr
  | int : Int -> SurfaceExpr
  | nil : SurfaceExpr
  | add : SurfaceExpr -> SurfaceExpr -> SurfaceExpr
  | ifThenElse : SurfaceExpr -> SurfaceExpr -> SurfaceExpr -> SurfaceExpr
  | performBool : Weft.EffectName -> SurfaceExpr
  | handleBool : Weft.EffectName -> Bool -> SurfaceExpr -> SurfaceExpr
  deriving Repr, DecidableEq

def parseSurface : SurfaceExpr -> Expr
  | .bool b => .bool b
  | .int n => .int n
  | .nil => .nil
  | .add lhs rhs => .add (parseSurface lhs) (parseSurface rhs)
  | .ifThenElse cond thenBranch elseBranch =>
      .ifThenElse (parseSurface cond) (parseSurface thenBranch) (parseSurface elseBranch)
  | .performBool effect => .performBool effect
  | .handleBool effect value body => .handleBool effect value (parseSurface body)

structure CheckedExpr : Type where
  expr : Expr
  ty : Weft.Ty
  effects : Weft.EffectSet
  typed : HasType expr ty effects

structure CheckedTy (expr : Expr) : Type where
  ty : Weft.Ty
  effects : Weft.EffectSet
  typed : HasType expr ty effects

def check : (expr : Expr) -> Option (CheckedTy expr)
  | .bool b =>
      some { ty := Weft.Ty.bool, effects := Weft.EffectSet.empty, typed := HasType.bool b }
  | .int n =>
      some { ty := Weft.Ty.int, effects := Weft.EffectSet.empty, typed := HasType.int n }
  | .nil =>
      some { ty := Weft.Ty.nil, effects := Weft.EffectSet.empty, typed := HasType.nil }
  | .add lhs rhs =>
      match check lhs, check rhs with
      | some { ty := Weft.Ty.int, effects := eL, typed := hLhs },
        some { ty := Weft.Ty.int, effects := eR, typed := hRhs } =>
          some {
            ty := Weft.Ty.int
            effects := Weft.EffectSet.union eL eR
            typed := HasType.add lhs rhs eL eR hLhs hRhs
          }
      | _, _ => none
  | .ifThenElse cond thenBranch elseBranch =>
      match check cond, check thenBranch, check elseBranch with
      | some { ty := Weft.Ty.bool, effects := eCond, typed := hCond },
        some { ty := Weft.Ty.bool, effects := eThen, typed := hThen },
        some { ty := Weft.Ty.bool, effects := eElse, typed := hElse } =>
          some {
            ty := Weft.Ty.bool
            effects := Weft.EffectSet.union eCond (Weft.EffectSet.union eThen eElse)
            typed := HasType.ifThenElse cond thenBranch elseBranch Weft.Ty.bool eCond eThen eElse hCond hThen hElse
          }
      | some { ty := Weft.Ty.bool, effects := eCond, typed := hCond },
        some { ty := Weft.Ty.int, effects := eThen, typed := hThen },
        some { ty := Weft.Ty.int, effects := eElse, typed := hElse } =>
          some {
            ty := Weft.Ty.int
            effects := Weft.EffectSet.union eCond (Weft.EffectSet.union eThen eElse)
            typed := HasType.ifThenElse cond thenBranch elseBranch Weft.Ty.int eCond eThen eElse hCond hThen hElse
          }
      | some { ty := Weft.Ty.bool, effects := eCond, typed := hCond },
        some { ty := Weft.Ty.nil, effects := eThen, typed := hThen },
        some { ty := Weft.Ty.nil, effects := eElse, typed := hElse } =>
          some {
            ty := Weft.Ty.nil
            effects := Weft.EffectSet.union eCond (Weft.EffectSet.union eThen eElse)
            typed := HasType.ifThenElse cond thenBranch elseBranch Weft.Ty.nil eCond eThen eElse hCond hThen hElse
          }
      | _, _, _ => none
  | .performBool effect =>
      some {
        ty := Weft.Ty.bool
        effects := Weft.EffectSet.singleton effect
        typed := HasType.performBool effect
      }
  | .handleBool effect value body =>
      match check body with
      | some { ty := ty, effects := bodyEffects, typed := hBody } =>
          some {
            ty := ty
            effects := Weft.EffectSet.handle bodyEffects (Weft.EffectSet.singleton effect)
            typed := HasType.handleBool effect value body ty bodyEffects hBody
          }
      | none => none

def inferType (expr : Expr) : Option Weft.Ty :=
  match check expr with
  | some checked => some checked.ty
  | none => none

def inferEffects (expr : Expr) : Option Weft.EffectSet :=
  match check expr with
  | some checked => some checked.effects
  | none => none

def checkAgainst (expr : Expr) (expected : Weft.Ty) : Bool :=
  match inferType expr, Weft.CoreSetTy.ofTy expected with
  | some inferred, some expectedCore =>
      match Weft.CoreSetTy.ofTy inferred with
      | some inferredCore => inferredCore.subtypeb expectedCore
      | none => false
  | _, _ => false

inductive IRExpr : Type where
  | const : RuntimeVal -> IRExpr
  | add : IRExpr -> IRExpr -> IRExpr
  | ite : IRExpr -> IRExpr -> IRExpr -> IRExpr
  | performBool : Weft.EffectName -> IRExpr
  | handleBool : Weft.EffectName -> Bool -> IRExpr -> IRExpr
  deriving Repr, DecidableEq

def IRExpr.toExpr : IRExpr -> Expr
  | .const (.bool b) => .bool b
  | .const (.int n) => .int n
  | .const .nil => .nil
  | .add lhs rhs => .add lhs.toExpr rhs.toExpr
  | .ite cond thenBranch elseBranch =>
      .ifThenElse cond.toExpr thenBranch.toExpr elseBranch.toExpr
  | .performBool effect => .performBool effect
  | .handleBool effect value body => .handleBool effect value body.toExpr

inductive IREval : Oracle -> IRExpr -> RuntimeVal -> List Weft.EffectName -> Prop where
  | const (oracle : Oracle) (value : RuntimeVal) :
      IREval oracle (.const value) value []
  | add (oracle : Oracle) (lhs rhs : IRExpr) (lhsVal rhsVal : Int)
      (traceL traceR : List Weft.EffectName) :
      IREval oracle lhs (.int lhsVal) traceL ->
      IREval oracle rhs (.int rhsVal) traceR ->
      IREval oracle (.add lhs rhs) (.int (lhsVal + rhsVal)) (traceL ++ traceR)
  | ifTrue (oracle : Oracle) (cond thenBranch elseBranch : IRExpr) (value : RuntimeVal)
      (traceCond traceThen : List Weft.EffectName) :
      IREval oracle cond (.bool true) traceCond ->
      IREval oracle thenBranch value traceThen ->
      IREval oracle (.ite cond thenBranch elseBranch) value (traceCond ++ traceThen)
  | ifFalse (oracle : Oracle) (cond thenBranch elseBranch : IRExpr) (value : RuntimeVal)
      (traceCond traceElse : List Weft.EffectName) :
      IREval oracle cond (.bool false) traceCond ->
      IREval oracle elseBranch value traceElse ->
      IREval oracle (.ite cond thenBranch elseBranch) value (traceCond ++ traceElse)
  | performBool (oracle : Oracle) (effect : Weft.EffectName) :
      IREval oracle (.performBool effect) (.bool (oracle effect)) [effect]
  | handleBool (oracle : Oracle) (effect : Weft.EffectName) (value : Bool)
      (body : IRExpr) (result : RuntimeVal) (trace : List Weft.EffectName) :
      IREval (fun effect' => if effect' = effect then value else oracle effect') body result trace ->
      IREval oracle (.handleBool effect value body) result (trace.filter (fun effect' => effect' != effect))

def lower : Expr -> IRExpr
  | .bool b => .const (.bool b)
  | .int n => .const (.int n)
  | .nil => .const .nil
  | .add lhs rhs => .add (lower lhs) (lower rhs)
  | .ifThenElse cond thenBranch elseBranch =>
      .ite (lower cond) (lower thenBranch) (lower elseBranch)
  | .performBool effect => .performBool effect
  | .handleBool effect value body => .handleBool effect value (lower body)

def emitIR : IRExpr -> Code -> Code
  | .const (.bool b), k => .pushBool b k
  | .const (.int n), k => .pushInt n k
  | .const .nil, k => .pushNil k
  | .add lhs rhs, k => emitIR lhs (emitIR rhs (.add k))
  | .ite cond thenBranch elseBranch, k =>
      emitIR cond (.branch (emitIR thenBranch k) (emitIR elseBranch k))
  | .performBool effect, k => .performBool effect k
  | .handleBool effect value body, k =>
      .handleBool effect value (emitIR body .halt) k

def emitClosed (ir : IRExpr) : Code :=
  emitIR ir .halt

def parseStage : Weft.Stage SurfaceExpr Expr where
  compile surface := .ok (parseSurface surface)

def typecheckStage : Weft.Stage Expr CheckedExpr where
  compile expr :=
    match check expr with
    | some checked =>
        .ok {
          expr := expr
          ty := checked.ty
          effects := checked.effects
          typed := checked.typed
        }
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

end Weft.CoreEffects
