-- Thanks you https://mods.factorio.com/user/numgun for idea https://mods.factorio.com/mod/pack-scenarios/discussion/5aa15877becc0e000a2ea2eb
gui_mode = require("pvp/modes/genocide of biters/gui")

local mod_gui = require("mod-gui")
local M = {}

M.on_biter_base_built = function(entity)
    if global.team_won then return end
    global.biters_on_pvp = global.biters_on_pvp + 1
    entity.operable = false
    gui_mode.check_update_score()
end

M.on_chunk_generated = function(event)
    if global.team_won then return end
    local surface = event.surface
    local area = event.area
    local count = 0
    local entities = surface.find_entities_filtered{area = area, type = "unit-spawner"}
    for i=1, #entities do
        local entity = entities[i]
        if entity.operable then
            count = count + 1
            entity.operable = false
        end
    end
    global.biters_on_pvp = global.biters_on_pvp + count
    gui_mode.check_update_score()
end

M.on_entity_died = function(event)
    if global.team_won then return end
    local entity = event.entity
    if not (entity and entity.valid) then return end
    if entity.type ~= "unit-spawner" then return end
    -- if entity.operable then return end
    global.biters_on_pvp = global.biters_on_pvp - 1
    local force = entity.force
    if not (force and force.valid) then gui_mode.check_update_score() return end
    local killing_force = event.force
    if not (killing_force and killing_force.valid) then gui_mode.check_update_score() return end
    if killing_force == force then gui_mode.check_update_score() return end
    local team_map = {}
    for _, team in pairs(global.teams) do
        team_map[team.name] = true
    end
    if team_map[killing_force.name] then
        global.genocide_biters_score[killing_force.name] = global.genocide_biters_score[killing_force.name] + 1
    end
    gui_mode.check_update_score()
end

M.button_press = function(event, player)
    local flow = mod_gui.get_frame_flow(player)
    local frame = flow.genocide_biters_frame
    if frame then
        frame.destroy()
        return
    end
    -- WIPs
    frame = flow.add{type = "frame", name = "genocide_biters_frame", caption = {"genocide_of_biters"}, direction = "vertical"}
    frame.add{type = "label", name = "count_spawner", caption = {"", {"count_spawner"}, {"colon"}, " ", util.format_number(global.biters_on_pvp)}}
    -- if global.game_config.required_kill_biter_spawner > 0 then
    --     frame.add{type = "label", caption = {"", {"required_oil_barrels"}, {"colon"}, " ", util.format_number(global.game_config.required_oil_barrels)}}
    -- end
    local inner_frame = frame.add{type = "frame", style = "inside_shallow_frame", name = "genocide_biters_inner_frame", direction = "vertical"}
    inner_frame.style.left_padding = 8
    inner_frame.style.top_padding = 8
    inner_frame.style.right_padding = 8
    inner_frame.style.bottom_padding = 8
    gui_mode.update_frame(player)
  end

--genocide_of_biters.on_robot_built_entity = function(event)


--genocide_of_biters.on_player_mined_entity = function(event)


--genocide_of_biters.on_built_entity = function(event)


M.check = function()
    if global.biters_on_pvp > 0 then return end
    if global.game_config.game_mode.selected ~= "genocide_of_biters" then return end
    if global.team_won then return end
    if global.genocide_biters_score == nil or global.genocide_biters_score == {} then return end
    local winner = {"none"}
    local winning_score = 0
    for team_name, score in pairs(global.genocide_biters_score) do
        if score > winning_score then
            winner = team_name
            winning_score = score
        end
    end
    if winning_score > 20 then
        team_won(winner)
    end
end


--[[
function how_many_unit_spawner_on_global_surface()
    local count = 0
    for _, entity in pairs(global.surface.find_entities_filtered{type = "unit-spawner"}) do
        count = count + 1
    end
    game.print(count)
end
]]--

return M
