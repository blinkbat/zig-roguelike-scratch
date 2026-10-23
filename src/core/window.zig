const rl = @import("raylib");
const P = @import("mathx.zig").P;

pub const WINDOW_W: i32 = 1600;
pub const WINDOW_H: i32 = 900;
pub const WINDOW = P{ .x = WINDOW_W, .y = WINDOW_H };
/// Screens the shots and layout tests cover besides the window's.
pub const SCREEN_720 = P{ .x = 1280, .y = 720 };
pub const SCREEN_1080 = P{ .x = 1920, .y = 1080 };
pub const SCREEN_1440 = P{ .x = 2560, .y = 1440 };
pub const SCREENS = [_]P{ SCREEN_720, SCREEN_1080, SCREEN_1440 };

// X11/KDE panels and the macOS menu bar/Dock stay over an undecorated screen-sized window; only a monitor-owned one covers them.
pub const MONITOR_OWNED = switch (@import("builtin").os.tag) {
    .linux, .macos => true,
    else => false,
};

pub const glfw = struct {
    const GLProc = *const fn () callconv(.c) void;
    pub extern fn glfwGetProcAddress(name: [*:0]const u8) ?GLProc;
    const Window = opaque {};
    const Monitor = opaque {};
    const VidMode = extern struct { width: c_int, height: c_int, red: c_int, green: c_int, blue: c_int, refresh: c_int };
    extern fn glfwGetCurrentContext() ?*Window;
    extern fn glfwGetWindowMonitor(w: *Window) ?*Monitor;
    extern fn glfwGetMonitors(count: *c_int) ?[*]*Monitor;
    extern fn glfwGetVideoMode(m: *Monitor) ?*const VidMode;
    extern fn glfwGetWindowPos(w: *Window, x: *c_int, y: *c_int) void;
    extern fn glfwGetWindowSize(w: *Window, width: *c_int, height: *c_int) void;
    extern fn glfwSetWindowMonitor(w: *Window, m: ?*Monitor, x: c_int, y: c_int, width: c_int, height: c_int, refresh: c_int) void;
};

const Rect = struct { x: c_int = 0, y: c_int = 0, w: c_int = WINDOW_W, h: c_int = WINDOW_H };

var windowed: Rect = .{};

fn currentMonitor() ?*glfw.Monitor {
    var count: c_int = 0;
    const all = glfw.glfwGetMonitors(&count) orelse return null;
    const i = rl.getCurrentMonitor();
    return if (i >= 0 and i < count) all[@intCast(i)] else null;
}

pub fn toggleMonitorOwned() void {
    const w = glfw.glfwGetCurrentContext() orelse return;
    if (glfw.glfwGetWindowMonitor(w) != null) {
        glfw.glfwSetWindowMonitor(w, null, windowed.x, windowed.y, windowed.w, windowed.h, 0);
        return;
    }
    const m = currentMonitor() orelse return;
    const mode = glfw.glfwGetVideoMode(m) orelse return;
    glfw.glfwGetWindowPos(w, &windowed.x, &windowed.y);
    glfw.glfwGetWindowSize(w, &windowed.w, &windowed.h);
    glfw.glfwSetWindowMonitor(w, m, 0, 0, mode.width, mode.height, mode.refresh);
}

pub fn fullscreen() bool {
    if (MONITOR_OWNED) {
        const w = glfw.glfwGetCurrentContext() orelse return false;
        return glfw.glfwGetWindowMonitor(w) != null;
    }
    return rl.isWindowState(.{ .borderless_windowed_mode = true });
}
