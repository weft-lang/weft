import Weft.TyTheory

namespace Weft

inductive PtrTagKind : Type where
  | raw
  | mut
  | rc
  deriving Repr

inductive KernelTag : Type where
  | bool
  | int
  | nil
  | fn (arg : Ty) (eff : EffectSet) (ret : Ty)
  | record (fields : List (Name × Ty))
  | ptr (kind : PtrTagKind) (inner : Ty)
  | nominal (name : Name) (args : List Ty)
  deriving Repr

namespace TyAtom

def denotesTag : TyAtom -> KernelTag -> Prop
  | .bool, .bool => True
  | .int, .int => True
  | .nil, .nil => True
  | .fn arg eff ret, .fn arg' eff' ret' =>
      arg.SubtypeIn KernelTheory.theory arg' ∧
        EffectSet.subset eff' eff ∧
        ret'.SubtypeIn KernelTheory.theory ret
  | .record fields, .record fields' => fields = fields'
  | .ptr inner, .ptr _ inner' => inner'.SubtypeIn KernelTheory.theory inner
  | .mptr inner, .ptr .mut inner' => inner = inner'
  | .rc inner, .ptr .rc inner' => inner'.SubtypeIn KernelTheory.theory inner
  | .nominal name args, .nominal name' args' => name = name' ∧ args = args'
  | _, _ => False

theorem denotesTag_congr
    {lhs rhs : TyAtom}
    {tag : KernelTag}
    (hEq : lhs = rhs) :
    lhs.denotesTag tag -> rhs.denotesTag tag := by
  cases hEq
  intro hVal
  exact hVal

end TyAtom

namespace KernelTag

def valuation (tag : KernelTag) : TyAtom -> Prop :=
  fun atom => atom.denotesTag tag

theorem soundValuation (tag : KernelTag) :
    KernelTheory.theory.SoundValuation (valuation tag) := by
  refine ⟨?_, ?_⟩
  · intro lhs rhs hImplies hVal
    change KernelTheory.Implies lhs rhs at hImplies
    cases lhs <;> cases rhs <;> simp [KernelTheory.Implies] at hImplies
    case bool.bool =>
      exact hVal
    case int.int =>
      exact hVal
    case nil.nil =>
      exact hVal
    case fn.fn =>
      rcases hImplies with ⟨hArg, hEff, hRet⟩
      cases tag <;> simp [valuation, TyAtom.denotesTag] at hVal ⊢
      case fn argTag effTag retTag =>
        rcases hVal with ⟨hArgVal, hEffVal, hRetVal⟩
        cases hArg
        cases hRet
        exact ⟨hArgVal, EffectSet.subset_trans hEffVal hEff, hRetVal⟩
    case record.record =>
      simpa [valuation, TyAtom.denotesTag, hImplies] using hVal
    case ptr.ptr =>
      simpa [valuation, TyAtom.denotesTag, hImplies] using hVal
    case mptr.ptr =>
      cases tag <;> simp [valuation, TyAtom.denotesTag] at hVal ⊢
      case ptr kind inner =>
        cases kind <;> simp at hVal ⊢
        ·
          cases hImplies
          cases hVal
          simpa using (Ty.subtypeIn_refl KernelTheory.theory _)
    case mptr.mptr =>
      cases hImplies
      exact hVal
    case rc.ptr =>
      cases tag <;> simp [valuation, TyAtom.denotesTag] at hVal ⊢
      case ptr kind inner =>
        cases kind <;> simp at hVal ⊢
        ·
          cases hImplies
          exact hVal
    case rc.rc =>
      cases hImplies
      exact hVal
    case nominal.nominal =>
      cases hImplies.1
      cases hImplies.2
      exact hVal
  · intro lhs rhs hDisjoint hPair
    change KernelTheory.Disjoint lhs rhs at hDisjoint
    cases lhs <;> cases rhs <;> cases tag <;>
      simp [KernelTheory.Disjoint, valuation, TyAtom.denotesTag] at hDisjoint hPair
    case mptr.rc.ptr kind inner =>
      cases kind <;> simp at hDisjoint hPair
    case rc.mptr.ptr kind inner =>
      cases kind <;> simp at hDisjoint hPair

theorem exists_soundValuation :
    ∃ ν : TyAtom -> Prop, KernelTheory.theory.SoundValuation ν := by
  exact ⟨valuation .bool, soundValuation .bool⟩

end KernelTag

namespace Ty

def denotesTag (tag : KernelTag) (ty : Ty) : Prop :=
  ty.denotesUnder (KernelTag.valuation tag)

end Ty

end Weft
