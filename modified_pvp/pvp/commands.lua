local function change_force(cmd)
  if not global.setup_finished then return end
  local player = game.player
  if cmd.parameter ~= nil then
    local target = game.get_player(cmd.parameter)
    if not target then player.print({"unknown-username"}) return end
    if player.admin then
      create_pick_join_gui(target.gui.center)
    elseif global.team_config.who_decides_diplomacy.selected == "team_leader" then
      if player.force.connected_players[1] == player and player.force == target.force then
        create_pick_join_gui(target.gui.center)
      end
    end
  elseif player.online_time < 60 * 60 * 30 then -- < 30 min
    local setting = global.team_config.team_joining.selected
    if setting == "random" then
      player.print({"achievement-name.no-time-for-chitchat"}) -- temp
      return
    end
    if setting == "player_pick" then
      if player.online_time < 60 * 60 * 60 then -- < 60 min
        create_pick_join_gui(player.gui.center)
        return
      else
        player.print({"achievement-name.no-time-for-chitchat"}) -- temp
      end
    end
    if setting == "auto_assign" then
      create_auto_assign_gui(player.gui.center)
      return
    else
      player.print({"achievement-name.no-time-for-chitchat"}) -- temp
    end
  elseif not (player.admin) then
    player.print({"help_command.cant_run", player.name})
    return
  else
    create_pick_join_gui(player.gui.center)
  end
end
commands.add_command("change-force", {"command-help.change_force", 60, 30}, change_force)
