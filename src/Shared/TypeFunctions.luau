--!strict
--[[
	User-defined type functions that compute precise types from RoShell definitions (requires the new Luau type
	solver). These are what make `Run(ctx, args)` receive a fully typed `args` record.

	- `ValueOf<Ty>`      value type of a `Type<T>` (T)
	- `ArgsOf<A>`        args record of a command's `Args` list: `{ { name = RoShell.Arg(...) }, ... }`
	- `RecordOf<M>`      record of a tuple's members: `{ { count = Count }, { item = Item } }` -> `{ count: number, item: Item }`
	- `StructOf<F>`      record of a struct's fields: `{ x = Number, y = Number }` -> `{ x: number, y: number }`
	- `UnionOf<M>`       union of the value types of a list of types
	- `EnumItemOf<E>`    item type of a Roblox Enum (`Enum.Material` -> `Enum.Material` items)

	Errors raised here surface as type errors at the use site with the message given.
]]

--// Type functions

--- Reads a property of a table type, looking through intersections (e.g. `Type<T> & { Invalidate: ... }`).
export type function PropertyOf(target, name)
	if target:is("table") then
		return target:readproperty(name) or types.never
	elseif target:is("intersection") then
		for _, component in target:components() do
			if component:is("table") then
				const found = component:readproperty(name)
				if found then
					return found
				end
			end
		end
	end
	return types.never
end

--- The value type `T` of a `Type<T>`.
export type function ValueOf(typeObject)
	local parse = nil
	if typeObject:is("table") then
		parse = typeObject:readproperty(types.singleton("Parse"))
	elseif typeObject:is("intersection") then
		for _, component in typeObject:components() do
			if component:is("table") and parse == nil then
				parse = component:readproperty(types.singleton("Parse"))
			end
		end
	end
	if parse == nil or not parse:is("function") then
		error("RoShell: expected a RoShell type (a value created with RoShell.Type.* or RoShell.Types.*)")
	end
	const result = parse:returns().head
	if result == nil or result[1] == nil then
		error("RoShell: a type's Parse must return a ParseResult")
	end
	const returned = result[1]
	const components = if returned:is("union") then returned:components() else { returned }
	for _, component in components do
		if component:is("table") then
			const value = component:readproperty(types.singleton("Value"))
			if value then
				return value
			end
		end
	end
	error("RoShell: could not determine the value type of a RoShell type")
end

--- The `args` record handed to command handlers, computed from the `Args` list.
export type function ArgsOf(argsList)
	const record = types.newtable()
	if not argsList:is("table") then
		return record
	end
	const indexer = argsList:readindexer()
	if indexer == nil then
		return record
	end
	const element = indexer.result
	if not element:is("table") and not element:is("union") then
		-- `Args = {}` infers an unknown/never element: no arguments.
		return record
	end
	const entries = if element:is("union") then element:components() else { element }
	for _, entry in entries do
		if not entry:is("table") then
			error("RoShell: each Args entry must be a table with one key, like { name = RoShell.Arg(RoShell.Types.String) }")
		end
		local keys = 0
		for key, property in entry:properties() do
			keys += 1
			const spec = property.read
			if spec == nil or not spec:is("table") then
				error("RoShell: Args values must be created with RoShell.Arg / Optional / Default / Rest / Flag / Dynamic")
			end
			const kindType = spec:readproperty(types.singleton("Kind"))
			const typeObject = spec:readproperty(types.singleton("Type"))
			if kindType == nil or typeObject == nil or not kindType:is("singleton") then
				error("RoShell: Args values must be created with RoShell.Arg / Optional / Default / Rest / Flag / Dynamic")
			end
			const kind = kindType:value()
			local value = ValueOf(typeObject)
			if kind == "optional" then
				value = types.unionof(value, types.singleton(nil))
			elseif kind == "rest" then
				value = types.newtable(nil, { index = types.number, readresult = value, writeresult = value })
			elseif kind == "dynamic" then
				value = types.unknown
			end
			record:setproperty(key, value)
		end
		if keys ~= 1 then
			error("RoShell: each Args entry must have exactly one key, like { name = RoShell.Arg(...) }")
		end
	end
	return record
end

--- Record of a tuple's members (`{ { name = Type }, ... }`).
export type function RecordOf(membersList)
	const record = types.newtable()
	if not membersList:is("table") then
		return record
	end
	const indexer = membersList:readindexer()
	if indexer == nil then
		return record
	end
	const element = indexer.result
	const entries = if element:is("union") then element:components() else { element }
	for _, entry in entries do
		if entry:is("table") then
			for key, property in entry:properties() do
				if property.read then
					record:setproperty(key, ValueOf(property.read))
				end
			end
		end
	end
	return record
end

--- Record of a struct's fields (`{ name = Type, ... }`).
export type function StructOf(fields)
	const record = types.newtable()
	if not fields:is("table") then
		error("RoShell: Struct fields must be a table of types")
	end
	for key, property in fields:properties() do
		if property.read then
			record:setproperty(key, ValueOf(property.read))
		end
	end
	return record
end

--- Union of the value types of a list of types.
export type function UnionOf(membersList)
	if not membersList:is("table") then
		error("RoShell: Union members must be a list of types")
	end
	const indexer = membersList:readindexer()
	if indexer == nil then
		error("RoShell: Union members must be a list of types")
	end
	const element = indexer.result
	const members = if element:is("union") then element:components() else { element }
	const values = {}
	for _, member in members do
		table.insert(values, ValueOf(member))
	end
	if #values == 1 then
		return values[1]
	end
	return types.unionof(table.unpack(values))
end

--- Item type of a Roblox Enum (`Enum.Material` -> items of type `Enum.Material`).
export type function EnumItemOf(enumObject)
	if enumObject:is("extern") or enumObject:is("class") then
		for key, property in enumObject:properties() do
			if key:value() == "GetEnumItems" and property.read then
				const list = property.read:returns().head[1]
				const listIndexer = list:readindexer()
				if listIndexer then
					return listIndexer.result
				end
			end
		end
	end
	error("RoShell.Type.FromEnum: expected a Roblox Enum such as Enum.Material")
end

return table.freeze({})
