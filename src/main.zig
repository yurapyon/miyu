const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const maru = @import("maru");
const events = maru.events;
const flat = maru.flat;
const gfx = maru.gfx;
const states = maru.states;

usingnamespace maru.math;
usingnamespace maru.c;

const nitori = @import("nitori");
const Matrix = nitori.matrix.Matrix;

//;

// react to input events when activated
// can use window data to draw
pub const Module = struct {
    const Self = @This();

    window: *Window,
};

pub const Window = struct {
    const Self = @This();

    top_left: UVec2,
    width: usize,
    height: usize,
    char_buf: Matrix(u8),

    pub fn init(allocator: *Allocator, top_left: UVec2, width: usize, height: usize) Allocator.Error!Self {
        var ret = Self{
            .top_left = top_left,
            .width = width,
            .height = height,
            .char_buf = try Matrix(u8).init(allocator, width, height),
        };
        var i: usize = 0;
        while (i < width) : (i += 1) {
            var j: usize = 0;
            while (j < height) : (j += 1) {
                ret.char_buf.get_mut(i, j).* = ' ';
            }
        }
        return ret;
    }
};

pub const Screen = struct {
    const Self = @This();

    // TODO camera_zoom
    camera_offset: Vec2,
    windows: ArrayList(Window),
    tile_w: f32,
    tile_h: f32,

    pub fn init(allocator: *Allocator, tile_w: f32, tile_h: f32) Self {
        return .{
            .camera_offset = Vec2.zero(),
            .windows = ArrayList(Window).init(allocator),
            .tile_w = tile_w,
            .tile_h = tile_h,
        };
    }
};

//;

pub const Programs = struct {
    const Self = @This();

    pixel_sb: flat.Program2d,

    fn init(workspace_alloc: *Allocator) Allocator.Error!Self {
        const pixel_sb = flat.Program2d.initDefaultSpritebatch(
            workspace_alloc,
            \\ mat3 my_mat3_from_transform2d(float x, float y, float r, float sx, float sy) {
            \\     mat3 ret = mat3(1.0);
            \\     float rc = cos(r);
            \\     float rs = sin(r);
            \\     ret[0][0] =  rc * sx;
            \\     ret[0][1] =  rs * sx;
            \\     ret[1][0] = -rs * sy;
            \\     ret[1][1] =  rc * sy;
            \\     //ret[2][0] = floor(x);
            \\     //ret[2][1] = floor(y);
            \\     ret[2][0] = x;
            \\     ret[2][1] = y;
            \\     return ret;
            \\ }
            \\
            \\ void my_ready_spritebatch() {
            \\     // scale main uv coords by sb_uv
            \\     //   automatically handles flip uvs
            \\     //   as long as this is called after flipping the uvs in main (it is)
            \\     float uv_w = _ext_sb_uv.z - _ext_sb_uv.x;
            \\     float uv_h = _ext_sb_uv.w - _ext_sb_uv.y;
            \\     _sb_uv.x = _uv_coord.x * uv_w + _ext_sb_uv.x;
            \\     _sb_uv.y = _uv_coord.y * uv_h + _ext_sb_uv.y;
            \\
            \\     _sb_color = _ext_sb_color;
            \\     _sb_model = my_mat3_from_transform2d(_ext_sb_position.x,
            \\                                          _ext_sb_position.y,
            \\                                          _ext_sb_rotation,
            \\                                          _ext_sb_scale.x,
            \\                                          _ext_sb_scale.y);
            \\ }
            \\
            \\vec3 effect() {
            \\  my_ready_spritebatch();
            \\  return _screen * _view * _model * _sb_model * vec3(_ext_vertex, 1.0);
            \\}
        ,
            null,
        ) catch |err| switch (err) {
            error.OutOfMemory => |e| return e,
            // TODO dont have unreachable
            //   for if program cant compile on some1s hardware ?
            //   lol at least make an error log
            // die() instead of unreachable
            else => unreachable,
        };

        return Self{
            .pixel_sb = pixel_sb,
        };
    }

    fn deinit(self: *Self) void {
        self.pixel_sb.deinit();
    }
};

pub const Context = struct {
    pub const Config = struct {
        hunk_size: usize,
    };

    // note: use heap alloc for anything thats not temporary
    heap_alloc: *Allocator,
    hunk: nitori.hunk.Hunk,

    gfx_ctx: *const gfx.Context,
    evs: *const events.EventHandler,

    draw_defaults: *const flat.DrawDefaults,
    programs: *const Programs,
    drawer: *flat.Drawer2d,

    tm: *maru.frame_timer.FrameTimer,
    delta_time: f32,

    screen: Screen,
};

pub fn main() anyerror!void {
    const heap_alloc = std.heap.c_allocator;

    const cfg = Context.Config{
        .hunk_size = 1024 * 2,
    };

    var gfx_ctx: gfx.Context = undefined;
    try gfx_ctx.init(.{
        .window_width = 800,
        .window_height = 600,
    });
    defer gfx_ctx.deinit();

    gfx_ctx.installEventHandler(heap_alloc);
    var evs = &gfx_ctx.event_handler.?;

    // glfwSetInputMode(gfx_ctx.window, GLFW_CURSOR, GLFW_CURSOR_DISABLED);

    // TODO use hunk ?
    var draw_defaults = try flat.DrawDefaults.init(heap_alloc);
    defer draw_defaults.deinit();

    var programs = try Programs.init(heap_alloc);
    defer programs.deinit();

    var drawer = try flat.Drawer2d.init(heap_alloc, .{
        .spritebatch_size = 500,
        .circle_resolution = 50,
    });
    defer drawer.deinit();

    var tm = try maru.frame_timer.FrameTimer.start();

    // var state_machine = states.StateMachine.init(heap_alloc);
    // defer state_machine.deinit();

    var app_ctx = Context{
        .heap_alloc = heap_alloc,
        .hunk = undefined,
        .gfx_ctx = &gfx_ctx,
        .evs = evs,
        .draw_defaults = &draw_defaults,
        .programs = &programs,
        .drawer = &drawer,
        .tm = &tm,
        .delta_time = 0,

        .screen = Screen.init(
            heap_alloc,
            @intToFloat(f32, draw_defaults.ibm_font.glyph_width) + 1,
            @intToFloat(f32, draw_defaults.ibm_font.glyph_height) + 1,
        ),
    };

    var hunk_mem = try heap_alloc.alloc(u8, cfg.hunk_size);
    defer heap_alloc.free(hunk_mem);

    app_ctx.hunk.init(hunk_mem[0..]);

    //;

    _ = tm.step();
    app_ctx.delta_time = @floatCast(f32, tm.step());

    var mouse_held: bool = false;
    var mouse_was_held: bool = false;
    var mouse_pos: Vec2 = Vec2.zero();
    var mouse_was_pos: Vec2 = Vec2.zero();

    try app_ctx.screen.windows.append(try Window.init(heap_alloc, UVec2.init(0, 0), 15, 10));

    {
        var i: usize = 0;
        while (i < 15) : (i += 1) {
            var j: usize = 0;
            while (j < 10) : (j += 1) {
                app_ctx.screen.windows.items[0].char_buf.get_mut(i, j).* = 'a' + @intCast(u8, i);
            }
        }
    }

    while (glfwWindowShouldClose(gfx_ctx.window) == GLFW_FALSE) {
        app_ctx.delta_time = @floatCast(f32, tm.step());

        mouse_was_pos = mouse_pos;
        mouse_was_held = mouse_held;

        for (evs.mouse_events.items) |m_ev| {
            switch (m_ev) {
                .Button => |ev| {
                    if (ev.button == .Left and ev.mods.shift) {
                        mouse_held = ev.action == .Press;
                    }
                },
                .Move => |ev| {
                    mouse_pos = TVec2(f64).init(ev.x, ev.y).cast(f32);
                },
                else => {},
            }
        }

        if (mouse_held) {
            const diff = mouse_pos.sub(mouse_was_pos);
            app_ctx.screen.camera_offset.x += diff.x;
            app_ctx.screen.camera_offset.y += diff.y;
        }

        glClear(GL_COLOR_BUFFER_BIT);

        {
            const tile_w = app_ctx.screen.tile_w;
            const tile_h = app_ctx.screen.tile_h;

            var sprites = app_ctx.drawer.bindSpritebatch(false, .{
                .program = &app_ctx.programs.pixel_sb,
                .diffuse = &app_ctx.draw_defaults.white_texture,
                .canvas_width = 800,
                .canvas_height = 600,
            });
            defer sprites.unbind();

            sprites.sprite_color = Color.initRgba(0.95, 0.95, 0.95, 1);
            sprites.rectangle(0, 0, 800, 600);

            try sprites.pushCoord(.{ .Translate = app_ctx.screen.camera_offset });

            {
                const cam = app_ctx.screen.camera_offset;
                //                 const cam_grid = IVec2.init(
                //                     @floatToInt(i32, std.math.floor(cam.x / tile_w)),
                //                     @floatToInt(i32, std.math.floor(cam.y / tile_h)),
                //                 );
                const top_left = Vec2.zero().sub(cam);
                const top_left_grid = IVec2.init(
                    @floatToInt(i32, std.math.floor(top_left.x / tile_w)),
                    @floatToInt(i32, std.math.floor(top_left.y / tile_h)),
                );
                const bottom_right = top_left.add(Vec2.init(800, 600));
                const bottom_right_grid = IVec2.init(
                    @floatToInt(i32, std.math.floor(bottom_right.x / tile_w)),
                    @floatToInt(i32, std.math.floor(bottom_right.y / tile_h)),
                );

                var i: i32 = top_left_grid.x - 1;
                while (i < bottom_right_grid.x + 1) : (i += 1) {
                    const x = @intToFloat(f32, i) * tile_w;
                    //                     if (i == 0) {
                    //                         sprites.sprite_color = Color.initRgba(0.9, 0.3, 0.3, 0.5);
                    //                     } else {
                    //                         sprites.sprite_color = Color.initRgba(0.4, 0.4, 0.4, 0.25);
                    //                     }
                    //
                    //                     if (@mod(i, 2) != 0) {
                    //                         sprites.sprite_color.a = 0.1;
                    //                     }
                    //
                    //                     sprites.rectangle(x - 1, top_left.y, x + 1, bottom_right.y);

                    if (i == 0) {
                        sprites.sprite_color = Color.initRgba(0.9, 0.3, 0.3, 0.5);
                        sprites.rectangle(x - 1, top_left.y, x + 1, bottom_right.y);
                    }
                }

                var j: i32 = top_left_grid.y - 1;
                while (j < bottom_right_grid.y + 1) : (j += 1) {
                    const y = @intToFloat(f32, j) * tile_h;
                    sprites.sprite_color = Color.initRgba(0.3, 0.3, 0.9, 0.5);

                    if (@mod(j, 2) != 0) {
                        // sprites.sprite_color.a = 0.1;
                    }

                    if (j >= 0) {
                        sprites.rectangle(top_left.x, y - 0.5, bottom_right.x, y + 0.5);
                    }
                }
            }

            for (app_ctx.screen.windows.items) |win| {
                var top_left = win.top_left.cast(f32);
                top_left.x *= tile_w;
                top_left.y *= tile_h;
                const w = @intToFloat(f32, win.width) * tile_w;
                const h = @intToFloat(f32, win.height) * tile_h;

                try sprites.pushCoord(.{ .Translate = top_left });

                sprites.sprite_color = Color.white();
                sprites.rectangle(0, 0, w, h);

                sprites.sprite_color = Color.initRgba(0.8, 0.8, 0.8, 1);
                sprites.rectangle(0, 0, 2, h);
                sprites.rectangle(0, 0, w, 2);
                sprites.rectangle(w - 2, 0, w, h);
                sprites.rectangle(0, h - 2, w, h);

                sprites.sprite_color = Color.initRgba(0, 0, 0, 1);

                const font = app_ctx.draw_defaults.ibm_font;
                var i: usize = 0;
                var j: usize = 0;
                while (i < win.width) : (i += 1) {
                    j = 0;
                    while (j < win.height) : (j += 1) {
                        const ch = win.char_buf.get(i, j).*;
                        const x = @intToFloat(f32, i);
                        const y = @intToFloat(f32, j);
                        sprites.setDiffuse(&font.texture);
                        sprites.sprite_uv = font.uvRegion(ch);
                        sprites.rectangle(
                            x * tile_w,
                            y * tile_h,
                            x * tile_w + @intToFloat(f32, font.glyph_width),
                            y * tile_h + @intToFloat(f32, font.glyph_height),
                        );
                    }
                }

                try sprites.popCoord();
            }

            try sprites.popCoord();
        }

        glfwSwapBuffers(gfx_ctx.window);
        evs.poll();
    }
}
