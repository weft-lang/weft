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

mutual

def eqb : Ty -> Ty -> Bool
  | .bool, .bool => true
  | .int, .int => true
  | .nil, .nil => true
  | .never, .never => true
  | .any, .any => true
  | .union lhs₁ rhs₁, .union lhs₂ rhs₂ => eqb lhs₁ lhs₂ && eqb rhs₁ rhs₂
  | .inter lhs₁ rhs₁, .inter lhs₂ rhs₂ => eqb lhs₁ lhs₂ && eqb rhs₁ rhs₂
  | .compl inner₁, .compl inner₂ => eqb inner₁ inner₂
  | .fn arg₁ eff₁ ret₁, .fn arg₂ eff₂ ret₂ =>
      eqb arg₁ arg₂ && decide (eff₁ = eff₂) && eqb ret₁ ret₂
  | .record fields₁, .record fields₂ => fieldsEqb fields₁ fields₂
  | .ptr inner₁, .ptr inner₂ => eqb inner₁ inner₂
  | .mptr inner₁, .mptr inner₂ => eqb inner₁ inner₂
  | .rc inner₁, .rc inner₂ => eqb inner₁ inner₂
  | .nominal name₁ args₁, .nominal name₂ args₂ =>
      decide (name₁ = name₂) && listEqb args₁ args₂
  | _, _ => false

def listEqb : List Ty -> List Ty -> Bool
  | [], [] => true
  | lhs :: restLhs, rhs :: restRhs => eqb lhs rhs && listEqb restLhs restRhs
  | _, _ => false

def fieldsEqb : List (Name × Ty) -> List (Name × Ty) -> Bool
  | [], [] => true
  | (nameLhs, tyLhs) :: restLhs, (nameRhs, tyRhs) :: restRhs =>
      decide (nameLhs = nameRhs) && eqb tyLhs tyRhs && fieldsEqb restLhs restRhs
  | _, _ => false

end

mutual

theorem eqb_refl : ∀ ty : Ty, eqb ty ty = true
  | .bool => rfl
  | .int => rfl
  | .nil => rfl
  | .never => rfl
  | .any => rfl
  | .union lhs rhs => by simp [eqb, eqb_refl lhs, eqb_refl rhs]
  | .inter lhs rhs => by simp [eqb, eqb_refl lhs, eqb_refl rhs]
  | .compl inner => by simp [eqb, eqb_refl inner]
  | .fn arg eff ret => by simp [eqb, eqb_refl arg, eqb_refl ret]
  | .record fields => by simp [eqb, fieldsEqb_refl fields]
  | .ptr inner => by simp [eqb, eqb_refl inner]
  | .mptr inner => by simp [eqb, eqb_refl inner]
  | .rc inner => by simp [eqb, eqb_refl inner]
  | .nominal name args => by simp [eqb, listEqb_refl args]

theorem listEqb_refl : ∀ tys : List Ty, listEqb tys tys = true
  | [] => rfl
  | ty :: tys => by simp [listEqb, eqb_refl ty, listEqb_refl tys]

theorem fieldsEqb_refl : ∀ fields : List (Name × Ty), fieldsEqb fields fields = true
  | [] => rfl
  | (name, ty) :: fields => by
      simp [fieldsEqb, eqb_refl ty, fieldsEqb_refl fields]

theorem eqb_spec : ∀ lhs rhs : Ty, eqb lhs rhs = true ↔ lhs = rhs
  | .bool, .bool => by simp [eqb]
  | .bool, .int => by simp [eqb]
  | .bool, .nil => by simp [eqb]
  | .bool, .never => by simp [eqb]
  | .bool, .any => by simp [eqb]
  | .bool, .union _ _ => by simp [eqb]
  | .bool, .inter _ _ => by simp [eqb]
  | .bool, .compl _ => by simp [eqb]
  | .bool, .fn _ _ _ => by simp [eqb]
  | .bool, .record _ => by simp [eqb]
  | .bool, .ptr _ => by simp [eqb]
  | .bool, .mptr _ => by simp [eqb]
  | .bool, .rc _ => by simp [eqb]
  | .bool, .nominal _ _ => by simp [eqb]
  | .int, .bool => by simp [eqb]
  | .int, .int => by simp [eqb]
  | .int, .nil => by simp [eqb]
  | .int, .never => by simp [eqb]
  | .int, .any => by simp [eqb]
  | .int, .union _ _ => by simp [eqb]
  | .int, .inter _ _ => by simp [eqb]
  | .int, .compl _ => by simp [eqb]
  | .int, .fn _ _ _ => by simp [eqb]
  | .int, .record _ => by simp [eqb]
  | .int, .ptr _ => by simp [eqb]
  | .int, .mptr _ => by simp [eqb]
  | .int, .rc _ => by simp [eqb]
  | .int, .nominal _ _ => by simp [eqb]
  | .nil, .bool => by simp [eqb]
  | .nil, .int => by simp [eqb]
  | .nil, .nil => by simp [eqb]
  | .nil, .never => by simp [eqb]
  | .nil, .any => by simp [eqb]
  | .nil, .union _ _ => by simp [eqb]
  | .nil, .inter _ _ => by simp [eqb]
  | .nil, .compl _ => by simp [eqb]
  | .nil, .fn _ _ _ => by simp [eqb]
  | .nil, .record _ => by simp [eqb]
  | .nil, .ptr _ => by simp [eqb]
  | .nil, .mptr _ => by simp [eqb]
  | .nil, .rc _ => by simp [eqb]
  | .nil, .nominal _ _ => by simp [eqb]
  | .never, .bool => by simp [eqb]
  | .never, .int => by simp [eqb]
  | .never, .nil => by simp [eqb]
  | .never, .never => by simp [eqb]
  | .never, .any => by simp [eqb]
  | .never, .union _ _ => by simp [eqb]
  | .never, .inter _ _ => by simp [eqb]
  | .never, .compl _ => by simp [eqb]
  | .never, .fn _ _ _ => by simp [eqb]
  | .never, .record _ => by simp [eqb]
  | .never, .ptr _ => by simp [eqb]
  | .never, .mptr _ => by simp [eqb]
  | .never, .rc _ => by simp [eqb]
  | .never, .nominal _ _ => by simp [eqb]
  | .any, .bool => by simp [eqb]
  | .any, .int => by simp [eqb]
  | .any, .nil => by simp [eqb]
  | .any, .never => by simp [eqb]
  | .any, .any => by simp [eqb]
  | .any, .union _ _ => by simp [eqb]
  | .any, .inter _ _ => by simp [eqb]
  | .any, .compl _ => by simp [eqb]
  | .any, .fn _ _ _ => by simp [eqb]
  | .any, .record _ => by simp [eqb]
  | .any, .ptr _ => by simp [eqb]
  | .any, .mptr _ => by simp [eqb]
  | .any, .rc _ => by simp [eqb]
  | .any, .nominal _ _ => by simp [eqb]
  | .union lhs₁ rhs₁, rhs => by
      cases rhs with
      | bool => simp [eqb]
      | int => simp [eqb]
      | nil => simp [eqb]
      | never => simp [eqb]
      | any => simp [eqb]
      | union lhs₂ rhs₂ =>
          constructor
          · intro h
            simp [eqb, Bool.and_eq_true] at h
            cases (eqb_spec lhs₁ lhs₂).1 h.1
            cases (eqb_spec rhs₁ rhs₂).1 h.2
            rfl
          · intro h
            cases h
            simpa [eqb, Bool.and_eq_true] using And.intro (eqb_refl lhs₁) (eqb_refl rhs₁)
      | inter _ _ => simp [eqb]
      | compl _ => simp [eqb]
      | fn _ _ _ => simp [eqb]
      | record _ => simp [eqb]
      | ptr _ => simp [eqb]
      | mptr _ => simp [eqb]
      | rc _ => simp [eqb]
      | nominal _ _ => simp [eqb]
  | .inter lhs₁ rhs₁, rhs => by
      cases rhs with
      | bool => simp [eqb]
      | int => simp [eqb]
      | nil => simp [eqb]
      | never => simp [eqb]
      | any => simp [eqb]
      | union _ _ => simp [eqb]
      | inter lhs₂ rhs₂ =>
          constructor
          · intro h
            simp [eqb, Bool.and_eq_true] at h
            cases (eqb_spec lhs₁ lhs₂).1 h.1
            cases (eqb_spec rhs₁ rhs₂).1 h.2
            rfl
          · intro h
            cases h
            simpa [eqb, Bool.and_eq_true] using And.intro (eqb_refl lhs₁) (eqb_refl rhs₁)
      | compl _ => simp [eqb]
      | fn _ _ _ => simp [eqb]
      | record _ => simp [eqb]
      | ptr _ => simp [eqb]
      | mptr _ => simp [eqb]
      | rc _ => simp [eqb]
      | nominal _ _ => simp [eqb]
  | .compl inner₁, rhs => by
      cases rhs with
      | bool => simp [eqb]
      | int => simp [eqb]
      | nil => simp [eqb]
      | never => simp [eqb]
      | any => simp [eqb]
      | union _ _ => simp [eqb]
      | inter _ _ => simp [eqb]
      | compl inner₂ =>
          constructor
          · intro h
            cases (eqb_spec inner₁ inner₂).1 h
            rfl
          · intro h
            cases h
            simpa [eqb] using eqb_refl inner₁
      | fn _ _ _ => simp [eqb]
      | record _ => simp [eqb]
      | ptr _ => simp [eqb]
      | mptr _ => simp [eqb]
      | rc _ => simp [eqb]
      | nominal _ _ => simp [eqb]
  | .fn arg₁ eff₁ ret₁, rhs => by
      cases rhs with
      | bool => simp [eqb]
      | int => simp [eqb]
      | nil => simp [eqb]
      | never => simp [eqb]
      | any => simp [eqb]
      | union _ _ => simp [eqb]
      | inter _ _ => simp [eqb]
      | compl _ => simp [eqb]
      | fn arg₂ eff₂ ret₂ =>
          constructor
          · intro h
            simp [eqb, Bool.and_eq_true] at h
            rcases h with ⟨⟨hArg, hEff⟩, hRet⟩
            cases (eqb_spec arg₁ arg₂).1 hArg
            cases hEff
            cases (eqb_spec ret₁ ret₂).1 hRet
            rfl
          · intro h
            cases h
            simpa [eqb, Bool.and_eq_true] using
              And.intro
                (And.intro (eqb_refl arg₁) (show eff₁ = eff₁ from rfl))
                (eqb_refl ret₁)
      | record _ => simp [eqb]
      | ptr _ => simp [eqb]
      | mptr _ => simp [eqb]
      | rc _ => simp [eqb]
      | nominal _ _ => simp [eqb]
  | .record fields₁, rhs => by
      cases rhs with
      | bool => simp [eqb]
      | int => simp [eqb]
      | nil => simp [eqb]
      | never => simp [eqb]
      | any => simp [eqb]
      | union _ _ => simp [eqb]
      | inter _ _ => simp [eqb]
      | compl _ => simp [eqb]
      | fn _ _ _ => simp [eqb]
      | record fields₂ =>
          constructor
          · intro h
            cases (fieldsEqb_spec fields₁ fields₂).1 h
            rfl
          · intro h
            cases h
            simpa [eqb] using fieldsEqb_refl fields₁
      | ptr _ => simp [eqb]
      | mptr _ => simp [eqb]
      | rc _ => simp [eqb]
      | nominal _ _ => simp [eqb]
  | .ptr inner₁, rhs => by
      cases rhs with
      | bool => simp [eqb]
      | int => simp [eqb]
      | nil => simp [eqb]
      | never => simp [eqb]
      | any => simp [eqb]
      | union _ _ => simp [eqb]
      | inter _ _ => simp [eqb]
      | compl _ => simp [eqb]
      | fn _ _ _ => simp [eqb]
      | record _ => simp [eqb]
      | ptr inner₂ =>
          constructor
          · intro h
            cases (eqb_spec inner₁ inner₂).1 h
            rfl
          · intro h
            cases h
            simpa [eqb] using eqb_refl inner₁
      | mptr _ => simp [eqb]
      | rc _ => simp [eqb]
      | nominal _ _ => simp [eqb]
  | .mptr inner₁, rhs => by
      cases rhs with
      | bool => simp [eqb]
      | int => simp [eqb]
      | nil => simp [eqb]
      | never => simp [eqb]
      | any => simp [eqb]
      | union _ _ => simp [eqb]
      | inter _ _ => simp [eqb]
      | compl _ => simp [eqb]
      | fn _ _ _ => simp [eqb]
      | record _ => simp [eqb]
      | ptr _ => simp [eqb]
      | mptr inner₂ =>
          constructor
          · intro h
            cases (eqb_spec inner₁ inner₂).1 h
            rfl
          · intro h
            cases h
            simpa [eqb] using eqb_refl inner₁
      | rc _ => simp [eqb]
      | nominal _ _ => simp [eqb]
  | .rc inner₁, rhs => by
      cases rhs with
      | bool => simp [eqb]
      | int => simp [eqb]
      | nil => simp [eqb]
      | never => simp [eqb]
      | any => simp [eqb]
      | union _ _ => simp [eqb]
      | inter _ _ => simp [eqb]
      | compl _ => simp [eqb]
      | fn _ _ _ => simp [eqb]
      | record _ => simp [eqb]
      | ptr _ => simp [eqb]
      | mptr _ => simp [eqb]
      | rc inner₂ =>
          constructor
          · intro h
            cases (eqb_spec inner₁ inner₂).1 h
            rfl
          · intro h
            cases h
            simpa [eqb] using eqb_refl inner₁
      | nominal _ _ => simp [eqb]
  | .nominal name₁ args₁, rhs => by
      cases rhs with
      | bool => simp [eqb]
      | int => simp [eqb]
      | nil => simp [eqb]
      | never => simp [eqb]
      | any => simp [eqb]
      | union _ _ => simp [eqb]
      | inter _ _ => simp [eqb]
      | compl _ => simp [eqb]
      | fn _ _ _ => simp [eqb]
      | record _ => simp [eqb]
      | ptr _ => simp [eqb]
      | mptr _ => simp [eqb]
      | rc _ => simp [eqb]
      | nominal name₂ args₂ =>
          constructor
          · intro h
            simp [eqb, Bool.and_eq_true] at h
            rcases h with ⟨hName, hArgs⟩
            cases hName
            cases (listEqb_spec args₁ args₂).1 hArgs
            rfl
          · intro h
            cases h
            simpa [eqb, Bool.and_eq_true] using
              And.intro (show name₁ = name₁ from rfl) (listEqb_refl args₁)

theorem listEqb_spec : ∀ lhs rhs : List Ty, listEqb lhs rhs = true ↔ lhs = rhs
  | [], [] => by simp [listEqb]
  | [], _ :: _ => by simp [listEqb]
  | _ :: _, [] => by simp [listEqb]
  | lhs :: restLhs, rhs :: restRhs => by
      simp [listEqb, eqb_spec lhs rhs, listEqb_spec restLhs restRhs]

theorem fieldsEqb_spec :
    ∀ lhs rhs : List (Name × Ty), fieldsEqb lhs rhs = true ↔ lhs = rhs
  | [], [] => by simp [fieldsEqb]
  | [], _ :: _ => by simp [fieldsEqb]
  | _ :: _, [] => by simp [fieldsEqb]
  | (nameLhs, tyLhs) :: restLhs, (nameRhs, tyRhs) :: restRhs => by
      simp [fieldsEqb, eqb_spec tyLhs tyRhs, fieldsEqb_spec restLhs restRhs, and_assoc]

end

def pureFn (arg ret : Ty) : Ty :=
  fn arg EffectSet.empty ret

def nullable (ty : Ty) : Ty :=
  union ty nil

end Ty

end Weft
