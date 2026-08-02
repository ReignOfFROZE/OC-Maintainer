local cfg = {}

cfg["items"] = {
    { -- Group 0
        priority = 0,
        batchMode = false,
        entries = {
            ["Molten Atomic Separation Catalyst"] = {18432, 36864, "molten.atomic separation catalyst"},
            ["Kerosene"] = {256000, 128000, "fluid.kerosene"},
            ["Blazing Pyrotheum"] = {64000, 64000, "pyrotheum"},
            ["Gelid Cryotheum"] = {256000, 128000, "cryotheum"},
            ["Nitric Acid"] = {64000, 64000, "nitricacid"},
            ["Orbis Terrae"] = {16, 8},
            ["Activated Carbon Filter Mesh"] = {8, 4},
            ["Alumina Milling Ball"] = {64, 64},
            ["Molten Hellish Metal"] = {1296, 1296, "molten.hellishmetal"},
            ["Drone (Level 2)"] = {4, 4},
            ["Prismarine Shard"] = {1024, 4096},
            ["Sodium Hydroxide Dust"] = {1024, 1024},
            ["Molten Crystalline Alloy"] = {9216, 9216, "molten.crystallinealloy"},
            ["Quicklime Dust"] = {16384, 16384},
            ["Fluxed Electrum Dust"] = {128, 1024},
            ["Super Coolant"] = {32000, 32000, "supercoolant"},
            ["Nether Star Dust"] = {256, 512},
            ["Molten Titanium"] = {64000, 64000, "molten.titanium"},
            ["Molten Gallium"] = {128000, 64000, "molten.gallium"},
            ["Raw Neutronium Dust"] = {128, 256},
            ["Agar"] = {1024, 2048},
            ["Cerium-doped Lutetium Aluminium Oxygen Blend Dust"] = {2048, 4096},
            ["Graphene Electrode"] = {64, 32},
            ["Unknown Nutrient Agar"] = {1024000, 2048000, "unknownnutrientagar"},
            ["Tungsten Rod"] = {256, 128},
            ["Enriched Naquadah Rod"] = {256, 128},
            ["Long Beryllium Rod"] = {256, 128},
            ["Long Lanthanum Hexaboride Rod"] = {256, 128},
            ["Energium Dust"] = {8192, 16384},
            ["Stemcells"] = {2048, 4096},
            ["Unknown Crystal Shard"] = {1024, 2048},
            ["Plutonium 239 Rod"] = {1024, 2048},
            ["Tiny Pile of Infinity Catalyst Dust"] = {256, 512},
            ["Naquadah Dust"] = {512, 512},
            ["Praecantatio"] = {2048, 1024}
            -- Example item without threshold:
            -- ["My Item"] = {nil, 1024}
        }
    }
}

-- Higher values reduce lag, but decrease throughput.
cfg["sleep"] = 10

-- Randomizes the order recipes are scheduled within their group
-- Higher values reduce lag, but lower values increase fairness.
-- 0 to disable.
-- If priorityMode is false, recipe groups are additionally scheduled in random order.
cfg["randomizeFrequency"] = 2

-- false: disable randomization of the order recipe groups are attemped
-- to be scheduled.
-- true: higher priority recipe groups are scheduled first.
cfg["priorityMode"] = false

return cfg

