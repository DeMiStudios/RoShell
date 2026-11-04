--!strict
--[[
	Scheduled commands: `in 5m <cmd>`, `every 30s <cmd>`, `repeat 5 <cmd>`. Jobs run as their creator (permissions
	are re-checked each run), report to the creator's console, and are canceled when the creator leaves.
--]]

--// Imports
const Types = require(script.Parent.Parent.Shared.Types)
const Util = require(script.Parent.Parent.Shared.Util)

--// Types
export type Job = {
	Id: number,
	Owner: Player?,
	Text: string,
	--- Seconds between runs (repeating jobs).
	Interval: number?,
	--- Remaining runs (nil = until canceled for `every`).
	Remaining: number?,
	NextRun: number,
	Runs: number,
	_thread: thread?,
	_canceled: boolean,
}

export type Scheduler = {
	read Schedule: (self: Scheduler, owner: Player?, text: string, delay: number, interval: number?, count: number?) -> Job,
	read Cancel: (self: Scheduler, id: number, requester: Player?) -> boolean,
	read List: (self: Scheduler, owner: Player?) -> { Job },
	read CancelAll: (self: Scheduler, owner: Player?) -> number,
	_jobs: { [number]: Job },
	_nextId: number,
	_shell: Types.Shell,
	_output: (owner: Player?, block: Types.Block) -> (),
}

--// Constants
const MAX_JOBS_PER_OWNER = 25
const MIN_INTERVAL = 1

--// Scheduler Class
const Scheduler = {}
Scheduler.__index = Scheduler

const function runJob(self: Scheduler, job: Job)
	const shell = self._shell
	job.Runs += 1
	self._output(job.Owner, { Kind = "text", Text = `⏱ #{job.Id} {job.Text}`, Level = "muted" })
	shell.Dispatcher:Run({
		Text = job.Text,
		Executor = job.Owner,
		Options = { IsHuman = false, Yes = true },
		OnBlock = function(block: Types.Block)
			self._output(job.Owner, block)
		end,
	})
end

function Scheduler.Schedule(
	self: Scheduler,
	owner: Player?,
	text: string,
	delay: number,
	interval: number?,
	count: number?
): Job
	local owned = 0
	for _, job in self._jobs do
		if job.Owner == owner then
			owned += 1
		end
	end
	assert(owned < MAX_JOBS_PER_OWNER, `You already have {MAX_JOBS_PER_OWNER} scheduled commands`)
	self._nextId += 1
	const shell = self._shell
	const job: Job = {
		Id = self._nextId,
		Owner = owner,
		Text = text,
		Interval = if interval then math.max(interval, MIN_INTERVAL) else nil,
		Remaining = count,
		NextRun = shell.Platform.Clock() + delay,
		Runs = 0,
		_canceled = false,
	}
	self._jobs[job.Id] = job
	job._thread = shell.Platform.Spawn(function()
		local wait = delay
		while not job._canceled do
			shell.Platform.Wait(wait)
			if job._canceled then
				break
			end
			runJob(self, job)
			const remaining = job.Remaining
			if remaining then
				job.Remaining = remaining - 1
				if remaining - 1 <= 0 then
					break
				end
			end
			const step = job.Interval
			if step == nil then
				break
			end
			wait = step
			job.NextRun = shell.Platform.Clock() + step
		end
		self._jobs[job.Id] = nil
	end)
	return job
end

function Scheduler.Cancel(self: Scheduler, id: number, requester: Player?): boolean
	const job = self._jobs[id]
	if job == nil or (requester ~= nil and job.Owner ~= requester) then
		return false
	end
	job._canceled = true
	self._jobs[id] = nil
	const thread = job._thread
	if thread then
		self._shell.Platform.Cancel(thread)
	end
	return true
end

function Scheduler.List(self: Scheduler, owner: Player?): { Job }
	const jobs: { Job } = {}
	for _, job in self._jobs do
		if owner == nil or job.Owner == owner then
			table.insert(jobs, job)
		end
	end
	table.sort(jobs, function(a: Job, b: Job): boolean
		return a.Id < b.Id
	end)
	return jobs
end

function Scheduler.CancelAll(self: Scheduler, owner: Player?): number
	local canceled = 0
	for id, job in table.clone(self._jobs) do
		if job.Owner == owner then
			self:Cancel(id)
			canceled += 1
		end
	end
	return canceled
end

function Scheduler.new(shell: Types.Shell, output: (owner: Player?, block: Types.Block) -> ()): Scheduler
	return setmetatable({ _jobs = {}, _nextId = 0, _shell = shell, _output = output }, Scheduler)
end

--- Describes a job for listings.
function Scheduler.Describe(job: Job, now: number): string
	const due = math.max(0, job.NextRun - now)
	const repeatText = if job.Interval then ` every {Util.FormatDuration(job.Interval)}{if job.Remaining then ` ({job.Remaining} left)` else ""}`
		else ""
	return `#{job.Id} in {Util.FormatDuration(due)}{repeatText}: {job.Text}`
end

return table.freeze(Scheduler)
