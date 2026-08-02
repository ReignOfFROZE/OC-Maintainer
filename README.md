# OC Maintainer

An AE2 level maintainer for GT: New Horizons that prevents recipe starvation.
Based on [Smart-Maintainer](https://github.com/rajsugavanam/Smart-Maintainer) by rajsugavanam,
with colored status output and a live dashboard mode added.

Keeps items and fluids stocked up to a threshold (or indefinitely). Scheduling
order can be randomized so that, on average, no single recipe repeatedly grabs
high-priority crafting CPUs and starves the others.

## Requirements

In addition to a working OpenComputers computer:

- A full-block ME Interface connected to an OpenComputers Adapter;
- Crafting Monitors on **all** crafting CPUs attached to the interface's network;
- An Internet Card (for installation);
- A tier 2/3 GPU and screen if you want colored output and the dashboard
  (everything still runs on tier 1, just without color).

## Installation

Download and run the installer on the computer:

```bash
wget https://raw.githubusercontent.com/ReignOfFROZE/OC-Maintainer/master/installer.lua && installer
```

## Usage

Classic scrolling-log maintainer (supports priority mode, randomization, and
batch mode; prints green on successful craft requests and red on failures):

```bash
Maintainer
```

Dashboard maintainer — draws a static table of every configured item and
updates stored amounts and statuses in place:

```bash
Maintainer2
```

Dashboard statuses:

| Status      | Color  | Meaning                                        |
| ----------- | ------ | ---------------------------------------------- |
| OK          | green  | Stored amount meets or exceeds the threshold   |
| Requested   | yellow | A craft was scheduled this pass                |
| Crafting    | cyan   | A crafting CPU is currently working on it      |
| Failed      | red    | The craft request was rejected                 |
| Uncraftable | orange | No pattern for this item was found             |

Dashboard features:

- Fill bars, percentages, and trend arrows (`↑`/`↓`) show how close each item
  is to its threshold and which way it moved since the last pass.
- A summary line counts items per status at a glance.
- A crafting CPU panel shows what every CPU is working on.
- A rolling log keeps the last few failures on screen with timestamps.
- A background watcher polls the crafting CPUs between passes, so Requested
  items flip to Crafting and finished crafts flip to OK without waiting for
  the next full pass.

Controls: `Q` quits, `P` pauses, `R` clears the craftable cache and forces a
refresh. Tap an item row to force-request one batch immediately (ignores the
threshold); tap its Status cell to see the item's full last message.

> [!NOTE]
> `Maintainer2` is a proof of concept: it iterates groups in config order and
> does not implement the priority/randomization/batch logic from `Maintainer`.

## Config

Maintained items are set in `config.lua`, organized into **recipe groups**:

```lua
cfg["items"] = {
    { -- Group 0
        priority = 2,
        batchMode = false,
        entries = {
            ["drop of Molten Polybenzimidazole"] = {512000, 16000, "molten.polybenzimidazole"},
        }
    },
    { -- Group 1
        priority = 3,
        batchMode = true,
        entries = {
            ["Aluminium Ingot"] = {nil, 16},
            ["Stainless Steel Ingot"] = {512, 8},
        }
    }
}
```

**Items**: `["item_name"] = {threshold, batch_size}`

**Fluids**: `["fluid_name"] = {threshold, batch_size, registry_name}`

> [!TIP]
> Find a fluid's registry name by hovering over it in NEI.

> [!NOTE]
> Set `threshold` to `nil` to stock an item indefinitely with no upper limit.

Global options:

- `cfg["sleep"]` — seconds between passes. Higher values reduce lag but
  decrease throughput.
- `cfg["priorityMode"]` — when `true`, groups with higher `priority` are
  attempted first each cycle (unspecified priorities default to 0). When
  `false`, group order is randomized instead.
- `cfg["randomizeFrequency"]` — every *k* cycles, the order items are
  attempted within a group is shuffled (`0` disables shuffling).
- `batchMode` (per group) — when `true`, items in the group only craft if
  none of the group's items are currently crafting. Decreases throughput but
  greatly increases fairness for slow recipes; most useful together with
  in-group randomization.

> [!NOTE]
> Reboot the computer and rerun the maintainer after changing config values.

> [!CAUTION]
> Smart blocking can alter the effectiveness of this program.

## Example

Suppose you passively smelt Stainless Steel, Aluminium, and Black Steel in a
single very slow EBF. Without intervention, Stainless Steel gets rescheduled
as soon as its recipe finishes and hogs the EBF, while Black Steel almost
never gets machine time.

This group resolves the problem:

```lua
    {
        priority = 0,
        batchMode = true,
        entries = {
            ["Aluminium Ingot"] = {nil, 16},
            ["Stainless Steel Ingot"] = {nil, 8},
            ["Black Steel Ingot"] = {nil, 8},
        }
    }
```

together with:

```lua
cfg["randomizeFrequency"] = 2
cfg["priorityMode"] = true
```

With batch mode and shuffling, every ingot gets its chance to smelt.
