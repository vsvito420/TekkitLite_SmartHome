-- v50: workspaces, top/centred bar, touch assist and remote monitor text scale.
return function(tests, newBus, monitor, serialize, unserialize, equal)
    local Gui, Desktop = dofile("lib_gui.lua"), dofile("lib_desktop.lua")
    local function read(path) local f = assert(io.open(path, "r")); local s = f:read("*a"); f:close(); return s end
    local apps = {["apps_notes.lua"] = read("apps_notes.lua"), ["apps_clock.lua"] = read("apps_clock.lua")}
    local function setup(width, height)
        local t = {bus = newBus()}
        t.central = t.bus.computer(10, "server", {apps = apps}):start()
        t.top = monitor(width or 64, height or 20)
        t.display = t.bus.computer(13, "monitor", {monitors = {top = t.top}}):start()
        t.bus.advance(2)
        t.id, t.api, t.server = "monitor_13:top", t.central.server.api, t.central.server
        function t.paint() t.server.refreshMonitors(true); t.bus.pump() end
        function t.touch(x, y) t.bus.queue(t.display, {"monitor_touch", "top", x, y}); t.bus.pump(); t.paint() end
        function t.row(y) return t.top.lines[y] or "" end
        function t.screen() return table.concat(t.top.lines, "\n", 1, t.top.height) end
        function t.bar(action, value)
            for _, hit in ipairs(t.server.monitors[t.id].taskbar) do
                if hit.action == action and (value == nil or hit.id == value) then return hit end
            end
            error("Missing bar item " .. action)
        end
        function t.windows()
            local names = {}
            for _, win in pairs(t.server.state.windows) do names[#names + 1] = win.appName .. "@" .. tostring(win.workspace) end
            table.sort(names); return table.concat(names, ",")
        end
        t.paint()
        return t
    end
    local function settingsClick(t, id, action, value)
        local win = t.server.state.windows[id]
        local app = t.server.systemApps["@settings"]
        local content = app.render(win.width - 2, win.height - 2, t.server.state.appStates["@settings"], t.api,
            {windowId = id, appName = "@settings", monitorId = win.monitorId, view = t.server.views[id]})
        local shift = t.server.monitors[t.id].barTop and 1 or 0
        for _, hit in ipairs(content.hits) do
            if hit.action == action and hit.enabled ~= false and (value == nil or hit.value == value) then
                return t.touch(win.x + hit.x1, win.y + (hit.y1 or hit.y) + shift)
            end
        end
        error("Missing Settings action " .. action)
    end

    function tests.v50_default_desktop_is_the_classic_bottom_bar_without_workspaces()
        local t = setup()
        local settings = t.api.getOSSettings()
        equal(settings.barPosition, "bottom"); equal(settings.barLayout, "classic")
        equal(settings.workspaces, 1); equal(settings.touchAssist, true)
        equal(t.row(20):sub(1, 3), "[+]"); assert(t.row(20):sub(-5):find(":", 1, true))
        assert(t.api.openApp("notes", t.id)); t.paint()
        equal(t.windows(), "notes@nil")
        for _, hit in ipairs(t.server.monitors[t.id].taskbar) do assert(hit.action ~= "workspace") end
        -- Old saves with odd values read as the classic desktop.
        t.server.state.appearance.workspaces, t.server.state.appearance.barPosition = 42, "left"
        equal(t.api.getOSSettings().workspaces, 1); equal(t.api.getOSSettings().barPosition, "bottom")
        equal(t.api.setDesktopOptions({workspaces = 10}), false); equal(t.api.setDesktopOptions({barPosition = "left"}), false)
        equal(t.api.setDesktopOptions({unknown = true}), false); equal(t.api.setDesktopOptions("top"), false)
    end

    function tests.v50_tiling_preset_from_settings_moves_the_bar_up_with_coloured_workspace_strokes_and_a_centred_clock()
        local t = setup()
        local id = assert(t.api.openApp("@settings", t.id)); t.paint()
        settingsClick(t, id, "appearance"); settingsClick(t, id, "desktop"); settingsClick(t, id, "presetTiling")
        local settings = t.api.getOSSettings()
        equal(settings.barPosition, "top"); equal(settings.barLayout, "centered"); equal(settings.workspaces, 4)
        -- Workspace 1 is a solid red block; the others are thin strokes in their own colour.
        local bar = t.row(1)
        equal(bar:sub(1, 11), "   -- -- --")
        equal(t.top.bg[1][1], 16384); equal(t.top.bg[1][2], 16384)
        equal(t.top.fg[1][4], 2); equal(t.top.fg[1][7], 16); equal(t.top.fg[1][10], 32)
        assert(not bar:sub(1, 12):find("%d"), "Workspaces show no numbers")
        equal(bar:sub(13, 15), "[+]")
        local clock = t.bar("inbox")
        equal(clock.x1, math.floor((64 - 5) / 2) + 1); assert(bar:sub(clock.x1, clock.x2):find(":", 1, true))
        equal(t.row(20):find("[+]", 1, true), nil, "No bar in the bottom row")
        -- The Settings window keeps working one row lower, and survives a reboot.
        settingsClick(t, id, "barLayout"); equal(t.api.getOSSettings().barLayout, "classic")
        assert(t.row(1):sub(-5):find(":", 1, true))
        settingsClick(t, id, "touchAssist"); equal(t.api.getOSSettings().touchAssist, false)
        settingsClick(t, id, "workspaceCount"); settingsClick(t, id, "setWorkspaces", 6)
        equal(t.api.getOSSettings().workspaces, 6)
        t.central = t.bus.computer(10, "server", {disk = t.central.disk}):start(); t.bus.advance(6)
        local restored = t.central.server.api.getOSSettings()
        equal(restored.barPosition, "top"); equal(restored.workspaces, 6); equal(restored.touchAssist, false)
        t.server, t.api = t.central.server, t.central.server.api
        id = next(t.server.state.windows); t.paint()
        settingsClick(t, id, "presetClassic")
        equal(t.api.getOSSettings().barPosition, "bottom"); equal(t.api.getOSSettings().workspaces, 1)
        equal(t.row(20):sub(1, 3), "[+]")
    end

    function tests.v50_workspaces_switch_by_touch_keep_apps_running_and_new_windows_join_the_visible_one()
        local t = setup()
        assert(t.api.setDesktopOptions({barPosition = "top", barLayout = "centered", workspaces = 4}))
        assert(t.api.openApp("notes", t.id)); t.paint()
        assert(t.screen():find("Notes", 1, true))
        local second = t.bar("workspace", 2)
        t.touch(second.x1, 1)
        equal(t.api.getWorkspaces(t.id).current, 2)
        assert(not t.row(2):find("Notes", 1, true), "Windows of workspace 1 are hidden")
        equal(t.server.running.notes, true, "Hidden windows keep their app running")
        equal(t.row(1):sub(1, 2), "==", "Workspace 1 is marked as occupied")
        equal(t.top.bg[1][second.x1], 2)
        -- Launcher opens under the top bar; a new window lands on workspace 2.
        local launcher = t.bar("launcher")
        t.touch(launcher.x1 + 1, 1)
        local monitorState = t.server.monitors[t.id]
        equal(monitorState.launcher, true)
        local item
        for _, hit in ipairs(monitorState.menuHits) do if hit.item and hit.item.value == "clock" then item = hit end end
        assert(item and item.y1 <= 3, "Menu hangs below the bar")
        t.touch(item.x1 + 1, item.y1 + 1)
        equal(t.windows(), "clock@2,notes@1")
        -- Title bar controls work under the rotated frame: close the clock window.
        local clockWindow
        for _, win in pairs(t.server.state.windows) do if win.appName == "clock" then clockWindow = win end end
        local close = Desktop.controls(clockWindow)[3]
        t.touch(close.x1 + 1, clockWindow.y + 1)
        equal(t.windows(), "notes@1")
        t.touch(t.bar("workspace", 1).x1, 1)
        assert(t.screen():find("Notes", 1, true)); equal(t.api.getWorkspaces(t.id).current, 1)
        equal(t.api.setWorkspace(t.id, 5), false); equal(t.api.setWorkspace("monitor_99:top", 1), false)
        -- The selected workspace survives an OS reboot.
        assert(t.api.setWorkspace(t.id, 3))
        t.central = t.bus.computer(10, "server", {disk = t.central.disk}):start(); t.bus.advance(6)
        equal(t.central.server.api.getWorkspaces(t.id).current, 3)
        equal(t.central.server.api.getWorkspaces(t.id).occupied[1], true)
    end

    function tests.v50_layout_menu_sends_a_window_to_another_workspace_and_fewer_workspaces_never_lose_windows()
        local t = setup()
        assert(t.api.setDesktopOptions({workspaces = 3}))
        local id = assert(t.api.openApp("notes", t.id)); t.paint()
        local win = t.server.state.windows[id]
        local layout = Desktop.controls(win)[2]
        t.touch(layout.x1 + 1, win.y)
        local function menu(value)
            for _, hit in ipairs(t.server.monitors[t.id].layoutMenu.menuHits) do
                if hit.item and hit.item.value == value then return t.touch(hit.x1 + 1, hit.y1 or hit.y) end
            end
            error("Missing layout item " .. value)
        end
        menu("workspace"); menu("ws_3")
        equal(t.server.monitors[t.id].layoutMenu, nil); equal(win.workspace, 3)
        equal(t.api.getWorkspaces(t.id).current, 1, "Sending a window away keeps the current workspace")
        assert(not t.screen():find("Notes", 1, true))
        equal(t.api.moveWindowToWorkspace(id, 4), false); equal(t.api.moveWindowToWorkspace(999, 1), false)
        -- Presets remember the workspace of each window.
        local preset = t.api.captureWindowPreset(t.id)
        equal(preset[1].windows[1].workspace, 3)
        -- With one workspace the menu entry disappears and every window is reachable again.
        assert(t.api.setDesktopOptions({workspaces = 1})); t.paint()
        assert(t.screen():find("Notes", 1, true))
        t.touch(Desktop.controls(win)[2].x1 + 1, win.y)
        for _, hit in ipairs(t.server.monitors[t.id].layoutMenu.menuHits) do
            assert(not hit.item or hit.item.value ~= "workspace")
        end
    end

    function tests.v50_touch_assist_snaps_a_one_cell_miss_only_to_a_single_enabled_control()
        local hits = {{x1 = 3, x2 = 8, y = 2, action = "a"}, {x1 = 10, x2 = 14, y = 2, action = "b"},
            {x1 = 3, x2 = 8, y1 = 5, y2 = 6, action = "tall"}, {x1 = 20, x2 = 24, y = 2, action = "off", enabled = false}}
        equal(Gui.actionAt(hits, 2, 2), "a"); equal(Gui.actionAt(hits, 5, 1), "a"); equal(Gui.actionAt(hits, 5, 3), "a")
        equal(Gui.actionAt(hits, 9, 2), nil, "Between two controls stays a miss")
        equal(Gui.actionAt(hits, 15, 2), "b"); equal(Gui.actionAt(hits, 16, 2), nil)
        equal(Gui.actionAt(hits, 2, 1), nil, "Diagonal misses stay misses")
        equal(Gui.actionAt(hits, 5, 7), "tall"); equal(Gui.actionAt(hits, 5, 4), "tall"); equal(Gui.actionAt(hits, 9, 5), "tall")
        equal(Gui.actionAt(hits, 22, 2), nil); equal(Gui.actionAt(hits, 19, 2), nil)
        Gui.touchAssist = false
        equal(Gui.actionAt(hits, 2, 2), nil); equal(Gui.actionAt(hits, 3, 2), "a")
        Gui.touchAssist = true
        -- The bar applies the same rule and honours the setting.
        local t = setup()
        assert(t.api.setDesktopOptions({workspaces = 2}))
        t.paint()
        local launcher = t.bar("launcher")
        t.touch(launcher.x2 + 1, 20); equal(t.server.monitors[t.id].launcher, true)
        t.touch(launcher.x1, 20); equal(t.server.monitors[t.id].launcher, false)
        assert(t.api.setDesktopOptions({touchAssist = false})); t.paint()
        t.touch(launcher.x2 + 1, 20); equal(t.server.monitors[t.id].launcher, false)
    end

    function tests.v50_classic_bar_with_workspaces_fits_narrow_monitors_and_scrolls_window_labels()
        local saved = {}
        local windows = {}
        for i = 1, 6 do windows[i] = {id = i, title = "Window " .. i} end
        local shell = {workspaces = 4, current = 2, occupied = {[1] = true}, layout = "centered"}
        local line, hits = Desktop.taskbar(windows, {width = 60, height = 20}, "12:34", saved, 1, shell)
        equal(#line, 60)
        local seen, previousEnd = {}, 0
        for _, hit in ipairs(hits) do
            seen[hit.action] = (seen[hit.action] or 0) + 1
            assert(hit.x1 >= 1 and hit.x2 <= 60 and hit.x1 <= hit.x2)
        end
        equal(seen.workspace, 4); equal(seen.launcher, 1); equal(seen.inbox, 1); equal(seen.next, 1)
        assert(seen.window >= 2 and seen.window < 6)
        local clock
        for _, hit in ipairs(hits) do if hit.action == "inbox" then clock = hit end end
        for _, hit in ipairs(hits) do
            if hit.action == "window" then assert(hit.x2 < clock.x1 or hit.x1 > clock.x2, "No label crosses the clock") end
        end
        equal(line:sub(clock.x1, clock.x2), "12:34")
        -- One-cell strokes on a narrow screen; the launcher always stays reachable.
        line, hits = Desktop.taskbar({}, {width = 16, height = 8}, "12:34", {}, nil, {workspaces = 9, current = 9})
        equal(#line, 16); seen = {}
        for _, hit in ipairs(hits) do seen[hit.action] = (seen[hit.action] or 0) + 1; assert(hit.x2 <= 16) end
        equal(seen.launcher, 1); equal(seen.workspace, 9); assert(line:find("[+]", 1, true))
        -- No shell argument: byte-identical classic bar.
        local classic = Desktop.taskbar(windows, {width = 60, height = 20}, "12:34", {}, 1)
        equal(classic:sub(1, 3), "[+]"); equal(classic:sub(-5), "12:34")
    end

    function tests.v50_settings_changes_a_monitor_text_scale_remotely_and_the_monitor_saves_it()
        local t = setup()
        local list = t.api.getMonitors()
        equal(#list, 1); equal(list[1].id, t.id); equal(list[1].textScale, 0.5); equal(list[1].width, 64)
        local id = assert(t.api.openApp("@settings", t.id)); t.paint()
        settingsClick(t, id, "appearance"); settingsClick(t, id, "monitors"); settingsClick(t, id, "monitor", t.id)
        assert(t.screen():find("Text scale 0.5", 1, true))
        settingsClick(t, id, "scale", 0.5)
        equal(t.top.scale, 1)
        equal(unserialize(t.display.disk.files["configs_monitor.txt"]).textScales.top, 1)
        t.bus.advance(2); t.paint()
        equal(t.api.getMonitors()[1].textScale, 1)
        assert(t.screen():find("Text scale 1", 1, true), "The screen is repainted after rescaling")
        -- The saved scale is used again after the monitor computer restarts.
        t.top.scale = nil
        t.display = t.bus.computer(13, "monitor", {disk = t.display.disk, monitors = {top = t.top}}):start()
        equal(t.top.scale, 1)
        -- Invalid values and old monitor clients are refused without sending anything.
        equal(t.api.setMonitorScale(t.id, 0.75), false); equal(t.api.setMonitorScale(t.id, 6), false)
        equal(t.api.setMonitorScale("monitor_99:top", 1), false)
        t.server.monitors[t.id].textScale = nil
        local ok, why = t.api.setMonitorScale(t.id, 2)
        equal(ok, false); assert(why:find("Update this monitor", 1, true)); equal(t.top.scale, 1)
    end
end
