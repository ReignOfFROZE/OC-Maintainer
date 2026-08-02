local ae2 = require("src.AE2")
local cfg = require("config")
local util = require("src.Utility") 

local groups = cfg.items
local sleepInterval = cfg.sleep
local randomizeFrequency = cfg.randomizeFrequency
local priorityMode = cfg.priorityMode

local shuffleCounter = 0
local shuffleLists = false
local recipeGroupsRandomized = randomizeFrequency ~= 0


function batchReady(groupTbl, itemsCrafting, groupNumber)
    if groupTbl.batchMode == true then
        local batchReady = ae2.batchReady(groupTbl.entries, itemsCrafting)
        if (not batchReady) then
            logInfo("Group " .. groupNumber .. " has batch mode enabled but items still crafting!")
            return false
        end
    end
    return true
end


logInfo("Setting up group cache...")
local groupCache = setupGroupCache(groups)
logInfo("Group cache initialized.")

local idxTable = {}
for i=1, #groups do
    idxTable[i] = i
end

-- Clean up potential unspecified priorities and batch mode specifiers
for _, group in ipairs(groups) do
    if group.priority == nil then
        group.priority = 0
    end
    if group.batchMode == nil then
        group.batchMode = false
    end
end

if priorityMode then
    -- Sort based on priority.
    table.sort(groups, function (groupA, groupB)
        return groupA.priority > groupB.priority
    end)
end

while true do
    clearScreen()

    local itemsCrafting = ae2.checkIfCrafting()

    -- randomize recipe groups
    if (not priorityMode) and recipeGroupsRandomized and shuffleLists then
        logInfo(">> Group order randomized!")
        randomizeTable(idxTable)
    end

    for _, randGroupIdx in ipairs(idxTable) do
        local groupTbl = groups[randGroupIdx]

        logInfo("=== Group " .. randGroupIdx .. " =============")

        -- Step 1: Randomize if necessary.
        local itemKeys = groupCache[randGroupIdx]
        -- shuffle in-group items if necessary.
        if shuffleLists then -- stays false if randomization is disabled.
            logInfo(">> Scheduling order shuffled for group " .. randGroupIdx .. "!")
            randomizeTable(itemKeys)
            groupCache[randGroupIdx] = itemKeys
        end

        -- Step 2: Skip group if batch isn't ready.
        if (not batchReady(groupTbl, itemsCrafting, randGroupIdx)) then
            goto skipGroup
        end

        -- Step 3: Craft items in group.
        for _, item in ipairs(itemKeys) do
            local config = groupTbl.entries[item]
            if itemsCrafting[item] == true then
                logInfo(item .. " is already being crafted, skipping...")
            else
                local success, answer = ae2.requestItem(item, config[1], config[2], config[3])
                if success == true then
                    logSuccess(answer)
                elseif success == false then
                    logError(answer)
                else
                    logInfo(answer)
                end
            end
        end

        ::skipGroup::
    end

    -- Update flag that indicates groups should be randomized.
    if recipeGroupsRandomized then
        shuffleLists = (shuffleCounter == 0)
        shuffleCounter = (shuffleCounter + 1) % randomizeFrequency
    end

    os.sleep(sleepInterval)
end
