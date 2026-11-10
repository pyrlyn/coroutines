# Vendored `std.Io` evented backends (Zig 0.17.1)

`std.Io.Evented` does not compile in Zig 0.17.0 or 0.17.1. The backends lag
behind `std.Io`:

| Zig | backend | first compile error |
|---|---|---|
| 0.17.0 | `Io/Dispatch.zig` (macOS) | `Io.VTable` has no field `processReplacePath` |
| 0.17.0 | `Io/Uring.zig` (Linux) | `Io.VTable` has no field `processReplacePath` |
| 0.17.0 / 0.17.1 | `Io/Kqueue.zig` (BSD) | `Io.VTable` has no field `fileWriteStreaming` |
| 0.17.1 | `Io/Dispatch.zig` | `Io.Operation` has no member `net_accept` |
| 0.17.1 | `Io/Uring.zig` | `Io.Operation` has no member `net_accept` |

`Uring.zig` and `Dispatch.zig` here are the 0.17.1 files with the minimal patches
in `*.patch`. The patches remove the `net_accept` switch prongs, which referred to an
operation that no longer exists. `Uring.zig` also imports `std` as a module
instead of `../std.zig`. Nothing else is changed. `coroutines.evented` uses these
files only when built with Zig 0.17.1. Drop them once upstream compiles again.

Known upstream runtime bugs in `Dispatch.zig` (macOS); `coroutines.evented` works
around the first two:

1. `deinit` does not wait for finished fibers to be destroyed. The destroy runs later
   on a libdispatch thread and can free memory after `deinit` (a leak report, or a crash
   in a later test). Workaround: `Runtime.deinit` waits until every allocation made
   through the runtime is freed.
2. With `backing_allocator_needs_mutex = true`, freeing a fiber from the main-loop
   context can take a contended fiber mutex and yield outside a fiber. Result: SIGSEGV
   in `Sleeper.init`. Workaround: the runtime requires a thread-safe allocator and
   passes `backing_allocator_needs_mutex = false`.
3. A canceled `io.sleep` returns success instead of `error.Canceled`. A task looping
   on `sleep` therefore never observes cancellation, and `Group.cancel` hangs.
   Not worked around.
4. Canceling tasks blocked in `Io.Queue.get` (a contended `Io.Mutex`/`Condition`) can
   crash in `Sleeper.init` (SIGSEGV). Not worked around.

Tests that depend on 3 or 4 are skipped on Dispatch.

License: MIT (Zig contributors), see `LICENSE` in this directory.
