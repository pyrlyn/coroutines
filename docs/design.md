# Design notes

See [README](../README.md#design) for the API. Key invariants:

* `state_machine.runAll` permutes the task slice: finished tasks move to the end.
  The step count it returns equals the sum of `step` calls, which the tests check exactly.
* `state_machine.runParallel` never allocates. Workers share one `Cursor`; a chunk
  belongs to exactly one worker, so tasks need no synchronisation of their own.
  Shutdown order: every worker returns (queue empty or cancel observed) → caller joins
  all handles → result. Thread stacks default to `worker_stack_size` (1 MiB; 256 KiB fails
  to spawn with glibc on aarch64 Linux). `stack_size` raises that for deep recursion, and
  `caller_works = false` covers the one stack a run cannot choose, the caller's.
* `io.Dispatcher` must not move after `start` (workers hold a pointer to it).
  `shutdown` = `Queue.close` + `Group.await`; `cancel` = `Queue.close` + `Group.cancel`.
