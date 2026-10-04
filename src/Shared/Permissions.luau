--!strict
--[[
	Permissions. Default deny: a command runs for a player only when its `Permissions` (or its parent's, or its
	group's mapping set with `shell.Permissions:SetGroup`) grants it. Server/console execution (no player) is
	always allowed, and everything is allowed in Studio unless `StudioBypass = false`.

		Permissions = RoShell.Permissions.Allow({ Users = { 123 }, Group = { Id = 456, MinRank = 200 } })
		shell.Permissions:SetGroup("Admin", RoShell.Permissions.Role("Moderator"))
		shell.Permissions:DefineRole("Moderator", RoShell.Permissions.Group(456, 100))

	Checks that need the network (group rank, game pass, badge) are cached per player for a minute and only run
	where they are allowed to yield (right before execution, or when the server builds a visibility list).
]]

--// Imports
const ShellDirectory = require("./ShellDirectory")
const Types = require("./Types")

--// Types
type Permission = Types.Permission
type PermissionRequest = Types.PermissionRequest
type PermissionManager = Types.PermissionManager

export type AllowSpec = {
	Everyone: boolean?,
	Users: { number }?,
	Group: { Id: number, MinRank: number? }?,
	Groups: { { Id: number, MinRank: number? } }?,
	Role: string?,
	Roles: { string }?,
	Gamepass: number?,
	Badge: number?,
	Studio: boolean?,
	Predicate: ((player: Player?, command: Types.Command, args: Types.ArgValues?) -> boolean)?,
}

--// Constants
const CACHE_SECONDS = 60
const MAX_ROLE_DEPTH = 8

--// Globals
-- Guards against roles that (directly or indirectly) reference themselves.
local roleDepth = 0

--// Helpers

const function make(kind: string, check: (request: PermissionRequest) -> boolean, describe: () -> string): Permission
	return table.freeze({ Kind = kind, Check = check, Describe = describe })
end

--- Caches a yielding boolean lookup per (player, key) for CACHE_SECONDS.
const function cached(lookup: (player: Player) -> boolean): (player: Player, now: number) -> boolean
	const cache: { [Player]: { Value: boolean, Expires: number } } = setmetatable({}, { __mode = "k" })
	return function(player: Player, now: number): boolean
		const entry = cache[player]
		if entry and entry.Expires > now then
			return entry.Value
		end
		const ok, value = pcall(lookup, player)
		const result = ok and value == true
		cache[player] = { Value = result, Expires = now + CACHE_SECONDS }
		return result
	end
end

--- Reads a field of an untyped engine result (`unknown` until narrowed).
const function field(value: unknown, key: string): unknown
	if type(value) == "table" then
		for name, item in pairs(value) do
			if name == key then
				return item
			end
		end
	end
	return nil
end

--- Highest rank in a `GroupService:GetRolesInGroupAsync` result (0 when not a member).
const function highestRank(result: unknown): number
	if field(result, "IsMember") ~= true then
		return 0
	end
	local best = 0
	const roles = field(result, "Roles")
	if type(roles) == "table" then
		for _, role in pairs(roles) do
			const roleRank = field(role, "Rank")
			if type(roleRank) == "number" and roleRank > best then
				best = roleRank
			end
		end
	end
	return best
end

const function clock(request: PermissionRequest): number
	return request.Shell.Platform.Clock()
end

--// Permissions
const Permissions = {}

--- Everyone may run the command.
function Permissions.Everyone(): Permission
	return make("everyone", function(): boolean
		return true
	end, function(): string
		return "everyone"
	end)
end

--- Nobody may run the command (players); server/console execution still works.
function Permissions.Nobody(): Permission
	return make("nobody", function(): boolean
		return false
	end, function(): string
		return "nobody"
	end)
end

--- Only the listed user ids.
function Permissions.Users(userIds: { number }): Permission
	const allowed: { [number]: true } = {}
	for _, userId in userIds do
		allowed[userId] = true
	end
	return make("users", function(request: PermissionRequest): boolean
		return request.Player ~= nil and allowed[request.Player.UserId] == true
	end, function(): string
		return `{#userIds} specific user(s)`
	end)
end

--- Members of a Roblox group with at least `minimumRank` (default 1).
function Permissions.Group(groupId: number, minimumRank: number?): Permission
	const rank = minimumRank or 1
	const check = cached(function(player: Player): boolean
		return highestRank(game:GetService("GroupService"):GetRolesInGroupAsync(player.UserId, groupId)) >= rank
	end)
	return make("group", function(request: PermissionRequest): boolean
		return request.Player ~= nil and check(request.Player, clock(request))
	end, function(): string
		return `group {groupId} rank ≥ {rank}`
	end)
end

--- Owners of a game pass.
function Permissions.Gamepass(gamePassId: number): Permission
	const check = cached(function(player: Player): boolean
		return game:GetService("MarketplaceService"):UserOwnsGamePassAsync(player.UserId, gamePassId)
	end)
	return make("gamepass", function(request: PermissionRequest): boolean
		return request.Player ~= nil and check(request.Player, clock(request))
	end, function(): string
		return `game pass {gamePassId}`
	end)
end

--- Owners of a badge.
function Permissions.Badge(badgeId: number): Permission
	const check = cached(function(player: Player): boolean
		return game:GetService("BadgeService"):UserHasBadgeAsync(player.UserId, badgeId)
	end)
	return make("badge", function(request: PermissionRequest): boolean
		return request.Player ~= nil and check(request.Player, clock(request))
	end, function(): string
		return `badge {badgeId}`
	end)
end

--- A named role defined with `shell.Permissions:DefineRole(name, permission)`.
function Permissions.Role(role: string): Permission
	return make("role", function(request: PermissionRequest): boolean
		const definition = request.Shell.Permissions:GetRole(role)
		if definition == nil or roleDepth >= MAX_ROLE_DEPTH then
			return false
		end
		roleDepth += 1
		const ok, result = pcall(definition.Check, request)
		roleDepth -= 1
		return ok and result == true
	end, function(): string
		return `role {role}`
	end)
end

--- A custom predicate. `args` is only available right before execution.
function Permissions.Predicate(
	check: (player: Player?, command: Types.Command, args: Types.ArgValues?) -> boolean,
	description: string?
): Permission
	return make("predicate", function(request: PermissionRequest): boolean
		return check(request.Player, request.Command, request.Args)
	end, function(): string
		return description or "custom rule"
	end)
end

--- Allowed only while running in Studio.
function Permissions.Studio(): Permission
	return make("studio", function(request: PermissionRequest): boolean
		return request.Shell.Platform.IsStudio()
	end, function(): string
		return "Studio only"
	end)
end

--- Granted when any of the permissions grants.
function Permissions.Any(permissions: { Permission }): Permission
	return make("any", function(request: PermissionRequest): boolean
		for _, permission in permissions do
			if permission.Check(request) then
				return true
			end
		end
		return false
	end, function(): string
		const parts: { string } = {}
		for _, permission in permissions do
			table.insert(parts, permission.Describe())
		end
		return table.concat(parts, " or ")
	end)
end

--- Granted when all of the permissions grant.
function Permissions.All(permissions: { Permission }): Permission
	return make("all", function(request: PermissionRequest): boolean
		for _, permission in permissions do
			if not permission.Check(request) then
				return false
			end
		end
		return true
	end, function(): string
		const parts: { string } = {}
		for _, permission in permissions do
			table.insert(parts, permission.Describe())
		end
		return table.concat(parts, " and ")
	end)
end

--- Inverts a permission.
function Permissions.Not(permission: Permission): Permission
	return make("not", function(request: PermissionRequest): boolean
		return not permission.Check(request)
	end, function(): string
		return "not " .. permission.Describe()
	end)
end

--- Convenience: grants when any listed rule matches.
--- `Allow({ Users = { 1 }, Group = { Id = 2, MinRank = 100 }, Role = "Mod", Studio = true })`
function Permissions.Allow(spec: AllowSpec): Permission
	const rules: { Permission } = {}
	if spec.Everyone then
		table.insert(rules, Permissions.Everyone())
	end
	if spec.Users then
		table.insert(rules, Permissions.Users(spec.Users))
	end
	if spec.Group then
		table.insert(rules, Permissions.Group(spec.Group.Id, spec.Group.MinRank))
	end
	for _, group in spec.Groups or {} do
		table.insert(rules, Permissions.Group(group.Id, group.MinRank))
	end
	if spec.Role then
		table.insert(rules, Permissions.Role(spec.Role))
	end
	for _, role in spec.Roles or {} do
		table.insert(rules, Permissions.Role(role))
	end
	if spec.Gamepass then
		table.insert(rules, Permissions.Gamepass(spec.Gamepass))
	end
	if spec.Badge then
		table.insert(rules, Permissions.Badge(spec.Badge))
	end
	if spec.Studio then
		table.insert(rules, Permissions.Studio())
	end
	if spec.Predicate then
		table.insert(rules, Permissions.Predicate(spec.Predicate))
	end
	if #rules == 1 then
		return rules[1]
	end
	return Permissions.Any(rules)
end

--// Permission manager
const ManagerClass = {}
ManagerClass.__index = ManagerClass

--- The permission that governs a command: its own, its parent's, or its group's.
const function governing(self: PermissionManager, command: Types.Command): Permission?
	local current: Types.Command? = command
	while current do
		if current.Permissions then
			return current.Permissions
		end
		if current.Group and self._groups[current.Group] then
			return self._groups[current.Group]
		end
		current = current._parent
	end
	return nil
end

function ManagerClass.SetGroup(self: PermissionManager, group: string, permission: Permission)
	self._groups[group] = permission
end

function ManagerClass.GetGroup(self: PermissionManager, group: string): Permission?
	return self._groups[group]
end

function ManagerClass.DefineRole(self: PermissionManager, role: string, permission: Permission)
	self._roles[role] = permission
end

function ManagerClass.GetRole(self: PermissionManager, role: string): Permission?
	return self._roles[role]
end

function ManagerClass.SetAdmins(self: PermissionManager, permission: Permission?)
	self._admins = permission
end

function ManagerClass.CanRun(self: PermissionManager, player: Player?, command: Types.Command, args: Types.ArgValues?): (boolean, string?)
	if player == nil then
		return true, nil
	end
	const shell = ShellDirectory.Expect(self._handle)
	if shell.Options.StudioBypass ~= false and shell.Platform.IsStudio() then
		return true, nil
	end
	const visibility = self._visibility
	if visibility then
		-- Client side: mirror the server's decision (subcommands follow their root command).
		local root = command
		while root._parent do
			root = root._parent
		end
		if visibility[root.Name] or root._isAlias then
			return true, nil
		end
		return false, shell.Locale:Get("run.permissionDenied", { command = command.Name })
	end
	const request: PermissionRequest = { Player = player, Command = command, Shell = shell, Args = args }
	const admins = self._admins
	if admins then
		const ok, granted = pcall(admins.Check, request)
		if ok and granted then
			return true, nil
		end
	end
	const permission = governing(self, command)
	if permission == nil then
		return false, shell.Locale:Get("run.permissionDenied", { command = command.Name })
	end
	const ok, granted = pcall(permission.Check, request)
	if ok and granted then
		return true, nil
	end
	return false, shell.Locale:Get("run.permissionDenied", { command = command.Name })
end

function ManagerClass.CanSee(self: PermissionManager, player: Player?, command: Types.Command): boolean
	if command.Hidden then
		return false
	end
	return (self:CanRun(player, command, nil))
end

table.freeze(ManagerClass)

--- Creates the permission manager of a shell.
function Permissions.Manager(handle: Types.ShellHandle): PermissionManager
	return setmetatable(
		{
			_groups = {},
			_roles = {},
			_admins = nil :: Permission?,
			_handle = handle,
			_visibility = nil :: { [string]: true }?,
		},
		ManagerClass
	)
end

return table.freeze(Permissions)
