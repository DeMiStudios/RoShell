--!strict
--[[
	Player and team types.

	`player`/`players` accept names, display names, `.`/`me`, `*`, `**`, `?`, `~fuzzy`, globs, set arithmetic and
	two selectors: `%Team` (members of a team) and `#Tag` (players whose Player or character carries a
	CollectionService tag). `userId` also accepts players who are not in the server.
]]

--// Imports
const Fuzzy = require("../Fuzzy")
const TypeBuilder = require("../TypeBuilder")
const Types = require("../Types")

--// Types
type ParseRequest = Types.ParseRequest
type CompleteRequest = Types.CompleteRequest
type Candidate<T> = Types.Candidate<T>

--// Helpers

const function playerCandidates(request: Types.CandidateRequest): { read Candidate<Player> }
	const candidates: { Candidate<Player> } = {}
	for _, player in request.Platform.GetPlayers() do
		const displayName = player.DisplayName
		table.insert(candidates, {
			Key = player.Name,
			Value = player,
			Aliases = if displayName ~= player.Name then { displayName } else nil,
			Detail = if displayName ~= player.Name then displayName else nil,
			Icon = "player",
		})
	end
	return candidates
end

const function teamCandidates(request: Types.CandidateRequest): { read Candidate<Team> }
	const candidates: { Candidate<Team> } = {}
	for _, team in request.Platform.GetTeams() do
		table.insert(candidates, { Key = team.Name, Value = team, Detail = team.TeamColor.Name, Icon = "team" })
	end
	return candidates
end

const function identity(name: string): string
	return name
end

const function suggest(request: CompleteRequest, names: { string }, kind: string): { Types.Suggestion }
	const suggestions: { Types.Suggestion } = {}
	const ranked = Fuzzy.Filter(request.Text, names, identity, request.Limit)
	for _, result in ranked do
		table.insert(suggestions, {
			Text = result.Item,
			Display = result.Item,
			Kind = kind,
			Score = result.Score,
			MatchRanges = result.Ranges,
		})
	end
	return suggestions
end

--- Finds a team by exact, prefix, or fuzzy name.
const function findTeam(request: ParseRequest): Team?
	const teams = request.Platform.GetTeams()
	const wanted = request.Text:lower()
	for _, team in teams do
		if team.Name:lower() == wanted then
			return team
		end
	end
	for _, team in teams do
		if team.Name:lower():sub(1, #wanted) == wanted then
			return team
		end
	end
	const names: { string } = {}
	for _, team in teams do
		table.insert(names, team.Name)
	end
	const best = Fuzzy.Suggest(request.Text, names)
	for _, team in teams do
		if team.Name == best then
			return team
		end
	end
	return nil
end

--// Selectors

const TeamSelector: Types.Selector<Player> = {
	Prefix = "%",
	Name = "team",
	Description = "Players on a team",
	Example = "%Red",
	Complete = function(request: CompleteRequest): { Types.Suggestion }
		const names: { string } = {}
		for _, team in request.Platform.GetTeams() do
			table.insert(names, team.Name)
		end
		return suggest(request, names, "team")
	end,
	Resolve = function(request: ParseRequest): Types.ParseResult<{ read Player }>
		const team = findTeam(request)
		if team == nil then
			return { Ok = false, Error = `Unknown team '{request.Text}'`, Span = request.Span }
		end
		return { Ok = true, Value = team:GetPlayers(), Display = team.Name }
	end,
}

const TagSelector: Types.Selector<Player> = {
	Prefix = "#",
	Name = "tag",
	Description = "Players whose player or character has a CollectionService tag",
	Example = "#Boss",
	Complete = function(request: CompleteRequest): { Types.Suggestion }
		const ok, tags = pcall(function(): { string }
			return game:GetService("CollectionService"):GetAllTags()
		end)
		return suggest(request, if ok then tags else {}, "tag")
	end,
	Resolve = function(request: ParseRequest): Types.ParseResult<{ read Player }>
		const CollectionService = game:GetService("CollectionService")
		const tagged: { Player } = {}
		for _, player in request.Platform.GetPlayers() do
			const character = player.Character
			if CollectionService:HasTag(player, request.Text)
				or (character and CollectionService:HasTag(character, request.Text)) then
				table.insert(tagged, player)
			end
		end
		return { Ok = true, Value = tagged, Display = "#" .. request.Text }
	end,
}

--// Types

const Player = TypeBuilder.Enumerable({
	Name = "player",
	Plural = "players",
	Description = "A player in this server (name or display name)",
	Examples = { "Builderman", ".", "~bui" },
	Candidates = playerCandidates,
	Default = function(request: ParseRequest): Player?
		return request.Executor
	end,
	Selectors = { TeamSelector, TagSelector },
	Color = "type.player",
	Icon = "player",
})

const Players = TypeBuilder.List(Player, {
	Name = "players",
	Description = "One or more players: names, *, **, ., ?3, %Team, #Tag, globs and set arithmetic",
	Examples = { "*", "*-Bob", "%Red&%Admins", "Guest*" },
})

const Team = TypeBuilder.Enumerable({
	Name = "team",
	Description = "A team",
	Candidates = teamCandidates,
	Default = function(request: ParseRequest): Team?
		const executor = request.Executor
		return if executor then executor.Team else nil
	end,
	Color = "type.team",
	Icon = "team",
})

const Teams = TypeBuilder.List(Team, { Name = "teams" })

const TeamPlayers = TypeBuilder.Transform({
	From = Team,
	To = function(team: Team): { Player }
		return team:GetPlayers()
	end,
	Name = "teamPlayers",
	Description = "The players on a team",
	Display = function(players: { Player }): string
		return `{#players} player(s)`
	end,
})

--- A user id: a number, an in-server player's name, or any Roblox username (looked up when the command runs).
const UserId = TypeBuilder.Custom({
	Name = "userId",
	Description = "A user id, an online player's name, or any username",
	Examples = { "1", "Builderman" },
	Yields = true,
	Parse = function(request: ParseRequest): Types.ParseResult<number>
		const text = request.Text:gsub("^@", "")
		const numeric = tonumber(text)
		if numeric and numeric == math.floor(numeric) and numeric > 0 then
			return { Ok = true, Value = numeric, Display = tostring(numeric) }
		end
		for _, player in request.Platform.GetPlayers() do
			if player.Name:lower() == text:lower() then
				return { Ok = true, Value = player.UserId, Display = `{player.Name} ({player.UserId})` }
			end
		end
		if not text:match("^[%w_]+$") then
			return { Ok = false, Error = `'{request.Text}' is not a username or user id`, Span = request.Span }
		end
		if not request.Final then
			-- Validated (with a network lookup) right before running.
			return { Ok = true, Value = 0, Display = text }
		end
		const ok, id = pcall(function(): number
			return game:GetService("Players"):GetUserIdFromNameAsync(text)
		end)
		if not ok then
			return { Ok = false, Error = `No user named '{text}'`, Span = request.Span }
		end
		return { Ok = true, Value = id, Display = `{text} ({id})` }
	end,
	Complete = function(request: CompleteRequest): { Types.Suggestion }
		const names: { string } = {}
		for _, player in request.Platform.GetPlayers() do
			table.insert(names, player.Name)
		end
		return suggest(request, names, "player")
	end,
	Color = "type.player",
	Icon = "player",
})

const PlayerTypes = {
	Player = Player,
	Players = Players,
	Team = Team,
	Teams = Teams,
	TeamPlayers = TeamPlayers,
	UserId = UserId,
	UserIds = TypeBuilder.List(UserId, { Name = "userIds" }),
	TeamSelector = TeamSelector,
	TagSelector = TagSelector,
}

return table.freeze(PlayerTypes)
