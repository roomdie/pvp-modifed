function load_config(dummy_load)
  local config = global
  if dummy_load then
    config = {}
  end

  config.setup_finished = false
  config.disabled_items = config.disabled_items or
  {
    ["land-mine"] = true,
    ["atomic-bomb"] = true,
    ["rocket-silo"] = true,
    ["artillery-wagon"] = true,
    ["artillery-turret"] = true,
    ["player-port"] = true,
    ["electric-energy-interface"] = true
  }
  config.map_config =
  {
    average_team_displacement = 1024,
    map_height = 0,
    map_width = 0,
    map_seed = 0,
    starting_area_size =
    {
      options = {"none", "very-low", "low", "normal", "high", "very-high"},
      selected = "normal"
    },
    always_day = false,
    biters_disabled = false,
    peaceful_mode = false,
    evolution_factor = 0,
    duplicate_starting_area_entities = true,
    cheat_mode = false,
    technology_price_multiplier = 1
  }

  config.game_config =
  {
    game_mode =
    {
      options = {"conquest", "space_race", "last_silo_standing", "freeplay", "production_score", "oil_harvest", "genocide_of_biters"},
      selected = "conquest"
    },
    disband_on_loss = false,
    time_limit = 0,
    required_production_score = 50000000,
    required_oil_barrels = 1000,
    required_satellites_sent = 1,
    oil_only_in_center = false,
    allow_spectators = false,
    spectator_fog_of_war = true,
    no_rush_time = 0,
    base_exclusion_time = 60,
    reveal_team_positions = true,
    prohibition_spawn_biters_in_starting_zone = false,
    reveal_map_center = false,
    team_walls = true,
    team_turrets = true,
    turret_ammunition =
    {
      options = {"firearm-magazine"},
      selected = ""
    },
    team_artillery = false,
    give_artillery_remote = false,
    team_artillery_minable = false,
    disable_check_color_team = true,
    auto_new_round_time = 0,
    protect_empty_teams = true,
    enemy_building_restriction = true,
    neutral_chests = false
  }

  local items = game.item_prototypes

  local entity_name = "gun-turret"
  local prototype = game.entity_prototypes[entity_name]
  if not prototype then
    config.game_config.team_turrets = nil
    config.game_config.turret_ammunition = nil
  else
    local category = prototype.attack_parameters.ammo_category
    if category then
      local ammos = {}
      for name, item in pairs (items) do
        if item.type == "ammo" then
          local ammo = item.get_ammo_type()
          if ammo and ammo.category == category then
            table.insert(ammos, name)
          end
        end
      end
      config.game_config.turret_ammunition.options = ammos
      if not items["firearm-magazine"] then
        config.game_config.turret_ammunition.selected = ammos[1] or ""
      end
    end
  end

  config.team_config =
  {
    max_players = 0,
    friendly_fire = false,
    locked_teams = false,
    ----diplomacy_enabled = false, -- hmmm
    share_chart = true,
    who_decides_diplomacy =
    {
      options = {"all_players", "team_leader"},
      selected = "all_players"
    },
    team_joining =
    {
      options = {"player_pick", "random", "auto_assign"},
      selected = "player_pick"
    },
    spawn_position =
    {
      options = {"random", "fixed", "team_together"},
      selected = "team_together"
    },
    research_level =
    {
      options = {"none"},
      selected = "none"
    },
    unlock_combat_research = false,
    defcon_mode = false,
    defcon_timer = 5,
    starting_equipment =
    {
      options = {"none", "small", "medium", "large"},
      selected = "large"
    },
    starting_inventory =
    {
      options = {"none", "small", "medium", "large"},
      selected = "large"
    },
    starting_chest =
    {
      options = {"none", "small", "medium", "large"},
      selected = "none"
    },
    starting_chest_multiplier = 5
  }

  local packs = {}
  local sorted_packs = {}
  local techs = game.technology_prototypes
  for k, tech in pairs (techs) do
    for k, ingredient in pairs (tech.research_unit_ingredients) do
      if not packs[ingredient.name] then
        packs[ingredient.name] = true
        local order = tostring(items[ingredient.name].order) or "Z-Z"
        local added = false
        for k, t in pairs (sorted_packs) do
          if order < t.order then
            table.insert(sorted_packs, k, {name = ingredient.name, order = order})
            added = true
            break
          end
        end
        if not added then
          table.insert(sorted_packs, {name = ingredient.name, order = order})
        end
      end
    end
  end

  for k, t in pairs (sorted_packs) do
    table.insert(config.team_config.research_level.options, t.name)
  end

  config.research_ingredient_list = {}
  for _, research in pairs (config.team_config.research_level.options) do
    config.research_ingredient_list[research] = false
  end

  config.colors =
  {
    { name = "orange" , color = { r = 0.869, g = 0.5  , b = 0.130, a = 0.5 }},
    { name = "purple" , color = { r = 0.485, g = 0.111, b = 0.659, a = 0.5 }},
    { name = "red"    , color = { r = 0.815, g = 0.024, b = 0.0  , a = 0.5 }},
    { name = "green"  , color = { r = 0.093, g = 0.768, b = 0.172, a = 0.5 }},
    { name = "blue"   , color = { r = 0.155, g = 0.540, b = 0.898, a = 0.5 }},
    { name = "yellow" , color = { r = 0.835, g = 0.666, b = 0.077, a = 0.5 }},
    { name = "pink"   , color = { r = 0.929, g = 0.386, b = 0.514, a = 0.5 }},
    { name = "white"  , color = { r = 0.8  , g = 0.8  , b = 0.8  , a = 0.5 }},
    { name = "black"  , color = { r = 0.1  , g = 0.1  , b = 0.1,   a = 0.5 }},
    { name = "gray"   , color = { r = 0.4  , g = 0.4  , b = 0.4,   a = 0.5 }},
    { name = "brown"  , color = { r = 0.300, g = 0.117, b = 0.0,   a = 0.5 }},
    { name = "cyan"   , color = { r = 0.275, g = 0.755, b = 0.712, a = 0.5 }},
    { name = "acid"   , color = { r = 0.559, g = 0.761, b = 0.157, a = 0.5 }},
  }

  config.color_map = {}
  for k, color in pairs (config.colors) do
    config.color_map[color.name] = k
  end

  config.teams =
  {
    {
      name = game.backer_names[math.random(#game.backer_names)],
      color = config.colors[math.random(#config.colors)].name,
      team = "-"
    },
    {
      name = game.backer_names[math.random(#game.backer_names)],
      color = config.colors[math.random(#config.colors)].name,
      team = "-"
    }
  }

  config.inventory_list =
  {
    none =
    {
      ["iron-plate"] = 8,
      ["burner-mining-drill"] = 1,
      ["stone-furnace"] = 1
    },
    small =
    {
      ["iron-plate"] = 200,
      ["pipe"] = 100,
      ["pipe-to-ground"] = 20,
      ["copper-plate"] = 200,
      ["iron-gear-wheel"] = 200,
      ["electronic-circuit"] = 200,
      ["transport-belt"] = 400,
      ["repair-pack"] = 20,
      ["inserter"] = 100,
      ["small-electric-pole"] = 50,
      ["burner-mining-drill"] = 50,
      ["stone-furnace"] = 50,
      ["burner-inserter"] = 100,
      ["assembling-machine-1"] = 20,
      ["electric-mining-drill"] = 20,
      ["boiler"] = 5,
      ["steam-engine"] = 10,
      ["offshore-pump"] = 2,
      ["wood"] = 50,
      ["poison-capsule"] = 3,
      ["landfill"] = 20
    },
    medium =
    {
      ["iron-plate"] = 200,
      ["pipe"] = 100,
      ["pipe-to-ground"] = 20,
      ["iron-gear-wheel"] = 100,
      ["copper-plate"] = 100,
      ["steel-plate"] = 100,
      ["electronic-circuit"] = 400,
      ["transport-belt"] = 400,
      ["underground-belt"] = 20,
      ["splitter"] = 20,
      ["repair-pack"] = 20,
      ["inserter"] = 150,
      ["small-electric-pole"] = 100,
      ["medium-electric-pole"] = 50,
      ["fast-inserter"] = 50,
      ["long-handed-inserter"] = 50,
      ["burner-inserter"] = 100,
      ["burner-mining-drill"] = 50,
      ["electric-mining-drill"] = 40,
      ["stone-furnace"] = 100,
      ["steel-furnace"] = 30,
      ["assembling-machine-1"] = 40,
      ["assembling-machine-2"] = 20,
      ["boiler"] = 10,
      ["steam-engine"] = 20,
      ["chemical-plant"] = 20,
      ["oil-refinery"] = 5,
      ["pumpjack"] = 8,
      ["offshore-pump"] = 2,
      ["wood"] = 50,
      ["poison-capsule"] = 8,
      ["landfill"] = 20
    },
    large =
    {
      ["iron-plate"] = 200,
      ["pipe"] = 100,
      ["pipe-to-ground"] = 20,
      ["copper-plate"] = 200,
      ["steel-plate"] = 200,
      ["electronic-circuit"] = 400,
      ["iron-gear-wheel"] = 250,
      ["transport-belt"] = 400,
      ["underground-belt"] = 40,
      ["splitter"] = 40,
      ["repair-pack"] = 20,
      ["inserter"] = 200,
      ["burner-inserter"] = 50,
      ["small-electric-pole"] = 50,
      ["burner-mining-drill"] = 50,
      ["electric-mining-drill"] = 50,
      ["stone-furnace"] = 100,
      ["steel-furnace"] = 50,
      ["electric-furnace"] = 20,
      ["assembling-machine-1"] = 50,
      ["assembling-machine-2"] = 40,
      ["assembling-machine-3"] = 20,
      ["fast-inserter"] = 100,
      ["long-handed-inserter"] = 100,
      ["medium-electric-pole"] = 50,
      ["substation"] = 10,
      ["big-electric-pole"] = 10,
      ["boiler"] = 10,
      ["steam-engine"] = 20,
      ["chemical-plant"] = 20,
      ["oil-refinery"] = 5,
      ["pumpjack"] = 10,
      ["offshore-pump"] = 2,
      ["wood"] = 50,
      ["poison-capsule"] = 15,
      ["landfill"] = 20
    }
  }
  if dummy_load then
    return config
  end
end

function give_equipment(player)
  local setting = global.team_config.starting_equipment.selected

  if setting == "none" then
    player.insert{name = "pistol", count = 1}
    player.insert{name = "firearm-magazine", count = 10}
    return
  end

  if setting == "small" then
    player.insert{name = "submachine-gun", count = 1}
    player.insert{name = "firearm-magazine", count = 30}
    player.insert{name = "shotgun", count = 1}
    player.insert{name = "shotgun-shell", count = 20}
    player.insert{name = "heavy-armor", count = 1}
    return
  end

  if setting == "medium" then
    player.insert{name = "submachine-gun", count = 1}
    player.insert{name = "firearm-magazine", count = 40}
    player.insert{name = "shotgun", count = 1}
    player.insert{name = "shotgun-shell", count = 20}
    player.insert{name = "car", count = 1}
    player.insert{name = "modular-armor", count = 1}
    return
  end

  if setting == "large" then
    player.insert{name = "submachine-gun", count = 1}
    player.insert{name = "piercing-rounds-magazine", count = 40}
    player.insert{name = "combat-shotgun", count = 1}
    player.insert{name = "piercing-shotgun-shell", count = 20}
    player.insert{name = "rocket-launcher", count = 1}
    player.insert{name = "rocket", count = 80}
    player.insert{name = "power-armor", count = 1}
    local armor = player.get_inventory(defines.inventory.character_armor)[1].grid
    armor.put({name = "fusion-reactor-equipment"})
    armor.put({name = "exoskeleton-equipment"})
    armor.put({name = "energy-shield-equipment"})
    armor.put({name = "energy-shield-equipment"})
    armor.put({name = "personal-roboport-mk2-equipment"})
    player.insert{name = "construction-robot", count = 25}
    --player.insert{name = "blueprint", count = 3}
    --player.insert{name = "deconstruction-planner", count = 1}
    player.insert{name = "car", count = 1}
    return
  end

end

function parse_config_from_gui(gui, config)
  local config_table = gui.config_table
  if not config_table then
    error("Trying to parse config from gui with no config table present")
  end
  for name, value in pairs (config) do
    if config_table[name.."_box"] then
      local text = config_table[name.."_box"].text
      local n = tonumber(text)
      if text == "" then n = 0 end
      if n ~= nil then
        if n > 4294967295 then
          game.get_player(config_table.player_index).print({"value-too-big", {name}})
          return
        end
        if n < 0 then
          game.get_player(config_table.player_index).print({"value-below-zero", {name}})
          return
        end
        config[name] = n
      else
        game.get_player(config_table.player_index).print({"must-be-number", {name}})
        return
      end
    end
    if type(value) == "boolean" then
      if config_table[name] then
        config[name] = config_table[name.."_boolean"].state
      end
    end
    if type(value) == "table" then
      local menu = config_table[name.."_dropdown"]
      if not menu then game.print("Error trying to read drop down menu of gui element "..name)return end
      config[name].selected = config[name].options[menu.selected_index]
    end
  end
  return true
end

local localised_names =
{
  peaceful_mode = {"gui-map-generator.peaceful-mode-checkbox"},
  map_height = {"gui-map-generator.map-width-simple"},
  map_width = {"gui-map-generator.map-height-simple"},
  map_seed = {"gui-map-generator.map-seed-simple"},
  starting_area_size = {"gui-map-generator.starting-area-size"},
  technology_price_multiplier = {"gui-map-generator.price-multiplier"}
}

-- "" for no tooltip
local localised_tooltips =
{
  game_mode =
  {
    "", {"game_mode_tooltip"},
    "\n", {"conquest_description"},
    "\n", {"space_race_description"},
    "\n", {"last_silo_standing_description"},
    "\n", {"freeplay_description"},
    "\n", {"production_score_description"},
    "\n", {"oil_harvest_description"}
  },
  friendly_fire = "",
  map_width = "",
  map_height = "",
  always_day = "",
  peaceful_mode = "",
  evolution_factor = "",
  starting_area_size = "",
  duplicate_starting_area_entities = "",
  technology_price_multiplier = ""
}

function make_config_table(gui, config)
  local config_table = gui.config_table
  if config_table then
    config_table.clear()
  else
    config_table = gui.add{type = "table", name = "config_table", column_count = 2}
    config_table.style.column_alignments[2] = "right"
  end
  local items = game.item_prototypes
  for k, data in pairs(config) do
    local label = config_table.add{type = "label", name = k}
    if tonumber(data) then
      local input = config_table.add{type = "textfield", name = k.."_box"}
      input.text = tostring(data)
      input.style.maximal_width = 100
    elseif tostring(type(data)) == "boolean" then
      config_table.add{type = "checkbox", name = k.."_boolean", state = data}
    else
      local menu = config_table.add{type = "drop-down", name = k.."_dropdown"}
      local index
      if data.options then
        for j, option in pairs (data.options) do
          if items[option] then
            menu.add_item(items[option].localised_name)
          else
            menu.add_item(localised_names[option] or {option})
          end
          if option == data.selected then index = j end
        end
        menu.selected_index = index or 1
      else
        log("bug >" .. data .. "< with make_config_table") --WIP
        for _, player in pairs (game.connected_players) do
          if player.admin then
            game.print("bug >" .. data .. "< with make_config_table") --WIP
          end
        end
      end
    end
    label.caption = {"", localised_names[k] or {k}, {"colon"}}
    label.tooltip = localised_tooltips[k] or {k.."_tooltip"}
  end
end
