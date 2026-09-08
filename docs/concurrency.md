# Concurrency in Weft

Concurrency policy lives at the call boundary. Tests can run children in a
deterministic order; an event-loop handler can run other children while one
waits for a timer or socket, using the same task functions.

Weft separates pure parallel computation from effectful task scheduling.
Both are structured: their handler owns every child, waits for
accepted work during normal return or abort, and destroys unobserved results.
There is no detached task hidden behind either API.

| Need | Namespace | Callback | Observation |
|---|---|---|---|
| CPU/data parallelism | `stdlib/par` | Pure `() -> T` | `par.fork` then `handle.join()` |
| Task scheduling and readiness | `stdlib/task` | Effectful `() -[TaskScope, E]> T` | `task.spawn` then `child.join()` |
| Bounded task communication | `stdlib/task/channel` | `Channel<T>` operations | Typed send/receive/close outcomes |
| Cooperative cancellation | `stdlib/task/cancellation` | Explicit checkpoints | Typed completion or reason |
| Process shutdown | `stdlib/task/shutdown` | Event-loop signal observation | Portable typed signal reason |

## Structured tasks

`Task<T>` is a unique, single-use observation right, not a lifetime owner.
The enclosing `TaskScope` owns the child. Consuming `join` returns an ordinary
`T`:

```weft run
use stdlib/task as task

fn total() -[task.TaskScope]> i64 {
  let left = task.spawn(() => 20)
  let right = task.spawn(() => 22)
  left.join() + right.join()
}

fn main() -> i64 {
  if task.with_sequential(total) == 42 { 0 } else { 1 }
}
```

Effects remain the function's real capability contract. `TaskScope` does not
create an `async fn` kind, and `Task<T>` is not a `Future<T>`: there is no
public poll/wake protocol and no async colouring. A task that waits for a
duration, TCP readiness, or channel capacity suspends its one-shot continuation
inside the chosen handler; callers keep using the ordinary `Sleep`,
`TcpReadiness`, or `Channel<T>` effects. Deadlines read
`time/monotonic.MonotonicClock`, so wall-clock adjustment cannot move them.
Certificate validation and other civil-time work use the independent
`time/wall.WallClock` authority; possessing an event-loop scheduler does not
grant it.

Suspension therefore does not change a function kind. The event-loop handler
interprets `Sleep` at the boundary, while the child remains an ordinary
effectful function:

```weft run
use stdlib/result.{Err, Ok}
use stdlib/task as task
use stdlib/time as time
use stdlib/time/sleep as sleep
use stdlib/time/sleep.{Sleep}

fn delayed_answer() -[Sleep]> i64 {
  match sleep.wait(time.milliseconds(10)) {
    Ok(nil) -> 42
    Err(error) -> 0
  }
}

fn main() -> i64 {
  task.with_event_loop(() => {
    let child = task.spawn(delayed_answer)
    if child.join() == 42 { 0 } else { 1 }
  })
}
```

The standard handlers deliberately share one semantic contract:

- `task.with_sequential` gives deterministic issue-order execution for tests
  and effectful work that needs no platform readiness.
- `task.with_event_loop` schedules timers and TCP readiness without blocking
  runnable children.
- `task.with_sequential_channel` and `task.with_event_loop_channel` add one
  bounded typed channel without changing producer or consumer signatures.
- Cancellation and shutdown variants return `CancellationOutcome<T>` and run
  the same structured cleanup before leaving scope.

See [`examples/structured_tasks.weft`](../examples/structured_tasks.weft) for
a bounded producer/consumer whose capacity-one channel suspends both sides
without changing either function into an async function.

## Deterministic parallelism

`Par` is narrower and intentionally stronger. `par.fork` accepts only a pure,
`Sendable` computation. A pool may reorder execution, while `handle.join()` and
`par.map` preserve deterministic observation order:

```weft run
use stdlib/par as par
use stdlib/result.{Ok, Err}

fn total() -[par.Par]> i64 {
  let left = par.fork(() => 20)
  let right = par.fork(() => 22)
  left.join() + right.join()
}

fn main() -> i64 {
  let config = match par.pool_config(2, 8) {
    Ok(value) -> value
    Err(error) -> return 1
  }
  let sequential = par.with_sequential(total)
  let parallel = par.with_pool(config, total)
  if sequential == 42 and parallel == 42 { 0 } else { 1 }
}
```

`pool_config` takes `usize` counts and validates them without starting
threads. Match `NoWorkers`, `NoTaskCapacity`, `WorkerCountTooLarge`, or
`TaskCapacityTooLarge` when reporting invalid configuration. A valid
configuration checks word-array size arithmetic; it does not reserve
physical resources. Allocation exhaustion is process-terminal, as for other
default managed storage. Thread creation failure selects sequential execution.

Both policies preserve the scope body's result type and residual effects.
Results may be managed values or owned resources; the scope result stays on
its caller's thread and needs no `Sendable` bound. Before returning, aborting,
or dropping a suspended continuation, the scope joins workers, destroys
unobserved task results, and reclaims pool storage. Returned results keep their
independent lifetimes.

Use `Par` when purity permits checked parallel execution. Use `TaskScope` when
children perform effects or suspend on readiness. `Task<T>` represents scoped
computation plus its result; it is not an actor identity or a send capability.

All Weft examples in this guide are checked by the suite. Complete programs
are also compiled and run.
