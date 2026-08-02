-- Maintainer2: PoC dashboard version of Maintainer.
-- Static table of every configured craftable, updated in place: fill bars,
-- trend arrows, a summary line, a crafting-CPU panel, a rolling failure log,
-- and a background watcher thread that keeps Requested/Crafting statuses
-- fresh between passes.
-- Keyboard: Q quit, P pause, R clear cache + refresh.
-- Touch: tap an item row to force-request one batch (ignores threshold),
-- tap its Status cell to see the item's full last message.
-- Note: iterates groups in config order; no shuffle/priority/batch logic.

local component = require("component")
local computer = require("computer")
local event = require("event")
local term = require("term")
local thread = require("thread")
local unicode = require("unicode")
local gpu = component.gpu

local ae2 = require("src.AE2")
local cfg = require("config")

local sleepInterval = cfg.sleep
local WATCH_INTERVAL = 2 -- seconds between watcher-thread CPU polls

local COLOR = {
    title       = 0xFFFFFF,
    header      = 0xFFFFFF,
    label       = 0xCCCCCC,
    dim         = 0x808080,
    ok          = 0x00FF00, -- threshold met
    requested   = 0xFFFF00, -- craft scheduled
    crafting    = 0x00FFFF, -- CPU currently working on it
    failed      = 0xFF0000, -- craft request failed
    uncraftable = 0xFF8000, -- no pattern for this item
    bg          = 0x000000,
    stripeBg    = 0x2D2D2D, -- background for every other item row
}

-- Flatten config groups into an ordered list of items.
local items = {}
for groupIdx, group in ipairs(cfg.items) do
    for name, entry in pairs(group.entries) do
        table.insert(items, {
            name = name,
            group = groupIdx,
            threshold = entry[1],
            count = entry[2],
            fluid = entry[3],
            state = {stored = nil, prev = nil, status = "Pending", color = COLOR.dim, msg = nil},
        })
    end
end
table.sort(items, function(a, b)
    if a.group ~= b.group then return a.group < b.group end
    return a.name < b.name
end)

-- Non-fluid labels, for the once-per-pass batched stored lookup.
local itemLabels = {}
for _, it in ipairs(items) do
    if not it.fluid then table.insert(itemLabels, it.name) end
end

-- Use the biggest resolution the GPU/screen pair supports for maximum rows.
gpu.setResolution(gpu.maxResolution())
local screenW, screenH = gpu.getResolution()

-- Vertical layout, top to bottom: title, summary, column headers, item rows,
-- CPU panel, failure log, touch/detail line, footer.
local ROW_TITLE       = 1
local ROW_SUMMARY     = 2
local ROW_HEADER      = 3
local ROW_FIRST_ITEM  = 4
local ROW_FOOTER      = screenH
local ROW_DETAIL      = screenH - 1
local FAIL_LINES      = 3
local ROW_FAIL_FIRST  = screenH - 1 - FAIL_LINES
local ROW_FAIL_HEADER = ROW_FAIL_FIRST - 1
local CPU_LINES       = 2
local ROW_CPU_FIRST   = ROW_FAIL_HEADER - CPU_LINES
local ROW_CPU_HEADER  = ROW_CPU_FIRST - 1
local ROW_LAST_ITEM   = ROW_CPU_HEADER - 2

local maxVisible = math.max(0, math.min(#items, ROW_LAST_ITEM - ROW_FIRST_ITEM + 1))

-- Column layout: | G | Item | Stored | trend | bar | % | Target | Status |
local COL_GROUP_W  = 3
local COL_STORED_W = 8
local COL_TREND_W  = 1
local COL_BAR_W    = 22
local COL_PCT_W    = 4
local COL_THRESH_W = 8
local COL_STATUS_W = 12
local COL_NAME_W = screenW - (COL_GROUP_W + COL_STORED_W + COL_TREND_W
    + COL_BAR_W + COL_PCT_W + COL_THRESH_W + COL_STATUS_W + 7)
if COL_NAME_W > 50 then
    -- Give surplus width to the bar and status columns instead of the name.
    local extra = COL_NAME_W - 50
    COL_NAME_W = 50
    local barExtra = math.min(extra, 18)
    COL_BAR_W = COL_BAR_W + barExtra
    COL_STATUS_W = COL_STATUS_W + (extra - barExtra)
end

local X_GROUP  = 1
local X_NAME   = X_GROUP + COL_GROUP_W + 1
local X_STORED = X_NAME + COL_NAME_W + 1
local X_TREND  = X_STORED + COL_STORED_W + 1
local X_BAR    = X_TREND + COL_TREND_W + 1
local X_PCT    = X_BAR + COL_BAR_W + 1
local X_THRESH = X_PCT + COL_PCT_W + 1
local X_STATUS = X_THRESH + COL_THRESH_W + 1

local running = true
local paused = false
local forcePass = false
local passRunning = false
local passCount = 0
local nextPass = 0
local failLog = {}

local function leftAlign(value, width)
    local s = tostring(value)
    local len = unicode.len(s)
    if len > width then return unicode.sub(s, 1, width) end
    return s .. string.rep(" ", width - len)
end

local function rightAlign(value, width)
    local s = tostring(value)
    local len = unicode.len(s)
    if len > width then return unicode.sub(s, 1, width) end
    return string.rep(" ", width - len) .. s
end

local function fmtNum(n)
    if n == nil then return "-" end
    if n >= 1000000000 then return string.format("%.2fG", n / 1000000000) end
    if n >= 1000000 then return string.format("%.2fM", n / 1000000) end
    if n >= 10000 then return string.format("%.1fK", n / 1000) end
    return tostring(n)
end

local function rowBg(row)
    if (row - ROW_FIRST_ITEM) % 2 == 1 then
        return COLOR.stripeBg
    end
    return COLOR.bg
end

local function drawCell(x, row, text, width, color, alignRight, bg)
    gpu.setBackground(bg or COLOR.bg)
    gpu.setForeground(color)
    if alignRight then
        gpu.set(x, row, rightAlign(text, width))
    else
        gpu.set(x, row, leftAlign(text, width))
    end
end

local function fillColor(ratio)
    if ratio >= 1 then return COLOR.ok end
    if ratio >= 0.5 then return COLOR.requested end
    return COLOR.failed
end

local function drawTitle()
    gpu.setBackground(COLOR.bg)
    gpu.fill(1, ROW_TITLE, screenW, 1, " ")
    drawCell(1, ROW_TITLE, "AE2 Maintainer Dashboard", 40, COLOR.title)
    local info
    if paused then
        info = "PAUSED - press P to resume"
    else
        info = "pass " .. passCount .. " @ " .. os.date("%H:%M:%S") .. " - every " .. sleepInterval .. "s"
    end
    drawCell(screenW - 44 + 1, ROW_TITLE, info, 44, paused and COLOR.requested or COLOR.dim, true)
end

local function drawSummary()
    local counts = {}
    for i = 1, maxVisible do
        local s = items[i].state.status
        counts[s] = (counts[s] or 0) + 1
    end
    gpu.setBackground(COLOR.bg)
    gpu.fill(1, ROW_SUMMARY, screenW, 1, " ")
    local order = {
        {"OK", COLOR.ok}, {"Requested", COLOR.requested}, {"Crafting", COLOR.crafting},
        {"Failed", COLOR.failed}, {"Uncraftable", COLOR.uncraftable}, {"Pending", COLOR.dim},
    }
    local x = 1
    local first = true
    for _, entry in ipairs(order) do
        local n = counts[entry[1]] or 0
        if n > 0 then
            if not first then
                gpu.setForeground(COLOR.dim)
                gpu.set(x, ROW_SUMMARY, " | ")
                x = x + 3
            end
            first = false
            local segment = n .. " " .. entry[1]:lower()
            gpu.setForeground(entry[2])
            gpu.set(x, ROW_SUMMARY, segment)
            x = x + unicode.len(segment)
        end
    end
end

local function showDetail(text, color)
    drawCell(1, ROW_DETAIL, text or "", screenW, color or COLOR.label)
end

local function drawItemRow(i)
    local it = items[i]
    local st = it.state
    local row = ROW_FIRST_ITEM + i - 1
    local bg = rowBg(row)

    local ratio = nil
    if st.stored ~= nil and it.threshold and it.threshold > 0 then
        ratio = st.stored / it.threshold
    end

    local storedColor = COLOR.dim
    if st.stored ~= nil then
        storedColor = ratio and fillColor(ratio) or COLOR.label
    end
    drawCell(X_STORED, row, st.stored and fmtNum(st.stored) or "?", COL_STORED_W, storedColor, true, bg)

    local trendChar, trendColor = "·", COLOR.dim
    if st.prev ~= nil and st.stored ~= nil then
        if st.stored > st.prev then
            trendChar, trendColor = "↑", COLOR.ok
        elseif st.stored < st.prev then
            trendChar, trendColor = "↓", COLOR.failed
        end
    end
    drawCell(X_TREND, row, trendChar, COL_TREND_W, trendColor, false, bg)

    if ratio ~= nil then
        local fc = fillColor(ratio)
        local filled = math.max(0, math.min(COL_BAR_W, math.floor(ratio * COL_BAR_W + 0.5)))
        local bar = string.rep("█", filled) .. string.rep("░", COL_BAR_W - filled)
        drawCell(X_BAR, row, bar, COL_BAR_W, fc, false, bg)
        drawCell(X_PCT, row, math.min(999, math.floor(ratio * 100 + 0.5)) .. "%", COL_PCT_W, fc, true, bg)
    else
        drawCell(X_BAR, row, string.rep("░", COL_BAR_W), COL_BAR_W, COLOR.dim, false, bg)
        drawCell(X_PCT, row, "-", COL_PCT_W, COLOR.dim, true, bg)
    end

    drawCell(X_STATUS, row, st.status, COL_STATUS_W, st.color, false, bg)
end

local function drawFailLog()
    for i = 1, FAIL_LINES do
        drawCell(1, ROW_FAIL_FIRST + i - 1, failLog[i] or "", screenW,
            i == 1 and COLOR.failed or COLOR.dim)
    end
end

local function pushFailure(name, msg)
    table.insert(failLog, 1, "[" .. os.date("%H:%M:%S") .. "] " .. name .. ": " .. (msg or "unknown error"))
    while #failLog > FAIL_LINES do table.remove(failLog) end
    drawFailLog()
end

local CPU_CHIP_W = 26
local cpusPerRow = math.max(1, math.floor(screenW / (CPU_CHIP_W + 1)))

local function drawCpuPanel(cpuList)
    gpu.setBackground(COLOR.bg)
    gpu.fill(1, ROW_CPU_FIRST, screenW, CPU_LINES, " ")
    local maxChips = cpusPerRow * CPU_LINES
    for idx, c in ipairs(cpuList) do
        if idx > maxChips then
            drawCell(screenW - 5, ROW_CPU_FIRST + CPU_LINES - 1,
                "+" .. (#cpuList - maxChips), 5, COLOR.dim, true)
            break
        end
        local row = ROW_CPU_FIRST + math.floor((idx - 1) / cpusPerRow)
        local x = 1 + ((idx - 1) % cpusPerRow) * (CPU_CHIP_W + 1)
        local id = (c.name ~= nil and c.name ~= "" and c.name) or ("#" .. idx)
        local text, color
        if c.crafting then
            text, color = c.crafting, COLOR.crafting
        elseif c.busy then
            text, color = "busy", COLOR.requested
        else
            text, color = "idle", COLOR.dim
        end
        drawCell(x, row, id, 4, COLOR.label)
        drawCell(x + 5, row, text, CPU_CHIP_W - 5, color)
    end
    drawCell(15, ROW_CPU_HEADER, "(" .. #cpuList .. ")", 8, COLOR.dim)
end

local function drawStatic()
    term.clear()
    drawTitle()

    drawCell(X_GROUP, ROW_HEADER, "G", COL_GROUP_W, COLOR.header)
    drawCell(X_NAME, ROW_HEADER, "Item", COL_NAME_W, COLOR.header)
    drawCell(X_STORED, ROW_HEADER, "Stored", COL_STORED_W, COLOR.header, true)
    drawCell(X_BAR, ROW_HEADER, "Fill", COL_BAR_W, COLOR.header)
    drawCell(X_PCT, ROW_HEADER, "%", COL_PCT_W, COLOR.header, true)
    drawCell(X_THRESH, ROW_HEADER, "Target", COL_THRESH_W, COLOR.header, true)
    drawCell(X_STATUS, ROW_HEADER, "Status", COL_STATUS_W, COLOR.header)

    for i = 1, maxVisible do
        local it = items[i]
        local row = ROW_FIRST_ITEM + i - 1
        local bg = rowBg(row)
        -- Paint the whole row first so the stripe covers column gaps too.
        gpu.setBackground(bg)
        gpu.fill(1, row, screenW, 1, " ")
        drawCell(X_GROUP, row, it.group, COL_GROUP_W, COLOR.dim, false, bg)
        drawCell(X_NAME, row, it.name, COL_NAME_W, COLOR.label, false, bg)
        drawCell(X_THRESH, row, fmtNum(it.threshold), COL_THRESH_W, COLOR.dim, true, bg)
        drawItemRow(i)
    end

    drawCell(1, ROW_CPU_HEADER, "Crafting CPUs", 14, COLOR.header)
    drawCell(1, ROW_FAIL_HEADER, "Recent failures", screenW, COLOR.header)
    drawFailLog()
    drawCell(1, ROW_FOOTER,
        "[Q]uit  [P]ause  [R]efresh+clear cache  |  tap item: force craft  |  tap status: last message",
        screenW, COLOR.dim)
end

local function updateItem(i, itemsCrafting, storedMap)
    local it = items[i]
    local st = it.state
    st.prev = st.stored
    if it.fluid then
        st.stored = ae2.getStored(it.name, it.fluid)
    else
        st.stored = storedMap[it.name] or 0
    end

    local prevStatus = st.status
    local newStatus, newColor
    if itemsCrafting[it.name] then
        newStatus, newColor = "Crafting", COLOR.crafting
    else
        local row = ROW_FIRST_ITEM + i - 1
        drawCell(X_STATUS, row, "Checking...", COL_STATUS_W, COLOR.dim, false, rowBg(row))
        local success, answer = ae2.requestItem(it.name, it.threshold, it.count, it.fluid, st.stored)
        st.msg = answer
        if success == true then
            newStatus, newColor = "Requested", COLOR.requested
        elseif success == false then
            if answer:find("not craftable") then
                newStatus, newColor = "Uncraftable", COLOR.uncraftable
            else
                newStatus, newColor = "Failed", COLOR.failed
            end
        else -- nil: threshold met, nothing to do
            newStatus, newColor = "OK", COLOR.ok
        end
    end

    if (newStatus == "Failed" or newStatus == "Uncraftable") and prevStatus ~= newStatus then
        pushFailure(it.name, st.msg)
    end
    st.status, st.color = newStatus, newColor
    drawItemRow(i)
end

local function runPass()
    passRunning = true
    passCount = passCount + 1
    local cpuList = ae2.getCpuStatus()
    drawCpuPanel(cpuList)
    local itemsCrafting = {}
    for _, c in ipairs(cpuList) do
        if c.crafting then itemsCrafting[c.crafting] = true end
    end
    local storedMap = ae2.getStoredMap(itemLabels)
    for i = 1, maxVisible do
        updateItem(i, itemsCrafting, storedMap)
    end
    drawSummary()
    drawTitle()
    passRunning = false
end

-- Watcher: between passes, cheaply poll the crafting CPUs so Requested items
-- flip to Crafting and finished crafts flip to OK without waiting for the
-- next full pass. Only queries stored amounts for items that just finished.
local function pollWatched()
    local watched = {}
    local any = false
    for i = 1, maxVisible do
        local s = items[i].state.status
        if s == "Requested" or s == "Crafting" then
            watched[items[i].name] = i
            any = true
        end
    end
    if not any then return end

    local cpuList = ae2.getCpuStatus()
    drawCpuPanel(cpuList)
    local crafting = {}
    for _, c in ipairs(cpuList) do
        if c.crafting then crafting[c.crafting] = true end
    end

    local changed = false
    for name, i in pairs(watched) do
        local st = items[i].state
        if crafting[name] then
            if st.status ~= "Crafting" then
                st.status, st.color = "Crafting", COLOR.crafting
                drawItemRow(i)
                changed = true
            end
        elseif st.status == "Crafting" then
            -- No CPU holds it anymore: the craft finished (or was cancelled).
            local it = items[i]
            st.prev = st.stored
            st.stored = ae2.getStored(it.name, it.fluid)
            st.status, st.color = "OK", COLOR.ok
            drawItemRow(i)
            changed = true
        end
    end
    if changed then drawSummary() end
end

local watcher = thread.create(function()
    while true do
        os.sleep(WATCH_INTERVAL)
        if not paused and not passRunning then
            pcall(pollWatched)
        end
    end
end)

local function onKey(char)
    if char <= 0 or char > 255 then return end
    local c = string.char(char):lower()
    if c == "q" then
        running = false
    elseif c == "p" then
        paused = not paused
        drawTitle()
    elseif c == "r" then
        ae2.clearCache()
        forcePass = true
        showDetail("Cache cleared, refreshing...", COLOR.dim)
    end
end

local function onTouch(x, y)
    local i = y - ROW_FIRST_ITEM + 1
    if i < 1 or i > maxVisible then return end
    local it = items[i]
    if x >= X_STATUS then
        showDetail(it.name .. ": " .. (it.state.msg or "no message yet"))
    else
        showDetail("Force-requesting " .. it.count .. " x " .. it.name .. "...", COLOR.requested)
        local success, answer = ae2.requestItem(it.name, nil, it.count, it.fluid)
        it.state.msg = answer
        if success == true then
            it.state.status, it.state.color = "Requested", COLOR.requested
        elseif success == false then
            it.state.status, it.state.color = "Failed", COLOR.failed
            pushFailure(it.name, answer)
        end
        drawItemRow(i)
        drawSummary()
        showDetail(answer, success and COLOR.ok or COLOR.failed)
    end
end

local function main()
    drawStatic()
    if #items > maxVisible then
        showDetail((#items - maxVisible) .. " item(s) don't fit on screen and are not shown!", COLOR.requested)
    end
    while running do
        if forcePass or (not paused and computer.uptime() >= nextPass) then
            forcePass = false
            runPass()
            nextPass = computer.uptime() + sleepInterval
        end
        local timeout = paused and math.huge or math.max(0.1, nextPass - computer.uptime())
        local ev = table.pack(event.pull(timeout))
        local name = ev[1]
        if name == "key_down" then
            onKey(ev[3])
        elseif name == "touch" then
            onTouch(ev[3], ev[4])
        elseif name == "interrupted" then
            running = false
        end
    end
end

-- Restore a usable terminal even if the loop crashes or is interrupted.
local ok, err = pcall(main)
watcher:kill()
gpu.setForeground(0xFFFFFF)
gpu.setBackground(0x000000)
term.clear()
if not ok then
    print("Maintainer2 stopped: " .. tostring(err))
end
