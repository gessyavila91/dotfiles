local icons = require("icons")
local colors = require("colors")
local settings = require("settings")

-- These providers take exactly two arguments: "<event-name>" "<event-freq>".
-- Passing anything else (a --quiet flag, say) makes them print usage and exit,
-- which leaves every label blank.
sbar.exec("killall cpu_load 2>/dev/null; $CONFIG_DIR/helpers/event_providers/cpu_load/bin/cpu_load cpu_update 2.0")
sbar.exec("killall memory_load 2>/dev/null; $CONFIG_DIR/helpers/event_providers/memory_load/bin/memory_load memory_update 2.0")
sbar.exec("killall hdd_load 2>/dev/null; $CONFIG_DIR/helpers/event_providers/hdd_load/bin/hdd_load hdd_update 2.0")

-- Update the padding for each metric widget
-- `overrides` is merged one level deep, so callers can tweak just icon.font
-- or add update_freq without restating the whole table.
local function create_metric_item(name, icon, overrides)
    local opts = {
        position = "right",
        background = {
            height = 22,
            color = { alpha = 0 },
            border_width = 0,
            drawing = true,
        },
        icon = {
            string = icon,
            color = colors.yellow,
            padding_right = 0,  -- Reduced padding
        },
        label = {
            font = {
                family = settings.font.numbers,
                style = settings.font.style_map["Regular"],  -- Lighter weight
            },
            align = "right",
            padding_right = 0,
        },
        padding_right = settings.paddings
    }

    for key, value in pairs(overrides or {}) do
        if type(value) == "table" and type(opts[key]) == "table" then
            for sub_key, sub_value in pairs(value) do
                opts[key][sub_key] = sub_value
            end
        else
            opts[key] = value
        end
    end

    return sbar.add("item", name, 42, opts)
end

local hdd = create_metric_item("widgets.hdd", icons.hdd)
local memory = create_metric_item("widgets.memory", icons.memory)
-- SF Symbols ships no GPU glyph, so icons.gpu is the text "GPU". Shrink it so
-- it sits at the same visual weight as the chip glyphs next to it.
local gpu = create_metric_item("widgets.gpu", icons.gpu, {
    update_freq = 2,
    icon = {
        font = {
            family = settings.font.numbers,
            style = settings.font.style_map["Bold"],
            size = 10.0,
        },
        -- A text icon needs the gap the glyphs don't: without it the label
        -- runs straight into the word, reading as "GPU43%".
        padding_right = 4,
    },
})
local cpu = create_metric_item("widgets.cpu", icons.cpu)

-- SbarLua's subscribe takes (event, callback). A { event = ..., action = ... }
-- table is read as an array of event names, finds none, and registers nothing.
cpu:subscribe("cpu_update", function(env)
  cpu:set({ label = env.total_load .. "%" })
end)

-- memory_load and percent_used already carry the % sign.
memory:subscribe("memory_update", function(env)
  memory:set({ label = env.memory_load })
end)

hdd:subscribe("hdd_update", function(env)
  hdd:set({ label = env.percent_used })
end)

-- No event provider for the GPU: read Device Utilization straight off the
-- IOAccelerator registry entry. Works without sudo on Apple Silicon, unlike
-- powermetrics.
local GPU_CMD = "ioreg -r -d 1 -w 0 -c IOAccelerator"
  .. " | grep -o '\"Device Utilization %\"=[0-9]*'"
  .. " | head -1 | cut -d= -f2"

gpu:subscribe({ "routine", "forced", "system_woke" }, function()
  sbar.exec(GPU_CMD, function(output)
    local percent = tonumber((output or ""):match("%d+"))
    gpu:set({ label = percent and (percent .. "%") or "-" })
  end)
end)

for _, item in ipairs({ cpu, gpu, memory, hdd }) do
  item:subscribe("mouse.clicked", function(env)
    if env.button == "left" then  -- Only trigger on left click
      sbar.exec("open -a 'Activity Monitor'")
    end
  end)
end

-- Background around the cpu item
sbar.add("bracket", "widgets.metrics.bracket", { cpu.name, gpu.name, memory.name, hdd.name }, {
  background = { color = colors.bg1 },
  padding_left = 0,
  padding_right = 0
})

-- Background around the cpu item
sbar.add("item", "widgets.metrics.padding", {
  position = "right",
  width = 2
})
