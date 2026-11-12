"""Build the one-paste installer using only the repository's current Lua sources."""
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parent
PATHS = [
    "lib_work.lua", "lib_storage.lua", "lib_network.lua", "lib_console.lua", "lib_gui.lua", "lib_me.lua", "lib_settings.lua", "lib_system.lua", "lib_alert_inbox.lua", "lib_io_history.lua", "lib_io_picker.lua", "lib_desktop.lua", "lib_server.lua", "lib_io.lua", "lib_monitor.lua",
    "main_os.lua", "clients_io_client.lua", "clients_monitor_client.lua",
    "lib_sensor_data.lua", "lib_sensor.lua", "lib_sensor_server.lua", "lib_sensor_picker.lua", "clients_sensor_client.lua",
    "lib_relay.lua", "clients_relay_client.lua",
]

def lua_string(value):
    equals = "="
    while "]" + equals + "]" in value:
        equals += "="
    return "[" + equals + "[" + value + "]" + equals + "]"

header = '''-- SmartHome OS installer: bundled-v50
-- Flat-root layout: lib_*, clients_*, apps_*, configs_*.
-- Upload this ONE file to Pastebin. All role files are included below.
-- Usage: inst server|io|monitor|sensor|relay [--startup]
-- Everything at once on the OS computer: inst server --startup --apps
-- App store: inst store | inst list | inst apps [NAME ...] | inst remove NAME
-- User apps: inst app NAME [--ref BRANCH_OR_COMMIT] (GitHub)
-- Alternatives: inst app NAME PASTE_ID   or   inst app NAME --file PATH
-- Pastebin sharing: inst share NAME | inst backup [--apps] | inst restore PASTE_ID
-- OS/client installation is offline. Apps are fetched only on request.
local sources = {
'''
entries = [f'    ["{path}"] = {lua_string((ROOT / path).read_text())},\n' for path in PATHS]
runner = r'''}
local repo = "vsvito420/TekkitLite_SmartHome"
local bundledCatalog = __CATALOG__
local workChunk = assert(loadstring(sources["lib_work.lua"], "lib_work.lua"))
setfenv(workChunk, getfenv(1))
workChunk()
local args = {...}
local role, autorun, withApps = args[1], false, false
local entry = {server = "main_os.lua", io = "clients_io_client.lua", monitor = "clients_monitor_client.lua", sensor = "clients_sensor_client.lua", relay = "clients_relay_client.lua"}
local commands = {app = true, apps = true, store = true, list = true, remove = true, share = true, backup = true, restore = true}
print("SmartHome installer: bundled-v50")
local roleUsage = "Usage: inst server|io|monitor|sensor|relay [--startup] (server also: --apps)"
local appUsage = "Usage: inst app NAME [--ref REF] | inst app NAME PASTE_ID | inst app NAME --file PATH"
if not entry[role] and not commands[role] then
    print(roleUsage)
    print(appUsage)
    print("All apps: inst apps [NAME ...] [--ref REF]")
    print("App store: inst store | inst list | inst remove NAME")
    print("Pastebin: inst share NAME | inst backup [--apps] [--local]")
    print("          inst restore PASTE_ID | inst restore --file PATH")
    return
end
assert(shell.dir() == "", "Run cd / first")

local function loadStorage()
    local storageChunk = assert(loadstring(sources["lib_storage.lua"], "lib_storage.lua"))
    setfenv(storageChunk, getfenv(1))
    return storageChunk()
end
local function readFile(path)
    if not fs.exists(path) or fs.isDir(path) then return nil end
    local file = fs.open(path, "r")
    if not file then return nil end
    local contents = file.readAll(); file.close()
    return contents
end
-- Check every file before replacing any installed program.
local function install(files)
    for _, path in ipairs(files) do
        local contents = assert(sources[path], "Missing bundled file: " .. path)
        if path:match("%.lua$") or path == "startup" then
            local chunk, err = loadstring(contents, path)
            assert(chunk, "Invalid Lua: " .. path .. ": " .. tostring(err))
        else assert(type(textutils.unserialize(contents)) == "table", "Invalid settings: " .. path) end
    end
    for _, path in ipairs(files) do
        assert(not path:find("/", 1, true), "Install targets must be root filenames")
        local file = assert(fs.open(path .. ".download", "w"), "Cannot stage " .. path)
        file.write(sources[path])
        file.close()
    end
    for _, path in ipairs(files) do
        if fs.exists(path) then
            if fs.exists(path .. ".pre_update") then fs.delete(path .. ".pre_update") end
            fs.move(path, path .. ".pre_update")
        end
        fs.move(path .. ".download", path)
        print("Installed " .. path)
    end
end
local function validRef(ref)
    return type(ref) == "string" and ref:match("^[%w_./-]+$") and not ref:find("..", 1, true)
        and ref:sub(1, 1) ~= "/" and ref:sub(-1) ~= "/"
end
local function download(address)
    -- A child coroutine catches native request errors without preventing
    -- http.get from yielding on Lua 5.1. Terminate still aborts the install.
    local request = coroutine.create(function() return http.get(address) end)
    local result = {coroutine.resume(request)}
    while result[1] and coroutine.status(request) ~= "dead" do
        result = {coroutine.resume(request, os.pullEvent(result[2]))}
    end
    if not result[1] then return nil, "Request error: " .. tostring(result[2]) end
    local response = result[2] or result[4] -- Newer CC may return an error handle.
    if not response then return nil, tostring(result[3] or "No response; CC supplied no reason") end
    -- Reading/closing response handles does not yield, unlike http.get.
    local ok, code, body = pcall(function()
        return response.getResponseCode and response.getResponseCode() or 200, response.readAll()
    end)
    local closed, closeError = pcall(response.close)
    if not ok then return nil, "Cannot read response: " .. tostring(code) end
    if not closed then return nil, "Cannot close response: " .. tostring(closeError) end
    if code ~= 200 then return nil, "GitHub returned HTTP " .. tostring(code) end
    if not result[2] then return nil, tostring(result[3] or "HTTP request failed") end
    if type(body) ~= "string" or #body == 0 then return nil, "Empty app source" end
    return body
end
local function checkLua(body, path)
    if body == nil then return nil end
    local chunk, err = loadstring(body, path)
    if not chunk then return nil, "Invalid app Lua: " .. tostring(err) end
    return body
end
local function apiSource(body, path)
    -- Read only GitHub's known base64 content field; no JSON API or
    -- execution of downloaded text is needed on old ComputerCraft.
    if not body:match('"type"%s*:%s*"file"') or not body:match('"encoding"%s*:%s*"base64"')
        or body:match('"name"%s*:%s*"([^"]*)"') ~= path then
        return nil, "GitHub API did not return the requested base64 file"
    end
    local encoded = body:match('"content"%s*:%s*"([^"]*)"')
    if not encoded then return nil, "GitHub API response has no file content" end
    encoded = encoded:gsub("\\n", ""):gsub("\\r", ""):gsub("\\/", "/"):gsub("%s", "")
    local padding = encoded:match("=*$")
    local data = encoded:sub(1, #encoded - #padding)
    if #encoded % 4 ~= 0 or #padding > 2 or data:find("[^A-Za-z0-9+/]") then
        return nil, "Invalid base64 in GitHub API response"
    end
    local alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    local output, value, bits = {}, 0, 0
    for index = 1, #data do
        value, bits = value * 64 + alphabet:find(data:sub(index, index), 1, true) - 1, bits + 6
        if bits >= 8 then
            bits = bits - 8
            output[#output + 1] = string.char(math.floor(value / 2 ^ bits))
            value = value % 2 ^ bits
        end
    end
    local decoded = table.concat(output)
    if value ~= 0 or tonumber(body:match('"size"%s*:%s*(%d+)')) ~= #decoded then
        return nil, "GitHub API file size/encoding mismatch"
    end
    if #decoded == 0 then return nil, "Empty app source" end
    return decoded
end
-- Never throws: returns contents, or nil plus the API and raw reasons. This
-- keeps http.get free to yield and lets a multi-app install skip one failure.
local function fetchRepo(path, ref, check, quiet)
    if not (http and type(http.get) == "function") then
        return nil, "HTTP is disabled; GitHub app downloads need HTTP enabled"
    end
    local say = quiet and function() end or print
    local url = "https://raw.githubusercontent.com/" .. repo .. "/" .. ref .. "/" .. path
    local apiUrl = "https://api.github.com/repos/" .. repo .. "/contents/" .. path .. "?ref=" .. ref
    say("Downloading " .. path .. " from GitHub (" .. ref .. ")")
    local contents, rawError
    local body, apiError = download(apiUrl)
    if body then contents, apiError = apiSource(body, path) end
    if contents and check then contents, apiError = check(contents, path) end
    if contents then say("Downloaded via GitHub API"); return contents end
    say("GitHub API failed; trying raw download")
    contents, rawError = download(url)
    if contents and check then contents, rawError = check(contents, path) end
    if contents then say("Downloaded via GitHub raw"); return contents end
    return nil, "Raw: " .. tostring(rawError), "API: " .. tostring(apiError)
end
local function validCatalog(value)
    if type(value) ~= "table" then return nil end
    local result, seen = {}, {}
    for _, item in ipairs(value) do
        if type(item) == "table" and type(item.name) == "string" and item.name:match("^[%w_-]+$")
            and #item.name <= 32 and not seen[item.name] and item.name ~= "system" and item.name ~= "level_emitter" then
            seen[item.name] = true
            result[#result + 1] = {name = item.name,
                title = type(item.title) == "string" and item.title:gsub("[%c]", " "):sub(1, 24) or item.name,
                about = type(item.about) == "string" and item.about:gsub("[%c]", " "):sub(1, 60) or ""}
        end
    end
    return #result > 0 and result or nil
end
-- Old CraftOS returns the input string or throws for text that is not a table.
local function parseTable(text)
    local ok, value = pcall(textutils.unserialize, text)
    return ok and type(value) == "table" and value or nil
end
-- The bundled list always works offline; GitHub may know newer apps.
local function loadCatalog(ref)
    local text = fetchRepo("apps_catalog.txt", ref, nil, true)
    local online = text and validCatalog(parseTable(text))
    if online then return online, true end
    return assert(validCatalog(parseTable(bundledCatalog)), "Invalid bundled app catalog"), false
end
local function requireServer()
    assert(fs.exists("main_os.lua") and fs.exists("lib_server.lua"), "Install apps on the central OS computer")
end
local function readSettings()
    local storage = loadStorage()
    local configPath = "configs_os.txt"
    local settings = storage.load(configPath)
    if not settings then
        for _, suffix in ipairs({"", ".tmp", ".bak"}) do
            assert(not fs.exists(configPath .. suffix), "Unreadable OS settings")
        end
        settings = {}
    end
    if settings.enabledApps == nil then settings.enabledApps = {} end
    assert(type(settings.enabledApps) == "table", "Invalid enabledApps setting")
    return settings, configPath
end
local function appName(name)
    name = type(name) == "string" and name:lower() or name
    assert(type(name) == "string" and name:match("^[%w_-]+$"), "Specify a simple app name without .lua")
    assert(name ~= "system", "System Overview is built into Settings")
    assert(name ~= "level_emitter", "Level Emitter has been retired. Use Logic Sandbox for item rules.")
    return name
end
-- Download and install several apps one at a time, so a single failure or a
-- full disk never blocks the others. Settings are written once at the end.
local function installApps(names, ref)
    requireServer()
    assert(http and type(http.get) == "function", "HTTP is disabled; GitHub app downloads need HTTP enabled")
    local settings, configPath = readSettings()
    local done, same, failed = {}, {}, {}
    for index, name in ipairs(names) do
        local path = "apps_" .. name .. ".lua"
        print("[" .. index .. "/" .. #names .. "] " .. name)
        local contents, rawError, apiError = fetchRepo(path, ref, checkLua, true)
        if not contents then
            failed[#failed + 1] = name
            print("  FAILED " .. tostring(rawError))
            if apiError then print("  " .. apiError) end
        elseif contents == readFile(path) then
            same[#same + 1] = name
            settings.enabledApps[name] = true
            print("  already up to date")
        else
            if fs.getFreeSpace and fs.exists(path .. ".pre_update") and fs.getFreeSpace("") < #contents + 4096 then
                fs.delete(path .. ".pre_update")
            end
            if fs.getFreeSpace and fs.getFreeSpace("") < #contents + 4096 then
                failed[#failed + 1] = name
                print("  FAILED: disk full (" .. #contents .. " bytes needed)")
            else
                sources[path] = contents
                install({path})
                sources[path] = nil
                settings.enabledApps[name] = true
                done[#done + 1] = name
            end
        end
    end
    if #done + #same > 0 then
        local text = textutils.serialize(settings)
        if text ~= readFile(configPath) then
            sources[configPath] = text
            install({configPath})
        end
    end
    print("Apps installed: " .. #done .. ", unchanged: " .. #same .. ", failed: " .. #failed)
    if #failed > 0 then print("Retry with: inst apps " .. table.concat(failed, " ")) end
    if #done > 0 then print("Restart the central OS to load them") end
    return #failed == 0
end
local function printCatalog(catalog)
    local width = term.getSize()
    for index, item in ipairs(catalog) do
        local mark = fs.exists("apps_" .. item.name .. ".lua") and "[x]" or "[ ]"
        local line = string.format("%2d %s %s", index, mark, item.name)
        if item.about ~= "" then line = line .. string.rep(" ", math.max(1, 21 - #line)) .. item.about end
        print(line:sub(1, width))
    end
end
local function pastebinPut(path)
    assert(http, "HTTP is disabled; Pastebin needs HTTP enabled")
    print("Uploading " .. path .. " to Pastebin...")
    assert(shell.run("pastebin", "put", path), "Pastebin upload failed")
end

local files
if role == "apps" or role == "store" or role == "list" then
    local ref, names = "main", {}
    local index = 2
    while args[index] do
        if args[index] == "--ref" then ref, index = args[index + 1], index + 1
        else names[#names + 1] = appName(args[index]) end
        index = index + 1
    end
    assert(validRef(ref), "Invalid GitHub branch or commit")
    assert(role == "apps" or #names == 0, "Usage: inst " .. role .. " [--ref REF]")
    if role ~= "list" then requireServer() end
    if role == "apps" and #names > 0 then installApps(names, ref); return end
    local catalog, online = loadCatalog(ref)
    print("App catalog: " .. repo .. (online and "" or " (bundled list)"))
    if role == "apps" then
        for _, item in ipairs(catalog) do names[#names + 1] = item.name end
        installApps(names, ref)
        return
    end
    printCatalog(catalog)
    if role == "list" then print("[x] = installed. Install: inst store, inst apps or inst app NAME"); return end
    print("Numbers (e.g. 1 3 5), all, new (missing only); empty = quit")
    write("> ")
    local answer = read():lower()
    local chosen = {}
    for word in answer:gmatch("%S+") do
        if word == "all" or word == "new" then
            for _, item in ipairs(catalog) do
                if word == "all" or not fs.exists("apps_" .. item.name .. ".lua") then chosen[item.name] = true end
            end
        else
            local item = catalog[tonumber(word)]
            for _, known in ipairs(catalog) do if known.name == word then item = known end end
            assert(item, "Unknown app: " .. word)
            chosen[item.name] = true
        end
    end
    for _, item in ipairs(catalog) do if chosen[item.name] then names[#names + 1] = item.name end end
    if #names == 0 then print("Nothing selected"); return end
    installApps(names, ref)
    return
elseif role == "remove" then
    local name = appName(args[2])
    assert(not args[3], "Usage: inst remove NAME")
    requireServer()
    local settings, configPath = readSettings()
    local path = "apps_" .. name .. ".lua"
    assert(fs.exists(path) or settings.enabledApps[name], "App is not installed: " .. name)
    settings.enabledApps[name] = nil
    sources[configPath] = textutils.serialize(settings)
    install({configPath})
    if fs.exists(path) then
        if fs.exists(path .. ".pre_update") then fs.delete(path .. ".pre_update") end
        fs.move(path, path .. ".pre_update")
    end
    print("Removed app " .. name .. "; its saved data is kept. Code moved to " .. path .. ".pre_update")
    print("Restart the central OS")
    return
elseif role == "share" then
    local name = appName(args[2])
    assert(not args[3], "Usage: inst share NAME")
    local path = "apps_" .. name .. ".lua"
    assert(fs.exists(path), "App is not installed here: " .. name)
    pastebinPut(path)
    print("Install it elsewhere with: inst app " .. name .. " CODE")
    return
elseif role == "backup" then
    local includeApps, upload = false, true
    for index = 2, #args do
        if args[index] == "--apps" then includeApps = true
        elseif args[index] == "--local" then upload = false
        else error("Usage: inst backup [--apps] [--local]", 0) end
    end
    local backup = {format = "SmartHomeBackup/1", computerId = os.getComputerID(), files = {}, apps = {}}
    local count, bytes = 0, 0
    for _, path in ipairs(fs.list("")) do
        local app = path:match("^apps_([%w_-]+)%.lua$")
        -- The transport boot counter must keep counting upwards on this computer.
        local config = path:match("^configs_[%w_]+%.txt$") and path ~= "configs_transport.txt"
        if not fs.isDir(path) and (config or app) then
            if app then backup.apps[#backup.apps + 1] = app end
            if config or includeApps then
                local contents = assert(readFile(path), "Cannot read " .. path)
                backup.files[path] = contents
                count, bytes = count + 1, bytes + #contents
            end
        end
    end
    assert(count > 0 or #backup.apps > 0, "Nothing to back up on this computer")
    table.sort(backup.apps)
    local target = "smarthome_backup.txt"
    local file = assert(fs.open(target .. ".download", "w"), "Cannot write " .. target)
    file.write(textutils.serialize(backup)); file.close()
    if fs.exists(target) then fs.delete(target) end
    fs.move(target .. ".download", target)
    print("Saved " .. count .. " files (" .. bytes .. " bytes) to /" .. target)
    if not includeApps and #backup.apps > 0 then
        print(#backup.apps .. " app names noted; restore reloads them from GitHub")
    end
    if upload then
        if bytes > 480000 then print("Too large for Pastebin (512 KB); leave out --apps"); return end
        print("Note: anyone with the code can read this paste")
        pastebinPut(target)
        print("Restore with: inst restore CODE")
    else print("Share later with: pastebin put " .. target) end
    return
elseif role == "restore" then
    local source = args[2]
    assert(source and (source == "--file" and args[3] and not args[4] or source:match("^%w+$") and not args[3]),
        "Usage: inst restore PASTE_ID | inst restore --file PATH")
    local path = source == "--file" and args[3] or "smarthome_backup.download"
    if source ~= "--file" then
        if fs.exists(path) then fs.delete(path) end
        assert(shell.run("pastebin", "get", source, path) and fs.exists(path), "Pastebin backup download failed")
    end
    local text = assert(readFile(path), "Cannot read backup: " .. path)
    if source ~= "--file" then fs.delete(path) end
    local backup = parseTable(text)
    assert(backup and backup.format == "SmartHomeBackup/1" and type(backup.files) == "table",
        "Not a SmartHome backup")
    files = {}
    local included = {}
    for name, contents in pairs(backup.files) do
        local app = type(name) == "string" and name:match("^apps_([%w_-]+)%.lua$")
        assert(type(name) == "string" and type(contents) == "string" and name ~= "configs_transport.txt"
            and (app or name:match("^configs_[%w_]+%.txt$")), "Unexpected file in backup: " .. tostring(name))
        if app then included[app] = true end
        sources[name] = contents
        files[#files + 1] = name
    end
    table.sort(files)
    install(files)
    print("Restored " .. #files .. " files; replaced files are kept as *.pre_update")
    local missing = {}
    for _, name in ipairs(type(backup.apps) == "table" and backup.apps or {}) do
        if type(name) == "string" and name:match("^[%w_-]+$") and not included[name]
            and not fs.exists("apps_" .. name .. ".lua") and name ~= "level_emitter" and name ~= "system" then
            missing[#missing + 1] = name
        end
    end
    if #missing > 0 then
        if fs.exists("main_os.lua") and http and type(http.get) == "function" then
            print("Reloading " .. #missing .. " apps from GitHub")
            installApps(missing, "main")
        else print("Apps still missing: inst apps " .. table.concat(missing, " ")) end
    end
    print("Run reboot to use the restored data")
    return
elseif role == "app" then
    local name, source = args[2], args[3]
    assert(type(name) == "string" and name:match("^[%w_-]+$"), "Specify a simple app name without .lua")
    assert(not source and not args[4]
        or (source == "--file" or source == "--ref") and args[4] and not args[5]
        or source and source:match("^%w+$") and not args[4], appUsage)
    name = appName(name)
    args[2] = name
    local github = source == nil or source == "--ref"
    local ref = source == "--ref" and args[4] or "main"
    assert(not github or validRef(ref), "Invalid GitHub branch or commit")
    requireServer()
    local path = "apps_" .. name .. ".lua"
    local contents
    if github then
        assert(http and type(http.get) == "function", "HTTP is disabled; GitHub app downloads need HTTP enabled")
        local rawError, apiError
        contents, rawError, apiError = fetchRepo(path, ref, checkLua)
        if not contents then
            print(tostring(rawError))
            print(tostring(apiError))
            print("No response from both? Ask the server admin to check GitHub HTTPS access and the Java/server log.")
            error("GitHub app download failed; installed files were not changed", 0)
        end
    elseif source == "--file" then
        local file = assert(fs.open(args[4], "r"), "Cannot read app source: " .. args[4])
        contents = file.readAll(); file.close()
    else
        local temporary = path .. ".download"
        if fs.exists(temporary) then fs.delete(temporary) end
        assert(shell.run("pastebin", "get", source, temporary) and fs.exists(temporary), "Pastebin app download failed")
        local file = assert(fs.open(temporary, "r"), "Cannot read downloaded app")
        contents = file.readAll(); file.close()
        fs.delete(temporary)
    end
    assert(type(contents) == "string" and #contents > 0, "Empty app source")
    local chunk, err = loadstring(contents, path)
    assert(chunk, "Invalid app Lua: " .. tostring(err))
    -- Read settings without resetting them or executing the app at install time.
    local settings, configPath = readSettings()
    settings.enabledApps[name] = true -- Explicit app installation opts this app in.
    sources[path], sources[configPath] = contents, textutils.serialize(settings)
    files = {path, configPath}
else
    for index = 2, #args do
        if args[index] == "--apps" and role == "server" then withApps = true
        else
            assert(args[index] == "--startup", roleUsage)
            autorun = true
        end
    end
    files = {"lib_work.lua", "lib_storage.lua", "lib_network.lua"}
    if role == "server" or role == "monitor" then files[#files + 1] = "lib_gui.lua" end
    if role == "server" then
        files[#files + 1] = "lib_me.lua"
        files[#files + 1] = "lib_console.lua"
        files[#files + 1] = "lib_settings.lua"
        files[#files + 1] = "lib_system.lua"
        files[#files + 1] = "lib_alert_inbox.lua"
        files[#files + 1] = "lib_io_history.lua"
        files[#files + 1] = "lib_io_picker.lua"
        files[#files + 1] = "lib_desktop.lua"
        files[#files + 1] = "lib_server.lua"
        files[#files + 1] = "lib_sensor_data.lua"
        files[#files + 1] = "lib_sensor_server.lua"
        files[#files + 1] = "lib_sensor_picker.lua"
    elseif role == "io" then files[#files + 1] = "lib_io.lua"
    elseif role == "sensor" then files[#files + 1] = "lib_sensor_data.lua"; files[#files + 1] = "lib_sensor.lua"
    elseif role == "relay" then files[#files + 1] = "lib_relay.lua"
    else files[#files + 1] = "lib_monitor.lua" end
    files[#files + 1] = entry[role]
    if autorun then
        sources.startup = 'shell.setDir("/")\nshell.run("' .. entry[role] .. '")\n'
        files[#files + 1] = "startup"
    end
end
if role ~= "app" then
    -- Upgrade old folder-based installations without resetting IDs, apps or state.
    -- Existing flat files take precedence; old files remain recovery copies.
    local storage = loadStorage()
    local function existsAny(path)
        return fs.exists(path) or fs.exists(path .. ".tmp") or fs.exists(path .. ".bak")
    end
    local function addFile(path, contents)
        sources[path] = contents
        for _, present in ipairs(files) do if present == path then return end end
        files[#files + 1] = path
    end
    local function readTable(path)
        local value = storage.load(path)
        assert(value or not existsAny(path), "Unreadable saved data: " .. path)
        return value
    end
    local function migrate(target, legacy)
        if existsAny(target) then return readTable(target), false end
        if not existsAny(legacy) then return nil, false end
        local value = assert(readTable(legacy))
        addFile(target, textutils.serialize(value))
        print("Migrating " .. legacy .. " to " .. target)
        return value, true
    end
    migrate("configs_network.txt", "Configs/network.txt")
    if role == "io" then migrate("configs_io.txt", "Configs/io.txt")
    elseif role == "sensor" then migrate("configs_sensor.txt", "Configs/sensor.txt")
    elseif role == "relay" then migrate("configs_relay.txt", "Configs/relay.txt")
    elseif role == "monitor" then migrate("configs_monitor.txt", "Configs/monitor.txt")
    else
        local settings, migrated = migrate("configs_os.txt", "Configs/os.txt")
        local legacyState = settings and settings.saveFile or "Configs/os_state.txt"
        assert(type(legacyState) == "string", "Invalid saved state path")
        migrate("configs_os_state.txt", legacyState)
        if settings then
            if settings.saveFile and settings.saveFile ~= "configs_os_state.txt" then
                settings.saveFile = "configs_os_state.txt"
                addFile("configs_os.txt", textutils.serialize(settings))
            end
            if migrated then
                assert(settings.enabledApps == nil or type(settings.enabledApps) == "table", "Invalid enabledApps setting")
                for name, enabled in pairs(settings.enabledApps or {}) do
                    if enabled == true and name ~= "system" and name ~= "level_emitter" then
                        assert(type(name) == "string" and name:match("^[%w_-]+$"), "Invalid enabled app name")
                        local path, oldPath = "apps_" .. name .. ".lua", "Apps/" .. name .. ".lua"
                        if not fs.exists(path) and fs.exists(oldPath) then
                            local file = assert(fs.open(oldPath, "r"), "Cannot read legacy app: " .. oldPath)
                            local contents = file.readAll(); file.close()
                            addFile(path, contents)
                            print("Migrating enabled app: " .. name)
                        end
                    end
                end
            end
        end
    end
end
install(files)
if role == "app" then
    print("Installed and enabled user app: " .. args[2])
    print("Restart the central OS to load it")
    return
end
print("Installed " .. role .. " from the bundled files")
if withApps then
    if http and type(http.get) == "function" then
        local names = {}
        for _, item in ipairs((loadCatalog("main"))) do names[#names + 1] = item.name end
        installApps(names, "main")
    else print("HTTP is disabled: apps skipped. Later: inst apps") end
end
if autorun then
    print("Autorun enabled; an existing startup is kept as startup.pre_update")
    print("Run reboot to start automatically")
else print("Autorun unchanged; add --startup to enable it") end
print("Start with: " .. entry[role])
'''
# The offline app list comes from apps_catalog.txt, which the store also
# refreshes from GitHub. Every catalog entry must be a real app file.
catalog = (ROOT / "apps_catalog.txt").read_text()
catalog_names = re.findall(r'\{name="([\w-]+)"', catalog)
app_files = sorted(p.name[5:-4] for p in ROOT.glob("apps_*.lua"))
if sorted(catalog_names) != app_files:
    raise SystemExit(f"apps_catalog.txt does not match the app files: {sorted(set(catalog_names) ^ set(app_files))}")
contents = header + "".join(entries) + runner.replace("__CATALOG__", lua_string(catalog))
path = ROOT / "install.lua"
if "--check" in sys.argv:
    if not path.exists() or path.read_text() != contents:
        raise SystemExit("install.lua is stale; run python3 tools_build_installer.py")
    print("Bundled installer matches all current source files")
else:
    path.write_text(contents)
    print(f"Built {path.name}: {len(contents.encode())} bytes, {len(PATHS)} bundled source files")
