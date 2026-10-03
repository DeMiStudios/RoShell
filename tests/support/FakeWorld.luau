--!strict
--[[
	Fake players and teams for headless tests. They are plain tables shaped like the engine objects the player
	types read (`Name`, `DisplayName`, `UserId`, `Team`, `Character`, `Kick`, `Team:GetPlayers()`), given their
	engine types once, here.
]]

const Platform = require("../../src/Shared/Platform")
const Unsafe = require("../../src/Shared/Unsafe")

export type World = {
	Controller: Platform.HeadlessController,
	Players: { [string]: Player },
	Teams: { [string]: Team },
	--- Names of players kicked so far, with the message.
	Kicked: { { Name: string, Message: string } },
}

const FakeWorld = {}

--- Creates players and teams: `{ Red = { "Bob", "Alice" }, Blue = { "Bobby" } }` plus team-less `extra` names.
--- Teams are created in name order.
function FakeWorld.new(teams: { [string]: { string } }, extra: { string }?): World
	const controller = Platform.Headless(2024)
	const world: World = { Controller = controller, Players = {}, Teams = {}, Kicked = {} }
	const playerList: { Player } = {}
	const teamList: { Team } = {}
	local nextId = 100

	const function makePlayer(name: string, team: Team?): Player
		nextId += 1
		const fake = {
			Name = name,
			DisplayName = name,
			UserId = nextId,
			Team = team,
			Character = nil,
			Kick = function(_self: unknown, message: string?)
				table.insert(world.Kicked, { Name = name, Message = message or "" })
			end,
		}
		const player = Unsafe.Assume(fake) :: Player
		world.Players[name] = player
		table.insert(playerList, player)
		return player
	end

	const teamNames: { string } = {}
	for name in teams do
		table.insert(teamNames, name)
	end
	table.sort(teamNames)
	for _, teamName in teamNames do
		const members: { Player } = {}
		const fakeTeam = {
			Name = teamName,
			TeamColor = { Name = teamName },
			GetPlayers = function(): { Player }
				return table.clone(members)
			end,
		}
		const team = Unsafe.Assume(fakeTeam) :: Team
		world.Teams[teamName] = team
		table.insert(teamList, team)
		for _, playerName in teams[teamName] do
			-- A name listed under several teams is one player in all of them (its `Team` is the first).
			table.insert(members, world.Players[playerName] or makePlayer(playerName, team))
		end
	end
	for _, name in extra or {} do
		makePlayer(name, nil)
	end

	controller:SetPlayers(playerList)
	controller:SetTeams(teamList)
	return world
end

return table.freeze(FakeWorld)
