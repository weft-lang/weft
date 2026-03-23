import Weft.Effects

namespace Weft

theorem handled_capabilities_do_not_grow
    (available handled : EffectSet) :
    EffectSet.subset (EffectSet.handle available handled) available :=
  EffectSet.handle_subset available handled

theorem handled_empty_context_stays_empty
    (handled : EffectSet) :
    EffectSet.subset (EffectSet.handle EffectSet.empty handled) EffectSet.empty :=
  EffectSet.handle_subset EffectSet.empty handled

end Weft
