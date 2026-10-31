//! coroutines — two coroutine flavours for Zig 0.17, std only.
//!
//! * `state_machine`: stackless, allocation-free state-machine coroutines
//!   with a round-robin scheduler and an optional multi-threaded runner.
//! * `io`: coroutines on top of `std.Io` (`Io.Group`, `Io.Queue`), running on
//!   whatever `Io` you pass (`std.Io.Threaded`, or an evented `Io`).
//! * `hybrid`: OS processes up to a task-count threshold (default 256),
//!   `Io` coroutines above it.
pub const state_machine = @import("state_machine.zig");
pub const io = @import("io.zig");
pub const hybrid = @import("hybrid.zig");

test {
    _ = state_machine;
    _ = io;
    _ = hybrid;
}
