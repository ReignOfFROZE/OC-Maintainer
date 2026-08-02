local component = require("component")
local ME = component.me_interface

local AE2 = {}

-- Lightweight cache for specific items only
local itemCache = {}
local cacheTimestamp = 0
local CACHE_DURATION = 600 -- 10 minutes in seconds

-- Function to get or cache a specific craftable item
local function getCraftableForItem(itemName)
    local currentTime = os.time()
    
    -- Check if we have a cached version of this specific item and it's still valid
    if itemCache[itemName] and currentTime - cacheTimestamp < CACHE_DURATION then
        return itemCache[itemName]
    end
    
    -- If cache is too old, clear it completely to save memory
    if currentTime - cacheTimestamp >= CACHE_DURATION then
        itemCache = {}
        cacheTimestamp = currentTime
    end
    
    -- Look for this specific item in craftables
    local craftables = ME.getCraftables({["label"] = itemName})
    if #craftables >= 1 then
        itemCache[itemName] = craftables[1] -- Cache only this one item
        return craftables[1]
    end
    
    itemCache[itemName] = nil -- Cache that it's not craftable
    return nil
end

-- storedHint: optional, skips the network query if the caller already knows the amount.
function AE2.requestItem(name, threshold, count, fluidRegistry, storedHint)
    local craftable = getCraftableForItem(name)

    if craftable then
        local item = craftable.getStack()
        if threshold ~= nil then
            local stored = storedHint or AE2.getStored(name, fluidRegistry)

            if stored >= threshold then
                -- nil = nothing to do (threshold met), distinct from false = craft failed.
                return nil, "The amount of " .. name .. " (" .. stored .. ") meets or exceeds threshold (" .. threshold .. ")! Aborting request."
            end
        end

        if item.label == name then
            local craft = craftable.request(count)

            while craft.isComputing() == true do
                os.sleep(1)
            end
            if craft.hasFailed() then
                return table.unpack({false, "Failed to request " .. name .. " x " .. count})
            else
                return table.unpack({true, "Requested " .. name .. " x " .. count})
            end
        end
    end
    return table.unpack({false, name .. " is not craftable!"})
end

-- One batched network query for many item labels at once; returns label -> total.
-- getItemsInNetworkById filters server-side by item id BEFORE converting stacks,
-- which is far cheaper than a label-filtered getItemsInNetwork (that call converts
-- every stack in the network on each query). Matching then happens by label,
-- because exact name+damage+NBT lookups miss items whose stored NBT differs from
-- the pattern output (e.g. GT++ chem items like Alumina Milling Balls).
function AE2.getStoredMap(labels)
    local seenIds = {}
    local idList = {}
    local wanted = {}
    for _, label in ipairs(labels) do
        wanted[label] = true
        local craftable = getCraftableForItem(label)
        if craftable then
            local stack = craftable.getStack()
            if stack.name and not seenIds[stack.name] then
                seenIds[stack.name] = true
                table.insert(idList, stack.name)
            end
        end
    end

    local map = {}
    if #idList > 0 then
        for _, stack in ipairs(ME.getItemsInNetworkById(idList)) do
            if wanted[stack.label] then
                map[stack.label] = (map[stack.label] or 0) + stack.size
            end
        end
    end
    return map
end

-- Returns the amount of an item/fluid in the network.
function AE2.getStored(name, fluidRegistry)
    if fluidRegistry then
        local fluid = ME.getFluidInNetwork(fluidRegistry)
        return fluid and fluid.size or 0
    end
    return AE2.getStoredMap({name})[name] or 0
end

-- Returns a list of {name, busy, crafting} for every crafting CPU.
function AE2.getCpuStatus()
    local cpus = ME.getCpus()
    local list = {}
    for _, v in pairs(cpus) do
        local finalOutput = v.cpu.finalOutput()
        table.insert(list, {
            name = v.name,
            busy = v.busy,
            crafting = finalOutput and finalOutput.label or nil,
        })
    end
    return list
end

function AE2.checkIfCrafting()
    local cpus = ME.getCpus()
    local items = {}
    for k, v in pairs(cpus) do
        local finaloutput = v.cpu.finalOutput()
        if finaloutput ~= nil then
            items[finaloutput.label] = true
        end
    end

    return items
end

-- Function to manually clear the cache if needed
function AE2.clearCache()
    itemCache = {}
    cacheTimestamp = 0
end

-- Returns true if none of the items from entries are crafting according to itemsCrafting.
function AE2.batchReady(entries, itemsCrafting)
    local batchReady = true
    for itemName, config in pairs(entries) do
        local craftable = getCraftableForItem(itemName)
        if itemsCrafting[itemName] then
            batchReady = false
        end
    end
    return batchReady
end

return AE2
