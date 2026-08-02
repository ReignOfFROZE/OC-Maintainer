local component = require("component")
local term = require("term")
local gpu = component.gpu

function dump(o, depth)
    if depth == nil then depth = 0 end

    if depth > 10 then return "..." end

    if type(o) == 'table' then
        local s = '{ '
        for k, v in pairs(o) do
            if type(k) ~= 'number' then k = '"' .. k .. '"' end
            s = s .. '[' .. k .. '] = ' .. dump(v, depth + 1) .. ',\n'
        end
        return s .. '} '
    else
        return tostring(o)
    end
end

function parser(string)
    if type(string) == "string" then
        local numberString = string.gsub(string, "([^0-9]+)", "")
        if tonumber(numberString) then
            return math.floor(tonumber(numberString) + 0)
        end
        return 0
    else
        return 0
    end
end

function logInfo(string)
    if type(string) == "string" then
        print("[" .. os.date("%H:%M:%S") .. "] " .. string)
    end
end

function logColored(color, string)
    if type(string) == "string" then
        -- Color only renders on tier 2/3 screens; on tier 1 this is a no-op.
        local oldColor = gpu.setForeground(color)
        print("[" .. os.date("%H:%M:%S") .. "] " .. string)
        gpu.setForeground(oldColor)
    end
end

function logSuccess(string)
    logColored(0x00FF00, string)
end

function logError(string)
    logColored(0xFF0000, string)
end

function clearScreen()
    term.clear()
end

function randomizeTable(inputTable)
    for i = #inputTable, 1, -1 do
        local j = math.random(i)
        inputTable[i], inputTable[j] = inputTable[j], inputTable[i]
    end
end


function getKeys(inputTable)
    local keys = {}
    for key, _ in pairs(inputTable) do
        table.insert(keys, key)
    end
    return keys
end

function setupGroupCache(groups)
    local groupCache = {}
    for i = 1, #groups do
        local entries = groups[i].entries
        groupCache[i] = getKeys(entries)
    end
    return groupCache
end
