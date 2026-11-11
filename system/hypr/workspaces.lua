-- Global workspaces 1-10 shared by every monitor, as before Omarchy 4.5.
--
-- 4.5's default/hypr/monitor-workspaces.lua gives each monitor its own block
-- (laptop 1-10, next monitor 11-20) and, when one is unplugged or the lid
-- closes, renumbers its workspaces onto the end of the remaining monitor's
-- block. Docking/undocking then shuffled the numbered workspaces.
--
-- Hyprland alone already moves an unplugged monitor's workspaces, numbers
-- intact, and returns them by connector. So:
--   * reconcile is a no-op: no renumbering on monitor add/remove/reload.
--   * every monitor maps slot N to workspace N, so SUPER+N is global again.
-- Both are looked up on `o.workspaces` at call time, so overriding them after
-- the defaults load is enough. The bar side lives in andres.workspaces
-- (block fixed at 0).

o.workspaces.reconcile = function() end
o.workspaces.workspace_id = function(_, slot) return slot end

-- The stock "move workspace to monitor" binds renumber the workspace into the
-- target monitor's block. Rebind them to a plain move that keeps the number.
local function move_workspace_to_monitor(direction)
  return function()
    -- Hyprland reports a move toward no monitor as an error on screen.
    local target = hl.get_monitor(direction)
    if target then
      hl.dispatch(hl.dsp.workspace.move({ monitor = target.name }))
    end
  end
end

for key, direction in pairs({ LEFT = "l", RIGHT = "r", UP = "u", DOWN = "d" }) do
  local keys = "SUPER + SHIFT + ALT + " .. key
  hl.unbind(keys)
  o.bind(keys, "Move workspace to " .. key:lower() .. " monitor", move_workspace_to_monitor(direction))
end
