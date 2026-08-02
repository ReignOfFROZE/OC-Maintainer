-- Maintainer2: PoC dashboard version of Maintainer.
-- Draws a static table of every configured craftable and updates each row's
-- stored amount and status in place, instead of scrolling log lines.
-- Note: this PoC iterates groups in config order; it does not implement the
-- shuffle/priority/batch logic from Maintainer.lua.

local component = require("component")
local term = require("term")
local gpu = component.gpu

local ae2 = require("src.AE2")
local cfg = require("config")

local COLOR = {
    title       = 0xFFFFFF,
    header      = 0xFFFFFF,
    label       = 0xCCCCCC,
    dim         = 0x808080,
    ok          = 0x00FF00, -- threshold met
    requested   = 0xFFFF00, -- craft scheduled this pass
    crafting    = 0x00FFFF, -- CPU currently working on it
    failed      = 0xFF0000, -- craft request failed
    uncraftable = 0xFF8000, -- no pattern for this item
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
        })
    end
end
table.sort(items, function(a, b)
    if a.group ~= b.group then return a.group < b.group end
    return a.name < b.name
end)

-- Use the biggest resolution the GPU/screen pair supports for maximum rows.
gpu.setResolution(gpu.maxResolution())
local screenW, screenH = gpu.getResolution()

-- Column layout: | G | Item name | Stored | Threshold | Status |
local COL_GROUP_W  = 3
local COL_AMOUNT_W = 12
local COL_STATUS_W = 14
local COL_NAME_W   = screenW - COL_GROUP_W - (COL_AMOUNT_W * 2) - COL_STATUS_W - 4

local X_GROUP  = 1
local X_NAME   = X_GROUP + COL_GROUP_W + 1
local X_STORED = X_NAME + COL_NAME_W + 1
local X_THRESH = X_STORED + COL_AMOUNT_W + 1
local X_STATUS = X_THRESH + COL_AMOUNT_W + 1

local ROW_FIRST_ITEM = 3
local ROW_FOOTER = screenH
local maxVisible = math.min(#items, ROW_FOOTER - ROW_FIRST_ITEM)

local function leftAlign(value, width)
    local s = tostring(value)
    if #s > width then s = s:sub(1, width) end
    return s .. string.rep(" ", width - #s)
end

local function rightAlign(value, width)
    local s = tostring(value)
    if #s > width then s = s:sub(1, width) end
    return string.rep(" ", width - #s) .. s
end

local function drawCell(x, row, text, width, color, alignRight)
    gpu.setForeground(color)
    if alignRight then
        gpu.set(x, row, rightAlign(text, width))
    else
        gpu.set(x, row, leftAlign(text, width))
    end
end

local function drawStatic()
    term.clear()
    drawCell(1, 1, "AE2 Maintainer Dashboard", screenW, COLOR.title)

    drawCell(X_GROUP, 2, "G", COL_GROUP_W, COLOR.header)
    drawCell(X_NAME, 2, "Item", COL_NAME_W, COLOR.header)
    drawCell(X_STORED, 2, "Stored", COL_AMOUNT_W, COLOR.header, true)
    drawCell(X_THRESH, 2, "Threshold", COL_AMOUNT_W, COLOR.header, true)
    drawCell(X_STATUS, 2, "Status", COL_STATUS_W, COLOR.header)

    for i = 1, maxVisible do
        local item = items[i]
        local row = ROW_FIRST_ITEM + i - 1
        drawCell(X_GROUP, row, item.group, COL_GROUP_W, COLOR.dim)
        drawCell(X_NAME, row, item.name, COL_NAME_W, COLOR.label)
        drawCell(X_STORED, row, "?", COL_AMOUNT_W, COLOR.dim, true)
        drawCell(X_THRESH, row, item.threshold or "-", COL_AMOUNT_W, COLOR.dim, true)
        drawCell(X_STATUS, row, "Pending", COL_STATUS_W, COLOR.dim)
    end

    if #items > maxVisible then
        drawCell(1, ROW_FOOTER - 1,
            "(+" .. (#items - maxVisible) .. " more items than screen rows)",
            screenW, COLOR.dim)
    end
end

local function updateFooter(passCount)
    drawCell(1, ROW_FOOTER,
        "Pass " .. passCount .. " finished at " .. os.date("%H:%M:%S")
            .. " - next in " .. cfg.sleep .. "s. Press Ctrl+Alt+C to stop.",
        screenW, COLOR.dim)
end

local function updateRow(row, item, itemsCrafting)
    local stored = ae2.getStored(item.name, item.fluid)
    drawCell(X_STORED, row, stored or "?", COL_AMOUNT_W,
        stored and COLOR.label or COLOR.dim, true)

    if itemsCrafting[item.name] then
        drawCell(X_STATUS, row, "Crafting", COL_STATUS_W, COLOR.crafting)
        return
    end

    drawCell(X_STATUS, row, "Checking...", COL_STATUS_W, COLOR.dim)
    local success, answer = ae2.requestItem(item.name, item.threshold, item.count, item.fluid)

    if success == true then
        drawCell(X_STATUS, row, "Requested", COL_STATUS_W, COLOR.requested)
    elseif success == false then
        if answer:find("not craftable") then
            drawCell(X_STATUS, row, "Uncraftable", COL_STATUS_W, COLOR.uncraftable)
        else
            drawCell(X_STATUS, row, "Failed", COL_STATUS_W, COLOR.failed)
        end
    else -- nil: threshold met, nothing to do
        drawCell(X_STATUS, row, "OK", COL_STATUS_W, COLOR.ok)
    end
end

local function main()
    drawStatic()
    local passCount = 0
    while true do
        local itemsCrafting = ae2.checkIfCrafting()
        for i = 1, maxVisible do
            updateRow(ROW_FIRST_ITEM + i - 1, items[i], itemsCrafting)
        end
        passCount = passCount + 1
        updateFooter(passCount)
        os.sleep(cfg.sleep)
    end
end

-- Restore a usable terminal even if the loop crashes or is interrupted.
local ok, err = pcall(main)
gpu.setForeground(0xFFFFFF)
term.clear()
if not ok then
    print("Maintainer2 stopped: " .. tostring(err))
end
