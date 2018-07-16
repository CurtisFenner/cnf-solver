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
			satisfied = {},
			horn = {},
			unit = {},
			contradiction = {},
			other = {},
		},

		-- {term => {Clause => true}}
		_termIndex = {},

		-- {term => boolean}
		_assignment = {},
	}

	return setmetatable(instance, {__index = ClauseDatabase})
end

-- RETURNS a classification of the clause as one of the following:
-- * satisfied: the current assignment satisfies the clause
-- * contradiction: the current assignment contradicts this clause
-- * unit: the current assignment leaves exactly 1 literal unsatisfied
-- * horn: the current assignment leaves the clause a Horn-clause
-- * other: the current assignment leaves the clause as a non-Horn non-unit
--          unsatisfied and uncontradicted clause
function ClauseDatabase:_classifyClause(clause)
	-- Count the number of positive and negative literals in the clause
	local positive = 0
	local negative = 0
	for term, truth in pairs(clause) do
		if self._assignment[term] == truth then
			return "satisfied"
		elseif self._assignment[term] == nil then
			if truth then
				positive = positive + 1
			else
				negative = negative + 1
			end
		end
	end

	if positive + negative == 0 then
		return "contradiction"
	elseif positive + negative == 1 then
		return "unit"
	elseif positive == 1 then
		return "horn"
	end
	return "other"
end

-- RETURNS nothing
-- MODIFIES this clause database
function ClauseDatabase:addClause(rawClause)
	local clause = {}
	
	for _, literal in ipairs(rawClause) do
		local term, truth = literal[1], literal[2]
		assert(clause[term] == nil, "terms cannot be repeated")
		assert(type(truth) == "boolean")

		clause[term] = truth
	end

	-- Make the reverse index
	for term, truth in pairs(clause) do
		self._termIndex[term] = self._termIndex[term] or {}
		self._termIndex[term][clause] = true
	end

	-- Classify and the group the clause
	local class = self:_classifyClause(clause)
	self._clauses[class][clause] = true
end

-- RETURNS nothing
-- MODIFIES this clause database to update the current assignment
function ClauseDatabase:assign(term, truth)
	assert(truth == true or truth == false or truth == nil)
	assert(self._assignment[term] ~= truth)

	-- Initialize the term
	self._termIndex[term] = self._termIndex[term] or {}

	-- Remove clauses from their old class
	for clause in pairs(self._termIndex[term]) do
		local oldClass = self:_classifyClause(clause)
		assert(self._clauses[oldClass][clause])
		self._clauses[oldClass][clause] = nil
	end

	-- Update the assignment
	self._assignment[term] = truth

	-- Insert clauses into their new class
	for clause in pairs(self._termIndex[term]) do
		local newClass = self:_classifyClause(clause)
		self._clauses[newClass][clause] = true
	end
end

-- RETURNS false if there is no unit clause
-- RETURNS a literal otherwise
function ClauseDatabase:unitLiteral()
	local unit = next(self._clauses.unit)
	if not unit then
		return false
	end

	for term, truth in pairs(unit) do
		if self._assignment[term] == nil then
			return {term, truth}
		end
	end

	error "unreachable"
end

-- RETURNS false if there is no pure literal
-- RETURNS a pure literal otherwise
function ClauseDatabase:pureLiteral()
	print("TODO: implement :pureLiteral()")
	return false
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

-- RETURNS whether or not the current assignment leaves all unsatisfied clauses
-- as non-unit Horn clauses
function ClauseDatabase:isHorn()
	for key, set in pairs(self._clauses) do
		if next(set) ~= nil and key ~= "satisfied" and key ~= "horn" then
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
				for term, truth in pairs(clause) do
					if self._assignment[term] == nil then
						return term
					end
				end
			end
		end
	end

	error "unreachable"
end

-- RETURNS false when this this database is not satisfiable (with respect to
-- the current assignment)
-- RETURNS a satisfying assignment map {term => boolean} otherwise
-- MODIFIES log, if provided, to be a list of actions taken by the solver
function ClauseDatabase:isSatisfiable(log)
	log = log or {}

	local stack = {}
	while true do
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
			while self:isContradiction() or not reversed do
				if #stack == 0 then
					-- This CNF is not satisfiable
					return false
				end

				local top = table.remove(stack)
				reversed = reversed or top.decision
				self:assign(top.term, nil)
				n = n + 1
			end
			table.insert(log, {"Backtrack", n})
		end

		local unit = self:unitLiteral()
		if unit then
			-- Unit assignments are not branching
			table.insert(log, {"Unit", unit[1], unit[2]})
			table.insert(stack, {
				term = unit[1],
				assignment = unit[2],
			})
			self:assign(unit[1], unit[2])
		elseif self:isHorn() then
			-- Horn formulas without unit clauses are satisfiable by assigning
			-- all free terms to false
			local term = self:branchingTerm()
			table.insert(log, {"Horn", term})
			table.insert(stack, {
				decision = true,
				term = term,
				assignment = false,
			})
			self:assign(term, false)
		else
			-- Pure terms can be assigned their preferred truth value to reduce
			-- the problem size
			local pure = self:pureLiteral()
			if pure then
				table.insert(log, {"Pure", pure[1], pure[2]})
				table.insert(stack, {
					decision = true,
					term = pure[1],
					assignment = pure[2],
				})
				self:assign(pure[1], pure[2])
			else
				-- Pick an arbitrary term and branch
				local term = self:branchingTerm()
				table.insert(log, {"Branch", term})
				table.insert(stack, {
					decision = true,
					term = term,
					assignment = false,
				})
				self:assign(term, false)
			end
		end
	end
end

return ClauseDatabase
