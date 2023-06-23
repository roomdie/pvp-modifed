local pvp = require("pvp/pvp")

script.on_load(pvp.on_load)
script.on_init(pvp.on_init)
script.on_configuration_changed(pvp.on_configuration_changed)

script.on_event(defines.events.on_tick, pvp.on_tick)
script.on_event(defines.events.on_rocket_launched, pvp.on_rocket_launched)
script.on_event(defines.events.on_entity_died, pvp.on_entity_died)
script.on_event(defines.events.on_player_joined_game, pvp.on_player_joined_game)
script.on_event(defines.events.on_player_respawned, pvp.on_player_respawned)
script.on_event(defines.events.on_gui_selection_state_changed, pvp.on_gui_selection_state_changed)
script.on_event(defines.events.on_gui_checked_state_changed, pvp.on_gui_checked_state_changed)
script.on_event(defines.events.on_player_left_game, pvp.on_player_left_game)
script.on_event(defines.events.on_gui_elem_changed, pvp.on_gui_elem_changed)
script.on_event(defines.events.on_player_crafted_item, pvp.on_player_crafted_item)
script.on_event(defines.events.on_player_display_resolution_changed, pvp.on_player_display_resolution_changed)
script.on_event(defines.events.on_research_finished, pvp.on_research_finished)
script.on_event(defines.events.on_player_demoted, pvp.on_player_demoted)
script.on_event(defines.events.on_built_entity, pvp.on_built_entity)
script.on_event(defines.events.on_robot_built_entity, pvp.on_robot_built_entity, {
  {filter = "type", type = "container"}
})
script.on_event(defines.events.on_research_started, pvp.on_research_started)
script.on_event(defines.events.on_player_promoted, pvp.on_player_promoted)
script.on_event(defines.events.on_biter_base_built, pvp.on_biter_base_built)
script.on_event(defines.events.on_forces_merged, pvp.on_forces_merged)
script.on_event(defines.events.on_gui_click, pvp.on_gui_click)
script.on_event(defines.events.on_chunk_generated, pvp.on_chunk_generated)

script.on_nth_tick(60, pvp.on_nth_tick[60])
script.on_nth_tick(300, pvp.on_nth_tick[300])