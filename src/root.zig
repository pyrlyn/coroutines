//! coroutines — two coroutine flavours for Zig 0.17, std only.
//!
//! * `state_machine`: stackless, allocation-free state-machine coroutines
//!   with a round-robin scheduler and an optional multi-threaded runner.
//! * `io`: coroutines on top of `std.Io` (`Io.Group`, `Io.Queue`), running on
//!   whatever `Io` you pass (`std.Io.Threaded`, or an evented `Io`).
pub const state_machine = @import("state_machine.zig");
pub const io = @import("io.zig");

test {
    _ = state_machine;
    _ = io;
}
