--!strict
--[[
	Where commands run:

	- `ClientRun` only: runs on the player's machine and never touches the network (`fov`).
	- `Run` only: the client forwards the text, the server re-parses and runs it (`teleport-here`).
	- `Data` collects client-only information and ships it with the request (`ctx:GetData()` on the server).
	- `ClientRun` returning nil falls through to the server (`look`): client-side preparation, server authority.
]]

const RoShell = require(game:GetService("ReplicatedStorage").RoShell)

const fov = RoShell.Command({
	Name = "fov",
	Description = "Sets your camera's field of view",
	Args = { { degrees = RoShell.Arg(RoShell.Type.Number({ Name = "degrees", Min = 20, Max = 120 })) } },
}):ClientRun(function(ctx, args)
	const camera = workspace.CurrentCamera
	if camera then
		camera.FieldOfView = args.degrees
	end
	return ctx:Success(`FOV {args.degrees}`)
end)

const teleportHere = RoShell.Command({
	Name = "teleport-here",
	Description = "Teleports players to where your camera looks",
	Args = { { targets = RoShell.Arg(RoShell.Types.Players) } },
}):Data(
	function(): unknown
		-- Runs on the client before sending; the server receives the camera's focus point.
		const camera = workspace.CurrentCamera
		return if camera then camera.Focus.Position else nil
	end
):Run(function(ctx, args)
	const target = ctx:GetData()
	if typeof(target) ~= "Vector3" then
		return ctx:Error("No camera position was sent")
	end
	for _, player in args.targets do
		const character = player.Character
		if character then
			character:PivotTo(CFrame.new(target + Vector3.new(0, 3, 0)))
		end
	end
	return ctx:Success(`Moved {#args.targets} player(s)`)
end)

const look = RoShell.Command({
	Name = "look",
	Description = "Describes the part under your mouse",
	Args = {},
}):ClientRun(
	function(ctx)
		if not ctx.IsClient then
			return nil
		end
		ctx:Info("Asking the server…")
		return nil -- continue on the server
	end
):Run(function(ctx)
	return ctx:Info(`Server sees {#game:GetService("Players"):GetPlayers()} player(s)`)
end)

return { fov, teleportHere, look }
