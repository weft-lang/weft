# Property testing in Weft

Weft property tests are ordinary typed computations interpreted through one
bounded-choice effect. A fixed seed finds failures reproducibly; an exact
choice log replays them independently of the random algorithm; shrinking
re-executes the same generator and property without cloning the generated
value or using multi-shot continuations.

The API lives under `stdlib/test/property`. Deterministic pseudo-random values
live separately in `stdlib/random`; they are not cryptographic randomness and
do not introduce process-global state.

```weft
use stdlib/random as random
use stdlib/result.{*}
use stdlib/test/property as prop

fn in_range(value: usize) -> bool {
  value < 1000
}

test "generated identifiers stay in range" {
  let configured = prop.config(random.seed(42), 100, 16, 1000, 1000)
  let config = configured.expect("a property campaign needs at least one case")
  let identifiers = prop.usize_below(1000).expect("the identifier domain is nonempty")

  prop.check(config, identifiers, in_range)
}
```

`config` makes every campaign budget explicit: cases, structural size,
discarded specimens, and shrinking. `prop.check` reports a structured `Test`
diagnostic. `prop.run` returns the exhaustive `Passed`, `Falsified`,
`GenerationExhausted`, or `HandlerContractViolated` variants for a custom
runner.

## Exact replay

A counterexample carries the size and discard limits as well as its minimized
choice program. Replay therefore does not depend on whatever pseudo-random
algorithm a later release uses.

```weft
use stdlib/test/property/replay as replay

let replayed = replay.run(
  generator,
  counterexample.limits(),
  counterexample.choices()
)
```

Replay checks the complete program. It distinguishes an exhausted choice log,
a changed bound, unused choices, discard exhaustion, and a generator contract
violation rather than silently adjusting stale data.

## Bounded exhaustive enumeration

`stdlib/test/property/enumerate` re-executes the same generator from the start
for each choice program. It does not capture a continuation or construct a
second generator tree. Both the total path count and the choices permitted in
one path are explicit bounds:

```weft
use stdlib/test/property/enumerate as enumerate
use stdlib/test/property/enumerate.{VisitNext, VisitStop}

fn stop_at_true_false(value: (bool, bool)) -> enumerate.Visit {
  match value {
    (true, false) -> VisitStop
    _ -> VisitNext
  }
}

let pairs = prop.pair(prop.boolean(), prop.boolean())
let outcome = enumerate.run(
  pairs,
  prop.limits(2, 0),
  enumerate.budget(4, 2),
  stop_at_true_false
)
```

Enumeration visits choice programs in stable lexicographic order. A visitor
consumes each generated value exactly once and returns `VisitNext` or
`VisitStop`; a stop outcome carries the exact replay log. Rejected generator
paths spend the total path budget but do not call the visitor.

## Refinement without hidden copying

The bounded refinement primitive is `filter_map`, not an unbounded `filter`.
Its callback consumes one generated value and returns `Some` with the accepted
value or `None` to discard it. This shape is safe for linearly owned values and
can change the result type while narrowing:

```weft
use stdlib/option.{None, Option, Some}

fn even_half(value: usize) -> Option<usize> {
  if value % 2 == 0 {
    Some<usize>(value / 2)
  } else {
    None<usize>()
  }
}

let source = prop.usize_below(100).expect("nonempty domain")
let even_halves = prop.filter_map(source, 20, even_half)
```

Both the local attempt count and the campaign discard limit are hard bounds.
There is deliberately no generator operation which may retry forever.

## Scalar and collection domains

`u8` through `u64`, `usize`, `i8` through `i64`, and `isize` cover their full
value sets. `unicode_scalar` maps around the surrogate interval, so every draw
is valid and the distribution does not depend on rejection. `either`,
`one_of`, and checked `frequency` preserve alternatives as typed generator
values.

Collection lengths are validated inclusive domains. The campaign size caps
their maximum while preserving an explicit minimum:

```weft
let small = prop.lengths(0, 32).expect("ordered finite lengths")
let labels = prop.str(small)
let packets = prop.bytes(small)
let counters = prop.vector(prop.i64(), small)
let snapshots = prop.persistent_vector(prop.boolean(), small)
```

`prop.str` measures the length domain in Unicode scalars and always returns
canonical UTF-8. It generates scalar values directly—surrogates are not part
of the domain—then encodes the finite traversal once instead of repeatedly
concatenating temporary one-scalar strings.

The mutable Vector generator returns `Gen<owned Vector<T>>`; ownership is not
erased merely to fit a common collection interface. Immutable Bytes, List, and
PersistentVector generators retain their ordinary value semantics.

## Alternate interpretations

`prop.sample(generator, limits) -[Draw]> SampleResult<T>` leaves the `Draw`
effect explicit. The standard random and replay modules interpret the same
generator semantics; custom deterministic handlers can enumerate or inject
choices without gaining access to `Gen<T>`'s closure representation or the
mutable campaign worklists. Every returned choice is checked against its
opaque nonempty `ChoiceBound` before it can select a value.
