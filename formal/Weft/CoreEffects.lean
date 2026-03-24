import Weft.Compiler
import Weft.CoreMachine
import Weft.Effects

namespace Weft.CoreEffects

open Weft.SafetyCore

abbrev Oracle : Type := Weft.EffectName -> Bool

def observeIOTrace (oracle : Oracle) : List Weft.EffectName -> List Weft.IOEvent
  | [] => []
  | effect :: trace => .effectQuery effect (oracle effect) :: observeIOTrace oracle trace

@[simp] theorem observeIOTrace_append
    (oracle : Oracle)
    (lhs rhs : List Weft.EffectName) :
    observeIOTrace oracle (lhs ++ rhs) = observeIOTrace oracle lhs ++ observeIOTrace oracle rhs := by
  induction lhs with
  | nil =>
      simp [observeIOTrace]
  | cons head tail ih =>
      simp [observeIOTrace, ih]

@[simp] theorem observeIOTrace_query_mem_iff
    {oracle : Oracle}
    {trace : List Weft.EffectName}
    {effect : Weft.EffectName}
    {response : Bool} :
    Weft.IOEvent.effectQuery effect response ∈ observeIOTrace oracle trace ↔
      effect ∈ trace ∧ response = oracle effect := by
  induction trace with
  | nil =>
      simp [observeIOTrace]
  | cons head tail ih =>
      constructor
      · intro hMem
        simp [observeIOTrace] at hMem
        rcases hMem with hHead | hTail
        · rcases hHead with ⟨rfl, hResp⟩
          exact ⟨List.mem_cons.mpr (Or.inl rfl), by simpa using hResp⟩
        · rcases ih.mp hTail with ⟨hInTail, hResp⟩
          exact ⟨List.mem_cons.mpr (Or.inr hInTail), hResp⟩
      · intro hObserved
        rcases hObserved with ⟨hInTrace, hResp⟩
        simp [observeIOTrace]
        rcases List.mem_cons.mp hInTrace with rfl | hInTail
        · left
          simp [hResp]
        · right
          exact ih.mpr ⟨hInTail, hResp⟩

theorem trace_eq_nil_of_forall_not_mem
    {trace : List Weft.EffectName}
    (hNone : ∀ effect : Weft.EffectName, effect ∉ trace) :
    trace = [] := by
  cases trace with
  | nil =>
      rfl
  | cons head tail =>
      exfalso
      exact hNone head (List.mem_cons.mpr (Or.inl rfl))

inductive Expr : Type where
  | bool : Bool -> Expr
  | int : Int -> Expr
  | nil : Expr
  | add : Expr -> Expr -> Expr
  | ifThenElse : Expr -> Expr -> Expr -> Expr
  | performBool : Weft.EffectName -> Expr
  | handleBool : Weft.EffectName -> Bool -> Expr -> Expr
  deriving Repr, DecidableEq

inductive HasType : Expr -> Weft.Ty -> Weft.EffectSet -> Prop where
  | bool (b : Bool) :
      HasType (.bool b) Weft.Ty.bool Weft.EffectSet.empty
  | int (n : Int) :
      HasType (.int n) Weft.Ty.int Weft.EffectSet.empty
  | nil :
      HasType .nil Weft.Ty.nil Weft.EffectSet.empty
  | add (lhs rhs : Expr) (eL eR : Weft.EffectSet) :
      HasType lhs Weft.Ty.int eL ->
      HasType rhs Weft.Ty.int eR ->
      HasType (.add lhs rhs) Weft.Ty.int (Weft.EffectSet.union eL eR)
  | ifThenElse (cond thenBranch elseBranch : Expr) (ty : Weft.Ty)
      (eCond eThen eElse : Weft.EffectSet) :
      HasType cond Weft.Ty.bool eCond ->
      HasType thenBranch ty eThen ->
      HasType elseBranch ty eElse ->
      HasType (.ifThenElse cond thenBranch elseBranch) ty
        (Weft.EffectSet.union eCond (Weft.EffectSet.union eThen eElse))
  | performBool (effect : Weft.EffectName) :
      HasType (.performBool effect) Weft.Ty.bool (Weft.EffectSet.singleton effect)
  | handleBool (effect : Weft.EffectName) (value : Bool) (body : Expr) (ty : Weft.Ty)
      (bodyEffects : Weft.EffectSet) :
      HasType body ty bodyEffects ->
      HasType (.handleBool effect value body) ty
        (Weft.EffectSet.handle bodyEffects (Weft.EffectSet.singleton effect))

inductive Eval : Oracle -> Expr -> RuntimeVal -> List Weft.EffectName -> Prop where
  | bool (oracle : Oracle) (b : Bool) :
      Eval oracle (.bool b) (.bool b) []
  | int (oracle : Oracle) (n : Int) :
      Eval oracle (.int n) (.int n) []
  | nil (oracle : Oracle) :
      Eval oracle .nil .nil []
  | add (oracle : Oracle) (lhs rhs : Expr) (lhsVal rhsVal : Int)
      (traceL traceR : List Weft.EffectName) :
      Eval oracle lhs (.int lhsVal) traceL ->
      Eval oracle rhs (.int rhsVal) traceR ->
      Eval oracle (.add lhs rhs) (.int (lhsVal + rhsVal)) (traceL ++ traceR)
  | ifTrue (oracle : Oracle) (cond thenBranch elseBranch : Expr) (value : RuntimeVal)
      (traceCond traceThen : List Weft.EffectName) :
      Eval oracle cond (.bool true) traceCond ->
      Eval oracle thenBranch value traceThen ->
      Eval oracle (.ifThenElse cond thenBranch elseBranch) value (traceCond ++ traceThen)
  | ifFalse (oracle : Oracle) (cond thenBranch elseBranch : Expr) (value : RuntimeVal)
      (traceCond traceElse : List Weft.EffectName) :
      Eval oracle cond (.bool false) traceCond ->
      Eval oracle elseBranch value traceElse ->
      Eval oracle (.ifThenElse cond thenBranch elseBranch) value (traceCond ++ traceElse)
  | performBool (oracle : Oracle) (effect : Weft.EffectName) :
      Eval oracle (.performBool effect) (.bool (oracle effect)) [effect]
  | handleBool (oracle : Oracle) (effect : Weft.EffectName) (value : Bool)
      (body : Expr) (result : RuntimeVal) (trace : List Weft.EffectName) :
      Eval (fun effect' => if effect' = effect then value else oracle effect') body result trace ->
      Eval oracle (.handleBool effect value body) result (trace.filter (fun effect' => effect' != effect))

end Weft.CoreEffects
