-- v49: multi-app installer, app store, Pastebin backup/restore and Net Scope.
return function(tests, newBus, monitor, serialize, unserialize, equal, githubFile)
    local repo = "vsvito420/TekkitLite_SmartHome"
    local function read(path) local f = assert(io.open(path, "r")); local s = f:read("*a"); f:close(); return s end
    local catalog = unserialize(read("apps_catalog.txt"))
    local function server(id)
        local comp = newBus().computer(id or 10, "server")
        comp.env.shell = {dir = function() return "" end}
        local install = assert(comp.env.loadfile("install.lua"))
        return comp, install
    end
    -- Serves real repository files through GitHub's contents API shape.
    local function github(comp, failing)
        local requests = {}
        comp.env.http = {get = function(url)
            requests[#requests + 1] = url
            local path = url:match("^https://api%.github%.com/repos/" .. repo:gsub("%-", "%%-") .. "/contents/([%w_.]+)%?ref=main$")
            if not path or failing and failing[path] then return nil, "Connection refused" end
            return {getResponseCode = function() return 200 end,
                readAll = function() return githubFile(path, read(path)) end, close = function() end}
        end}
        return requests
    end
    local function log(comp) return table.concat(comp.log, "\n") end

    function tests.v49_inst_apps_installs_the_whole_catalog_and_skips_only_a_failed_download()
        local comp, install = server()
        install("server", "--startup")
        local requests = github(comp, {["apps_coffee.lua"] = true})
        install("apps")
        local settings = unserialize(comp.disk.files["configs_os.txt"])
        for _, item in ipairs(catalog) do
            if item.name == "coffee" then
                equal(comp.disk.files["apps_coffee.lua"], nil); equal(settings.enabledApps.coffee, nil)
            else
                equal(comp.disk.files["apps_" .. item.name .. ".lua"], read("apps_" .. item.name .. ".lua"), item.name)
                equal(settings.enabledApps[item.name], true, item.name)
            end
        end
        equal(comp.disk.files["apps_level_emitter.lua"], nil)
        assert(log(comp):find("failed: 1", 1, true), log(comp))
        assert(log(comp):find("Retry with: inst apps coffee", 1, true))
        -- A second run only fetches; identical apps create no backups or rewrites.
        local before = comp.disk.files["configs_os.txt"]
        github(comp)
        install("apps", "Coffee", "notes")
        equal(comp.disk.files["apps_coffee.lua"], read("apps_coffee.lua"))
        equal(comp.disk.files["apps_notes.lua.pre_update"], nil)
        equal(unserialize(comp.disk.files["configs_os.txt"]).enabledApps.coffee, true)
        equal(comp.disk.files["configs_os.txt.pre_update"], before)
        comp:start()
        assert(comp.server.apps.net_scope and comp.server.apps.switchboard and comp.server.apps.coffee)
        assert(#requests >= #catalog)
    end

    function tests.v49_server_install_with_apps_flag_loads_everything_in_one_command()
        local comp, install = server()
        github(comp)
        install("server", "--startup", "--apps")
        assert(comp.disk.files.startup and comp.disk.files["main_os.lua"])
        for _, item in ipairs(catalog) do assert(comp.disk.files["apps_" .. item.name .. ".lua"], item.name) end
        comp:start()
        for _, item in ipairs(catalog) do assert(comp.server.apps[item.name], item.name) end
        -- Without HTTP the OS still installs and the apps are merely skipped.
        local offline, installOffline = server()
        offline.env.http = false
        installOffline("server", "--apps")
        assert(offline.disk.files["main_os.lua"]); assert(log(offline):find("apps skipped", 1, true))
        -- Other roles never accept the flag.
        local io = newBus().computer(11, "io"); io.env.shell = {dir = function() return "" end}
        equal(pcall(assert(io.env.loadfile("install.lua")), "io", "--apps"), false)
    end

    function tests.v49_store_lists_the_catalog_and_installs_the_typed_selection()
        local comp, install = server()
        install("server")
        github(comp)
        comp.disk.files["apps_notes.lua"] = "-- older notes"
        comp.env.read = function() return "1 net_scope" end
        install("store")
        local text = log(comp)
        for _, item in ipairs(catalog) do assert(text:find(item.name, 1, true), item.name) end
        assert(text:find("[x] notes", 1, true)); assert(text:find("[ ] clock", 1, true))
        assert(comp.disk.files["apps_" .. catalog[1].name .. ".lua"]); assert(comp.disk.files["apps_net_scope.lua"])
        equal(comp.disk.files["apps_notes.lua"], "-- older notes")
        equal(comp.disk.files["apps_switchboard.lua"], nil)
        comp.env.read = function() return "new" end
        install("store")
        assert(comp.disk.files["apps_switchboard.lua"]); equal(comp.disk.files["apps_notes.lua"], "-- older notes")
        comp.env.read = function() return "" end
        install("store"); assert(log(comp):find("Nothing selected", 1, true))
        comp.env.read = function() return "99" end
        equal(pcall(install, "store"), false)
        -- The list also works offline from the bundled catalog and on any computer.
        comp.env.http = false; comp.log = {}
        install("list"); assert(log(comp):find("bundled list", 1, true)); assert(log(comp):find("net_scope", 1, true))
    end

    function tests.v49_remove_disables_an_app_but_keeps_its_code_backup_and_saved_state()
        local comp, install = server()
        install("server"); github(comp); install("apps", "notes", "clock")
        comp.disk.files["configs_os_state.txt"] = serialize({appStates = {notes = {notes = {}, nextNote = 4}}})
        install("remove", "notes")
        equal(comp.disk.files["apps_notes.lua"], nil); assert(comp.disk.files["apps_notes.lua.pre_update"])
        local settings = unserialize(comp.disk.files["configs_os.txt"])
        equal(settings.enabledApps.notes, nil); equal(settings.enabledApps.clock, true)
        equal(unserialize(comp.disk.files["configs_os_state.txt"]).appStates.notes.nextNote, 4)
        equal(pcall(install, "remove", "notes"), false)
    end

    function tests.v49_backup_and_restore_move_settings_between_computers_through_pastebin()
        local comp, install = server()
        install("server", "--startup"); github(comp); install("apps", "notes", "clock")
        comp.disk.files["configs_network.txt"] = serialize({networkId = "my-home", channel = 45231})
        comp.disk.files["configs_os_state.txt"] = serialize({appStates = {notes = {nextNote = 7}}})
        comp.disk.files["configs_transport.txt"] = serialize({bootCounter = 41})
        comp.disk.files["configs_os.txt.bak"] = "stale"
        local pastes, uploads = {}, 0
        local function pastebin(owner)
            owner.env.shell.run = function(program, command, a, b)
                equal(program, "pastebin")
                if command == "put" then uploads = uploads + 1; pastes["Code" .. uploads] = owner.disk.files[a]; return true end
                if not pastes[a] then return false end
                owner.disk.files[b] = pastes[a]; return true
            end
        end
        pastebin(comp)
        install("backup")
        equal(uploads, 1)
        local saved = unserialize(pastes.Code1)
        equal(saved.format, "SmartHomeBackup/1"); equal(saved.files["configs_transport.txt"], nil)
        equal(saved.files["configs_os.txt.bak"], nil); equal(saved.files["apps_notes.lua"], nil)
        equal(table.concat(saved.apps, ","), "clock,notes")
        assert(log(comp):find("inst restore CODE", 1, true))
        -- A fresh central computer gets the settings back and reloads the noted apps.
        local fresh, installFresh = server(20)
        installFresh("server"); github(fresh); pastebin(fresh)
        fresh.disk.files["configs_transport.txt"] = serialize({bootCounter = 3})
        fresh.disk.files["configs_network.txt"] = serialize({networkId = "old", channel = 45231})
        installFresh("restore", "Code1")
        equal(unserialize(fresh.disk.files["configs_network.txt"]).networkId, "my-home")
        equal(unserialize(fresh.disk.files["configs_network.txt.pre_update"]).networkId, "old")
        equal(unserialize(fresh.disk.files["configs_os_state.txt"]).appStates.notes.nextNote, 7)
        equal(unserialize(fresh.disk.files["configs_transport.txt"]).bootCounter, 3)
        equal(fresh.disk.files["apps_notes.lua"], read("apps_notes.lua")); assert(fresh.disk.files["apps_clock.lua"])
        equal(fresh.disk.files["smarthome_backup.download"], nil)
        fresh:start(); assert(fresh.server.apps.notes)
        -- --apps embeds the app code; --local never uploads; restore --file reads it offline.
        install("backup", "--apps", "--local"); equal(uploads, 1)
        local full = unserialize(comp.disk.files["smarthome_backup.txt"])
        equal(full.files["apps_notes.lua"], read("apps_notes.lua"))
        local offline, installOffline = server(30)
        installOffline("server"); offline.env.http = false
        offline.disk.files["usb_backup"] = comp.disk.files["smarthome_backup.txt"]
        installOffline("restore", "--file", "usb_backup")
        equal(offline.disk.files["apps_clock.lua"], read("apps_clock.lua"))
        equal(unserialize(offline.disk.files["configs_os.txt"]).enabledApps.notes, true)
        -- Share uploads exactly one app file.
        install("share", "notes"); equal(uploads, 2); equal(pastes.Code2, read("apps_notes.lua"))
        equal(pcall(install, "share", "missing_app"), false)
    end

    function tests.v49_restore_rejects_foreign_data_and_unexpected_targets_without_writing()
        for _, body in ipairs({"<!DOCTYPE html>", serialize({format = "Other", files = {}}),
            serialize({format = "SmartHomeBackup/1", files = {startup = "shell.run('x')"}}),
            serialize({format = "SmartHomeBackup/1", files = {["configs_transport.txt"] = "{bootCounter=1}"}}),
            serialize({format = "SmartHomeBackup/1", files = {["configs_os.txt"] = "{}", ["lib_server.lua"] = "return {}"}}),
            serialize({format = "SmartHomeBackup/1", files = {["apps_bad.lua"] = "return {"}})}) do
            local comp, install = server()
            install("server", "--startup")
            local startup, core = comp.disk.files.startup, comp.disk.files["lib_server.lua"]
            comp.disk.files.incoming = body
            equal(pcall(install, "restore", "--file", "incoming"), false, body)
            equal(comp.disk.files.startup, startup); equal(comp.disk.files["lib_server.lua"], core)
            equal(comp.disk.files["configs_os.txt"], nil); equal(comp.disk.files["apps_bad.lua"], nil)
            equal(comp.disk.files["configs_transport.txt"], nil)
        end
    end

    local function scope()
        local t = {bus = newBus()}
        t.central = t.bus.computer(10, "server", {apps = {["apps_net_scope.lua"] = read("apps_net_scope.lua")}}):start()
        t.top = monitor(60, 24)
        t.display = t.bus.computer(13, "monitor", {monitors = {top = t.top}}):start()
        t.bus.advance(2)
        t.api, t.app = t.central.server.api, t.central.server.apps.net_scope
        t.state = t.central.server.state.appStates.net_scope
        t.id = assert(t.api.openApp("net_scope", "monitor_13:top", 1, 1))
        function t.view() return t.central.server.views[t.id] end
        function t.content()
            local win = t.central.server.state.windows[t.id]
            return t.app.render(win.width - 2, win.height - 2, t.state, t.api, {appName = "net_scope", windowId = t.id, view = t.view()})
        end
        function t.text() return table.concat(t.content(), "\n") end
        function t.click(action, value)
            local win = t.central.server.state.windows[t.id]
            for _, hit in ipairs(t.content().hits) do
                if hit.action == action and hit.enabled ~= false and (value == nil or hit.value == value
                    or type(hit.value) == "table" and hit.value.key == value) then
                    return t.app.handleTouch(hit.x1, hit.y, win.width - 2, win.height - 2, t.state, t.api,
                        {appName = "net_scope", windowId = t.id, view = t.view()})
                end
            end
            error("Missing Net Scope action " .. action)
        end
        return t
    end

    function tests.v49_net_scope_captures_live_packets_only_while_open_and_skips_its_own_redraws()
        local t = scope()
        local _, _, active = t.api.getPacketLog(); equal(active, true)
        t.bus.computer(11, "io", {modemSide = "right"}):start()
        t.bus.advance(3)
        local entries, total = t.api.getPacketLog()
        assert(#entries >= 2 and total == entries[#entries].n)
        local kinds = {}
        for _, entry in ipairs(entries) do
            local kind = entry.direction .. ":" .. tostring(entry.type)
            if entry.clientId == "io_11" and not kinds[kind] then kinds[kind] = entry end
            assert(entry.type ~= "render", "Redraws would feed the capture forever")
            assert(entry.bytes > 0 and entry.channel and entry.at >= 0)
        end
        local announce, welcome = assert(kinds["rx:announce"]), assert(kinds["tx:welcome"])
        equal(announce.sender, 11); equal(announce.clientId, "io_11"); equal(announce.status, "ok")
        equal(welcome.recipient, 11); assert(table.concat(welcome.info, " "):find("nonce=", 1, true))
        local text = t.text()
        assert(text:find("Net Scope LIVE", 1, true)); assert(text:find("< announce", 1, true)); assert(text:find("> welcome", 1, true))
        -- Relay copies of accepted packets are hidden until requested.
        assert(not text:find("ignored", 1, true))
        t.click("detail", welcome.n)
        assert(t.text():find("TX: OS -> ", 1, true)); assert(t.text():find("Computer 10 -> 11", 1, true))
        t.click("onlyType"); equal(t.view().kind, "welcome")
        assert(not t.text():find("announce", 1, true))
        -- Closing the last view stops capture; nothing is saved in app state.
        equal(t.state.packets, nil)
        assert(t.api.closeWindow(t.id))
        local _, _, still = t.api.getPacketLog(); equal(still, false)
        local _, before = t.api.getPacketLog(); t.bus.advance(5)
        local _, after = t.api.getPacketLog(); equal(after, before)
    end

    function tests.v49_net_scope_hold_filters_statistics_and_render_capture_setting()
        local t = scope()
        t.bus.computer(11, "io", {modemSide = "right"}):start(); t.bus.advance(3)
        t.click("hold"); local frozen = t.text()
        assert(frozen:find("HOLD", 1, true))
        t.bus.computer(12, "io", {modemSide = "right"}):start(); t.bus.advance(3)
        equal(t.text(), frozen); t.click("hold")
        assert(t.text():find("io_12", 1, true))
        t.click("menu"); t.click("direction"); equal(t.view().direction, "rx")
        t.click("clients"); t.click("pick", "io_12"); equal(t.view().client, "io_12")
        t.click("list")
        for _, line in ipairs(t.content()) do assert(not line:find(" > ", 1, true) and not line:find("io_11", 1, true), line) end
        t.click("menu"); t.click("stats")
        assert(t.text():find("announce: ", 1, true)); assert(t.text():find("by client", 1, true))
        t.click("menu"); t.click("ignored"); equal(t.state.hideIgnored, false)
        t.click("render"); equal(t.state.showRender, true)
        t.central.server.refreshMonitors(true); t.bus.pump(); t.bus.advance(2)
        local seen = false
        for _, entry in ipairs((t.api.getPacketLog())) do if entry.type == "render" then seen = true end end
        equal(seen, true)
        t.click("clear"); equal(#(t.api.getPacketLog()), 0); equal(t.view().screen, "list")
        -- The buffer is bounded.
        for _ = 1, 40 do t.central.server.refreshMonitors(true); t.bus.pump(); t.bus.advance(1) end
        assert(#(t.api.getPacketLog()) <= 200)
    end
end
