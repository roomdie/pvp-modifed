require("pvp/config")
require("pvp/balance")
require("pvp/commands")
local mod_gui = require("mod-gui")
local silo_script = require("silo-script")
local production_score = require("pvp/production-score")
local util = require("util")
require("story")
require("pvp/modes/control")
local pvp = {}

local statistics_period = 150 -- Seconds


local tinsert = table.insert
local floor = math.floor
local ceil = math.ceil
local max = math.max
local min = math.min
local abs = math.abs
local ignore_force_list =
{
  ["player"] = true,
  ["enemy"] = true,
  ["neutral"] = true,
  ["spectator"] = true,
  ["GM"] = true
}


local events = {
  on_round_end = script.generate_event_name(),
  on_round_start = script.generate_event_name(),
  on_team_lost = script.generate_event_name(),
  on_team_won = script.generate_event_name()
}

remote.add_interface("pvp",
{
  get_event_name = function(name)
    return events[name]
  end,
  get_teams = function()
    return global.teams
  end
})


local starting_area_chunk_radius =
{
  ["none"] = 3,
  ["very-low"] = 3,
  ["low"] = 4,
  ["normal"] = 5,
  ["high"] = 6,
  ["very-high"] = 7
}
local function get_starting_area_radius(as_tiles)
  if not global.map_config.starting_area_size then return 0 end

  local radius = starting_area_chunk_radius[global.map_config.starting_area_size.selected]
  return as_tiles and radius * 32 or radius
end

local function create_spawn_positions()
  local config = global.map_config
  local width = config.map_width
  local height = config.map_height
  local displacement = max(config.average_team_displacement, 64)
  local horizontal_offset = (width/displacement) * 10
  local vertical_offset = (height/displacement) * 10
  global.spawn_offset = {x = floor(0.5 + math.random(-horizontal_offset, horizontal_offset) / 32) * 32, y = floor(0.5 + math.random(-vertical_offset, vertical_offset) / 32) * 32}
  local height_scale = height/width
  local radius = get_starting_area_radius()
  local count = #global.teams
  local max_distance = get_starting_area_radius(true) * 2 + displacement
  local min_distance = get_starting_area_radius(true) + (32 * (count - 1))
  local edge_addition = (radius + 2) * 32
  local elevator_set = false
  if height_scale == 1 then
    if max_distance > width then
      displacement = width - edge_addition
    end
  end
  if height_scale < 1 then
    if #global.teams == 2 then
      if max_distance > width then
        displacement = width - edge_addition
      end
      max_distance = 0
    end
    if max_distance > height then
      displacement = height - edge_addition
    end
  end
  if height_scale > 1 then
    if #global.teams == 2 then
      if max_distance > height then
        displacement = height - edge_addition
      end
      elevator_set = true
      max_distance = 0
    end
    if max_distance > width then
      displacement = width - edge_addition
    end
  end
  local distance = 0.5*displacement
  if distance < min_distance then
    game.print({"map-size-below-minimum"})
  end
  local positions = {}
  if count == 1 then
    positions[1] = {x = 0, y = 0}
  else
    for k = 1, count do
      local rotation = (k*2*math.pi)/count
      local X = 32*(floor((math.cos(rotation)*distance+0.5)/32))
      local Y = 32*(floor((math.sin(rotation)*distance+0.5)/32))
      if elevator_set then
        --[[Swap X and Y for elevators]]
        Y = 32*(floor((math.cos(rotation)*distance+0.5)/32))
        X = 32*(floor((math.sin(rotation)*distance+0.5)/32))
      end
      positions[k] = {x = X, y = Y}
    end
  end
  if #positions == 2 and height_scale == 1 then
    --If there are 2 teams in a square map, we adjust positions so they are in the corners of the map
    for _, position in pairs(positions) do
      if position.x == 0 then position.x = position.y end
      if position.y == 0 then position.y = -position.x end
    end
  end
  if #positions == 4 then
    --If there are 4 teams we adjust positions so they are in the corners of the map
    height_scale = min(height_scale, 2)
    height_scale = max(height_scale, 0.5)
    for _, position in pairs(positions) do
      if position.x == 0 then position.x = position.y end
      if position.y == 0 then position.y = -position.x end
      if height_scale > 1 then
        position.y = position.y * height_scale
      else
        position.x = position.x * (1/height_scale)
      end
    end
    if height_scale < 1 then
      --If the map is wider than tall, swap 1 and 3 so two allied teams will be together
      positions[1], positions[3] = positions[3], positions[1]
    end
  end
  for _, position in pairs(positions) do
    position.x = position.x + global.spawn_offset.x
    position.y = position.y + global.spawn_offset.y
  end
  global.spawn_positions = positions
  return positions
end

function create_next_surface()
  local name = "battle_surface_1"
  if game.get_surface(name) ~= nil then
    name = "battle_surface_2"
  end
  global.round_number = global.round_number + 1
  local settings
  if global.copy_surface then
    settings = global.copy_surface.map_gen_settings
  else
    settings = game.get_surface(1).map_gen_settings
    if global.map_config.map_seed == 0 then
      settings.seed = math.random(4000000000)
    end
  end
  settings.starting_area = global.map_config.starting_area_size.selected
  if global.map_config.biters_disabled then
    settings.autoplace_controls["enemy-base"].size = "none"
  end
  settings.height = global.map_config.map_height
  settings.width = global.map_config.map_width
  settings.starting_points = create_spawn_positions()
  global.surface = game.create_surface(name, settings)
  global.surface.daytime = 0
  global.surface.always_day = global.map_config.always_day
end

function create_gui_GM(player)
  local gui = player.gui.left
  if gui.become_GM then
    gui.become_GM.destroy()
  end
  gui.add{type = "button", name = "become_GM", caption = {"become_GM"}}
end

function destroy_player_gui(player)
  local button_flow = mod_gui.get_button_flow(player)
  for _, name in pairs(
    {
      "objective_button", "diplomacy_button", "admin_button",
      "silo_gui_sprite_button", "production_score_button", "oil_harvest_button",
      "space_race_button", "spectator_join_team_button", "list_teams_button",
      "genocide_biters_button", "genocide_of_biters"
    }) do
    if button_flow[name] then
      button_flow[name].destroy()
    end
  end
  local frame_flow = mod_gui.get_frame_flow(player)
  for _, name in pairs(
    {
      "objective_frame", "admin_button", "admin_frame",
      "silo_gui_frame", "production_score_frame", "oil_harvest_frame",
      "space_race_frame", "team_list",
      "genocide_biters_button", "genocide_biters_frame", "genocide_of_biters"
    }) do
    if frame_flow[name] then
      frame_flow[name].destroy()
    end
  end
  local center_gui = player.gui.center
  for _, name in pairs({"diplomacy_frame", "progress_bar"}) do
    if center_gui[name] then
      center_gui[name].destroy()
    end
  end
  local left_gui = player.gui.left
  for _, name in pairs({"become_GM", "frame_customizing_force"}) do
    if left_gui[name] then
      left_gui[name].destroy()
    end
  end
end

function destroy_joining_guis(gui)
  if gui.random_join_frame then
    gui.random_join_frame.destroy()
  end
  if gui.pick_join_frame then
    gui.pick_join_frame.destroy()
  end
  if gui.auto_assign_frame then
    gui.auto_assign_frame.destroy()
  end
  if gui.become_GM then
    gui.become_GM.destroy()
  end
end

function make_color_dropdown(k, gui)
  local team = global.teams[k]
  local menu = gui.add{type = "drop-down", name = k.."_color"}
  local count = 1
  for _, color in pairs(global.colors) do
    menu.add_item({"color."..color.name})
    if color.name == team.color then
      menu.selected_index = count
    end
    count = count + 1
  end
end

function add_team_to_team_table(gui, k)
  local team = global.teams[k]
  local textfield = gui.add{type = "textfield", name = k, text = team.name}
  textfield.style.minimal_width = 0
  textfield.style.horizontally_stretchable = true
  --textfield.style.maximal_width = 100
  make_color_dropdown(k, gui)
  local caption
  if tonumber(team.team) then
    caption = team.team
  elseif team.team:find("?") then
    caption = "?"
  else
    caption = team.team
  end
  set_button_style(gui.add{type = "button", name = k.."_next_team_button", caption = caption, tooltip = {"team-button-tooltip"}})
  local bin = gui.add{name = k.."_trash_button", type = "sprite-button", sprite = "utility/trash", tooltip = {"remove-team-tooltip"}}
  bin.style.top_padding = 0
  bin.style.bottom_padding = 0
  bin.style.right_padding = 0
  bin.style.left_padding = 0
  bin.style.minimal_height = 26
  bin.style.minimal_width = 26
end

function create_game_config_gui(gui)
  local name = "game_config_gui"
  local frame = gui[name] or gui.add{type = "frame", name = name, caption = {"game-config-gui"}, direction = "vertical", style = "inner_frame"}
  frame.clear()
  make_config_table(frame, global.game_config)
  create_disable_frame(frame)
end

function create_team_config_gui(gui)
  local name = "team_config_gui"
  local frame = gui[name] or gui.add{type = "frame", name = name, caption = {"team-config-gui"}, direction = "vertical", style = "inner_frame"}
  frame.clear()
  local inner_frame = frame.add{type = "frame", style = "inside_shallow_frame", name = "team_config_gui_inner_frame", direction = "vertical"}
  inner_frame.style.left_padding = 8
  inner_frame.style.right_padding = 8
  inner_frame.style.top_padding = 8
  inner_frame.style.bottom_padding = 8
  local scroll = inner_frame.add{type = "scroll-pane", name = "team_config_gui_scroll"}
  scroll.style.maximal_height = 200
  local team_table = scroll.add{type = "table", column_count = 4, name = "team_table"}
  for _, _name in pairs({"team-name", "color", "team", "remove"}) do
    team_table.add{type = "label", caption = {_name}}
  end
  for k in pairs(global.teams) do
    add_team_to_team_table(team_table, k)
  end
  set_button_style(inner_frame.add{name = "add_team_button", type = "button", caption = {"add-team"}, tooltip = {"add-team-tooltip"}})
  make_config_table(frame, global.team_config)
end

function get_config_holder(player)
  local gui = player.gui.center
  local frame = gui.config_holding_frame
  if frame then return frame.scrollpane.horizontal_flow end
  frame = gui.add{name = "config_holding_frame", type = "frame", direction = "vertical"}
  frame.style.maximal_height = player.display_resolution.height * 0.95
  frame.style.maximal_width = player.display_resolution.width * 0.95
  local scroll = frame.add{name = "scrollpane", type = "scroll-pane"}
  local flow = scroll.add{name = "horizontal_flow", type = "table", column_count = 4}
  flow.draw_vertical_lines = true
  flow.style.horizontal_spacing = 32
  flow.style.horizontally_stretchable = true
  flow.style.horizontally_squashable = true
  return flow
end

function get_config_frame(player)
  local gui = player.gui.center
  local frame = gui.config_holding_frame
  if frame then return frame end
  get_config_holder(player)
  return gui.config_holding_frame
end

function check_config_frame_size(event)
  local player = game.get_player(event.player_index)
  if not player then return end
  local frame = player.gui.center.config_holding_frame
  if not frame then return end
  local visiblity = frame.visible
  frame.destroy()
  --In this case, it is better to destroy and re-create, instead of handling the sizing and scaling of all the elements in the gui
  create_config_gui(player)
  get_config_frame(player).visible = visiblity
end

function check_balance_frame_size(event)
  local player = game.get_player(event.player_index)
  if not player then return end
  local frame = player.gui.center.balance_options_frame
  if not frame then return end
  toggle_balance_options_gui(player)
  toggle_balance_options_gui(player)
end

local function set_mode_input(player)
  if not (player.gui.center.config_holding_frame) then return end
  local visibility_map = {
    required_production_score = function(gui)
      local dropdown = gui.game_mode_dropdown
      if not dropdown then return end
      local name = global.game_config.game_mode.options[dropdown.selected_index]
      return name == "production_score"
    end,
    required_oil_barrels = function(gui)
      local dropdown = gui.game_mode_dropdown
      if not dropdown then return end
      local name = global.game_config.game_mode.options[dropdown.selected_index]
      return name == "oil_harvest"
    end,
    oil_only_in_center = function(gui)
      local dropdown = gui.game_mode_dropdown
      if not dropdown then return end
      local name = global.game_config.game_mode.options[dropdown.selected_index]
      return name == "oil_harvest"
    end,
    time_limit = function(gui)
      local dropdown = gui.game_mode_dropdown
      if not dropdown then return end
      local name = global.game_config.game_mode.options[dropdown.selected_index]
      return name == "oil_harvest" or name == "production_score" or name == "genocide_of_biters"
    end,
    spectator_fog_of_war = function(gui) return gui.allow_spectators_boolean and gui.allow_spectators_boolean.state end,
    starting_chest_multiplier = function(gui)
      local dropdown = gui.starting_chest_dropdown
      local name = global.team_config.starting_chest.options[dropdown.selected_index]
      return name ~= "none"
    end,
    disband_on_loss = function(gui)
      local dropdown = gui.game_mode_dropdown
      if not dropdown then return end
      local name = global.game_config.game_mode.options[dropdown.selected_index]
      return name == "conquest" or name == "last_silo_standing"
    end,
    give_artillery_remote = function(gui)
      local option = gui.team_artillery_boolean
      if not option then return end
      return option.state
    end,
    turret_ammunition = function(gui)
      local option = gui.team_turrets_boolean
      if not option then return end
      return option.state
    end,
    team_artillery_minable = function(gui)
      local option = gui.team_artillery_boolean
      if not option then return end
      return option.state
    end,
    required_satellites_sent = function(gui)
      local dropdown = gui.game_mode_dropdown
      if not dropdown then return end
      local name = global.game_config.game_mode.options[dropdown.selected_index]
      return name == "space_race"
    end,
    defcon_timer = function(gui)
      local option = gui.defcon_mode_boolean
      if not option then return end
      return option.state
    end,
  }

  local gui = get_config_holder(player)
  for _, frame in pairs({gui.map_config_gui, gui.game_config_gui, gui.team_config_gui}) do
    if frame and frame.valid then
      local config = frame.config_table
      if (config and config.valid) then
        local children = config.children
        for j, child in pairs(children) do
          local name = child.name or ""
          local mapped = visibility_map[name]
          if mapped then
            local bool = mapped(config)
            children[j].visible = bool
            children[j+1].visible = bool
          end
        end
      end
    end
  end
end

function create_config_gui(player)
  local gui = get_config_holder(player)
  create_map_config_gui(gui)
  create_game_config_gui(gui)
  create_team_config_gui(gui)
  local frame = get_config_frame(player)
  if not frame.config_holder_button_flow then
    local button_flow = frame.add{type = "flow", direction = "horizontal", name = "config_holder_button_flow"}
    button_flow.style.horizontally_stretchable = true
    button_flow.add{type = "button", name = "balance_options", caption = {"balance-options"}}
    local spacer = button_flow.add{type = "flow"}
    spacer.style.horizontally_stretchable = true
    button_flow.add{type = "sprite-button", name = "pvp_export_button", sprite = "utility/export_slot", tooltip = {"gui.export-to-string"}, style = "slot_button"}
    button_flow.add{type = "sprite-button", name = "pvp_import_button", sprite = "utility/import_slot", tooltip = {"gui-blueprint-library.import-string"}, style = "slot_button"}
    button_flow.add{type = "button", name = "config_confirm", caption = {"config-confirm"}}
  end
  set_mode_input(player)
end

function create_map_config_gui(gui)
  local name = "map_config_gui"
  local frame = gui[name]
  if frame then
    frame.clear()
  else
    frame = gui.add{type = "frame", name = name, caption = {"map-config-gui"}, direction = "vertical", style = "inner_frame"}
    local button = frame.add{type = "button", name = "reroll_starting_area", caption = {"reroll-starting-area"}, tooltip = {"reroll-starting-area-tooltip"}}
    button.style.font = "default"
    button.style.top_padding = 0
    button.style.bottom_padding = 0
    local button2 = frame.add{type = "button", name = "change_surface", caption = {"change_surface"}, tooltip = {"change_surface_tooltip"}}
    button2.style.font = "default"
    button2.style.top_padding = 0
    button2.style.bottom_padding = 0
  end
  make_config_table(frame, global.map_config)
end

local function create_waiting_gui(player)
  local gui = player.gui.center
  local frame = gui.waiting_frame or gui.add{type = "frame", name = "waiting_frame"}
  frame.clear()
  frame.add{type = "label", caption = {"setup-in-progress"}}
end

local function end_round(admin)
  for _, player in pairs(game.players) do
    player.force = game.forces.player
    player.tag = ""
    destroy_player_gui(player)
    destroy_joining_guis(player.gui.center)
    if player.connected then
      if player.ticks_to_respawn then
        player.ticks_to_respawn = nil
      end
      local character = player.character
      player.character = nil
      if character then character.destroy() end
      player.set_controller{type = defines.controllers.ghost}
      player.teleport({0, 1000}, game.get_surface("Lobby"))
      if player.admin then
        create_config_gui(player)
      else
        create_waiting_gui(player)
      end
    end
  end
  if global.surface ~= nil then
    game.delete_surface(global.surface)
  end
  if admin then
    game.print({"admin-ended-round", admin.name})
  end
  global.copy_team = nil
  global.setup_finished = false
  global.check_starting_area_generation = false
  global.average_score = nil
  global.scores = nil
  global.exclusion_map = nil
  global.protected_teams = nil
  global.check_base_exclusion = nil
  global.oil_harvest_scores = nil
  global.production_scores = nil
  global.space_race_scores = nil
  global.last_defcon_tick = nil
  global.next_defcon_tech = nil
  global.biters_on_pvp = 0
  global.silos = nil
  script.raise_event(events.on_round_end, {})
  --roll_starting_area()
end

function prepare_next_round()
  global.setup_finished = false
  global.team_won = false
  create_next_surface()
  setup_teams()
  chart_starting_area_for_force_spawns()
  set_evolution_factor()
  game.remove_offline_players()
  game.difficulty_settings.technology_price_multiplier = global.map_config.technology_price_multiplier
end

game_mode_buttons = {
  ["production_score"] = {type = "button", caption = {"production_score"}, name = "production_score_button", style = mod_gui.button_style},
  ["oil_harvest"] = {type = "button", caption = {"oil_harvest"}, name = "oil_harvest_button", style = mod_gui.button_style},
  ["space_race"] = {type = "button", caption = {"space_race"}, name = "space_race_button", style = mod_gui.button_style},
  ["genocide_of_biters"] = {type = "button", caption = {"genocide_of_biters"}, name = "genocide_biters_button", style = mod_gui.button_style}
}

function init_player_gui(player)
  destroy_player_gui(player)
  if not global.setup_finished then return end
  local button_flow = mod_gui.get_button_flow(player)
  button_flow.add{type = "button", caption = {"objective"}, name = "objective_button", style = mod_gui.button_style}
  button_flow.add{type = "button", caption = {"teams"}, name = "list_teams_button", style = mod_gui.button_style}
  --if not global.team_config.locked_teams then
    --local button = button_flow.add{type = "button", caption = {"diplomacy"}, name = "diplomacy_button", style = mod_gui.button_style}
    --button.visible = #global.teams > 1 and player.force.name ~= "spectator"
  --end
  local game_mode_button = game_mode_buttons[global.game_config.game_mode.selected]
  if game_mode_button then
    button_flow.add(game_mode_button)
  end
  if player.admin then
    button_flow.add{type = "button", caption = {"admin"}, name = "admin_button", style = mod_gui.button_style}
  end
  if player.force.name == "spectator" then
    button_flow.add{type = "button", caption = {"join-team"}, name = "spectator_join_team_button", style = mod_gui.button_style}
  end
end

function get_color(team, lighten)
  local c = global.colors[global.color_map[team.color]].color
  if lighten then
    return {r = 1 - (1 - c.r) * 0.5, g = 1 - (1 - c.g) * 0.5, b = 1 - (1 - c.b) * 0.5, a = 1}
  end
  return c
end

function add_player_list_gui(force, gui)
  if not (force and force.valid) then return end
  if #force.players == 0 then
    gui.add{type = "label", caption = {"none"}}
    return
  end
  local scroll = gui.add{type = "scroll-pane"}
  scroll.style.maximal_height = 120
  local name_table = scroll.add{type = "table", column_count = 1}
  name_table.style.vertical_spacing = 0
  local added = {}
  local first = true
  if #force.connected_players > 0 then
    local online_names = ""
    for _, player in pairs(force.connected_players) do
      if not first then
        online_names = online_names..", "
      end
      first = false
      online_names = online_names..player.name
      added[player.name] = true
    end
    local online_label = name_table.add{type = "label", caption = {"online", online_names}}
    online_label.style.single_line = false
    online_label.style.maximal_width = 180
  end
  first = true
  if #force.players > #force.connected_players then
    local offline_names = ""
    for _, player in pairs(force.players) do
      if not added[player.name] then
      if not first then
        offline_names = offline_names..", "
      end
      first = false
      offline_names = offline_names..player.name
      added[player.name] = true
      end
    end
    local offline_label = name_table.add{type = "label", caption = {"offline", offline_names}}
    offline_label.style.single_line = false
    offline_label.style.font_color = {r = 0.7, g = 0.7, b = 0.7}
    offline_label.style.maximal_width = 180
  end
end

local function get_force_area(force)
  if not (force and force.valid) then return end
  local surface = global.surface
  if not (surface and surface.valid) then return end
  local radius = get_starting_area_radius(true)
  local origin = force.get_spawn_position(surface)
  return {{origin.x - radius, origin.y - radius}, {origin.x + (radius - 1), origin.y + (radius - 1)}}
end

local function protect_force_area(force)
  if not global.game_config.protect_empty_teams then return end
  local surface = global.surface
  if not (surface and surface.valid) then return end
  local non_destructible = {}
  local entities = surface.find_entities_filtered{force = force, area = get_force_area(force)}
  for i=#entities, 1, -1 do
    local entity = entities[i]
    if entity.destructible == false and entity.unit_number then
      non_destructible[entity.unit_number] = true
    end
    entity.destructible = false
  end
  if not global.protected_teams then
    global.protected_teams = {}
  end
  global.protected_teams[force.name] = non_destructible
end

local function unprotect_force_area(force)
  if not global.game_config.protect_empty_teams then return end
  local surface = global.surface
  if not (surface and surface.valid) then return end
  if not global.protected_teams then
    global.protected_teams = {}
  end
  local protected_entities = global.protected_teams[force.name] or {}
  local entities = surface.find_entities_filtered{force = force, area = get_force_area(force)}
  for i=#entities, 1, -1 do
    local entity = entities[i]
    if (not entity.unit_number) or (not protected_entities[entity.unit_number]) then
      entity.destructible = true
    end
  end
  global.protected_teams[force.name] = nil
end

---@return string #Force name
local function get_chunk_map_position(position)
  local map = global.exclusion_map
  local chunk_x = floor(position.x / 32)
  local chunk_y = floor(position.y / 32)
  if map[chunk_x] then
    return map[chunk_x][chunk_y]
  end
end

local function check_player_exclusion(player, force_name)
  if not force_name then return end
  local force = game.forces[force_name]
  if not (force and force.valid) then return end
  if force == player.force or force.get_friend(player.force) then return end
  if not (global.check_base_exclusion or (global.protected_teams and global.protected_teams[force_name])) then return end
  local surface = global.surface
  local origin = force.get_spawn_position(surface)
  -- local size = global.map_config.starting_area_size.selected --???
  local radius = get_starting_area_radius(true) + 5 --[[radius in tiles]]
  local position = {x = player.position.x, y = player.position.y}
  local vector = {x = 0, y = 0}

  if position.x < origin.x then
    vector.x = (origin.x - radius) - position.x
  elseif position.x > origin.x then
    vector.x = (origin.x + radius) - position.x
  end

  if position.y < origin.y then
    vector.y = (origin.y - radius) - position.y
  elseif position.y > origin.y then
    vector.y = (origin.y + radius) - position.y
  end

  if abs(vector.x) < abs(vector.y) then
    vector.y = 0
  else
    vector.x = 0
  end
  position = {x = position.x + vector.x, y = position.y + vector.y}
  local vehicle = player.vehicle
  if vehicle then
    position = surface.find_non_colliding_position(vehicle.name, position, 32, 1) or position
    if not vehicle.teleport(position) then
      player.driving = false
    end
    vehicle.orientation = vehicle.orientation + 0.5
  elseif player.character then
    position = surface.find_non_colliding_position(player.character.name, position, 32, 1) or position
    player.teleport(position)
  else
    player.teleport(position)
  end
  if global.check_base_exclusion then
    local time_left = ceil((global.round_start_tick + (global.game_config.base_exclusion_time * 60 * 60) - game.tick) / 3600)
    player.print({"base-exclusion-teleport", time_left})
  else
    player.print({"protected-base-area"})
  end
end

local function check_base_exclusion()
  if not (global.check_base_exclusion or global.protected_teams) then return end

  if global.check_base_exclusion and game.tick > (global.round_start_tick + (global.game_config.base_exclusion_time * 60 * 60)) then
    global.check_base_exclusion = nil
    game.print({"base-exclusion-ends"})
  end

  -- local surface = global.surface
  local exclusion_map = global.exclusion_map
  if not exclusion_map then return end

  for _, player in pairs(game.connected_players) do
    if player.valid and not ignore_force_list[player.force.name] then
      check_player_exclusion(player, get_chunk_map_position(player.position))
    end
  end
end

local function check_force_protection(force)
  if not global.game_config.protect_empty_teams then return end
  if not (force and force.valid) then return end
  if ignore_force_list[force.name] then return end
  if not global.protected_teams then global.protected_teams = {} end
  local should_protect = (#force.connected_players == 0)

  if global.protected_teams[force.name] then
    if not should_protect then
      unprotect_force_area(force)
    end
  elseif should_protect then
    protect_force_area(force)
    check_base_exclusion()
  end
end

function set_player(player, team)
  local force = game.forces[team.name]
  local surface = global.surface
  if not surface.valid then return end
  local position = surface.find_non_colliding_position("character", force.get_spawn_position(surface), 320, 1)
  if position then
    player.teleport(position, surface)
  else
    player.print({"cant-find-position"})
    choose_joining_gui(player)
    return
  end
  if player.character then
    player.character.destroy()
  end
  player.force = force
  player.cheat_mode = global.map_config.cheat_mode
  player.color = get_color(team)
  player.chat_color = get_color(team, true)
  player.tag = "["..force.name.."]"
  player.set_controller {
    type = defines.controllers.character,
    character = surface.create_entity{name = "character", position = position, force = force}
  }
  player.spectator = false
  init_player_gui(player)


  for _, player in pairs(game.connected_players) do
    update_team_list_frame(player)
  end

  if global.game_config.team_artillery and global.game_config.give_artillery_remote and game.item_prototypes["artillery-targeting-remote"] then
    player.insert("artillery-targeting-remote")
  end
  give_inventory(player)
  give_equipment(player)

  apply_character_modifiers(player)
  check_force_protection(force)
  game.print({"joined", player.name, player.force.name})
end

function choose_joining_gui(player)
  if #global.teams == 1 then
    local team = global.teams[1]
    -- local force = game.forces[team.name] --???
    set_player(player, team)
    return
  end
  local setting = global.team_config.team_joining.selected
  if player.admin then
    create_gui_GM(player)
  end
  if setting == "random" then
    create_random_join_gui(player.gui.center)
    return
  end
  if setting == "player_pick" then
    create_pick_join_gui(player.gui.center)
    return
  end
  if setting == "auto_assign" then
    create_auto_assign_gui(player.gui.center)
    return
  end
end

local function add_join_spectator_button(gui)
  local player = game.get_player(gui.player_index)
  if (not global.game_config.allow_spectators) and (not player.admin) then return end
  set_button_style(gui.add{type = "button", name = "join_spectator", caption = {"join-spectator"}})
end

function create_random_join_gui(gui)
  local name = "random_join_frame"
  local frame = gui[name] or gui.add{type = "frame", name = name, caption = {"random-join"}}
  frame.clear()
  set_button_style(frame.add{type = "button", name = "random_join_button", caption = {"random-join-button"}})
  add_join_spectator_button(frame)
end

function create_auto_assign_gui(gui)
  local name = "auto_assign_frame"
  local frame = gui[name] or gui.add{type = "frame", name = name, caption = {"auto-assign"}}
  frame.clear()
  set_button_style(frame.add{type = "button", name = "auto_assign_button", caption = {"auto-assign-button"}})
  add_join_spectator_button(frame)
end

function create_pick_join_gui(gui)
  local teams = get_eligible_teams(game.get_player(gui.player_index))
  if not teams then return end
  local name = "pick_join_frame"
  local frame = gui[name] or gui.add{type = "frame", name = name, caption = {"pick-join"}, direction = "vertical"}
  frame.clear()
  local inner_frame = frame.add{type = "frame", style = "inside_shallow_frame", name = "pick_join_inner_frame", direction = "vertical"}
  inner_frame.style.left_padding = 8
  inner_frame.style.top_padding = 8
  inner_frame.style.right_padding = 8
  inner_frame.style.bottom_padding = 8
  local pick_join_table = inner_frame.add{type = "table", name = "pick_join_table", column_count = 4}
  pick_join_table.style.horizontal_spacing = 16
  pick_join_table.style.vertical_spacing = 8
  pick_join_table.draw_horizontal_lines = true
  pick_join_table.draw_vertical_lines = true
  pick_join_table.style.column_alignments[3] = "right"
  pick_join_table.add{type = "label", name = "pick_join_table_force_name", caption = {"team-name"}}.style.font = "default-semibold"
  pick_join_table.add{type = "label", name = "pick_join_table_player_count", caption = {"players"}}.style.font = "default-semibold"
  pick_join_table.add{type = "label", name = "pick_join_table_team", caption = {"team-number"}}.style.font = "default-semibold"
  pick_join_table.add{type = "label", name = "pick_join_table_pad"}.style.font = "default-semibold"
  for _, team in pairs(teams) do
    local force = game.forces[team.name]
    if force then
      local label = pick_join_table.add{type = "label", name = force.name.."_label", caption = force.name}
      label.style.font = "default-semibold"
      label.style.font_color = get_color(team, true)
      add_player_list_gui(force, pick_join_table)
      local caption
      if tonumber(team.team) then
        caption = team.team
      elseif team.team:find("?") then
        caption = team.team:gsub("?", "")
      else
        caption = team.team
      end
      pick_join_table.add{type = "label", name = force.name.."_team", caption = caption}
      set_button_style(pick_join_table.add{type = "button", name = force.name.."_pick_join", caption = {"join"}})
    end
  end
  add_join_spectator_button(frame)
end

local function on_pick_join_button_press(gui, player)
  local name = gui.name
  local suffix = "_pick_join"
  if not name:find(suffix) then return end

  team_name = name:gsub(suffix, "")
  local joined_team
  for _, team in pairs(global.teams) do
    if team_name == team.name then
      joined_team = team
      break
    end
  end
  if not joined_team then return end
  local force = game.forces[joined_team.name]
  if not force then return end
  set_player(player, joined_team)
  player.gui.center.clear()

  for _, _player in pairs(game.forces.player.players) do
    create_pick_join_gui(_player.gui.center)
  end

  for _, player in pairs(game.connected_players) do
    update_team_list_frame(player)
  end

  return true
end

function add_team_button_press(event, player, gui)
  local index = #global.teams + 1
  for k = 1, index do
    if not global.teams[k] then
      index = k
      break
    end
  end
  if index > 24 then
    player.print({"too-many-teams", 24})
    return
  end
  local color = global.colors[(1+index%(#global.colors))]
  local name = game.backer_names[math.random(#game.backer_names)]
  --local name = color.name.." "..index
  local team = {name = name, color = color.name, team = "-"}
  global.teams[index] = team
  for _, _player in pairs(game.players) do
    local _gui = get_config_holder(_player).team_config_gui
    if _gui then
      add_team_to_team_table(_gui.team_config_gui_inner_frame.team_config_gui_scroll.team_table, index)
    end
  end
end

local function trash_team_button_press(gui, player)
  if not gui.name:find("_trash_button") then
    return
  end

  local team_index = gui.name:gsub("_trash_button", "")
  team_index = tonumber(team_index)
  local count = 0
  for _ in pairs(global.teams) do
    count = count + 1
  end
  if count > 1 then
    global.teams[team_index] = nil
    remove_team_from_team_table(gui)
  else
    player.print({"cant-remove-only-team"})
  end
  return true
end

function remove_team_from_team_table(gui)
  local index = nil
  for k, child in pairs(gui.parent.children) do
    if child == gui then
      index = k
      break
    end
  end
  -- local delete_list = {}
  for _, player in pairs(game.players) do
    local _gui = get_config_holder(player).team_config_gui
    if _gui then
      local children = _gui.team_config_gui_inner_frame.team_config_gui_scroll.team_table.children
      for j = -3, 0 do
        children[index+j].destroy()
      end
    end
  end
end

function set_teams_from_gui(player)
  local gui = get_config_holder(player).team_config_gui
  if not gui then return end
  local teams = {}
  -- local team = {}
  local duplicates = {}
  local team_table = gui.team_config_gui_inner_frame.team_config_gui_scroll.team_table
  local index = 1
  local g_colors = global.colors
  for _, element in pairs(team_table.children) do
    if (element.type == "textfield" or element.type == "text-box") then
      local text = element.text
      if ignore_force_list[text] then
        player.print({"disallowed-team-name", text})
        return
      end
      if text == "" then
        player.print({"empty-team-name"})
        return
      end
      if duplicates[text] then
        player.print({"duplicate-team-name", text})
        return
      end
      duplicates[text] = true
      local team = {}
      team.name = text
      team.color = g_colors[team_table[index.."_color"].selected_index].name
      local caption = team_table[index.."_next_team_button"].caption
      team.team = tonumber(caption) or caption
      tinsert(teams, team)
    end
  end
  if #teams > 64 then
    player.print({"too-many-teams", 64})
    return
  end
  global.teams = teams
  return true
end

local function on_team_button_press(event, gui)
  if not gui.name:find("_next_team_button") then return end

  local left_click = (event.button == defines.mouse_button_type.left)
  local index = gui.caption
  if index == "-" then
    if left_click then
      index = 1
    else
      index = "?"
    end
  elseif index == "?" then
    if left_click then
      index = "-"
    else
      index = #global.teams
    end
  elseif index == tostring(#global.teams) then
    if left_click then
      index = "?"
    else
      index = index -1
    end
  else
    if left_click then
      index = tonumber(index) + 1
    elseif index == tostring(1) then
      index = "-"
    else
      index = index -1
    end
  end
  gui.caption = index
  return true
end

function toggle_balance_options_gui(player)
  if not (player and player.valid) then return end
  local gui = player.gui.center
  local frame = gui.balance_options_frame
  local config = gui.config_holding_frame
  if frame then
    frame.destroy()
    if config then
      config.visible = true
    end
    return
  end
  if config then
    config.visible = false
  end
  frame = gui.add{name = "balance_options_frame", type = "frame", direction = "vertical", caption = {"balance-options"}}
  frame.style.maximal_height = player.display_resolution.height * 0.95
  frame.style.maximal_width = player.display_resolution.width * 0.95
  local scrollpane = frame.add{name = "balance_options_scrollpane", type = "scroll-pane"}
  local big_table = scrollpane.add{type = "table", column_count = 4, name = "balance_options_big_table", direction = "horizontal"}
  big_table.style.horizontal_spacing = 32
  big_table.draw_vertical_lines = true
  local entities = game.entity_prototypes
  local ammos = game.ammo_category_prototypes
  for modifier_name, array in pairs(global.modifier_list) do
    local flow = big_table.add{type = "frame", name = modifier_name.."_flow", caption = {modifier_name}, style = "inner_frame"}
    local table = flow.add{name = modifier_name.."table", type = "table", column_count = 2}
    table.style.column_alignments[2] = "right"
    for name, modifier in pairs(array) do
      if modifier_name == "ammo_damage_modifier" then
        local string = "ammo-category-name."..name
        table.add{type = "label", caption = {"", ammos[name].localised_name, {"colon"}}}
      elseif modifier_name == "gun_speed_modifier" then
        table.add{type = "label", caption = {"", ammos[name].localised_name, {"colon"}}}
      elseif modifier_name == "turret_attack_modifier" then
        table.add{type = "label", caption = {"", entities[name].localised_name, {"colon"}}}
      elseif modifier_name == "character_modifiers" then
        table.add{type = "label", caption = {"", {name}, {"colon"}}}
      end
      local input = table.add{name = name.."text", type = "textfield"}
      input.text = tostring((modifier * 100) + 100).."%"
      input.style.maximal_width = 50
    end
  end
  local flow = frame.add{type = "flow", direction = "horizontal"}
  flow.style.horizontally_stretchable = true
  flow.style.horizontal_align = "right"
  flow.add{type = "button", name = "balance_options_confirm", caption = {"balance-confirm"}}
  flow.add{type = "button", name = "balance_options_cancel", caption = {"cancel"}}
end

function create_disable_frame(gui)
  local frame = gui.disable_items_frame
  if gui.disable_items_frame then
    gui.disable_items_frame.clear()
  else
    frame = gui.add{name = "disable_items_frame", type = "frame", direction = "vertical", style = "inner_frame"}
    --frame.style.horizontally_stretchable = true
  end
  frame.add{type = "label", caption = {"", {"disabled-items"}, {"colon"}}}
  local disable_table = frame.add{type = "table", name = "disable_items_table", column_count = 7}
  disable_table.style.horizontal_spacing = 2
  disable_table.style.vertical_spacing = 2
  local items = game.item_prototypes
  if global.disabled_items then
    local elem_button = {type = "choose-elem-button", elem_type = "item"}
    for item in pairs(global.disabled_items) do
      if items[item] then
        disable_table.add(elem_button).elem_value = item
      end
    end
  end
  disable_table.add{type = "choose-elem-button", elem_type = "item"}
end

function set_balance_settings(player)
  local gui = player.gui.center
  local frame = gui.balance_options_frame
  local scroll = frame.balance_options_scrollpane
  local table = scroll.balance_options_big_table
  local modifier_list = global.modifier_list
  for modifier_name, array in pairs(modifier_list) do
    local flow = table[modifier_name.."_flow"]
    local modifier_table = flow[modifier_name.."table"]
    if modifier_table then
      local modifier_group = modifier_list[modifier_name]
      for name, modifier in pairs(array) do
        local text = modifier_table[name.."text"].text
        if text then
          text = string.gsub(text, "%%", "")
          local n = tonumber(text)
          if n == nil then
            player.print({"must-be-number", {modifier_name}})
            return
          end
          if n < -1 then
            player.print({"must-be-greater-than-negative-1", {modifier_name}})
            return
          end
          modifier_group[name] = (n - 100) / 100
        end
      end
    end
  end
  return true
end

function config_confirm(player)
  if not parse_config(player) then return end
  destroy_config_for_all()
  prepare_next_round()
end

local function parse_disabled_items(gui)
  if not gui.game_config_gui.disable_items_frame then return end
  local disable_table = gui.game_config_gui.disable_items_frame.disable_items_table
  if not disable_table then return end
  global.disabled_items = {}
  local disabled_items = global.disabled_items
  for _, child in pairs(disable_table.children) do
    if child.elem_value then
      disabled_items[child.elem_value] = true
    end
  end
end

function parse_config(player)
  if not set_teams_from_gui(player) then return end
  local frame = get_config_holder(player)
  if not parse_config_from_gui(frame.map_config_gui, global.map_config) then return end
  if not parse_config_from_gui(frame.game_config_gui, global.game_config) then return end
  if not parse_config_from_gui(frame.team_config_gui, global.team_config) then return end
  parse_disabled_items(frame)
  return true
end

function auto_assign(player)
  local teams = get_eligible_teams(player)
  if not teams then return end
  -- TODO: complete ratio
  --[[
  local ratio = {}
  for _, team in pairs(global.teams) do
    local force = game.forces[team.name]
    local total_connected_players = 0
    local total_time_players = 0
    local pack_researched = 0
    local total_pack = 0
    for _, player in pairs(force.players) do
      if player.online_time > 60 * 60 * 50 then -- 50 min
        total_connected_players = total_connected_players + 1
        total_time_players = total_time_players + player.online_time
      elseif player.online_time > 60 * 60 * 20 then -- 20 min
        total_connected_players = total_connected_players + 1
      end
    end
    for techname, tech in pairs(force.technologies) do
      if tech.research_unit_count_formula == nil and not tech.upgrade then -- not an infinite research and not an upgrade
        local count = #tech.research_unit_ingredients
        total_pack = total_pack + count
        if tech.researched then
          pack_researched = pack_researched + count
        end
      end
    end
    local total_players = #force.players
    local research_ratio = pack_researched / total_pack
    ratio[team.name] = -- WIP
  end
  local max_ratio_team = global.teams[1]
  local max_ratio = ratio[global.teams[1].name]
  for team, sum_ratio in pairs(ratio) do
    if sum_ratio => max_ratio then
      max_ratio_team = team
    end
  end
  set_player(player, max_ratio_team)
  ]]--
  local count = 1000
  for _, this_team in pairs(teams) do
    local other_force = game.forces[this_team.name]
    if other_force ~= nil then
      if #other_force.connected_players < count then
        count = #other_force.connected_players
        force = other_force
        team = this_team
      end
    end
  end
  set_player(player, team)
end

function get_eligible_teams(player)
  local limit = global.team_config.max_players
  local teams = {}
  local forces = game.forces
  for _, team in pairs(global.teams) do
    local force = forces[team.name]
    if force then
      if limit <= 0 or #force.connected_players < limit or player.admin then
        tinsert(teams, team)
      end
    end
  end
  if #teams == 0 then
    spectator_join(player)
    player.print({"no-space-available"})
    return
  end
  return teams
end

function destroy_config(player)
  local names = {"config_holding_frame", "balance_options_frame", "waiting_frame"}
  local gui = player.gui.center
  for _, name in pairs(names) do
    if gui[name] then
      gui[name].destroy()
    end
  end
end

function destroy_config_for_all()
  for _, player in pairs(game.players) do
    destroy_config(player)
  end
end

function set_evolution_factor()
  local n = global.map_config.evolution_factor
  if n >= 1 then
    n = 1
  end
  if n <= 0 then
    n = 0
  end
  game.forces.enemy.evolution_factor = n
  global.map_config.evolution_factor = n
end

function random_join(player)
  local teams = get_eligible_teams(player)
  if not teams then return end
  set_player(player, teams[math.random(#teams)])
end

function GM_join(player)
  local force = game.forces["GM"]
  local surface = global.surface
  if not surface.valid then return end
  if player.character then
    player.character.destroy()
  end
  local center_gui = player.gui.center
  if center_gui.random_join_frame then
    center_gui.random_join_frame.destroy()
  end
  if center_gui.pick_join_frame then
    center_gui.pick_join_frame.destroy()
  end
  if center_gui.auto_assign_frame then
    center_gui.auto_assign_frame.destroy()
  end
  init_player_gui(player)
  player.teleport({0, 0}, surface)
  player.force = force
  player.cheat_mode = true
  player.tag = "/GM/"
  player.set_controller{type = defines.controllers.god}
  force.enable_all_recipes()
  game.print({"joined", player.name, player.force.name})
end

function spectator_join(player)
  if player.character then player.character.destroy() end
  player.set_controller{type = defines.controllers.ghost}
  player.force = "spectator"
  player.teleport(global.spawn_offset, global.surface)
  player.tag = ""
  player.chat_color = {r = 1, g = 1, b = 1, a = 1}
  player.spectator = true
  init_player_gui(player)
  game.print({"joined-spectator", player.name})
end

local function objective_button_press(event, player, gui)
  local flow = mod_gui.get_frame_flow(player)
  local frame = flow.objective_scroll
  if frame then
    frame.destroy()
    return
  end
  local scroll = flow.add{type = "scroll-pane", name = "objective_scroll"}
  scroll.style.maximal_height = 250
  frame = scroll.add{type = "frame", name = "objective_frame", caption = {"objective"}, direction = "vertical"}
  frame.visible = true
  local big_label = frame.add{type = "label", caption = {global.game_config.game_mode.selected.."_description"}}
  big_label.style.single_line = false
  big_label.style.font = "default-bold"
  big_label.style.top_padding = 0
  big_label.style.maximal_width = 300
  local label_table = frame.add{type = "table", column_count = 2}
  for _, name in pairs({"friendly_fire", "team_joining", "spawn_position", "share_chart", "locked_teams", "who_decides_diplomacy", "disband_on_loss"}) do
    local child_label = label_table.add{type = "label", caption = {"", {name}, {"colon"}}, tooltip = {name.."_tooltip"}}
    local setting = global.team_config[name]
    if setting ~= nil then
      if type(setting) == "table" then
        label_table.add{type = "label", caption = {setting.selected}}
      elseif type(setting) == "boolean" then
        label_table.add{type = "label", caption = {setting}}
      else
        label_table.add{type = "label", caption = setting}
      end
    else
      child_label.destroy()
    end
  end
  local disabled_items = global.disabled_items
  local is_disabled_items = false
  for get_force_area in pairs(disabled_items) do
    is_disabled_items = true
    break
  end
  if is_disabled_items then
    label_table.add{type = "label", caption = {"", {"disabled-items", {"colon"}}, ":"}}
    local flow = frame.add{type = "table", column_count = 10}
    flow.style.horizontal_spacing = 2
    flow.style.vertical_spacing = 2
    local items = game.item_prototypes
    for item in pairs(disabled_items) do
      if items[item] then
        flow.add{type = "sprite", sprite = "item/"..item, tooltip = items[item].localised_name}
      end
    end
  end
end

function list_teams_button_press(event, player, gui)
  local flow = mod_gui.get_frame_flow(player)
  local frame = flow.team_list
  if frame then
    frame.destroy()
    return
  end
  frame = flow.add{type = "frame", caption = {"teams"}, direction = "vertical", name = "team_list"}
  update_team_list_frame(player)
end

function update_team_list_frame(player)
  if not (player and player.valid) then return end
  local flow = mod_gui.get_frame_flow(player)
  local frame = flow.team_list
  if not frame then return end
  frame.clear()
  local inner = frame.add{type = "frame", style = "inside_shallow_frame"}
  inner.style.left_padding = 8
  inner.style.right_padding = 8
  inner.style.top_padding = 8
  inner.style.bottom_padding = 8
  local scroll = inner.add{type = "scroll-pane"}
  scroll.style.maximal_height = player.display_resolution.height * 0.8
  local team_table = scroll.add{type = "table", column_count = 2}
  team_table.style.vertical_spacing = 8
  team_table.style.horizontal_spacing = 16
  team_table.draw_horizontal_lines = true
  team_table.draw_vertical_lines = true
  team_table.add{type = "label", caption = {"team-name"}, style = "bold_label"}
  team_table.add{type = "label", caption = {"players"}, style = "bold_label"}
  for _, team in pairs(global.teams) do
    local force = game.forces[team.name]
    if force then
      local label = team_table.add{type = "label", caption = team.name, style = "description_label"}
      label.style.font_color = get_color(team, true)
      add_player_list_gui(force, team_table)
    end
  end
end

function admin_button_press(event, player)
  local flow = mod_gui.get_frame_flow(player)
  if flow.admin_frame then
    flow.admin_frame.visible = not flow.admin_frame.visible
    return
  end
  local frame = flow.add{type = "frame", caption = {"admin"}, name = "admin_frame", direction = "vertical"}
  frame.visible = true
  set_button_style(frame.add{type = "button", caption = {"end-round"}, name = "admin_end_round", tooltip = {"end-round-tooltip"}})
  set_button_style(frame.add{type = "button", caption = {"reroll-round"}, name = "admin_reroll_round", tooltip = {"reroll-round-tooltip"}})
  set_button_style(frame.add{type = "button", caption = {"admin-change-team"}, name = "admin_change_team", tooltip = {"admin-change-team-tooltip"}})
end

function admin_frame_button_press(gui, player)
  local parent = gui.parent
  if not (parent and parent.valid) then return end
  if parent.name ~= "admin_frame" then return end

  local gui_name = gui.name
  if not player.admin then
    player.print({"only-admins"})
    init_player_gui(player)
  elseif gui_name == "admin_end_round" then
    end_round(player)
  elseif gui_name == "admin_reroll_round" then
    end_round()
    destroy_config_for_all()
    prepare_next_round()
  elseif gui.name == "admin_change_team" then
    local pick_join_frame = player.gui.center.pick_join_frame
    if pick_join_frame then
      pick_join_frame.destroy()
    else
      create_pick_join_gui(pick_join_frame)
    end
  end
  return true
end

function formattime(ticks)
  local hours = floor(ticks / (60 * 60 * 60))
  ticks = ticks - hours * (60 * 60 * 60)
  local minutes = floor(ticks / (60 * 60))
  ticks = ticks - minutes * (60 * 60)
  local seconds = floor(ticks / 60)
  if hours > 0 then
    return string.format("%d:%02d:%02d", hours, minutes, seconds)
  else
    return string.format("%d:%02d", minutes, seconds)
  end
end

function get_time_left()
  if not global.round_start_tick then return "Invalid" end
  if not global.game_config.time_limit then return "Invalid" end
  return formattime((max(global.round_start_tick + (global.game_config.time_limit * 60 * 60) - game.tick, 0)))
end

function production_score_button_press(event, player, gui)
  local flow = mod_gui.get_frame_flow(player)
  local frame = flow.production_score_frame
  if frame then
    frame.destroy()
    return
  end
  frame = flow.add{type = "frame", name = "production_score_frame", caption = {"production_score"}, direction = "vertical"}
  if global.game_config.required_production_score > 0 then
    frame.add{type = "label", caption = {"", {"required_production_score"}, {"colon"}, " ", util.format_number(global.game_config.required_production_score)}}
  end
  if global.game_config.time_limit > 0 then
    frame.add{type = "label", caption = {"time_left", get_time_left()}, name = "time_left"}
  end
  local inner_frame = frame.add{type = "frame", style = "inside_shallow_frame", name = "production_score_inner_frame", direction = "vertical"}
  inner_frame.style.left_padding = 8
  inner_frame.style.top_padding = 8
  inner_frame.style.right_padding = 8
  inner_frame.style.bottom_padding = 8
  local flow = frame.add{type = "flow", direction = "horizontal", name = "recipe_picker_holding_flow"}
  flow.add{type = "label", caption = {"", {"recipe-calculator"}, {"colon"}}}
  flow.add{type = "choose-elem-button", name = "recipe_picker_elem_button", elem_type = "recipe"}
  flow.style.vertical_align = "center"
  update_production_score_frame(player)
end

function update_production_score_frame(player)
  local gui = mod_gui.get_frame_flow(player)
  local frame = gui.production_score_frame
  if not frame then return end
  inner_frame = frame.production_score_inner_frame
  if not inner_frame then return end
  if frame.time_left then
    frame.time_left.caption = {"time_left", get_time_left()}
  end
  inner_frame.clear()
  local information_table = inner_frame.add{type = "table", column_count = 4}
  information_table.draw_horizontal_line_after_headers = true
  information_table.draw_vertical_lines = true
  information_table.style.horizontal_spacing = 16
  information_table.style.vertical_spacing = 8
  information_table.style.column_alignments[3] = "right"
  information_table.style.column_alignments[4] = "right"

  for _, caption in pairs({"", "team-name", "score", "score_per_minute"}) do
    local label = information_table.add{type = "label", caption = {caption}, tooltip = {caption.."_tooltip"}}
    label.style.font = "default-bold"
  end
  local team_map = {}
  for _, team in pairs(global.teams) do
    team_map[team.name] = team
  end
  local average_score = global.average_score
  if not average_score then return end
  local rank = 1
  for name, score in spairs(global.production_scores, function(t, a, b) return t[b] < t[a] end) do
    if not average_score[name] then
      average_score = nil
      return
    end
    if team_map[name] then
      local position = information_table.add{type = "label", caption = "#"..rank}
      if name == player.force.name then
        position.style.font = "default-semibold"
        position.style.font_color = {r = 1, g = 1}
      end
      local label = information_table.add{type = "label", caption = name}
      label.style.font = "default-semibold"
      label.style.font_color = get_color(team_map[name], true)
      information_table.add{type = "label", caption = util.format_number(score)}
      local delta_score = (score - (average_score[name] / statistics_period)) * (60 / statistics_period) * 2
      local delta_label = information_table.add{type = "label", caption = util.format_number(floor(delta_score))}
      if delta_score < 0 then
        delta_label.style.font_color = {r = 1, g = 0.2, b = 0.2}
      end
      rank = rank + 1
    end
  end
end

function oil_harvest_button_press(event, player, gui)
  local flow = mod_gui.get_frame_flow(player)
  local frame = flow.oil_harvest_frame
  if frame then
    frame.destroy()
    return
  end
  frame = flow.add{type = "frame", name = "oil_harvest_frame", caption = {"oil_harvest"}, direction = "vertical"}
  if global.game_config.required_oil_barrels > 0 then
    frame.add{type = "label", caption = {"", {"required_oil_barrels"}, {"colon"}, " ", util.format_number(global.game_config.required_oil_barrels)}}
  end
  local inner_frame = frame.add{type = "frame", style = "inside_shallow_frame", name = "oil_harvest_inner_frame", direction = "vertical"}
  inner_frame.style.left_padding = 8
  inner_frame.style.top_padding = 8
  inner_frame.style.right_padding = 8
  inner_frame.style.bottom_padding = 8
  update_oil_harvest_frame(player)
end

function update_oil_harvest_frame(player)
  local gui = mod_gui.get_frame_flow(player)
  local frame = gui.oil_harvest_frame
  if not frame then return end
  local inner_frame = frame.oil_harvest_inner_frame
  if not inner_frame then return end
  inner_frame.clear()
  local information_table = inner_frame.add{type = "table", column_count = 3}
  information_table.draw_horizontal_line_after_headers = true
  information_table.draw_vertical_lines = true
  information_table.style.horizontal_spacing = 16
  information_table.style.vertical_spacing = 8
  information_table.style.column_alignments[3] = "right"

  for _, caption in pairs({"", "team-name", "oil_harvest"}) do
    local label = information_table.add{type = "label", caption = {caption}}
    label.style.font = "default-bold"
  end
  local team_map = {}
  for _, team in pairs(global.teams) do
    team_map[team.name] = team
  end
  if not global.oil_harvest_scores then
    global.oil_harvest_scores = {}
  end
  local rank = 1
  for name, score in spairs(global.oil_harvest_scores, function(t, a, b) return t[b] < t[a] end) do
    if team_map[name] then
      local position = information_table.add{type = "label", caption = "#"..rank}
      if name == player.force.name then
        position.style.font = "default-semibold"
        position.style.font_color = {r = 1, g = 1}
      end
      local label = information_table.add{type = "label", caption = name}
      label.style.font = "default-semibold"
      label.style.font_color = get_color(team_map[name], true)
      information_table.add{type = "label", caption = util.format_number(score)}
      rank = rank + 1
    end
  end
end

local function update_space_race_frame(player)
  local gui = mod_gui.get_frame_flow(player)
  local frame = gui.space_race_frame
  if not frame then return end
  local inner_frame = frame.space_race_inner_frame
  if not inner_frame then return end
  inner_frame.clear()
  local information_table = inner_frame.add{type = "table", column_count = 4}
  information_table.draw_horizontal_line_after_headers = true
  information_table.draw_vertical_lines = true
  information_table.style.horizontal_spacing = 16
  information_table.style.vertical_spacing = 8
  information_table.style.column_alignments[4] = "right"

  for _, caption in pairs({"", "team-name", "rocket_parts", "satellites_sent"}) do
    local label = information_table.add{type = "label", caption = {caption}}
    label.style.font = "default-bold"
  end
  local colors = {}
  for _, team in pairs(global.teams) do
    colors[team.name] = get_color(team, true)
  end
  local rank = 1

  for name, score in spairs(global.space_race_scores, function(t, a, b) return t[b] < t[a] end) do
    local position = information_table.add{type = "label", caption = "#"..rank}
    if name == player.force.name then
      position.style.font = "default-semibold"
      position.style.font_color = {r = 1, g = 1}
    end
    local label = information_table.add{type = "label", caption = name}
    label.style.font = "default-semibold"
    label.style.font_color = colors[name]
    local progress = information_table.add{type = "progressbar", value = 1}
    progress.style.width = 0
    progress.style.horizontally_squashable = true
    progress.style.horizontally_stretchable = true
    progress.style.color = colors[name]
    local silo = global.silos[name]
    if silo and silo.valid then
      if silo.get_inventory(defines.inventory.rocket_silo_rocket) then
        progress.value = 1
      else
        progress.value = silo.rocket_parts / silo.prototype.rocket_parts_required
      end
    else
      progress.visible = false
    end
    information_table.add{type = "label", caption = util.format_number(score)}
    rank = rank + 1
  end
end

function space_race_button_press(event, player, gui)
  local flow = mod_gui.get_frame_flow(player)
  local frame = flow.space_race_frame
  if frame then
    frame.destroy()
    return
  end
  frame = flow.add{type = "frame", name = "space_race_frame", caption = {"space_race"}, direction = "vertical"}
  if global.game_config.required_satellites_sent > 0 then
    frame.add{type = "label", caption = {"", {"required_satellites_sent"}, {"colon"}, " ", util.format_number(global.game_config.required_satellites_sent)}}
  end
  local inner_frame = frame.add{type = "frame", style = "inside_shallow_frame", name = "space_race_inner_frame", direction = "vertical"}
  inner_frame.style.left_padding = 8
  inner_frame.style.top_padding = 8
  inner_frame.style.right_padding = 8
  inner_frame.style.bottom_padding = 8
  update_space_race_frame(player)
end

-- ???

-- function get_stance(force, other_force)
--   if force.get_friend(other_force) then
--     return "ally"
--   elseif force.get_cease_fire(other_force) then
--     return "neutral"
--   else
--     return "enemy"
--   end
-- end

function give_inventory(player)
  if not global.inventory_list then return end
  if not global.inventory_list[global.team_config.starting_inventory.selected] then return end
  local list = global.inventory_list[global.team_config.starting_inventory.selected]
  for name, count in pairs(list) do
    if game.item_prototypes[name] then
      player.insert{name = name, count = count}
    else
      game.print(name.." is not a valid item")
    end
  end
end

function setup_teams()
  local spectator = game.forces["spectator"]
  if not (spectator and spectator.valid) then
    spectator = game.create_force("spectator")
  end

  local names = {}
  for _, team in pairs(global.teams) do
    names[team.name] = true
  end

  for name in pairs(game.forces) do
    if not (ignore_force_list[name] or names[name]) then
      game.merge_forces(name, "player")
    end
  end

  for k, team in pairs(global.teams) do
    local new_team
    if game.forces[team.name] then
      new_team = game.forces[team.name]
    else
      new_team = game.create_force(team.name)
    end
    new_team.reset()
    set_spawn_position(k, new_team, global.surface)
    set_random_team(team)
  end
  for _, team in pairs(global.teams) do
    local force = game.forces[team.name]
    force.set_friend(spectator, true)
    spectator.set_friend(force, true)
    set_diplomacy(team)
    setup_research(force)
    disable_combat_technologies(force)
    force.reset_technology_effects()
    apply_combat_modifiers(force)
    if global.team_config.starting_equipment.selected == "large" then
      force.worker_robots_speed_modifier = 2.5
    end
  end
  disable_items_for_all()
end

function disable_items_for_all()
  --if not global.setup_finished then return end
  if not global.disabled_items then return end
  -- local items = game.item_prototypes
  local recipes = game.recipe_prototypes
  local recipes_to_disable = {}
  local forces = game.forces
  for item in pairs(global.disabled_items) do
    if recipes[item] then
      recipes_to_disable[item] = true
    else
      local found = false
      for _, recipe in pairs(recipes) do
        for _, product in pairs(recipe.products) do
          if product.name == item then
            recipes_to_disable[item] = recipe.name
            found = true
            break
          end
        end
        if found then break end
      end
    end
  end
  for _, team in pairs(global.teams) do
    local force = forces[team.name]
    if force and force.valid then
      local f_recipes = force.recipes
      for name in pairs(recipes_to_disable) do
        f_recipes[name].enabled = false
      end
    end
  end
end
--[[
function disable_items_for_all()
  if not global.disabled_items then return end
  local items = game.item_prototypes
  local recipes = game.recipe_prototypes
  local product_map = {}
  for _, recipe in pairs(recipes) do
    for _, product in pairs(recipe.products) do
      if not product_map[product.name] then
        product_map[product.name] = {}
      end
      tinsert(product_map[product.name], recipe)
    end
  end

  local recipes_to_disable = {}
  for name in pairs(global.disabled_items) do
    local mapping = product_map[name]
    if mapping then
      for _, recipe in pairs(mapping) do
        recipes_to_disable[recipe.name] = true
      end
    end
  end
  for _, force in pairs(game.forces) do
    for name, bool in pairs(recipes_to_disable) do
      force.recipes[name].enabled = false
    end
  end
end
]]--

function check_technology_for_disabled_items(event)
  if not global.setup_finished then return end
  if not global.disabled_items then return end
  local disabled_items = global.disabled_items
  local technology = event.research
  local recipes = technology.force.recipes
  for _, effect in pairs(technology.effects) do
    if effect.type == "unlock-recipe" then
      for _, product in pairs(recipes[effect.recipe].products) do
        --game.print(product.name)
        if disabled_items[product.name] then
          recipes[effect.recipe].enabled = false
        end
      end
    end
  end
end

function set_random_team(team)
  if tonumber(team.team) then return end
  if team.team == "-" then return end
  team.team = "?"..math.random(#global.teams)
end

function set_diplomacy(team)
  local force = game.forces[team.name]
  if not force or not force.valid then return end
  local team_number
  if tonumber(team.team) then
    team_number = team.team
  elseif team.team:find("?") then
    team_number = team.team:gsub("?", "")
    team_number = tonumber(team_number)
  else
    team_number = "Don't match me"
  end
  for _, other_team in pairs(global.teams) do
    if game.forces[other_team.name] then
      local other_number
      if tonumber(other_team.team) then
        other_number = other_team.team
      elseif other_team.team:find("?") then
        other_number = other_team.team:gsub("?", "")
        other_number = tonumber(other_number)
      else
        other_number = "Okay i won't match"
      end
      if other_number == team_number then
        force.set_cease_fire(other_team.name, true)
        force.set_friend(other_team.name, true)
      else
        force.set_cease_fire(other_team.name, false)
        force.set_friend(other_team.name, false)
      end
    end
  end
end

function set_spawn_position(k, force, surface)
  local setting = global.team_config.spawn_position.selected
  if setting == "fixed" then
    local position = global.spawn_positions[k]
    force.set_spawn_position(position, surface)
    return
  end
  if setting == "random" then
    local position
    local index
    repeat
      index = math.random(1, #global.spawn_positions)
      position = global.spawn_positions[index]
    until position ~= nil
    force.set_spawn_position(position, surface)
    table.remove(global.spawn_positions, index)
    return
  end
  if setting == "team_together" then
    if k == #global.spawn_positions then
      set_team_together_spawns(surface)
    end
  end
end

function set_team_together_spawns(surface)
  local grouping = {}
  for _, team in pairs(global.teams) do
    local team_number
    if tonumber(team.team) then
      team_number = team.team
    elseif team.team:find("?") then
      team_number = team.team:gsub("?", "")
      team_number = tonumber(team_number)
    else
      team_number = "-"
    end
    if tonumber(team_number) then
      if not grouping[team_number] then
        grouping[team_number] = {}
      end
      tinsert(grouping[team_number], team.name)
    else
      if not grouping.no_group then
        grouping.no_group = {}
      end
      tinsert(grouping.no_group, team.name)
    end
  end
  local count = 1
  for _, group in pairs(grouping) do
    for _, team_name in pairs(group) do
      local force = game.forces[team_name]
      if force then
        local position = global.spawn_positions[count]
        if position then
          force.set_spawn_position(position, surface)
          count = count + 1
        end
      end
    end
  end
end

function chart_starting_area_for_force_spawns()
  local surface = global.surface
  local radius = get_starting_area_radius()
  local size = radius*32
  for _, team in pairs(global.teams) do
    local name = team.name
    local force = game.forces[name]
    if force ~= nil then
      local origin = force.get_spawn_position(surface)
      local area = {{origin.x - size, origin.y - size},{origin.x + (size - 32), origin.y + (size - 32)}}
      surface.request_to_generate_chunks(origin, radius)
      force.chart(surface, area)
    end
  end
  global.check_starting_area_generation = true
end

local function check_starting_area_chunks_are_generated()
  if not global.check_starting_area_generation then return end
  if game.tick % (#global.teams) ~= 0 then return end
  local surface = global.surface
  local map_gen_settings = surface.map_gen_settings
  local width = map_gen_settings.width / 2
  local height = map_gen_settings.height / 2
  -- local size = global.map_config.starting_area_size.selected --???
  local check_radius = get_starting_area_radius() - 1
  local total = 0
  local generated = 0
  local forces = game.forces
  local chunk_position = {x = 0, y = 0}
  for _, team in pairs(global.teams) do
    local name = team.name
    local force = forces[name]
    if force ~= nil then
      local origin = force.get_spawn_position(surface)
      local origin_X = ceil(origin.x/32)
      local origin_Y = ceil(origin.y/32)
      for X = -check_radius, check_radius -1 do
        for Y = -check_radius, check_radius -1 do
          total = total + 1
          chunk_position.x = X + origin_X
          chunk_position.y = Y + origin_Y
          if (surface.is_chunk_generated(chunk_position)) then
            generated = generated + 1
          elseif (abs(chunk_position.x * 32) > width) or (abs(chunk_position.y * 32) > height) then
            --The chunk is outside the map
            generated = generated + 1
          end
        end
      end
    end
  end
  global.progress = generated/total
  if total == generated then
    game.speed = 1
    global.check_starting_area_generation = false
    global.finish_setup = game.tick + (#global.teams * 9)
    update_progress_bar()
    return
  end
  update_progress_bar()
end

local function check_player_color()
  local forces = game.forces
  for _, team in pairs(global.teams) do
    local force = forces[team.name]
    if force then
      local color = get_color(team)
      for _, player in pairs(force.connected_players) do
        local player_color = player.color
        for c, v in pairs(color) do
          if abs(player_color[c] - v) > 0.1 then
            game.print({"player-color-changed-back", player.name})
            player.color = color
            player.chat_color = get_color(team, true)
            break
          end
        end
      end
    end
  end
end

local function check_no_rush()
  if game.tick > global.end_no_rush then
    if global.game_config.no_rush_time > 0 then
      game.print({"no-rush-ends"})
    end
    global.end_no_rush = nil
    global.surface.peaceful_mode = global.map_config.peaceful_mode
    game.forces.enemy.kill_all_units()
    return
  end
  local radius = get_starting_area_radius(true)
  local surface = global.surface
  for _, player in pairs(force.connected_players) do
    local force = player.force
    if not ignore_force_list[force.name] then
      local origin = force.get_spawn_position(surface)
      local Xo = origin.x
      local Yo = origin.y
      local position = player.position
      local Xp = position.x
      local Yp = position.y
      if Xp > (Xo + radius) then
        Xp = Xo + (radius - 5)
      elseif Xp < (Xo - radius) then
        Xp = Xo - (radius - 5)
      end
      if Yp > (Yo + radius) then
        Yp = Yo + (radius - 5)
      elseif Yp < (Yo - radius) then
        Yp = Yo - (radius - 5)
      end
      if position.x ~= Xp or position.y ~= Yp then
        local new_position = {x = Xp, y = Yp}
        local vehicle = player.vehicle
        if vehicle then
          new_position = surface.find_non_colliding_position(vehicle.name, new_position, 32, 1) or new_position
          if not vehicle.teleport(new_position) then
            player.driving = false
          end
          vehicle.orientation = vehicle.orientation + 0.5
        elseif player.character then
          new_position = surface.find_non_colliding_position(player.character.name, new_position, 32, 1) or new_position
          player.teleport(new_position)
        else
          player.teleport(new_position)
        end
        local time_left = ceil((global.end_no_rush-game.tick)/3600)
        player.print({"no-rush-teleport", time_left})
      end
    end
  end
end

local function check_update_production_score()
  local tick = game.tick
  local new_scores = production_score.get_production_scores(global.price_list)
  -- local scale = statistics_period / 60 TODO: recheck
  local index = tick % (60 * statistics_period)

  if not (global.scores and global.average_score) then
    local average_score = {}
    local scores = {}
    for name, score in pairs(new_scores) do
      scores[name] = {}
      local score_n = scores[name]
      average_score[name] = score * statistics_period
      for k = 0, statistics_period do
        score_n[k * 60] = score
      end
    end
    global.scores = scores
    global.average_score = average_score
  end

  local scores = global.scores
  local average_score = global.average_score
  for name, score in pairs(new_scores) do
    local old_amount = scores[name][index]
    if not old_amount then
      --Something went wrong, reinitialize it next update
      global.scores = nil
      global.average_score = nil
      return
    end
    average_score[name] = (average_score[name] + score) - old_amount
    scores[name][index] = score
  end

  global.production_scores = new_scores

  for _, player in pairs(game.connected_players) do
    update_production_score_frame(player)
  end

  local required = global.game_config.required_production_score
  if required > 0 then
    for team_name, score in pairs(global.production_scores) do
      if score >= required then
        team_won(team_name)
      end
    end
  end
  if global.game_config.time_limit > 0 and tick > global.round_start_tick + (global.game_config.time_limit * 60 * 60) then
    local winner = {"none"}
    local winning_score = 0
    for team_name, score in pairs(global.production_scores) do
      if score > winning_score then
        winner = team_name
        winning_score = score
      end
    end
    team_won(winner)
  end
end

local function check_update_oil_harvest_score()
  local item_to_check = "crude-oil-barrel"
  if not game.item_prototypes[item_to_check] then error("Playing oil harvest game mode when crude oil barrels don't exist") end
  local scores = {}
  for _, team in pairs(global.teams) do
    local force = game.forces[team.name]
    if force then
      local statistics = force.item_production_statistics
      local input = statistics.get_input_count(item_to_check)
      local output = statistics.get_output_count(item_to_check)
      scores[team.name] = input - output
    end
  end

  global.oil_harvest_scores = scores
  for _, player in pairs(game.connected_players) do
    update_oil_harvest_frame(player)
  end

  local required = global.game_config.required_oil_barrels
  if required > 0 then
    for team_name, score in pairs(global.oil_harvest_scores) do
      if score >= required then
        team_won(team_name)
      end
    end
  end

  if global.game_config.time_limit > 0 and game.tick > (global.round_start_tick + (global.game_config.time_limit * 60 * 60)) then
    local winner = {"none"}
    local winning_score = 0
    for team_name, score in pairs(global.oil_harvest_scores) do
      if score > winning_score then
        winner = team_name
        winning_score = score
      end
    end
    team_won(winner)
  end
end

local function check_update_space_race_score()
  local item_to_check = "satellite"
  if not game.item_prototypes[item_to_check] then error("Playing space race when satellites don't exist") end
  local scores = {}
  local forces = game.forces
  for _, team in pairs(global.teams) do
    local force = forces[team.name]
    if force and force.valid then
      scores[team.name] = force.get_item_launched(item_to_check)
    end
  end
  global.space_race_scores = scores

  for _, player in pairs(game.connected_players) do
    update_space_race_frame(player)
  end

  local required = global.game_config.required_satellites_sent
  if required > 0 then
    for team_name, score in pairs(global.space_race_scores) do
      if score >= required then
        team_won(team_name)
      end
    end
  end
end

function finish_setup()
  if not global.finish_setup then return end
  local setup = global.force_setup or {step = 0, index = #global.teams}
  local surface = global.surface
  if ((global.finish_setup - game.tick) == 0) then
    final_setup_step()
    return
  end

  setup.step = setup.step + 1
  local name = global.teams[setup.index].name
  if not name then return end
  local force = game.forces[name]
  if not (force and force.valid) then return end

  if setup.step == 1 then
    duplicate_starting_area_entities(force)
  elseif setup.step == 2 then
    create_silo_for_force(force)
  elseif setup.step == 3 then
    -- local radius = get_starting_area_radius(true) --[[radius in tiles]]
    if global.game_config.reveal_team_positions then
      for _name, other_force in pairs(game.forces) do
        if not ignore_force_list[_name] then
          force.chart(surface, get_force_area(other_force))
        end
      end
    end
  elseif setup.step == 4 then
    create_wall_for_force(force)
  elseif setup.step == 5 then
    create_starting_chest(force)
  elseif setup.step == 6 then
    create_starting_turrets(force)
  elseif setup.step == 7 then
    create_starting_artillery(force)
  elseif setup.step == 8 then
    protect_force_area(force)
  elseif setup.step == 9 then
    force.friendly_fire = global.team_config.friendly_fire
    force.share_chart = global.team_config.share_chart
    local hide_crude_recipe_in_stats = global.game_config.game_mode.selected ~= "oil_harvest"
    local fill_recipe = force.recipes["fill-crude-oil-barrel"]
    if fill_recipe then
      fill_recipe.hidden_from_flow_stats = hide_crude_recipe_in_stats
    end
    local empty_recipe = force.recipes["empty-crude-oil-barrel"]
    if empty_recipe then
      empty_recipe.hidden_from_flow_stats = hide_crude_recipe_in_stats
    end
    
    local entities = surface.find_entities_filtered{force = "enemy", area = get_force_area(force)}
    for i=#entities, 1, -1 do
      entities[i].destroy()
    end

    setup.index = setup.index - 1
    setup.step = 0
  end
  global.force_setup = setup
end

function final_setup_step()
  local surface = global.surface
  --duplicate_starting_area_entities()
  global.finish_setup = nil
  game.print({"map-ready"})
  global.setup_finished = true
  global.round_start_tick = game.tick

  for _, player in pairs(game.connected_players) do
    if player.valid then
      destroy_player_gui(player)
      player.teleport({0, 1000}, "Lobby")
      choose_joining_gui(player)
    end
  end

  global.end_no_rush = game.tick + (global.game_config.no_rush_time * 60 * 60)
  if global.game_config.no_rush_time > 0 then
    global.surface.peaceful_mode = true
    game.forces.enemy.kill_all_units()
    game.print({"no-rush-begins", global.game_config.no_rush_time})
  end

  create_exclusion_map()

  if global.game_config.base_exclusion_time > 0 then
    global.check_base_exclusion = true
    game.print({"base-exclusion-begins", global.game_config.base_exclusion_time})
  end

  if global.game_config.reveal_map_center then
    local radius = global.map_config.average_team_displacement / 2
    local origin = global.spawn_offset
    local area = {{origin.x - radius, origin.y - radius}, {origin.x + (radius - 32), origin.y + (radius - 32)}}
    for _, force in pairs(game.forces) do
      force.chart(surface, area)
    end
  end

  global.space_race_scores = {}
  global.oil_harvest_scores = {}
  global.genocide_biters_score = {}
  global.force_setup = nil
  for _, team in pairs(global.teams) do
    global.genocide_biters_score[team.name] = 0
  end
  global.production_scores = {}
  if global.team_config.defcon_mode then
    defcon_research()
  end

  script.raise_event(events.on_round_start, {})
end

function update_progress_bar()
  if not global.progress then return end
  local percent = global.progress
  local finished = (percent >= 1)
  function update_bar_gui(gui)
    if gui.progress_bar then
      if finished then
        gui.progress_bar.destroy()
      else
        gui.progress_bar.bar.value = percent
      end
      return
    end
    if finished then return end
    local frame = gui.add{type = "frame", name = "progress_bar", caption = {"progress-bar"}}
    local bar = frame.add{type = "progressbar", size = 100, value = percent, name = "bar"}
  end
  for _, player in pairs(game.players) do
    update_bar_gui(player.gui.center)
  end
  if finished then
    global.progress = nil
    global.setup_duration = nil
    global.finish_tick = nil
  end
end

function create_silo_for_force(force)
  local condition = global.game_config.game_mode.selected
  local need_silo = {conquest = true, space_race = true, last_silo_standing = true}
  if not need_silo[condition] then return end
  if not force then return end
  if not force.valid then return end
  local surface = global.surface
  local origin = force.get_spawn_position(surface)
  local offset_x = 0
  local offset_y = -25
  local silo_position = {x = origin.x+offset_x, y = origin.y+offset_y}
  local area = {{silo_position.x - 5, silo_position.y - 6}, {silo_position.x + 6, silo_position.y + 6}}
  for _, entity in pairs(surface.find_entities_filtered({area = area})) do
    entity.destroy()
  end

  local silo_name = "rocket-silo"
  if not game.entity_prototypes[silo_name] then log("Silo not created as "..silo_name.." is not a valid entity prototype") return end
  local silo = surface.create_entity{name = silo_name, position = silo_position, force = force}
  silo.minable = false
  silo.backer_name = tostring(force.name)

  if global.game_config.game_mode.selected == "space_race" then
    silo.destructible = false
  end
  if not global.silos then global.silos = {} end
  global.silos[force.name] = silo

  local tile_name = "refined-hazard-concrete-left"
  if not game.tile_prototypes[tile_name] then tile_name = get_walkable_tile() end

  local tiles_2 = {}
  for X = -5, 5 do
    for Y = -6, 5 do
      tinsert(tiles_2, {name = tile_name, position = {silo_position.x + X, silo_position.y + Y}})
    end
  end
  set_tiles_safe(surface, tiles_2)
end

function setup_research(force)
  if not force then return end
  if not force.valid then return end
  local tier = global.team_config.research_level.selected
  local index
  local set = (tier ~= "none")
  for _, name in pairs(global.team_config.research_level.options) do
    if global.research_ingredient_list[name] ~= nil then
      global.research_ingredient_list[name] = set
    end
    if name == tier then set = false end
  end
  --[[Unlocks all research, and then unenables them based on a blacklist]]
  force.research_all_technologies()
  for _, technology in pairs(force.technologies) do
    for _, ingredient in pairs(technology.research_unit_ingredients) do
      if not global.research_ingredient_list[ingredient.name] then
        technology.researched = false
        break
      end
    end
  end
end

function create_starting_turrets(force)
  if not global.game_config.team_turrets then return end
  if not (force and force.valid) then return end
  local turret_name = "gun-turret"
  if not game.entity_prototypes[turret_name] then return end
  local ammo_name = global.game_config.turret_ammunition.selected or "firearm-magazine"
  if not game.item_prototypes[ammo_name] then return end
  local surface = global.surface
  local height = surface.map_gen_settings.height / 2
  local width = surface.map_gen_settings.width / 2
  -- local height = global.map_config.map_height / 2
  -- local width = global.map_config.map_width / 2
  local origin = force.get_spawn_position(surface)
  local radius = get_starting_area_radius(true) - 18 --[[radius in tiles]]
  local limit = min(width - abs(origin.x), height - abs(origin.y)) - 6
  radius = min(radius, limit)
  local positions = {}
  local Xo = origin.x
  local Yo = origin.y
  for X = -radius, radius do
    local Xt = X + Xo
    if X == -radius then
      for Y = -radius, radius do
        local Yt = Y + Yo
        if (Yt + 16) % 32 ~= 0 and Yt % 8 == 0 then
          tinsert(positions, {x = Xo - radius, y = Yt, direction = defines.direction.west})
          tinsert(positions, {x = Xo + radius, y = Yt, direction = defines.direction.east})
        end
      end
    elseif (Xt + 16) % 32 ~= 0 and Xt % 8 == 0 then
      tinsert(positions, {x = Xt, y = Yo - radius, direction = defines.direction.north})
      tinsert(positions, {x = Xt, y = Yo + radius, direction = defines.direction.south})
    end
  end
  local tiles = {}
  local tile_name = "hazard-concrete-left"
  if not game.tile_prototypes[tile_name] then tile_name = get_walkable_tile() end
  local stack = {name = ammo_name, count = 20}
  for _, position in pairs(positions) do
    local area = {{x = position.x - 1, y = position.y - 1},{x = position.x + 1, y = position.y + 1}}
    for _, entity in pairs(surface.find_entities_filtered{area = area, force = "neutral"}) do
      entity.destroy()
    end
    local turret = surface.create_entity{name = turret_name, position = position, force = force, direction = position.direction}
    turret.insert(stack)
    tinsert(tiles, {name = tile_name, position = {x = position.x, y = position.y}})
    tinsert(tiles, {name = tile_name, position = {x = position.x - 1, y = position.y}})
    tinsert(tiles, {name = tile_name, position = {x = position.x, y = position.y - 1}})
    tinsert(tiles, {name = tile_name, position = {x = position.x - 1, y = position.y - 1}})
  end
  set_tiles_safe(surface, tiles)
end

function create_starting_artillery(force)
  if not global.game_config.team_artillery then return end
  if not (force and force.valid) then return end
  local turret_name = "artillery-turret"
  if not game.entity_prototypes[turret_name] then return end
  local ammo_name = "artillery-shell"
  if not game.item_prototypes[ammo_name] then return end
  local surface = global.surface
  -- local height = surface.map_gen_settings.height / 2
  -- local width = surface.map_gen_settings.width / 2
  --local height = global.map_config.map_height / 2 --???
  --local width = global.map_config.map_width / 2 --???
  local origin = force.get_spawn_position(surface)
  -- local size = global.map_config.starting_area_size.selected
  local radius = get_starting_area_radius() - 1 --[[radius in chunks]]
  if radius < 1 then return end
  local positions = {}
  -- local tile_positions = {}
  for x = -radius, 0 do
    if x == -radius then
      for y = -radius, 0 do
        tinsert(positions, {x = 1 + origin.x + 32*x, y = 1 + origin.y + 32*y})
      end
    else
      tinsert(positions, {x = 1 + origin.x + 32*x, y = 1 + origin.y - radius*32})
    end
  end
  for x = 1, radius do
    if x == radius then
      for y = -radius, -1 do
        tinsert(positions, {x = -2 + origin.x + 32*x, y = 1 + origin.y + 32*y})
      end
    else
      tinsert(positions, {x = -2 + origin.x + 32*x, y = 1 + origin.y - radius*32})
    end
  end
  for x = -radius, -1 do
    if x == -radius then
      for y = 1, radius do
        tinsert(positions, {x = 1 + origin.x + 32*x, y = -2 + origin.y + 32*y})
      end
    else
      tinsert(positions, {x = 1 + origin.x + 32*x, y = -2 + origin.y + radius*32})
    end
  end
  for x = 0, radius do
    if x == radius then
      for y = 0, radius do
        tinsert(positions, {x = -2 + origin.x + 32*x, y = -2 + origin.y + 32*y})
      end
    else
      tinsert(positions, {x = -2 + origin.x + 32*x, y = -2 + origin.y + radius*32})
    end
  end
  local stack = {name = ammo_name, count = 20}
  local tiles = {}
  local tile_name = "hazard-concrete-left"
  if not game.tile_prototypes[tile_name] then tile_name = get_walkable_tile() end
  local artillery_minable = global.game_config.team_artillery_minable
  for _, position in pairs(positions) do
    local turret = surface.create_entity{name = turret_name, position = position, force = force, direction = position.direction}
    turret.minable = artillery_minable
    turret.insert(stack)
    for _, entity in pairs(surface.find_entities_filtered{area = turret.selection_box, force = "neutral"}) do
      entity.destroy()
    end
    for x = -1, 1 do
      for y = -1, 1 do
        tinsert(tiles, {name = tile_name, position = {position.x + x, position.y + y}})
      end
    end
  end
  set_tiles_safe(surface, tiles)
end

function create_wall_for_force(force)
  if not global.game_config.team_walls then return end
  if not force.valid then return end
  local surface = global.surface
  local height = surface.map_gen_settings.height / 2
  local width = surface.map_gen_settings.width / 2
  -- local height = global.map_config.map_height / 2
  -- local width = global.map_config.map_width / 2
  local origin = force.get_spawn_position(surface)
  -- local size = global.map_config.starting_area_size.selected
  local radius = get_starting_area_radius(true) - 13 --[[radius in tiles]]
  local limit = min(width - abs(origin.x), height - abs(origin.y)) - 1
  radius = min(radius, limit)
  if radius < 2 then return end
  local perimeter_top = {}
  local perimeter_bottom = {}
  local perimeter_left = {}
  local perimeter_right = {}
  local tiles = {}
  for X = -radius, radius - 1 do
    tinsert(perimeter_top, {x = origin.x + X, y = origin.y - radius})
    tinsert(perimeter_bottom, {x = origin.x + X, y = origin.y + (radius-1)})
  end
  for Y = -radius, radius - 1 do
    tinsert(perimeter_left, {x = origin.x - radius, y = origin.y + Y})
    tinsert(perimeter_right, {x = origin.x + (radius-1), y = origin.y + Y})
  end
  local tile_name = "concrete"
  if not game.tile_prototypes[tile_name] then tile_name = get_walkable_tile() end
  local areas = {
    {{perimeter_top[1].x, perimeter_top[1].y - 1}, {perimeter_top[#perimeter_top].x, perimeter_top[1].y + 3}},
    {{perimeter_bottom[1].x, perimeter_bottom[1].y - 3}, {perimeter_bottom[#perimeter_bottom].x, perimeter_bottom[1].y + 1}},
    {{perimeter_left[1].x - 1, perimeter_left[1].y}, {perimeter_left[1].x + 3, perimeter_left[#perimeter_left].y}},
    {{perimeter_right[1].x - 3, perimeter_right[1].y}, {perimeter_right[1].x + 1, perimeter_right[#perimeter_right].y}},
  }

  local filter = {area = nil}
  for _, area in pairs(areas) do
    filter.area = area
    local entities = surface.find_entities_filtered(filter)
    for i=#entities, 1, -1 do
      entities[i].destroy()
    end
  end
  local wall_name = "stone-wall"
  local gate_name = "gate"
  if not game.entity_prototypes[wall_name] then
    log("Setting walls cancelled as "..wall_name.." is not a valid entity prototype")
    return
  end
  if not game.entity_prototypes[gate_name] then
    log("Setting walls cancelled as "..gate_name.." is not a valid entity prototype")
    return
  end

  for i, position in ipairs(perimeter_left) do
    if (i ~= 1) and (i ~= #perimeter_left) then
      tinsert(tiles, {name = tile_name, position = {position.x + 2, position.y}})
      tinsert(tiles, {name = tile_name, position = {position.x + 1, position.y}})
    end
    local mod = position.y % 32
    if (mod == 14) or (mod == 15) or (mod == 16) or (mod == 17) then
      surface.create_entity{name = gate_name, position = position, direction = 0, force = force}
    else
      surface.create_entity{name = wall_name, position = position, force = force}
    end
  end
  for i, position in ipairs(perimeter_right) do
    if (i ~= 1) and (i ~= #perimeter_right) then
      tinsert(tiles, {name = tile_name, position = {position.x - 2, position.y}})
      tinsert(tiles, {name = tile_name, position = {position.x - 1, position.y}})
    end
    local mod = position.y % 32
    if (mod == 14) or (mod == 15) or (mod == 16) or (mod == 17) then
      surface.create_entity{name = gate_name, position = position, direction = 0, force = force}
    else
      surface.create_entity{name = wall_name, position = position, force = force}
    end
  end
  for i, position in ipairs(perimeter_top) do
    if (i ~= 1) and (i ~= #perimeter_top) then
      tinsert(tiles, {name = tile_name, position = {position.x, position.y + 2}})
      tinsert(tiles, {name = tile_name, position = {position.x, position.y + 1}})
    end
    local mod = position.x % 32
    if (mod == 14) or (mod == 15) or (mod == 16) or (mod == 17) then
      surface.create_entity{name = gate_name, position = position, direction = 2, force = force}
    else
      surface.create_entity{name = wall_name, position = position, force = force}
    end
  end
  for i, position in ipairs(perimeter_bottom) do
    if (i ~= 1) and (i ~= #perimeter_bottom) then
      tinsert(tiles, {name = tile_name, position = {position.x, position.y - 2}})
      tinsert(tiles, {name = tile_name, position = {position.x, position.y - 1}})
    end
    local mod = position.x % 32
    if (mod == 14) or (mod == 15) or (mod == 16) or (mod == 17) then
      surface.create_entity{name = gate_name, position = position, direction = 2, force = force}
    else
      surface.create_entity{name = wall_name, position = position, force = force}
    end
  end
  set_tiles_safe(surface, tiles)
end

function spairs(t, order)
  local keys = {}
  for k in pairs(t) do keys[#keys+1] = k end
  if order then
    table.sort(keys, function(a, b) return order(t, a, b) end)
  else
    table.sort(keys)
  end
  local i = 0
  return function()
    i = i + 1
    if keys[i] then
      return keys[i], t[keys[i]]
    end
  end
end

function verify_oil_harvest()
  if game.item_prototypes["crude-oil-barrel"] and game.entity_prototypes["crude-oil"] and game.recipe_prototypes["fill-crude-oil-barrel"] and game.recipe_prototypes["empty-crude-oil-barrel"] then return end
  local options = global.game_config.game_mode.options
  for k, mode in pairs(options) do
    if mode == "oil_harvest" then
      table.remove(options, k)
      log("Oil harvest mode removed from scenario, as oil barrels and crude oil were not present in this configuration.")
      break
    end
  end
end

local function oil_harvest_prune_oil(event)
  local area = event.area
  local center = {x = (area.left_top.x + area.right_bottom.x) / 2, y = (area.left_top.y + area.right_bottom.y) / 2}
  local origin = global.spawn_offset
  local distance_from_center = (((center.x - origin.x) ^ 2) + ((center.y - origin.y) ^ 2)) ^ 0.5
  if distance_from_center > global.map_config.average_team_displacement / 2.5 then
    local entities = event.surface.find_entities_filtered{area = area, name = "crude-oil"}
    for i=#entities, 1, -1 do
      entities[i].destroy()
    end
  end
end

function roll_starting_area()
  local name = "reroll_surface_1"
  local delete = "reroll_surface_2"
  if game.get_surface(name) ~= nil then
    delete = "reroll_surface_1"
    name = "reroll_surface_2"
  end

  local settings = game.get_surface(1).map_gen_settings
  settings.starting_area = global.map_config.starting_area_size.selected
  settings.width = global.map_config.map_width
  settings.height = global.map_config.map_height
  settings.seed = global.map_config.map_seed
  if settings.seed == 0 then
    settings.seed = math.random(999999999)
  end

  for _, player in pairs(game.connected_players) do
    local frame = get_config_holder(player)
    if frame then
      if frame.map_config_gui then
        frame.map_config_gui.config_table.map_seed_box.text = tostring(settings.seed)
      else
        log("map_config_gui not founded for "..player.name)
        if player.admin then
          game.print("map_config_gui not founded for "..player.name)
        end
      end
    end
  end

  if global.map_config.biters_disabled then
    settings.autoplace_controls["enemy-base"].size = "none"
  end
  global.copy_surface = game.create_surface(name, settings)
  --local radius = get_starting_area_radius() --[[radius in chunks]]
  global.copy_surface.request_to_generate_chunks({0,0}, 7)
  global.copy_surface.destroy_decoratives({{-500,-500},{500,500}})
  global.roll_surface = global.copy_surface

  for _, player in pairs(game.connected_players) do
    if player.admin then
     player.teleport({0,0}, global.copy_surface)
    end
  end

  if game.get_surface(delete) then
    game.delete_surface(delete)
  end
end

function delete_roll_surfaces()
  for _, name in pairs({"reroll_surface_1", "reroll_surface_2"}) do
    if game.get_surface(name) then
      game.delete_surface(name)
    end
  end
end

local function reroll_starting_area(event, player, gui)
  local frame = get_config_holder(player)
  if not parse_config_from_gui(frame.map_config_gui, global.map_config) then return end
  for _, name in pairs({"map_seed", "map_height", "map_width"}) do
    if global.map_config[name] < 0 then
      player.print({"value-below-zero", {name}})
      return
    end
  end
  roll_starting_area()


  for _, _player in pairs(game.connected_players) do
    if _player.admin then
      _player.print({"player-rerolled", player.name})
    end
  end
end

function create_change_surface_config_gui(player)
  local gui = mod_gui.get_frame_flow(player)
  if gui.change_surface_config then
    gui.change_surface_config.destroy()
  end
  local frame = gui.add{type = "frame", name = "change_surface_config", caption = {"change_surface_config"}, direction = "vertical"}
  local button = frame.add{type = "button", name = "open_config_again", caption = {"gui.yes"}}
  button.style.font = "default"
  button.style.top_padding = 0
  button.style.bottom_padding = 0
end

local function change_surface(event, player)
  if global.roll_surface == nil then
    roll_starting_area()
  end
  player.set_controller{type = defines.controllers.god}
  player.cheat_mode = true
  local frame = get_config_holder(player)
  if not parse_config_from_gui(frame.map_config_gui, global.map_config) then return end
  if not parse_config_from_gui(frame.game_config_gui, global.game_config) then return end
  if not parse_config_from_gui(frame.team_config_gui, global.team_config) then return end
  --not_fully_config_confirm(gui)
  destroy_config(player)
  create_change_surface_config_gui(player)
  local force = player.force
  force.reset()
  force.research_all_technologies()
  force.enable_all_recipes()
end

local function open_config_again(event, player)
  player.cheat_mode = false
  player.force.reset()
  player.set_controller{type = defines.controllers.ghost}
  player.force = game.forces["player"]
  local gui = mod_gui.get_frame_flow(player)
  if gui.change_surface_config then
    gui.change_surface_config.destroy()
  end
  local gui = player.gui.left
  if gui.frame_customizing_force then
    gui.frame_customizing_force.destroy()
  end
  create_config_gui(player)
end

pvp.button_press_functions = {
  add_team_button = add_team_button_press,
  admin_button = admin_button_press,
  auto_assign_button = function(event, player, gui) gui.parent.destroy() auto_assign(player) end,
  balance_options_cancel = function(event, player, gui) toggle_balance_options_gui(player) end,
  balance_options_confirm = function(event, player, gui) if set_balance_settings(player) then toggle_balance_options_gui(player) end end,
  balance_options = function(event, player, gui) toggle_balance_options_gui(player) end,
  config_confirm = function(event, player, gui) config_confirm(player) end,
  join_spectator = function(event, player, gui) gui.parent.destroy() spectator_join(player) end,
  objective_button = objective_button_press,
  list_teams_button = list_teams_button_press,
  oil_harvest_button = oil_harvest_button_press,
  space_race_button = space_race_button_press,
  production_score_button = production_score_button_press,
  random_join_button = function(event, player, gui) gui.parent.destroy() random_join(player) end,
  spectator_join_team_button = function(event, player, gui) choose_joining_gui(player) end,
  pvp_export_button = function(event, player, gui) export_button_press(player) end,
  pvp_export_close = function(event, player, gui) player.gui.center.clear() create_config_gui(player) end,
  pvp_import_button = function(event, player, gui) import_button_press(player) end,
  pvp_import_confirm = function(event, player, gui) import_confirm(player) end,
  reroll_starting_area = reroll_starting_area,
  change_surface = change_surface,
  open_config_again = open_config_again,
  become_GM = function(event, player, gui) gui.destroy() GM_join(player) end,
  genocide_biters_button = genocide_of_biters.button_press,
}
-- From require("story") functions recreate_entities_PvP and export_entities \/
--
function recreate_entities_PvP(array, param, bool)
  if not param then param = {} end
  local offset = param.offset or {0,0}
  local surface = param.surface or game.get_surface(1)
  local force = param.force or "player"
  local created_entities = {}
  local created_count = 1
  local remaining = {}
  local remaining_count = 1
  local index_map = {}
  local filter = param.filter
  local filter_map = {}
  if filter then
    for _, name in pairs(filter) do
      filter_map[name] = true
    end
  end
  for k, entity in pairs(array) do
    if not filter or filter_map[entity.name] then
      local save_position = {x = entity.position.x, y = entity.position.y}
      entity.position.x = entity.position.x + (offset[1] or offset.x)
      entity.position.y = entity.position.y + (offset[2] or offset.y)
      entity.force = force
      entity.expires = entity.expires or false
      if not param.check_can_place or surface.can_place_entity(entity) then
        if not entity.index then entity.index = -1 end
        local created = false
        if bool or (entity.name ~= "locomotive" and entity.name ~= "rail-signal") then
          created = surface.create_entity(entity)
          index_map[entity.index] = created
        end
        entity.position = save_position
        if created then
          index_map[entity.index] = created
          if entity.filters then
            for _, filter in pairs(entity.filters) do
              created.set_filter(filter.index, filter.name)
            end
          end
          if entity.parameters then
            created.parameters = entity.parameters
          end
          if entity.alert_parameters then
            created.alert_parameters = entity.alert_parameters
          end
          if entity.amount then
            created.amount = entity.amount
          end
          if entity.equipment then
            for i = 1, #entity.equipment do
              created.grid.put{name = entity.equipment[i].name, position = entity.equipment[i].position}
            end
          end
          if entity.inventory then
            for index, contents in pairs(entity.inventory) do
              local inventory = created.get_inventory(index)
              if inventory then
                for name, count in pairs(contents) do
                  created.insert({name = name, count = count})
                end
              end
            end
          end
          if entity.electric_buffer_size then
            created.electric_buffer_size = entity.electric_buffer_size
          end
          if entity.power_production then
            created.power_production = entity.power_production
          end
          if entity.power_usage then
            created.power_usage = entity.power_usage
          end
          if entity.line_contents then
            for k, contents in pairs(entity.line_contents) do
              local line = created.get_transport_line(k)
              for name, count in pairs(contents) do
                for i = 0, count-1 do
                  line.insert_at((0.1+i)/count, {name = name, count = 1})
                end
              end
            end
          end
          if entity.backer_name then
            created.backer_name = entity.backer_name
          end
          if entity.color then
            created.color = entity.color
          end
          if entity.recipe then
            created.set_recipe(entity.recipe)
          end
          if entity.inventoryBar ~= nil then
            created.get_inventory(defines.inventory.chest).setbar(entity.inventoryBar)
          end
          created.minable = entity.minable
          created.rotatable = entity.rotatable
          created.operable = entity.operable
          created.destructible = entity.destructible
          if entity.schedule then
            created.train.schedule = entity.schedule
            created.train.speed = entity.speed
            created.train.manual_mode = entity.manual_mode
          end
          created_entities[created_count] = created
          created_count = created_count + 1
        else
          remaining[remaining_count] = entity
          remaining_count = remaining_count + 1
        end
      end
    end
  end
  if not bool then
    for _, entity in pairs(recreate_entities_PvP(remaining, param, true)) do
      created_entities[created_count] = entity
      created_count = created_count + 1
    end
  end
  for _, entity in pairs(array) do
    local created = index_map[entity.index]
    if created and created.valid then
      if entity.circuit_connection_definitions then
        for index, definition in pairs(entity.circuit_connection_definitions) do
          entity_to_connect = index_map[index]
          if entity_to_connect.valid then
            created.connect_neighbour({wire = definition.wire, target_entity = entity_to_connect, source_circuit_id = definition.source_circuit_id, target_circuit_id = definition.target_circuit_id})
          end
        end
      end
    end
  end
  return created_entities
end

function export_entities_PvP(param)
  if not param then param = {} end
  local surface = param.surface or game.get_surface(1)
  local item = surface.create_entity{name = "item-on-ground", position = {-400, 0}, stack = "blueprint", force = "player"}
  local blueprint = item.stack
  local entities = param.entities
  if not entities then
    if param.area then
      entities = surface.find_entities_filtered{area = param.area}
    else
      entities = surface.find_entities()
    end
  end
  local ignore = param.ignore or {
    player = true,
    particle = true,
    projectile = true,
    ["item-request-proxy"] = true,
    explosion = true
  }

  local get_inventory = function(entity)
    if not entity.valid then return nil end
    local inventory = {}
    local get_inventory = entity.get_inventory
    for k = 1, 10 do
      local inv = get_inventory(k)
      if inv then
        inventory[k] = inv.get_contents()
      end
    end
    if #inventory > 0 then
      return inventory
    else
      return nil
    end
  end

  local exported = {}
  local index_map = {}
  local count = 1
  for _, entity in pairs(entities) do
    if entity.valid then
      if entity ~= item and not (ignore[entity.type]) then
        local info = {}
        blueprint.create_blueprint{surface = surface, force = "player", area = entity.bounding_box}
        list = blueprint.get_blueprint_entities()
        if list then
          local this = false
          for i, listed in pairs(list) do
            if listed.name == entity.name and entity.type ~= "curved-rail" and entity.type ~= "straight-rail" then
              this = list[i]
              break
            end
          end
          if this then
            info = this
          end
        end
        if entity.direction and entity.direction ~= 0 then
          info.direction = entity.direction
        end
        info.index = count
        local unit_number = entity.unit_number
        if unit_number then
          index_map[unit_number] = count
        end
        info.name = entity.name
        if entity.type == "resource" then
          info.amount = entity.amount
        elseif entity.type == "entity-ghost" then
          info.inner_name = entity.ghost_name
        elseif entity.type == "item-entity" then
          info.stack = {name = entity.stack.name, count = entity.stack.count}
        elseif entity.type == "transport-belt" or entity.type == "underground-belt" then
          info.line_contents = {}
          for k = 1, 2 do
            local line = entity.get_transport_line(k)
            info.line_contents[k] = line.get_contents()
            line.clear()
          end
          if entity.type == "underground-belt" then
            info.type = entity.belt_to_ground_type
          end
        elseif entity.type == "splitter" then
          info.line_contents = {}
          for k = 1, 8 do
            local line = entity.get_transport_line(k)
            info.line_contents[k] = line.get_contents()
            line.clear()
          end
        elseif entity.type == "locomotive" then
          info.schedule = entity.train.schedule
          info.speed = entity.train.speed
          info.manual_mode = entity.train.manual_mode
          info.direction = floor(0.5+entity.orientation*8)%8
        elseif entity.name == "flying-text" then
          info.text = ""
        elseif entity.type == "assembling-machine" then
          if entity.get_recipe() then
            info.recipe = entity.get_recipe().name
          end
        elseif entity.type == "programmable-speaker" then
          info.parameters = entity.parameters
          info.alert_parameters = entity.alert_parameters
        elseif entity.type == "electric-energy-interface" then
          info.electric_buffer_size = entity.electric_buffer_size
          info.power_production = entity.power_production
          info.power_usage = entity.power_usage
        end
        if entity.grid then
          info.equipment = entity.grid.equipment
        end
        info.color = entity.color
        info.force = entity.force.name
        info.position = entity.position
        info.inventory = get_inventory(entity)
        if entity.get_inventory(defines.inventory.chest) then
          if entity.get_inventory(defines.inventory.chest).hasbar() then
            info.inventoryBar = entity.get_inventory(defines.inventory.chest).getbar()
          end
        end
        info.backer_name = entity.backer_name
        info.minable = entity.minable
        info.rotatable = entity.rotatable
        info.operable = entity.operable
        info.destructible = entity.destructible
        info.entity_number = nil
        exported[count] = info
        count = count + 1
      end
    end
  end
  for _, entity in pairs(entities) do
    if entity.valid and entity.circuit_connected_entities and entity.unit_number then
      local entity_index = index_map[entity.unit_number]
      if entity_index then
        local connection_definitions = {}
        for _, definition in pairs(entity.circuit_connection_definitions) do
          local unit_number = definition.target_entity.unit_number
          if unit_number then
            local index = index_map[unit_number]
            if index then
              connection_definitions[index] = {
                wire = definition.wire,
                source_circuit_id = definition.source_circuit_id,
                target_circuit_id = definition.target_circuit_id
              }
            end
          end
        end
        if #connection_definitions > 0 then
          exported[entity_index].circuit_connection_definitions = connection_definitions
        end
      end
    end
  end
  -- for _, entity in pairs(entities) do
  --   if entity.valid then
  --     if entity ~= item and not (ignore[entity.type]) then
  --       entity.destroy()
  --     end
  --   end
  -- end
  -- if item.valid then
  --   item.destroy()
  -- end
  return exported
end
--

local function prohibition_spawn_biters_in_starting_zone(entity)
  -- Need tests
  local x = entity.position.x
  local y = entity.position.y
  local forces = game.forces
  for _, team in pairs(global.teams) do
    local force = forces[team.name]
    local area = get_force_area(force)
    if ((x > area[1][1] and x < area[2][1]) and (y > area[1][2] and y < area[2][2])) then
      entity.destroy()
      return true
    end
  end
end

function duplicate_starting_area_entities(force)
  if not global.map_config.duplicate_starting_area_entities then return end
  local surface = global.surface
  local radius = get_starting_area_radius(true) --[[radius in tiles]]
  local temp_area = {{-radius, -radius}, {radius, radius}}
  local tiles = {}
  local counts = {}
  local tile_map = {}
  local entities = {}
  local tile_name = "grass-1"

  if global.roll_surface then
    local temp_surface = global.roll_surface
    -- entities = temp_surface.find_entities_filtered{area = temp_area, force = "neutral"}
    local ignore_counts = {
      ["concrete"] = true,
      ["water"] = true,
      ["deepwater"] = true,
      ["hazard-concrete-left"] = true,
      ["refined-hazard-concrete-left"] = true
    }
    -- TODO: check \/
    for name, tile in pairs(game.tile_prototypes) do
      tile_map[name] = tile.collision_mask["resource-layer"] ~= nil
      counts[name] = temp_surface.count_tiles_filtered{name = name, area = temp_area}
    end
    local top_count = 0
    for name, count in pairs(counts) do
      if not ignore_counts[name] then
        if count > top_count then
          top_count = count
          tile_name = name
        end
      end
    end

    for name, bool in pairs(tile_map) do
      if bool and counts[name] > 0 then
        for _, tile in pairs(temp_surface.find_tiles_filtered{area = temp_area, name = name}) do
          tinsert(tiles, tile)
        end
      end
    end

    local spawn = force.get_spawn_position(surface)
    local area_team = {{spawn.x - radius, spawn.y - radius}, {spawn.x + radius, spawn.y + radius}}

    temp_surface.clone_area{
      source_area = temp_area,
      destination_area = area_team,
      destination_surface = surface,
      destination_force = force,
      clone_tiles = false,
      clone_entities = true,
      clone_decoratives = true,
      clear_destination_entities = true,
      clear_destination_decoratives = true,
      expand_map = true,
      create_build_effect_smoke = false
    }
  else
    local temp_surface = game.get_surface(1)
    entities = temp_surface.find_entities_filtered{area = temp_area, force = "neutral"}
    local ignore_counts = {
      ["concrete"] = true,
      ["water"] = true,
      ["deepwater"] = true,
      ["hazard-concrete-left"] = true,
      ["refined-hazard-concrete-left"] = true
    }
    -- TODO: check \/
    for name, tile in pairs(game.tile_prototypes) do
      tile_map[name] = tile.collision_mask["resource-layer"] ~= nil
      counts[name] = temp_surface.count_tiles_filtered{name = name, area = temp_area}
    end
    local top_count = 0
    for name, count in pairs(counts) do
      if not ignore_counts[name] then
        if count > top_count then
          top_count = count
          tile_name = name
        end
      end
    end

    for name, bool in pairs(tile_map) do
      if bool and counts[name] > 0 then
        for _, tile in pairs(temp_surface.find_tiles_filtered{area = temp_area, name = name}) do
          tinsert(tiles, tile)
        end
      end
    end

    local spawn = force.get_spawn_position(surface)
    local area_team = {{spawn.x - radius, spawn.y - radius}, {spawn.x + radius, spawn.y + radius}}
    for _, entity in pairs(surface.find_entities_filtered{area = area_team, force = "neutral"}) do
      entity.destroy()
    end

    local set_tiles = {}
    for name, bool in pairs(tile_map) do
      if bool then
        for _, tile in pairs(surface.find_tiles_filtered{area = area_team, name = name}) do
          tinsert(set_tiles, {name = tile_name, position = {x = tile.position.x, y = tile.position.y}})
        end
      end
    end

    for _, tile in pairs(tiles) do
      local position = {x = tile.position.x + spawn.x, y = tile.position.y + spawn.y}
      tinsert(set_tiles, {name = tile.name, position = position})
    end

    surface.set_tiles(set_tiles)
    for _, entity in pairs(entities) do
      if entity.valid then
        local position = {entity.position.x + spawn.x, entity.position.y + spawn.y}
        local type = entity.type
        if type ~= "item-entity" then
          --local stack = (type == "item-entity" and entity.stack) or nil -- bug?
          local amount = (type == "resource" and entity.amount) or nil
          local cliff_orientation = (type == "cliff" and entity.cliff_orientation) or nil
          surface.create_entity{name = entity.name, position = position, force = "neutral", amount = amount, cliff_orientation = cliff_orientation}
        end
      end
    end
  end
end

local function check_spectator_chart()
  --if not global.game_config.allow_spectators then return end
  local force = game.forces.spectator
  if not (force and force.valid) then return end
  if #force.connected_players > 0 then
    force.chart_all(global.surface)
  end
end

function create_starting_chest(force)
  if not (force and force.valid) then return end
  local value = global.team_config.starting_chest.selected
  if value == "none" then return end
  local multiplier = global.team_config.starting_chest_multiplier
  if not (multiplier > 0) then return end
  local inventory = global.inventory_list[value]
  if not inventory then return end
  local surface = global.surface
  local chest_name = "logistic-chest-passive-provider"
  local prototype = game.entity_prototypes[chest_name]
  if not prototype then
    log("Starting chest "..chest_name.." is not a valid entity prototype, picking a new container from prototype list")
    for name, chest in pairs(game.entity_prototypes) do
      if chest.type == "container" then
        chest_name = name
        prototype = chest
        break
      end
    end
  end

  local bounding_box = prototype.collision_box
  local size = ceil(max(bounding_box.right_bottom.x - bounding_box.left_top.x, bounding_box.right_bottom.y - bounding_box.left_top.y))
  local origin = force.get_spawn_position(surface)
  origin.y = origin.y + 8
  local index = 1
  local position = {x = origin.x + get_chest_offset(index).x * size, y = origin.y + get_chest_offset(index).y * size}
  local chest = surface.create_entity{name = chest_name, position = position, force = force}
  for _, v in pairs(surface.find_entities_filtered{force = "neutral", area = chest.bounding_box}) do
    v.destroy()
  end
  local tiles = {}
  -- local grass = {}
  local tile_name = "refined-concrete"
  if not game.tile_prototypes[tile_name] then tile_name = get_walkable_tile() end
  tinsert(tiles, {name = tile_name, position = {x = position.x, y = position.y}})
  chest.destructible = false
  for name, count in pairs(inventory) do
    local count_to_insert = ceil(count*multiplier)
    local difference = count_to_insert - chest.insert{name = name, count = count_to_insert}
    while difference > 0 do
      index = index + 1
      position = {x = origin.x + get_chest_offset(index).x * size, y = origin.y + get_chest_offset(index).y * size}
      chest = surface.create_entity{name = chest_name, position = position, force = force}
      for _, v in pairs(surface.find_entities_filtered{force = "neutral", area = chest.bounding_box}) do
        v.destroy()
      end
      tinsert(tiles, {name = tile_name, position = {x = position.x, y = position.y}})
      chest.destructible = false
      difference = difference - chest.insert{name = name, count = difference}
    end
  end
  set_tiles_safe(surface, tiles)
end

function get_chest_offset(n)
  local offset_x = 0
  n = n / 2
  if n % 1 == 0.5 then
    offset_x = -1
    n = n + 0.5
  end
  local root = n^0.5
  local nearest_root = floor(root+0.5)
  local upper_root = ceil(root)
  local root_difference = abs(nearest_root^2 - n)
  if nearest_root == upper_root then
    x = upper_root - root_difference
    y = nearest_root
  else
    x = upper_root
    y = root_difference
  end
  local orientation = 2 * math.pi * (45/360)
  x = x * (2^0.5)
  y = y * (2^0.5)
  local rotated_x = floor(0.5 + x * math.cos(orientation) - y * math.sin(orientation))
  local rotated_y = floor(0.5 + x * math.sin(orientation) + y * math.cos(orientation))
  return {x = rotated_x + offset_x, y = rotated_y}
end

function get_walkable_tile()
  for name, tile in pairs(game.tile_prototypes) do
    if tile.collision_mask["player-layer"] == nil and not tile.items_to_place_this then
      return name
    end
  end
  error("No walkable tile in prototype list")
end

function set_tiles_safe(surface, tiles)
  local grass = get_walkable_tile()
  local grass_tiles = {}
  for k, tile in pairs(tiles) do
    grass_tiles[k] = {position = {x = (tile.position.x or tile.position[1]), y = (tile.position.y or tile.position[2])}, name = grass}
  end
  surface.set_tiles(grass_tiles, false)
  surface.set_tiles(tiles)
end

function create_exclusion_map()
  local surface = global.surface
  if not (surface and surface.valid) then return end
  local exclusion_map = {}
  local radius = get_starting_area_radius() --[[radius in chunks]]
  for _, team in pairs(global.teams) do
    local name = team.name
    local force = game.forces[name]
    if force then
      local origin = force.get_spawn_position(surface)
      local Xo = floor(origin.x / 32)
      local Yo = floor(origin.y / 32)
      for X = -radius, radius - 1 do
        Xb = X + Xo
        if not exclusion_map[Xb] then exclusion_map[Xb] = {} end
        for Y = -radius, radius - 1 do
          local Yb = Y + Yo
          exclusion_map[Xb][Yb] = name
        end
      end
    end
  end
  global.exclusion_map = exclusion_map
end

function set_button_style(button)
  if not button.valid then return end
  button.style.font = "default"
  button.style.top_padding = 0
  button.style.bottom_padding = 0
end

--TODO: check & change
local function check_restart_round()
  local time = global.game_config.auto_new_round_time
  if not (time > 0) then return end
  if game.tick < (global.game_config.auto_new_round_time * 60 * 60) + global.team_won then return end
  --for _, player in pairs(game.connected_players) do
    --if player.admin then return end
  --end -- need before function: end_round()
  end_round()
  destroy_config_for_all()
  prepare_next_round()
end

function team_won(name)
  global.team_won = game.tick
  if global.game_config.auto_new_round_time > 0 then
    game.print({"team-won-auto", name, global.game_config.auto_new_round_time})
  else
    game.print({"team-won", name})
  end
  script.raise_event(events.on_team_won, {name = name})
end


local function offset_respawn_position(player)
  --This is to help the spawn camping situations.
  if not player.character then return end
  local surface = player.surface
  local origin = player.force.get_spawn_position(surface)
  local radius = get_starting_area_radius(true) - 32
  if not (radius > 0) then return end
  local random_position = {origin.x + math.random(-radius, radius), origin.y + math.random(-radius, radius)}
  local position = surface.find_non_colliding_position(player.character.name, random_position, 32, 1)
  if not position then return end
  player.teleport(position)
end

function disband_team(force, desination_force)
  local count = 0
  local forces = game.forces
  for _, team in pairs(global.teams) do
    if forces[team.name] then
      count = count + 1
    end
  end
  if not (count > 1) then
    --Can't disband the last team.
    return
  end
  force.print{"join-new-team"}
  local players = global.players_to_disband or {}
  for _, player in pairs(force.players) do
    players[player.name] = true
  end
  global.players_to_disband = players
  if desination_force and force ~= desination_force then
    game.merge_forces(force, desination_force)
  else
    game.merge_forces(force, "neutral")
  end
end

recursive_data_check = function(new_data, old_data)
  for k, data in pairs(new_data) do
    if not old_data[k] then
      old_data[k] = data
    elseif type(data) == "table" then
      recursive_data_check(new_data[k], old_data[k])
    end
  end
end

check_cursor_for_disabled_items = function(event)
  if not global.disabled_items then return end
  local player = game.get_player(event.player_index)
  if not (player and player.valid) then return end
  local stack = player.cursor_stack
  if (stack and stack.valid_for_read) then
    if global.disabled_items[stack.name] then
      stack.clear()
    end
  end
end

-- TODO: change
local function add_pusher(gui)
  local pusher = gui.add{type = "flow"}
  pusher.style.horizontally_stretchable = true
end

local function recipe_picker_elem_update(gui, player)
  local flow = gui.parent
  if not flow then return end
  local frame = flow.parent
  if not (frame and frame.name == "production_score_frame") then return end
  if frame.recipe_check_frame then
    frame.recipe_check_frame.destroy()
  end
  if gui.elem_value == nil then
    return
  end
  --if player.force.recipes[gui.elem_value] == nil then return end
  local recipe = player.force.recipes[gui.elem_value]
  local recipe_frame = frame.add{type = "frame", direction = "vertical", style = "inside_shallow_frame", name = "recipe_check_frame"}
  local title_flow = recipe_frame.add{type = "flow"}
  title_flow.style.horizontal_align = "center"
  title_flow.style.horizontally_stretchable = true
  title_flow.add{type = "label", caption = recipe.localised_name} -- TODO: change style
  local table = recipe_frame.add{type = "table", column_count = 2, name = "recipe_checker_table"}
  table.draw_horizontal_line_after_headers = true
  table.draw_vertical_lines = true
  table.style.horizontal_spacing = 16
  table.style.vertical_spacing = 2
  table.style.left_padding = 4
  table.style.right_padding = 4
  table.style.top_padding = 4
  table.style.bottom_padding = 4
  table.style.column_alignments[1] = "center"
  table.style.column_alignments[2] = "center"
  table.add{type = "label", caption = {"ingredients"}, style = "bold_label"}
  table.add{type = "label", caption = {"products"}, style = "bold_label"}
  local ingredients = recipe.ingredients
  local products = recipe.products
  local prices = global.price_list
  local cost = 0
  local gain = 0
  local prototypes = {
    fluid = game.fluid_prototypes,
    item = game.item_prototypes
  }
  for k = 1, max(#ingredients, #products) do
    local ingredient = ingredients[k]
    local flow = table.add{type = "flow", direction = "horizontal"}
    if k == 1 then
      flow.style.top_padding = 8
    end
    flow.style.vertical_align = "center"
    if ingredient then
      local ingredient_price = prices[ingredient.name] or 0
      flow.add
      {
        type = "sprite-button",
        name = ingredient.type.."/"..ingredient.name,
        sprite = ingredient.type.."/"..ingredient.name,
        number = ingredient.amount,
        style = "slot_button",
        tooltip = {"", "1 ", prototypes[ingredient.type][ingredient.name].localised_name, " = ", util.format_number(floor(ingredient_price * 100) / 100)},
      }
      local price = ingredient.amount * (ingredient_price or 0)
      add_pusher(flow)
      flow.add{type = "label", caption = util.format_number(floor(price * 100) / 100)}
      cost = cost + price
    end
    local product = products[k]
    flow = table.add{type = "flow", direction = "horizontal"}
    if k == 1 then
      flow.style.top_padding = 8
    end
    flow.style.vertical_align = "center"
    if product then
      local amount = product.amount or product.probability * (product.amount_max + product.amount_min) / 2 or 0
      local product_price = prices[product.name] or 0
      flow.add
      {
        type = "sprite-button",
        name = product.type.."/"..product.name,
        sprite = product.type.."/"..product.name,
        number = amount,
        style = "slot_button",
        tooltip = {"", "1 ", prototypes[product.type][product.name].localised_name, " = ", util.format_number(floor(product_price * 100) / 100)},
        show_percent_for_small_numbers = true
      }
      add_pusher(flow)
      local price = amount * (product_price or 0)
      flow.add{type = "label", caption = util.format_number(floor(price * 100) / 100)}
      gain = gain + price
    end
  end
  local line = table.add{type = "table", column_count = 1}
  line.draw_horizontal_lines = true
  add_pusher(line)
  add_pusher(line)
  line.style.top_padding = 8
  line.style.bottom_padding = 4
  local line2 = table.add{type = "table", column_count = 1}
  line2.draw_horizontal_lines = true
  add_pusher(line2)
  add_pusher(line2)
  line2.style.top_padding = 8
  line2.style.bottom_padding = 4
  local cost_flow = table.add{type = "flow"}
  cost_flow.add{type = "label", caption = {"", {"cost"}, {"colon"}}}
  add_pusher(cost_flow)
  cost_flow.add{type = "label", caption = util.format_number(floor(cost * 100) / 100)}
  local gain_flow = table.add{type = "flow"}
  gain_flow.add{type = "label", caption = {"", {"gain"}, {"colon"}}}
  add_pusher(gain_flow)
  gain_flow.add{type = "label", caption = util.format_number(floor(gain * 100) / 100)}
  table.add{type = "flow"}
  local total_flow = table.add{type = "flow"}
  total_flow.add{type = "label", caption = {"", {"total"}, {"colon"}}, style = "bold_label"}
  add_pusher(total_flow)
  local total = total_flow.add{type = "label", caption = util.format_number(floor((gain-cost) * 100) / 100), style = "bold_label"}
  if cost > gain then
    total.style.font_color = {r = 1, g = 0.3, b = 0.3}
  end
end

local function check_on_built_protection(entity, player)
  local force = entity.force
  local name = get_chunk_map_position(entity.position)
  if not name then return end
  if force.name == name then return end
  local other_force = game.forces[name]
  if not other_force then return end
  if other_force.get_friend(force) then return end

  if not player.mine_entity(entity, true) then
    entity.destroy()
  end
  player.print({"enemy-building-restriction"})
  return true
end

local function check_defcon()
  local defcon_tick = global.last_defcon_tick
  if not defcon_tick then
    global.last_defcon_tick = game.tick
    return
  end
  local duration = max(60, (global.team_config.defcon_timer * 60 * 60))
  local tick_of_defcon = defcon_tick + duration
  local current_tick = game.tick
  local progress = max(0, min(1, 1 - (tick_of_defcon - current_tick) / duration))
  local tech = global.next_defcon_tech
  if tech and tech.valid then
    for _, team in pairs(global.teams) do
      local force = game.forces[team.name]
      if force then
        if force.current_research ~= tech.name then
          force.current_research = tech.name
        end
        force.research_progress = progress
      end
    end
  end
  if current_tick >= tick_of_defcon then
    defcon_research()
    global.last_defcon_tick = current_tick
  end
end

recursive_technology_prerequisite = function(tech)
  for name, prerequisite in pairs(tech.prerequisites) do
    if not prerequisite.researched then
      return recursive_technology_prerequisite(prerequisite)
    end
  end
  return tech
end

function defcon_research()
  local tech = global.next_defcon_tech
  if tech and tech.valid then
    local forces = game.forces
    for _, team in pairs(global.teams) do
      local force = forces[team.name]
      if force then
        local _tech = force.technologies[tech.name]
        if _tech then
          _tech.researched = true
        end
      end
    end
    local sound = "utility/research_completed"
    if game.is_valid_sound_path(sound) then
      game.play_sound({path = sound})
    end
    game.print({"defcon-unlock", tech.localised_name}, {r = 1, g = 0.5, b = 0.5})
  end

  local force
  local forces = game.forces
  for _, team in pairs(global.teams) do
    force = forces[team.name]
    if force and force.valid then
      break
    end
  end
  if not force then return end
  local available_techs = {}
  for name, _tech in pairs(force.technologies) do
    if _tech.enabled and _tech.researched == false then
      tinsert(available_techs, _tech)
    end
  end
  if #available_techs == 0 then return end
  local random_tech = available_techs[math.random(#available_techs)]
  if not random_tech then return end
  random_tech = recursive_technology_prerequisite(random_tech)
  global.next_defcon_tech = game.technology_prototypes[random_tech.name]
  for _, team in pairs(global.teams) do
    local _force = forces[team.name]
    if _force then
      _force.current_research = random_tech.name
    end
  end
end

function export_button_press(player)
  if not (player and player.valid) then return end
  if not parse_config(player) then return end
  local gui = player.gui.center
  gui.clear()
  local frame = gui.add{type = "frame", caption = {"gui.export-to-string"}, name = "pvp_export_frame", direction = "vertical"}
  local textfield = frame.add{type = "text-box"}
  textfield.word_wrap = true
  textfield.read_only = true
  textfield.style.height = player.display_resolution.height * 0.6
  textfield.style.width = player.display_resolution.width * 0.6
  local data = {
    game_config = global.game_config,
    team_config = global.team_config,
    map_config = global.map_config,
    modifier_list = global.modifier_list,
    teams = global.teams,
    disabled_items = global.disabled_items
  }
  textfield.text = util.encode(serpent.dump(data))
  frame.add{type = "button", caption = {"gui.close"}, name = "pvp_export_close"}
  frame.visible = true
end

function import_button_press(player)
  if not (player and player.valid) then return end
  local gui = player.gui.center
  gui.clear()
  local frame = gui.add{type = "frame", caption = {"gui-blueprint-library.import-string"}, name = "pvp_import_frame", direction = "vertical"}
  local textfield = frame.add{type = "text-box", name = "import_textfield"}
  textfield.word_wrap = true
  textfield.style.height = player.display_resolution.height * 0.6
  textfield.style.width = player.display_resolution.width * 0.6
  local flow = frame.add{type = "flow", direction = "horizontal"}
  flow.add{type = "button", caption = {"gui.close"}, name = "pvp_export_close"}
  local pusher = flow.add{type = "flow"}
  pusher.style.horizontally_stretchable = true
  flow.add{type = "button", caption = {"gui-blueprint-library.import"}, name = "pvp_import_confirm"}
  frame.visible = true
end

function import_confirm(player)
  if not (player and player.valid) then return end
  local gui = player.gui.center
  local frame = gui.pvp_import_frame
  if not frame then return end
  local textfield = frame.import_textfield
  if not textfield then return end
  local text = textfield.text
  if text == "" then player.print({"import-failed"}) return end
  local result = load(util.decode(text))
  local new_config
  if result then
    new_config = result()
  else
    player.print({"import-failed"})
    return
  end
  for k, v in pairs(new_config) do
    global[k] = v
  end
  gui.clear()
  create_config_gui(player)
  player.print({"import-success"})
end

local function on_calculator_button_press(gui, player)
  local name = gui.name
  local flow = gui.parent
  if not flow then return end
  local recipe_table = flow.parent
  if not (recipe_table and recipe_table.name and recipe_table.name == "recipe_checker_table") then return end

  local delim = "/"
  local pos = name:find(delim)
  local type = name:sub(1, pos - 1)
  local elem_name = name:sub(pos + 1, name:len())
  local items = game.item_prototypes
  local fluids = game.fluid_prototypes
  local recipes = game.recipe_prototypes
  if type == "item" then
    if not items[elem_name] then return true end
  elseif type == "fluid" then
    if not fluids[elem_name] then return true end
  else
    return true
  end
  local frame = mod_gui.get_frame_flow(player).production_score_frame
  if not frame then return true end
  local picker_holding_flow = frame.recipe_picker_holding_flow
  if not picker_holding_flow then return true end
  local elem_button = picker_holding_flow.recipe_picker_elem_button
  local selected = elem_button.elem_value
  local candidates = {}
  for recipe_name, recipe in pairs(recipes) do
    for _, product in pairs(recipe.products) do
      if product.type == type and product.name == elem_name then
        tinsert(candidates, recipe_name)
      end
    end
  end
  if #candidates == 0 then return true end
  local index = 0
  for k, _name in pairs(candidates) do
    if _name == selected then
      index = k
      break
    end
  end
  local recipe_name = candidates[index + 1] or candidates[1]
  if not recipe_name then return true end
  elem_button.elem_value = recipe_name
  recipe_picker_elem_update(elem_button, player)
  return true
end

pvp.on_load = function()
  silo_script.on_load()
end
pvp.on_init = function()
  silo_script.on_init()
  load_config()
  init_balance_modifiers()
  verify_oil_harvest()
  local surface = game.get_surface(1)
  local settings = surface.map_gen_settings
  global.map_config.starting_area_size.selected = settings.starting_area
  global.map_config.map_height = settings.height
  global.map_config.map_width = settings.width
  global.map_config.starting_area_size.selected = settings.starting_area
  global.round_number = 0
  global.biters_on_pvp = 0
  local lobby_surface = game.create_surface("Lobby", {width = 1, height = 1})
  lobby_surface.set_tiles({{name = "out-of-map", position = {1, 1}}})

  for _, force in pairs(game.forces) do
    force.disable_all_prototypes()
    force.disable_research()
  end

  global.price_list = production_score.generate_price_list()

  local entities = lobby_surface.find_entities()
  for i=#entities, 1, -1 do
    entities[i].destroy()
  end
  lobby_surface.destroy_decoratives({})

  local GM = game.create_force("GM")
  GM.reset()
  GM.research_all_technologies()
  GM.enable_all_recipes()
  --roll_starting_area()
end

pvp.on_rocket_launched = function(event)
  if not global.setup_finished then return end
  production_score.on_rocket_launched(event)
  local mode = global.game_config.game_mode.selected
  if mode == "freeplay" then
    silo_script.events[defines.events.on_rocket_launched](event)
    return
  end
  if mode ~= "conquest" then return end
  local force = event.rocket.force
  if event.rocket.get_item_count("satellite") == 0 then
    force.print({"rocket-launched-without-satellite"})
    return
  end
  if not global.team_won then
    team_won(force.name)
  end
end

local function restore_rocket_silo_and_ban(silo, players, force)
  local new_silo = silo.surface.create_entity{name = silo.name, position = silo.position, force = silo.force}
  new_silo.minable = false
  new_silo.backer_name = tostring(force.name)
  silo.destroy()
  local all_players = ""
  for _, player in pairs(players) do
    all_players = all_players .. player.name .. " "
    game.ban_player(player, "tried to destroy own rocket silo")
  end
  all_players = all_players:match"(.-)%s*$" -- Rtrim
  log("BAN:" .. all_players .. " reason: tried to destroy own rocket silo in the force: " .. force.name)
  force.print({"silo-destroyed", force.name, all_players})
end

-- TODO: change and improve
pvp.on_entity_died = function(event)
  local entity = event.entity
  if entity.surface ~= global.surface then return end

  local mode = global.game_config.game_mode.selected
  if mode == "genocide_of_biters" then
    genocide_of_biters.on_entity_died(event)
    return
  end
  if not (mode == "conquest" or mode == "last_silo_standing") then return end
  local silo = entity
  if not (silo and silo.valid and silo.name == "rocket-silo") then
    return
  end

  local killing_force = event.force
  local force = silo.force
  if not global.silos then return end
  global.silos[force.name] = nil
  if killing_force then
    if killing_force == force then
      local cause = event.cause
      if cause then
        if cause.type == "character" then
          local player = cause.player
          restore_rocket_silo_and_ban(silo, {player}, force)
          return
        elseif cause.type == "car" then
          local passenger = cause.get_passenger()
          local driver = cause.get_driver()
          if passenger and driver then
            local players = {passenger.player, driver.player}
            restore_rocket_silo_and_ban(silo, {players}, force)
            return
          elseif passenger then
            restore_rocket_silo_and_ban(silo, {passenger.player}, force)
            return
          elseif driver then
            restore_rocket_silo_and_ban(silo, {driver.player}, force)
            return
          end
        end
      end
    end
    game.print({"silo-destroyed", force.name, killing_force.name})
  else
    game.print({"silo-destroyed", force.name, {"neutral"}})
  end
  script.raise_event(events.on_team_lost, {name = force.name})
  global.silos[force.name] = nil
  if global.game_config.disband_on_loss then
    disband_team(force, killing_force)
  end
  if not global.team_won then
    local index = 0
    local winner_name = {"none"}
    for name, listed_silo in pairs(global.silos) do
      if listed_silo ~= nil then
        index = index + 1
        winner_name = name
      end
    end
    if index == 1 then
      team_won(winner_name)
    end
  end
end

pvp.on_player_joined_game = function(event)
  local player = game.get_player(event.player_index)
  if not (player and player.valid) then return end

  if player.force.name ~= "player" then
    --If they are not on the player force, they have already picked a team this round.
    check_force_protection(player.force)

    for _, player in pairs(game.connected_players) do
      update_team_list_frame(player
    end
    return
  end

  local character = player.character
  player.character = nil
  if character then character.destroy() end
  player.set_controller{type = defines.controllers.ghost}
  player.teleport({0, 1000}, game.get_surface("Lobby"))
  player.gui.center.clear()

  if global.setup_finished then
    choose_joining_gui(player)
  else
    if player.admin then
      create_config_gui(player)
    else
      create_waiting_gui(player)
    end
  end
end

pvp.on_gui_selection_state_changed = function(event)
  local gui = event.element
  if not (gui and gui.valid) then return end
  local player = game.get_player(event.player_index)
  if not (player and player.valid) then return end

  set_mode_input(player)
end

pvp.on_gui_checked_state_changed = function(event)
  local player = game.get_player(event.player_index)
  if not (player and player.valid) then return end
  set_mode_input(player)
end

pvp.on_player_left_game = function(event)
  local player = game.get_player(event.player_index)
  if not (player and player.valid) then return end

  if global.game_config.protect_empty_teams then
    local force = player.force
    check_force_protection(force)
  end

  if player.online_time < 60 * 60 * 4 or player.force.name == "player" then
    game.remove_offline_players({player})
  end

  for _, _player in pairs(game.players) do
    if _player.valid then
      local gui = _player.gui.center
      if gui.pick_join_frame then
        create_pick_join_gui(gui)
      end
      if _player.connected then
        update_team_list_frame(_player)
      end
    end
  end
end

pvp.on_gui_elem_changed = function(event)
  local gui = event.element
  if not (gui and gui.valid) then return end
  local player = game.get_player(event.player_index)
  if not (player and player.valid) then return end

  recipe_picker_elem_update(gui, player)
  local parent = gui.parent
  if parent.name ~= "disable_items_table" then return end
  if not global.disabled_items then
    global.disabled_items = {}
  end
  -- local items = global.disabled_items
  local value = gui.elem_value

  if parent.name == "disable_items_table" then
    if value then
      for _, child in pairs(gui.parent.children) do
        if child ~= gui and child.elem_value == value then
          gui.destroy()
          player.print({"duplicate-disable"})
          break
        end
      end
      parent.add{type = "choose-elem-button", elem_type = "item"}
    else
      gui.destroy()
    end
  end

  --[[
  if value then
    local map = {}
    for _, child in pairs(parent.children) do
      if child.elem_value then
        map[child.elem_value] = true
      end
    end
    for _, item in pairs(items) do
      if not map[item] then
        items[item] = nil
      end
    end
    gui.destroy()
    return
  end
  if items[value] then
    if items[value] ~= gui.index then
      gui.elem_value = nil
      player.print({"duplicate-disable"})
    end
  else
    items[value] = gui.index
    parent.add{type = "choose-elem-button", elem_type = "item"}
  end
  global.disabled_items = items
  ]]--
end

pvp.on_gui_click = function(event)
  local gui = event.element
  if not (gui and gui.valid) then return end
  local player = game.get_player(event.player_index)
  if not (player and player.valid) then return end

  if gui.name then
    local button_function = pvp.button_press_functions[gui.name]
    if button_function then
      button_function(event, player, gui)
      return
    end

    if gui.name ~= "" then
      if trash_team_button_press(gui, player) then
        return
      elseif on_team_button_press(event, gui) then
        return
      elseif on_pick_join_button_press(gui, player) then
        return
      elseif on_calculator_button_press(gui, player) then
        return
      end
    end
    if admin_frame_button_press(gui, player) then
      return
    end
  end
end

pvp.on_tick = function(event)
  -- TODO: improve?
  if not global.setup_finished then
    check_starting_area_chunks_are_generated()
    finish_setup()
  end
end

pvp.on_nth_tick = {
  -- TODO: improve
  [60] = function()
    if global.setup_finished then
      if global.team_won then
        check_restart_round()
      else
        if global.end_no_rush then
          check_no_rush()
        end
        local game_mode = global.game_config.game_mode.selected
        if game_mode == "production_score" then
          check_update_production_score()
        elseif game_mode == "oil_harvest" then
          check_update_oil_harvest_score()
        elseif game_mode == "space_race" then
          check_update_space_race_score()
        end
        check_base_exclusion()
      end
      if global.team_config.defcon_mode then
        check_defcon()
      end
    end
  end,
  -- TODO: improve
  [300] = function()
    if global.setup_finished then
      local game_config = global.game_config
      if not game_config.disable_check_color_team then
        check_player_color()
      end
      if not game_config.spectator_fog_of_war then
        check_spectator_chart()
      end
    end
  end,
  -- TODO: improve
  [1200] = function()
    if global.setup_finished then
      genocide_of_biters.check()
    end
  end
}

-- TODO: change call functions for "game_mode"
-- game_mode.function(event)

-- TODO: improve
pvp.on_chunk_generated = function(event)
  if not global.setup_finished then return end
  if event.surface ~= global.surface then return end
  local game_mode = global.game_config.game_mode.selected
  if game_mode == "genocide_of_biters" then
    genocide_of_biters.on_chunk_generated(event)
  elseif game_mode == "oil_harvest" then
    if global.game_config.oil_only_in_center then
      oil_harvest_prune_oil(event)
    end
  end
end

--TODO: improve
pvp.on_biter_base_built = function(event)
  if not global.setup_finished then return end
  local entity = event.entity
  if not (entity and entity.valid) then return end
  if entity.surface ~= global.surface then return end

  local game_config = global.game_config
  if game_config.prohibition_spawn_biters_in_starting_zone then
    if prohibition_spawn_biters_in_starting_zone(entity) then
      return
    end
  end
  local game_mode = game_config.game_mode.selected
  if game_mode == "genocide_of_biters" then
    genocide_of_biters.on_biter_base_built(entity)
  end
end

pvp.on_player_respawned = function(event)
  local player = game.get_player(event.player_index)
  if not (player and player.valid) then return end
  if global.setup_finished then
    give_equipment(player)
    offset_respawn_position(player)
    apply_character_modifiers(player)
  else
    if player.character then
      player.character.destroy()
    end
  end
end

pvp.on_configuration_changed = function(event)
  silo_script.on_configuration_changed(event)
  recursive_data_check(load_config(true), global)
end

-- TODO: improve
pvp.on_player_crafted_item = function(event)
  if not global.setup_finished then return end
  production_score.on_player_crafted_item(event)
end

pvp.on_player_display_resolution_changed = function(event)
  check_config_frame_size(event)
  check_balance_frame_size(event)
  local player = game.get_player(event.player_index)
  if player and player.valid then
    update_team_list_frame(player)
  end
end

pvp.on_research_finished = function(event)
  if not global.setup_finished then return end
  check_technology_for_disabled_items(event)
end

-- TODO: improve
pvp.on_built_entity = function(event)
  if not global.setup_finished then return end
  local entity = event.created_entity
  if not (entity and entity.valid) then return end
  local player = game.get_player(event.player_index)
  if not (player and player.valid) then return end

  if global.game_config.enemy_building_restriction then
    if check_on_built_protection(entity, player) then
      return
    end
  end
  if entity.type == "container" then
    if global.game_config.neutral_chests then
      entity.force = "neutral"
    end
  end
end

-- TODO: improve
pvp.on_robot_built_entity = function(event)
  if not global.setup_finished then return end
  local entity = event.created_entity
  if not (entity and entity.valid) then return end

  if global.game_config.neutral_chests then
    entity.force = "neutral"
  end
end

-- TODO: improve
pvp.on_research_started = function(event)
  if not global.setup_finished then return end
  if global.team_config.defcon_mode then
    local tech = global.next_defcon_tech
    if tech and tech.valid and event.research.name ~= tech.name then
      event.research.force.current_research = nil
    end
  end
end

pvp.on_player_demoted = function(event)
  if not global.setup_finished then return end
  local player = game.get_player(event.player_index)
  if not (player and player.valid) then return end

  local admin_button = mod_gui.get_button_flow(player).admin_button
  if admin_button then
    admin_button.destroy()
  end
  local admin_frame = mod_gui.get_frame_flow(player).admin_frame
  if admin_frame then
    admin_frame.destroy()
  end
  local become_GM = player.gui.left.become_GM
  if become_GM then
    become_GM.destroy()
  end
end

pvp.on_player_promoted = function(event)
  if not global.setup_finished then return end
  local player = game.get_player(event.player_index)
  if not (player and player.valid) then return end
  init_player_gui(player)

  local button_flow = mod_gui.get_button_flow(player)
  if button_flow.admin_button == nil then
    button_flow.add{type = "button", caption = {"admin"}, name = "admin_button", style = mod_gui.button_style}
  end

  local center_gui = player.gui.center
  if center_gui.random_join_frame then
    create_gui_GM(player)
  elseif center_gui.pick_join_frame then
    create_gui_GM(player)
  elseif center_gui.auto_assign_frame then
    create_gui_GM(player)
  end
end

pvp.on_forces_merged = function (event)
  if not global.players_to_disband then return end

  local players = game.players
  for name in pairs(global.players_to_disband) do
    local player = players[name]
    if player and player.valid then
      player.force = game.forces.player
      if player.connected then
        local character = player.character
        player.character = nil
        if character then character.destroy() end
        player.set_controller{type = defines.controllers.ghost}
        player.teleport({0, 1000}, game.get_surface("Lobby"))
        destroy_player_gui(player)
        choose_joining_gui(player)
      end
    end
  end
  global.players_to_disband = nil
  create_exclusion_map()
end

return pvp
