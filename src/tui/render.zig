//! TODO(TUI): hand-rolled terminal UI. Zig has no blessed TUI lib — that's
//! the point. Layer 1: VT100/SGR primitives (alt screen, hide cursor, clear,
//! 256-color fg/bg, bold). Layer 2: diff-based renderer so you redraw only
//! changed cells (kills flicker). Layer 3: week grid widget + confirm modal.
//! Enable: bracketed paste off, raw mode via termios, SIGWINCH for resize.
//! Windows TUI build note: enable VT processing via GetConsoleMode +
//! ENABLE_VIRTUAL_TERMINAL_PROCESSING, or ship the GUI build there instead.

pub fn render() void {
    @panic("TODO(TUI)");
}
