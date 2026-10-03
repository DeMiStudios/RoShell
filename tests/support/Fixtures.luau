--!strict
--[[
	Request builders for unit tests (headless platform, fake shell handle).
]]

const Platform = require("../../src/Shared/Platform")
const Types = require("../../src/Shared/Types")

export type RequestOptions = {
	Quoted: boolean?,
	Final: boolean?,
	Executor: Player?,
	Platform: Types.PlatformInfo?,
}

const DEFAULT_CONTROLLER = Platform.Headless(4242)
const HANDLE: Types.ShellHandle = { Name = "test", Id = 0 }

const Fixtures = {}

Fixtures.Controller = DEFAULT_CONTROLLER
Fixtures.Handle = HANDLE

function Fixtures.Parse(text: string, options: RequestOptions?): Types.ParseRequest
	const opts: RequestOptions = options or {}
	return {
		Text = text,
		Quoted = opts.Quoted == true,
		Span = { Start = 1, End = #text + 1 },
		Executor = opts.Executor,
		Shell = HANDLE,
		Platform = opts.Platform or DEFAULT_CONTROLLER.Platform,
		Final = opts.Final == true,
	}
end

function Fixtures.Complete(text: string, limit: number?): Types.CompleteRequest
	return {
		Text = text,
		Quoted = false,
		Shell = HANDLE,
		Platform = DEFAULT_CONTROLLER.Platform,
		Limit = limit or 50,
	}
end

--- Parses `text` with `valueType` and returns the value, erroring with the parse message on failure.
function Fixtures.Value<T>(valueType: Types.Type<T>, text: string, options: RequestOptions?): T
	const result = valueType.Parse(Fixtures.Parse(text, options))
	if not result.Ok then
		error(`expected '{text}' to parse as {valueType.Name}: {result.Error}`, 2)
	end
	return result.Value
end

--- Parses `text` and returns the error message, erroring if it parsed.
function Fixtures.Error<T>(valueType: Types.Type<T>, text: string, options: RequestOptions?): string
	const result = valueType.Parse(Fixtures.Parse(text, options))
	if result.Ok then
		error(`expected '{text}' to fail as {valueType.Name}`, 2)
	end
	return result.Error
end

--- Texts of the completion suggestions for `text`.
function Fixtures.Suggest<T>(valueType: Types.Type<T>, text: string, limit: number?): { string }
	const texts: { string } = {}
	for _, suggestion in valueType.Complete(Fixtures.Complete(text, limit)) do
		table.insert(texts, suggestion.Text)
	end
	return texts
end

return table.freeze(Fixtures)
