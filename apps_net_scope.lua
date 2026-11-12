-- Net Scope: a small packet viewer for the SmartHome radio network.
-- Capture belongs to the OS (api.capturePackets); this app only filters and draws.
local app = {title = "Net Scope", minWidth = 16, minHeight = 6, preferredWidth = 50, preferredHeight = 18}
local name = "net_scope"
local directions = {"all", "rx", "tx"}
local directionLabel = {all = "RX+TX", rx = "RX only", tx = "TX only"}
local statusText = {ok = "accepted", ignored = "ignored (duplicate or not for the OS)",
    foreign = "foreign (not a SmartHome packet)"}

local function capture(state, api)
    return api.capturePackets(true, state.showRender and {} or {render = true})
end
function app.init(state, api, context)
    assert(api.capturePackets and api.getPacketLog, "Net Scope requires bundled-v49 OS; run inst server")
    name = context.appName
    if state.hideIgnored == nil then state.hideIgnored = true end
    if state.showRender == nil then state.showRender = false end
    capture(state, api)
end
function app.shutdown(state, api) api.capturePackets(false) end

local function who(api, entry)
    if entry.clientId then return api.clientName(entry.clientId) end
    return entry.sender and ("pc " .. entry.sender) or "?"
end
local function visible(state, view, entry)
    if view.holdAt and entry.n > view.holdAt then return false end
    if state.hideIgnored and entry.status ~= "ok" then return false end
    if view.direction and view.direction ~= "all" and entry.direction ~= view.direction then return false end
    if view.kind and entry.type ~= view.kind then return false end
    if view.client and entry.clientId ~= view.client then return false end
    return true
end
-- Newest first, so page 1 is always the live end of the capture.
local function filtered(state, api, view)
    local log, total, active = api.getPacketLog()
    local rows = {}
    for index = #log, 1, -1 do
        if visible(state, view, log[index]) then rows[#rows + 1] = log[index] end
    end
    return rows, log, total, active
end
local function ink(entry)
    if entry.status == "foreign" then return 16384 end
    if entry.status == "ignored" then return 128 end
    return entry.direction == "tx" and 2048 or 8192
end
local function row(api, entry, width)
    local arrow = entry.direction == "tx" and ">" or "<"
    local size = entry.bytes .. "B"
    local text = string.format("%7.1f %s %s", entry.at, arrow, entry.type or "?")
    if width >= 30 then text = text .. " " .. who(api, entry) end
    local room = width - #size - 1
    if #text > room then text = text:sub(1, math.max(0, room)) end
    return text .. string.rep(" ", width - #text - #size) .. size
end
local function counts(log, field, api)
    local seen, order = {}, {}
    for _, entry in ipairs(log) do
        local key = entry[field]
        if key then
            if not seen[key] then
                seen[key] = {key = key, packets = 0, bytes = 0}
                order[#order + 1] = seen[key]
            end
            seen[key].packets, seen[key].bytes = seen[key].packets + 1, seen[key].bytes + entry.bytes
        end
    end
    table.sort(order, function(a, b)
        if a.packets ~= b.packets then return a.packets > b.packets end
        return tostring(a.key) < tostring(b.key)
    end)
    return order
end
local function build(w, h, state, api, view)
    local ui = api.ui.form(w, h, view, api.getAppColour(name))
    local screen = view.screen or "list"
    if screen == "list" then
        local rows = filtered(state, api, view)
        -- Only visible rows are counted, so hidden traffic never forces a redraw.
        ui.heading("Net Scope " .. (view.holdAt and "HOLD " or "LIVE ") .. #rows .. " pkts", api.getAppColour(name))
        local slots = #rows <= h - 2 and h - 2 or h - 3
        local first = ui.page("list", #rows, slots, h - 1)
        for i = 1, slots do
            local entry = rows[first + i]
            if entry then ui.action(i + 1, row(api, entry, w), "detail", entry.n, 1, w, true, ink(entry)) end
        end
        if #rows == 0 then ui.put(1, 3, "No packets yet", w, true) end
        ui.footer({{"Menu", "menu"}, {view.holdAt and "Live" or "Hold", "hold"}, {"Close", "close"}})
    elseif screen == "detail" then
        local log = api.getPacketLog()
        local entry
        for _, item in ipairs(log) do if item.n == view.packet then entry = item; break end end
        if not entry then
            ui.info("Packet", {"This packet left the capture buffer."}, "detail", "list")
        else
            local lines = {"#" .. entry.n .. " at " .. string.format("%.2f", entry.at) .. "s OS uptime",
                (entry.direction == "tx" and "TX: OS -> " or "RX: -> OS from ") .. who(api, entry),
                "Type: " .. (entry.type or "?"), "Status: " .. (statusText[entry.status] or entry.status),
                "Channel " .. tostring(entry.channel) .. ", " .. entry.bytes .. " bytes"}
            if entry.clientId then lines[#lines + 1] = "Client ID: " .. entry.clientId end
            if entry.sender then
                lines[#lines + 1] = "Computer " .. entry.sender .. " -> " .. tostring(entry.recipient or "any")
            end
            if entry.sequence then
                lines[#lines + 1] = "Sequence " .. entry.sequence .. ", relay hops " .. (entry.hops or 0)
            end
            if entry.info and #entry.info > 0 then
                lines[#lines + 1] = "--- fields ---"
                for _, field in ipairs(entry.info) do lines[#lines + 1] = field end
            end
            ui.info("Packet #" .. entry.n, lines, "detail", "list")
            if entry.type or entry.clientId then
                ui.footer({{"Back", "list"}, {"Type", "onlyType", entry.type, entry.type ~= nil},
                    {"Client", "onlyClient", entry.clientId, entry.clientId ~= nil}})
            end
        end
    elseif screen == "menu" then
        ui.menu("Net Scope menu", {
            {"Direction: " .. directionLabel[view.direction or "all"], "direction"},
            {"Type: " .. (view.kind or "all"), "types"},
            {"Client: " .. (view.client and api.clientName(view.client) or "all"), "clients"},
            {"Ignored/foreign: " .. (state.hideIgnored and "hidden" or "shown"), "ignored"},
            {"Render packets: " .. (state.showRender and "captured" or "skipped"), "render"},
            {"Statistics", "stats"}, {"Clear capture", "clear"}, {"UI color", "colour"}}, "menu", {{"Back", "list"}})
    elseif screen == "types" or screen == "clients" then
        local log = api.getPacketLog()
        local field = screen == "types" and "type" or "clientId"
        local rows = {{"All", "pick", {field = field}}}
        for _, item in ipairs(counts(log, field, api)) do
            local label = field == "clientId" and api.clientName(item.key) or item.key
            rows[#rows + 1] = {label .. " (" .. item.packets .. ")", "pick", {field = field, key = item.key}}
        end
        ui.menu(screen == "types" and "Packet type" or "Client", rows, screen, {{"Back", "menu"}})
    elseif screen == "stats" then
        local log, total = api.getPacketLog()
        local bytes, rx, tx = 0, 0, 0
        for _, entry in ipairs(log) do
            bytes = bytes + entry.bytes
            if entry.direction == "tx" then tx = tx + 1 else rx = rx + 1 end
        end
        local lines = {#log .. " in buffer, " .. total .. " captured", "RX " .. rx .. " / TX " .. tx .. ", " .. bytes .. " bytes",
            "--- by type ---"}
        for _, item in ipairs(counts(log, "type", api)) do
            lines[#lines + 1] = item.key .. ": " .. item.packets .. " pkts, " .. item.bytes .. " B"
        end
        lines[#lines + 1] = "--- by client ---"
        for _, item in ipairs(counts(log, "clientId", api)) do
            lines[#lines + 1] = api.clientName(item.key) .. ": " .. item.packets .. " pkts, " .. item.bytes .. " B"
        end
        ui.info("Statistics", lines, "stats", "menu")
    else ui.info("Net Scope", {view.message or "Select a packet"}, "notice", "list") end
    return ui
end
function app.render(w, h, state, api, context) return build(w, h, state, api, context.view).lines end
function app.handleTouch(x, y, w, h, state, api, context)
    local view = context.view
    local action, value = api.ui.actionAt(build(w, h, state, api, view).hits, x, y)
    if not action then return false end
    if action == "page" then view.pages[value.key] = value.page
    elseif action == "close" then return api.closeWindow(context.windowId)
    elseif action == "detail" then view.packet, view.screen, view.pages.detail = value, "detail", 1
    elseif action == "hold" then
        if view.holdAt then view.holdAt = nil else
            local _, total = api.getPacketLog()
            view.holdAt = total
        end
        view.pages.list = 1
    elseif action == "direction" then
        local current = 1
        for i, item in ipairs(directions) do if item == (view.direction or "all") then current = i end end
        view.direction = directions[current % #directions + 1]
    elseif action == "pick" then
        if value.field == "type" then view.kind = value.key else view.client = value.key end
        view.screen, view.pages.list = "menu", 1
    elseif action == "onlyType" then view.kind, view.screen, view.pages.list = value, "list", 1
    elseif action == "onlyClient" then view.client, view.screen, view.pages.list = value, "list", 1
    elseif action == "ignored" or action == "render" then
        local key = action == "ignored" and "hideIgnored" or "showRender"
        state[key] = not state[key]
        local ok, err = api.save()
        if not ok then state[key] = not state[key]; view.screen, view.message = "notice", tostring(err) end
        capture(state, api)
    elseif action == "clear" then
        api.clearPacketLog()
        view.holdAt, view.screen, view.pages = nil, "list", {}
    elseif action == "colour" then return api.pickColour(context.windowId)
    else view.screen = action end
    api.invalidateAppViews(name)
    return true
end
return app
