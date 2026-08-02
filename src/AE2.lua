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

function AE2.requestItem(name, threshold, count, fluidRegistry)
    local craftable = getCraftableForItem(name)

    if craftable then
        local item = craftable.getStack()
        if threshold ~= nil then
            local itemInSystem = nil

            if fluidRegistry then
                itemInSystem = ME.getFluidInNetwork(fluidRegistry)
            else
                if item.name then
                    if item.tag then
                        itemInSystem = ME.getItemInNetwork(item.name, item.damage or 0, item.tag)
                    end

                    -- Fallback: try with just the internal name and damage
                    if itemInSystem == nil then
                        itemInSystem = ME.getItemInNetwork(item.name, item.damage or 0)
                    end
                end
            end

            if itemInSystem ~= nil and itemInSystem.size >= threshold then
                -- nil = nothing to do (threshold met), distinct from false = craft failed.
                return nil, "The amount of " .. (itemInSystem.label or name) .. " (" .. itemInSystem.size .. ") meets or exceeds threshold (" .. threshold .. ")! Aborting request."
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

-- Returns the amount of an item/fluid in the network, or nil if it can't be resolved.
function AE2.getStored(name, fluidRegistry)
    if fluidRegistry then
        local fluid = ME.getFluidInNetwork(fluidRegistry)
        return fluid and fluid.size or 0
    end

    local craftable = getCraftableForItem(name)
    if craftable then
        local item = craftable.getStack()
        if item.name then
            local found = nil
            if item.tag then
                found = ME.getItemInNetwork(item.name, item.damage or 0, item.tag)
            end
            if found == nil then
                found = ME.getItemInNetwork(item.name, item.damage or 0)
            end
            return found and found.size or 0
        end
    end
    return nil
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
