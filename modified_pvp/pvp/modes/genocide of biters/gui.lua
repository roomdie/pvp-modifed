local M = {}

local mod_gui = require("mod-gui")

function update_frame_genocide_biters_frame(player)
  local gui = mod_gui.get_frame_flow(player)
  local frame = gui.genocide_biters_frame
  if not frame then return end
  frame.count_spawner.caption = {"", {"known_number_of_biter_spawner"}, {"colon"}, " ", util.format_number(global.biters_on_pvp)}
  inner_frame = frame.genocide_biters_inner_frame
  if not inner_frame then return end
  inner_frame.clear()
  local information_table = inner_frame.add{type = "table", column_count = 3}
  information_table.draw_horizontal_line_after_headers = true
  information_table.draw_vertical_lines = true
  information_table.style.horizontal_spacing = 16
  information_table.style.vertical_spacing = 8
  information_table.style.column_alignments[3] = "right"

  for _, caption in pairs({"", "team-name", "killed"}) do
      local label = information_table.add{type = "label", caption = {caption}}
      label.style.font = "default-bold"
  end
  local team_map = {}
  for _, team in pairs(global.teams) do
    team_map[team.name] = team
  end
  if not global.genocide_biters_score then
    global.genocide_biters_score = {}
  end
  local rank = 1
  for name, score in spairs(global.genocide_biters_score, function(t, a, b) return t[b] < t[a] end) do
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

M.update_frame = function(player)
  update_frame_genocide_biters_frame(player)
end

M.check_update_score = function()
  --if global.game_config.game_mode.selected ~= "genocide_of_biters" then return end
  --if global.team_won then return end
  for _, player in pairs(game.players) do --connected_players
    update_frame_genocide_biters_frame(player)
  end
  -- TODO: \/
  -- local required = global.game_config.required_genocide_biters
  -- if required > 0 then
  --   for team_name, score in pairs(global.genocide_biters_score) do
  --     if score >= required then
  --       team_won(team_name)
  --     end
  --   end
  -- end

  -- maybe it is very bad variant "time limit" \/
  if global.game_config.time_limit > 0 and game.tick > (global.round_start_tick + (global.game_config.time_limit * 60 * 60)) then
    local winner = {"none"}
    local winning_score = 0
    for team_name, score in pairs(global.genocide_biters_score) do
      if score > winning_score then
        winner = team_name
        winning_score = score
      end
    end
    team_won(winner)
  end
end

return M
