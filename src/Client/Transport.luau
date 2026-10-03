--!strict
--[[
	The client side of the remote protocol: sends run requests, routes streamed blocks and prompts back to the
	command that is waiting for them, forwards cancellation, and narrows every server message.
]]

--// Imports
const Constants = require("../Shared/Constants")
const Net = require("../Shared/Net")
const Signal = require("../Shared/Signal")
const Types = require("../Shared/Types")

--// Types
export type Handshake = {
	Visible: { string },
	UserData: { [string]: unknown },
	IsStudio: boolean,
}

export type ClientTransport = {
	--- Matches `Types.Transport` so the dispatcher can use it directly.
	read RunRemote: (
		self: Types.Transport,
		request: Types.RemoteRunRequest,
		token: Types.CancelToken,
		onBlock: (block: Types.Block) -> (),
		onPrompt: ((prompt: Types.PromptRequest) -> Types.PromptAnswer)?
	) -> Types.CommandResult,
	read Connect: (timeout: number?) -> Handshake?,
	read SaveUserData: (key: string, value: unknown) -> (),
	read IsConnected: () -> boolean,
	--- Server announcements (`announce`), notifications (scheduled commands) and custom events.
	read Announced: Types.Signal<string, Types.Level, string?>,
	read Notified: Types.Signal<Types.Block>,
	read VisibilityChanged: Types.Signal<{ string }>,
	read CustomEvent: Types.Signal<string, unknown>,
}

type Pending = {
	OnBlock: (block: Types.Block) -> (),
	OnPrompt: ((prompt: Types.PromptRequest) -> Types.PromptAnswer)?,
}

--// Helpers

const function readLevel(value: unknown): Types.Level
	if value == "success" or value == "warning" or value == "error" or value == "muted" or value == "plain" then
		return value
	end
	return "info"
end

const function readNames(raw: unknown): { string }
	const names: { string } = {}
	if type(raw) == "table" then
		for _, name in pairs(raw) do
			if type(name) == "string" then
				table.insert(names, name)
			end
		end
	end
	return names
end

const function failed(message: string): Types.CommandResult
	return table.freeze({ Ok = false, Message = message, Value = nil, Blocks = {}, Duration = 0, Cancelled = false })
end

--// Transport
const Transport = {}

function Transport.new(shellName: string, registry: Types.Registry): ClientTransport
	const folderName = shellName .. "Remotes"
	local remoteFunction: RemoteFunction? = nil
	local remoteEvent: RemoteEvent? = nil
	local nextId = 0
	const pending: { [number]: Pending } = {}
	const announced: Types.Signal<string, Types.Level, string?> = Signal.new()
	const notified: Types.Signal<Types.Block> = Signal.new()
	const visibilityChanged: Types.Signal<{ string }> = Signal.new()
	const customEvent: Types.Signal<string, unknown> = Signal.new()

	const function onEvent(kind: unknown, payload: unknown)
		if kind == "Block" then
			const id = Net.Field(payload, "Id")
			const block = Net.ReadBlock(Net.Field(payload, "Block"))
			const waiting = if type(id) == "number" then pending[id] else nil
			if waiting and block then
				waiting.OnBlock(block)
			end
		elseif kind == "Prompt" then
			const id = Net.Field(payload, "Id")
			const promptId = Net.Field(payload, "PromptId")
			const prompt = Net.ReadPrompt(Net.Field(payload, "Prompt"))
			const waiting = if type(id) == "number" then pending[id] else nil
			const event = remoteEvent
			if type(promptId) == "number" and prompt and event then
				task.spawn(function()
					local answer: string? = nil
					if waiting and waiting.OnPrompt then
						answer = waiting.OnPrompt(prompt)
					end
					event:FireServer("PromptAnswer", { Id = id, PromptId = promptId, Answer = answer })
				end)
			end
		elseif kind == "Announcement" then
			const text = Net.Field(payload, "Text")
			const from = Net.Field(payload, "From")
			if type(text) == "string" then
				announced:Fire(
					text,
					readLevel(Net.Field(payload, "Level")),
					if type(from) == "string" then from else nil
				)
			end
		elseif kind == "Notify" then
			const block = Net.ReadBlock(Net.Field(payload, "Block"))
			if block then
				notified:Fire(block)
			end
		elseif kind == "Visible" then
			visibilityChanged:Fire(readNames(Net.Field(payload, "Visible")))
		elseif kind == "Custom" then
			const name = Net.Field(payload, "Name")
			if type(name) == "string" then
				customEvent:Fire(name, Net.Field(payload, "Payload"))
			end
		end
	end

	const function connect(timeout: number?): Handshake?
		const ReplicatedStorage = game:GetService("ReplicatedStorage")
		const folder = ReplicatedStorage:WaitForChild(folderName, timeout or 30)
		if folder == nil then
			return nil
		end
		const functionInstance = folder:WaitForChild("Function", 10)
		const eventInstance = folder:WaitForChild("Event", 10)
		if functionInstance == nil or eventInstance == nil then
			return nil
		end
		if not functionInstance:IsA("RemoteFunction") or not eventInstance:IsA("RemoteEvent") then
			return nil
		end
		remoteFunction = functionInstance
		remoteEvent = eventInstance
		eventInstance.OnClientEvent:Connect(onEvent)

		const ok, response = pcall(function(): unknown
			return functionInstance:InvokeServer("Handshake", { Protocol = Constants.ProtocolVersion })
		end)
		if not ok then
			return nil
		end
		const userData: { [string]: unknown } = {}
		const rawData = Net.Field(response, "UserData")
		if type(rawData) == "table" then
			for key, value in pairs(rawData) do
				if type(key) == "string" then
					userData[key] = value
				end
			end
		end
		if Net.Field(response, "Protocol") ~= Constants.ProtocolVersion then
			warn(`[{Constants.Name}] The server speaks a different protocol version; update both sides together.`)
		end
		return {
			Visible = readNames(Net.Field(response, "Visible")),
			UserData = userData,
			IsStudio = Net.Field(response, "IsStudio") == true,
		}
	end

	const function runRemote(
		_self: Types.Transport,
		request: Types.RemoteRunRequest,
		token: Types.CancelToken,
		onBlock: (block: Types.Block) -> (),
		onPrompt: ((prompt: Types.PromptRequest) -> Types.PromptAnswer)?
	): Types.CommandResult
		const functionInstance = remoteFunction
		const eventInstance = remoteEvent
		if functionInstance == nil or eventInstance == nil then
			return failed("Not connected to the server")
		end
		nextId += 1
		const id = nextId
		pending[id] = { OnBlock = onBlock, OnPrompt = onPrompt }
		const disconnect = token:OnCancel(function()
			eventInstance:FireServer("Cancel", { Id = id })
		end)
		const pipe = request.Pipe
		const ok, raw = pcall(function(): unknown
			return functionInstance:InvokeServer("Run", {
				Id = id,
				Text = request.Text,
				Dry = request.Options.Dry,
				Yes = request.Options.Yes,
				IsHuman = request.Options.IsHuman,
				Data = Net.Sanitize(request.Options.Data),
				Pipe = if pipe then { Ref = pipe.Ref, Text = pipe.Text } else nil,
			})
		end)
		disconnect()
		pending[id] = nil
		const result = if ok then Net.ReadResult(raw) else nil
		if result == nil then
			return failed(if ok then "Invalid server response" else `Request failed: {raw}`)
		end
		const typeName = result.TypeName
		return table.freeze({
			Ok = result.Ok,
			Command = result.Command,
			Message = result.Message,
			Value = result.Value,
			ValueType = if typeName then registry:GetType(typeName) else nil,
			Display = result.Display,
			Blocks = {},
			Duration = result.Duration,
			Cancelled = result.Cancelled,
			Ref = result.Ref,
		})
	end

	const transport: ClientTransport = {
		RunRemote = runRemote,
		Connect = connect,
		SaveUserData = function(key: string, value: unknown)
			const eventInstance = remoteEvent
			if eventInstance then
				eventInstance:FireServer("SaveUserData", { Key = key, Value = Net.Sanitize(value) })
			end
		end,
		IsConnected = function(): boolean
			return remoteFunction ~= nil
		end,
		Announced = announced,
		Notified = notified,
		VisibilityChanged = visibilityChanged,
		CustomEvent = customEvent,
	}
	return table.freeze(transport)
end

return table.freeze(Transport)
