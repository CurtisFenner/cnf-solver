

--------------------------------------------------------------------------------

-- A CNF satisfiability decider
local ClauseDatabase = {}

-- RETURNS an empty ClauseDatabase
-- Invoke :addClause(list of literals) to add clauses
-- After adding all clauses, invoke :isSatisfiable() to check satisfiability
function ClauseDatabase.new()
	local instance = {
		-- Clause = {term => boolean}

		-- {classname => {Clause => true}}
		_clauses = {
			contradiction = {},
			satisfied = {},
			unit = {},
			other = {},
		},

		-- {term => {Clause => true}}
		_termIndex = {},

		-- {term => boolean}
		_assignment = {},

		_inputClauses = {},
	}

	return setmetatable(instance, {__index = ClauseDatabase})
end

-- RETURNS nothing
-- MODIFIES this clause database
function ClauseDatabase:addClause(rawClause)
	local literals = {}
	
	for _, literal in ipairs(rawClause) do
		local term, truth = literal[1], literal[2]
		assert(literals[term] == nil, "terms cannot be repeated")
		assert(truth == true or truth == false)

		literals[term] = truth
	end

	local clause = {literals = literals, nYet = 0, nSat = 0}

	-- Make the reverse index
	for term, truth in pairs(literals) do
		self._termIndex[term] = self._termIndex[term] or {}
		self._termIndex[term][clause] = true
		if self._assignment[term] == nil then
			clause.nYet = clause.nYet + 1
		elseif self._assignment[term] == truth then
			clause.nSat = clause.nSat + 1
		end
	end

	local class = (clause.nSat ~= 0 and "satisfied") or (clause.nYet == 0 and "contradiction") or (clause.nYet == 1 and "unit") or "other"

	self._clauses[class][clause] = true
	clause.class = class

	table.insert(self._inputClauses, rawClause)
end

-- RETURNS nothing
-- MODIFIES this clause database to update the current assignment
function ClauseDatabase:assign(changeTerm, truth)
	assert(truth == true or truth == false or truth == nil)
	assert(changeTerm ~= nil, "term must not be nil")
	assert(self._assignment[changeTerm] ~= truth)
	
	-- Don't transition directly true <-> false
	if self._assignment[changeTerm] ~= nil and truth ~= nil then
		self:assign(changeTerm, nil)
	end

	-- Initialize the term
	self._termIndex[changeTerm] = self._termIndex[changeTerm] or {}

	-- Update the assignment
	local oldAssignment = self._assignment[changeTerm]
	self._assignment[changeTerm] = truth

	-- Update all the clauses that use this literal
	if truth == nil then
		-- Freeing a literal
		for clause in pairs(self._termIndex[changeTerm]) do
			local oldClass = clause.class

			clause.nYet = clause.nYet + 1
			if clause.literals[changeTerm] == oldAssignment then
				clause.nSat = clause.nSat - 1
			end

			-- Update the classification
			local newClass = (clause.nSat ~= 0 and "satisfied") or (clause.nYet == 0 and "contradiction") or (clause.nYet == 1 and "unit") or "other"
			if oldClass ~= newClass then
				-- TODO: This does not allow O(1) next!
				self._clauses[oldClass][clause] = nil
				self._clauses[newClass][clause] = true
				clause.class = newClass
			end
		end
	else
		-- Satisfying/contradicting a literal
		for clause in pairs(self._termIndex[changeTerm]) do
			local oldClass = clause.class

			clause.nYet = clause.nYet - 1
			if clause.literals[changeTerm] == truth then
				clause.nSat = clause.nSat + 1
			end

			-- Update the classification
			local newClass = (clause.nSat ~= 0 and "satisfied") or (clause.nYet == 0 and "contradiction") or (clause.nYet == 1 and "unit") or "other"
			if oldClass ~= newClass then
				-- TODO: This does not allow O(1) next!
				self._clauses[oldClass][clause] = nil
				self._clauses[newClass][clause] = true
				clause.class = newClass
			end
		end
	end
end

-- RETURNS false if there is no unit clause
-- RETURNS a literal otherwise
function ClauseDatabase:unitLiteral()
	local unit = next(self._clauses.unit)
	if not unit then
		return false
	end

	for term, truth in pairs(unit.literals) do
		if self._assignment[term] == nil then
			return {term, truth}
		end
	end

	error "unreachable"
end

-- RETURNS whether or not the current assignment contradicts the clauses
function ClauseDatabase:isContradiction()
	return next(self._clauses.contradiction) ~= nil
end

-- RETURNS whether or not the current assignment satisfies all clauses
function ClauseDatabase:isSatisfied()
	for key, set in pairs(self._clauses) do
		if next(set) ~= nil and key ~= "satisfied" then
			return false
		end
	end
	return true
end

-- RETURNS an unassigned term to branch on
-- REQUIRES this is not satisfied nor a contradiction
function ClauseDatabase:branchingTerm()
	assert(not self:isSatisfied())
	assert(not self:isContradiction())

	for key, set in pairs(self._clauses) do
		if key ~= "satisfied" then
			local clause = next(set)
			if clause then
				local positiveCount = 0
				local negativeCount = 0
				local positiveLiteral
				local negativeLiteral
				for term, truth in pairs(clause.literals) do
					if self._assignment[term] == nil then
						if truth then
							positiveCount = positiveCount + 1
							positiveLiteral = term
						else
							negativeCount = negativeCount + 1
							negativeLiteral = term
						end
					end
				end

				if (positiveCount <= 1 and negativeLiteral) or not positiveLiteral then
					return negativeLiteral, false
				end
				return positiveLiteral, true
			end
		end
	end

	error "unreachable"
end

function ClauseDatabase:clauseList()
	local copy = {}
	for i = 1, #self._inputClauses do
		copy[i] = self._inputClauses[i]
	end
	return copy
end

-- RETURNS false when this this database is not satisfiable (with respect to
-- the current assignment)
-- RETURNS a satisfying assignment map {term => boolean} otherwise
-- MODIFIES log, if provided, to be a list of actions taken by the solver
function ClauseDatabase:isSatisfiable(log)
	log = log or {}

	local stack = {}
	local ops = 0
	local begin = os.clock()
	local assignTime = 0
	local assigns = 0
	while true do
		ops = ops + 1
		if ops % 1e3 == 0 then
			print(math.floor(ops / (os.clock() - begin)) .. " ops/second", #self._inputClauses)
			print(string.format("\t%.2f", assignTime / (os.clock() - begin) * 100) .. "% spent assigning")
		end

		if self:isSatisfied() then
			-- Record the current assignment
			local satisfyingAssignment = {}
			for k, v in pairs(self._assignment) do
				satisfyingAssignment[k] = v
			end

			-- Return this database to the original assignment
			for _, e in ipairs(stack) do
				self:assign(e.term, nil)
			end

			table.insert(log, {"Done"})
			return satisfyingAssignment
		elseif self:isContradiction() then
			-- Forbid the current assignment: future assignments must differ
			-- in at least one of the decisions
			local newClause = {}
			for _, e in ipairs(stack) do
				if e.decision then
					table.insert(newClause, {e.term, not e.assignment})
				end
			end
			self:addClause(newClause)

			-- Backtrack
			local n = 0
			local reversed = false
			assignTime = assignTime - os.clock()
			while not reversed do
				if #stack == 0 then
					-- This CNF is not satisfiable
					table.insert(log, {"Done"})
					return false
				end
				
				local top = table.remove(stack)
				reversed = reversed or top.decision
				self:assign(top.term, nil)
				n = n + 1
			end
			assigns = assigns + n
			assignTime = assignTime + os.clock()

			table.insert(log, {"Backtrack", n})
		else
			local unit = self:unitLiteral()
			if unit then
				-- Unit assignments are not branching
				table.insert(log, {"Unit", unit[1], unit[2]})
				assert(unit[2] == true or unit[2] == false)
				table.insert(stack, {
					term = unit[1],
					assignment = unit[2],
					decision = false,
				})
				assignTime = assignTime - os.clock()
				self:assign(unit[1], unit[2])
				assignTime = assignTime + os.clock()
			else
				-- Pick an arbitrary term and branch
				local term, value = self:branchingTerm()
				assert(value == true or value == false)
				table.insert(log, {"Branch", term})
				table.insert(stack, {
					decision = true,
					term = term,
					assignment = value,
				})

				assignTime = assignTime - os.clock()
				self:assign(term, value)
				assignTime = assignTime + os.clock()
			end
			assigns = assigns + 1
		end
	end
end

return ClauseDatabase
