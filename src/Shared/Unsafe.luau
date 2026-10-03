--!strict
--[[
	The single trust boundary between runtime schemas and static types.

	Some values are assembled at runtime from a schema whose static type is computed from that same schema by a
	type function: the `args` record of a command (schema: `Args`, type: `ArgsOf<A>`), tuple values
	(`RecordOf<M>`) and struct values (`StructOf<F>`). Luau cannot prove that a loop over the schema builds a
	value of the computed type, so these few call sites state it explicitly through `FromSchema`, always with
	an explicit type argument (`Unsafe.FromSchema<<V>>(record)`).

	Invariant upheld by every caller: each key of the record is a schema entry name and each value was produced
	by that entry's own `Type<T>.Parse` (or its typed default), i.e. it has exactly the type the type function
	assigned to that key. This invariant is covered by the type tests and the resolver/dispatcher unit tests.
]]

--// Unsafe
const Unsafe = {}

--- Gives a schema-built record its statically computed type. See the module comment for the invariant.
function Unsafe.FromSchema<T>(record: { [string]: unknown }): T
	return record :: T
end

--- Gives a value produced by one member of a union type its union type (`UnionOf<M>`). Invariant: `value` was
--- returned by the `Parse` of one of the union's members, whose value types `UnionOf<M>` is the union of.
function Unsafe.FromMember<T>(value: unknown): T
	return value :: T
end

--- Marks a value whose static type the call site asserts with `::`, for types computed by type functions
--- (`Unsafe.Assume(record) :: TypeFunctions.StructOf<F>`). Same invariant as `FromSchema`/`FromMember`.
--- (An explicit `FromSchema<<StructOf<F>>>` instantiation would be preferable, but crashes luau-lsp 1.70.1.)
function Unsafe.Assume(value: unknown): unknown
	return value
end

return table.freeze(Unsafe)
