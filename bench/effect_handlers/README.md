# Effect Handlers Benchmark Suite — Weft ports

Ports of [effect-handlers/effect-handlers-bench](https://github.com/effect-handlers/effect-handlers-bench),
the shared suite used by the Eff (OOPSLA'21), Lexa (OOPSLA'24), libseff
(OOPSLA'24), and tracing-JIT (OOPSLA'25) evaluations. Run with
`bash bench/effect_handlers/run_eh_bench.sh`; results append to
`results.jsonl`. Every benchmark self-verifies the spec output and the
runner treats a wrong result as a failure.

## Ported (spec "large" inputs unless noted)

| Benchmark | Input | Expected | Exercises |
|---|---|---|---|
| countdown | 200000000 | 0 | State get/put through a tail-resumptive handler |
| fibonacci_recursive | 42 | 433494437 | pure call stack (no effects) |
| product_early | 100000 × 1000-list | 0 | abortive handler (clause never resumes), 1000-frame unwind |
| iterator | 40000000 | 800000020000000 | tail-resumptive emit + handler-side accumulation |
| generator | height 25 | 67108837 | Tier-5 fibers: 2^25−1 yields via `stdlib/generator` |
| handler_sieve | **20000** (spec: 60000) | 21171191 | ~2200 nested same-label handlers, clause delegates outward |
| parsing_dollars | 20000 | 200010000 | two simultaneous effects (Read supply + Emit sink) |

## Deviations

- **countdown**: the OCaml reference counts down by self-tail-call; Weft
  has no TCO yet (roadmap A5) so the loop is a `while`. The measured
  work — 200M get/put pairs through the handler — is identical.
- **handler_sieve**: pinned at n=20000. The sieve recursion keeps one
  native frame per candidate and overflows the 64MB stack between
  n=20000 and n=30000. Raise to the spec 60000 when frames shrink or
  self-tail-calls stop consuming stack (A5).

## Not portable — recorded, not skipped silently

- **resume_nontail**: requires resuming the continuation in NON-tail
  position (`let y = k(0) in ...`). Weft's checker rejects non-tail
  continuation calls by design ("continuation call must be tail
  position"). Revisit if Tier-5 grows non-tail resumption.
- **nqueens, triples, tree_explore**: require multi-shot continuations
  (resuming the same continuation more than once for backtracking /
  nondeterminism). Weft's continuations are one-shot by design — see
  roadmap B1.8 for the evidence-backed rationale (constant-time
  capture/resume, no stack copying, plain-RC soundness).
