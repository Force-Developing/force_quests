Config = {}

-- Prints extra info to the F8 / server console. Setup errors are always printed.
Config.Debug = false

-- "en", "sv" or "auto" (follows the replicated ox:locale convar: setr ox:locale "sv")
Config.Locale = "en"

-- "auto" (detected by the server: qbx_core, es_extended, qb-core), "esx", "qb", "qbx" or "custom"
Config.Framework = "auto"

-- "auto" (ox_target, then qb-target, else [E] + text UI), "ox_target", "qb-target" or "none" ([E] + text UI).
-- Used for the quest giver, the boxes and the cleaning spots. Vehicle stops and loading the van always use [E].
Config.Target = "auto"

-- The man who hands out the quests
Config.Ped = {
    name = "Philip",
    model = "a_m_y_cyclist_01",
    coords = vec4(-905.61, -2338.17, 5.71, 330.0),
    anim = { dict = "mini@strip_club@idles@bouncer@base", clip = "base" }, -- false for none
    blip = { sprite = 351, colour = 49, scale = 1.2 },                     -- false to hide; label = "..." to rename
}

-- How close (meters) the player has to stand to Philip, a box or a cleaning spot. The server allows a small margin.
Config.InteractDistance = 2.0

-- Only one player at a time per quest (its vehicles spawn on the same spots)
Config.OneAtATime = true

-- Minutes a quest may take. After that it is cancelled and its vehicles are removed.
Config.MaxDuration = 45

-- Give the player keys for the quest vehicles (qbx_vehiclekeys, qb-vehiclekeys; see server/custom/frameworks)
Config.GiveKeys = true

-- Draw what to do next at the bottom of the screen during a quest
Config.ShowHints = true

--[[
  The quests. The key is the quest id; Philip's menu lists them by key.
  label / description = menu texts (default: the locale keys quest_<id> and quest_<id>_desc)
  reward   = { min, max } money paid at the end (a random amount in between)
  account  = "cash" or "bank"
  cooldown = seconds before the same character can take this quest again after being paid
  area     = { coords, radius } optional circle on the map
  vehicles = quest vehicles, spawned by the server. { model, coords = vec4, type, label, sprite, spawnDistance,
             frozen, locked, keys }
             type: "automobile", "bike", "trailer", ... Without spawnDistance the vehicle spawns when the quest starts;
             with it, when the player gets that close. frozen / locked: the vehicle can't move / be entered.
             keys = false: no keys for it (trailers and locked vehicles never get keys).
  stops    = what has to be done, in order of `group` (stops with the same group can be done in any order):
             type = "deliver" bring `trailer` to coords (radius) hooked to `vehicle` and press E (the trailer stays)
                    "return"  bring `vehicle` back to coords and leave it (the vehicle is removed)
                    "carry"   pick up the box at coords (`duration` seconds) and put it in `vehicle`
                    "scrap"   ram `target` with `vehicle` until its body health is below `bodyHealth`
                    "task"    work at coords for `duration` seconds (`scenario`, facing `heading`); `action` picks
                              the texts: "clean", "brush" or "blow"
]]
Config.Quests = {
    cargo = {
        reward = { min = 2000, max = 5000 },
        account = "cash",
        cooldown = 300,
        vehicles = {
            truck = { model = "packer", label = "the truck", sprite = 477, coords = vec4(-918.65, -2326.62, 6.71, 330.0) },
            trailer = { model = "trailers", type = "trailer", label = "the trailer", sprite = 479, coords = vec4(-934.63, -2315.38, 6.71, 330.0) },
        },
        stops = {
            { type = "deliver", group = 1, vehicle = "truck", trailer = "trailer", radius = 7.5, coords = vec3(-338.15, 6143.37, 31.49) },
            { type = "return", group = 2, vehicle = "truck", radius = 5.0, coords = vec3(-918.65, -2326.62, 6.71) },
        },
    },
    boxes = {
        reward = { min = 2000, max = 5000 },
        account = "cash",
        cooldown = 300,
        vehicles = {
            van = { model = "mesa", label = "the van", sprite = 669, coords = vec4(-914.53, -2332.38, 6.71, 60.0) },
        },
        stops = {
            { type = "carry", group = 1, vehicle = "van", duration = 5, prop = "prop_cs_cardbox_01", coords = vec3(-181.00, 581.34, 196.64) },
            { type = "carry", group = 1, vehicle = "van", duration = 5, prop = "prop_cs_rub_box_01", coords = vec3(-179.05, 581.11, 196.64) },
            { type = "carry", group = 1, vehicle = "van", duration = 5, prop = "prop_cardbordbox_03a", coords = vec3(-176.96, 581.34, 196.64) },
            { type = "carry", group = 1, vehicle = "van", duration = 5, prop = "prop_cardbordbox_04a", coords = vec3(-179.67, 582.80, 196.64) },
        },
    },
    trash = {
        reward = { min = 2000, max = 5000 },
        account = "cash",
        cooldown = 300,
        vehicles = {
            car = { model = "rhapsody", label = "your car", sprite = 227, coords = vec4(-914.53, -2332.38, 6.71, 60.0) },
            bulldozer = { model = "bulldozer", label = "the bulldozer", sprite = 227, spawnDistance = 150.0, coords = vec4(-426.65, -1689.76, 19.03, 160.0) },
            wreck = { model = "rebel", label = "the wreck", spawnDistance = 150.0, frozen = true, locked = true, coords = vec4(-507.81, -1707.70, 19.31, 210.0) },
        },
        stops = {
            { type = "scrap", group = 1, vehicle = "bulldozer", target = "wreck", radius = 15.0, bodyHealth = 360, coords = vec3(-507.81, -1707.70, 19.31) },
        },
    },
    clean = {
        reward = { min = 2000, max = 5000 },
        account = "cash",
        cooldown = 300,
        area = { coords = vec3(-901.13, -2318.08, -3.50), radius = 30.0 },
        stops = {
            { type = "task", group = 1, action = "brush", duration = 15, scenario = "WORLD_HUMAN_JANITOR", heading = 19.0, coords = vec3(-907.12, -2336.07, -3.51) },
            { type = "task", group = 1, action = "brush", duration = 15, scenario = "WORLD_HUMAN_JANITOR", heading = 300.0, coords = vec3(-900.14, -2326.23, -3.51) },
            { type = "task", group = 1, action = "brush", duration = 15, scenario = "WORLD_HUMAN_JANITOR", heading = 115.0, coords = vec3(-904.75, -2317.50, -3.51) },
            { type = "task", group = 1, action = "blow", duration = 15, scenario = "WORLD_HUMAN_GARDENER_LEAF_BLOWER", heading = 240.0, coords = vec3(-897.47, -2315.88, -3.51) },
            { type = "task", group = 1, action = "blow", duration = 15, scenario = "WORLD_HUMAN_GARDENER_LEAF_BLOWER", heading = 320.0, coords = vec3(-887.31, -2309.04, -3.51) },
            { type = "task", group = 1, action = "blow", duration = 15, scenario = "WORLD_HUMAN_GARDENER_LEAF_BLOWER", heading = 210.0, coords = vec3(-871.40, -2318.63, -3.51) },
            { type = "task", group = 1, action = "clean", duration = 15, scenario = "WORLD_HUMAN_MAID_CLEAN", heading = 340.0, coords = vec3(-883.06, -2317.31, -3.51) },
            { type = "task", group = 1, action = "clean", duration = 15, scenario = "WORLD_HUMAN_MAID_CLEAN", heading = 160.0, coords = vec3(-881.36, -2313.84, -3.51) },
            { type = "task", group = 1, action = "clean", duration = 15, scenario = "WORLD_HUMAN_MAID_CLEAN", heading = 155.0, coords = vec3(-916.85, -2341.95, -3.51) },
        },
    },
}
