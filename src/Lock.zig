const Lock = @This();

const std = @import("std");
const assert = std.debug.assert;
const log = std.log;
const os = std.os;

const wayland = @import("wayland");
const wl = wayland.client.wl;
const ext = wayland.client.ext;

const Output = @import("Output.zig");

const gpa = std.heap.c_allocator;

state: enum {
    /// The session lock object has not yet been created.
    initializing,
    /// The session lock object has been created but the locked event has not been recieved.
    locking,
    /// The compositor has sent the locked event indicating that the session is locked.
    locked,
    /// Gracefully exiting and cleaning up resources. This could happen because the compositor
    /// did not grant waylock's request to lock the screen or because the user or compositor
    /// has unlocked the session.
    exiting,
} = .initializing,

shm: ?*wl.Shm = null,
compositor: ?*wl.Compositor = null,
session_lock_manager: ?*ext.SessionLockManagerV1 = null,
session_lock: ?*ext.SessionLockV1 = null,

outputs: std.SinglyLinkedList(Output) = .{},

pub fn run() void {
    const display = wl.Display.connect(null) catch |e| {
        fatal("failed to connect to a wayland compositor: {s}", .{@errorName(e)});
    };
    const registry = display.getRegistry() catch fatal_oom();

    var lock: Lock = .{};

    registry.setListener(*Lock, registry_listener, &lock);
    _ = display.roundtrip() catch |e| fatal("initial roundtrip failed: {s}", .{@errorName(e)});

    if (lock.shm == null) fatal_not_advertised(wl.Shm);
    if (lock.compositor == null) fatal_not_advertised(wl.Compositor);
    if (lock.session_lock_manager == null) fatal_not_advertised(ext.SessionLockManagerV1);

    lock.session_lock = lock.session_lock_manager.?.lock() catch fatal_oom();
    lock.session_lock.?.setListener(*Lock, session_lock_listener, &lock);

    // From this point onwards we may no longer handle OOM by exiting.
    assert(lock.state == .initializing);
    lock.state = .locking;

    {
        var initial_outputs = lock.outputs;
        lock.outputs = .{};
        while (initial_outputs.popFirst()) |node| {
            node.data.init(&lock, node.data.name, node.data.wl_output) catch {
                log.err("out of memory", .{});
                node.data.wl_output.destroy();
                gpa.destroy(node);
                return;
            };
            lock.outputs.prepend(node);
        }
    }

    while (lock.state != .exiting) {
        _ = display.dispatch() catch |err| {
            // TODO are there any errors here that we can handle without exiting?
            fatal("wayland display dispatch failed: {s}", .{@errorName(err)});
        };
    }
}

fn registry_listener(registry: *wl.Registry, event: wl.Registry.Event, lock: *Lock) void {
    lock.registry_event(registry, event) catch |err| switch (err) {
        error.OutOfMemory => {
            log.err("out of memory", .{});
            return;
        },
    };
}

fn registry_event(lock: *Lock, registry: *wl.Registry, event: wl.Registry.Event) !void {
    switch (event) {
        .global => |ev| {
            if (std.cstr.cmp(ev.interface, wl.Shm.getInterface().name) == 0) {
                lock.shm = try registry.bind(ev.name, wl.Shm, 1);
            } else if (std.cstr.cmp(ev.interface, wl.Compositor.getInterface().name) == 0) {
                lock.compositor = try registry.bind(ev.name, wl.Compositor, 4);
            } else if (std.cstr.cmp(ev.interface, ext.SessionLockManagerV1.getInterface().name) == 0) {
                lock.session_lock_manager = try registry.bind(ev.name, ext.SessionLockManagerV1, 1);
            } else if (std.cstr.cmp(ev.interface, wl.Output.getInterface().name) == 0) {
                const wl_output = try registry.bind(ev.name, wl.Output, 1);
                errdefer wl_output.destroy();

                const node = try gpa.create(std.SinglyLinkedList(Output).Node);
                errdefer gpa.destroy(node);

                switch (lock.state) {
                    .initializing => node.data = .{
                        .lock = undefined,
                        .name = ev.name,
                        .wl_output = wl_output,
                        .surface = undefined,
                        .lock_surface = undefined,
                    },
                    .locking, .locked, .exiting => try node.data.init(lock, ev.name, wl_output),
                }

                lock.outputs.prepend(node);
            }
        },
        .global_remove => |ev| {
            var it = lock.outputs.first;
            while (it) |node| : (it = node.next) {
                if (node.data.name == ev.name) {
                    switch (lock.state) {
                        .initializing => {
                            lock.outputs.remove(node);
                            node.data.wl_output.destroy();
                            gpa.destroy(node);
                        },
                        .locking, .locked, .exiting => node.data.destroy(),
                    }
                    break;
                }
            }
        },
    }
}

fn session_lock_listener(_: *ext.SessionLockV1, event: ext.SessionLockV1.Event, lock: *Lock) void {
    switch (event) {
        .locked => {
            assert(lock.state == .locking);
            lock.state = .locked;
        },
        .finished => {
            switch (lock.state) {
                .initializing => unreachable,
                .locking => {
                    log.err("the wayland compositor has denied our attempt to lock the session, " ++
                        "is another ext-session-lock client already running?", .{});
                    lock.state = .exiting;
                },
                .locked => {
                    log.info("the wayland compositor has unlocked the session, exiting", .{});
                    lock.state = .exiting;
                },
                .exiting => unreachable,
            }
        },
    }
}

fn fatal(comptime format: []const u8, args: anytype) noreturn {
    log.err(format, args);
    os.exit(1);
}

fn fatal_oom() noreturn {
    fatal("out of memory during initialization", .{});
}

fn fatal_not_advertised(comptime Global: type) noreturn {
    fatal("{s} not advertised", .{Global.getInterface().name});
}
