-- A CNF satisfiability decider

-- Uses the "rel_sat" Conflict Driven Clause Learning method described in
-- "Efficient Conflict Driven Learning in a Boolean Satisfiability Solver"
-- http://dl.acm.org/citation.cfm?id=603095.603153 (2001)
-- From the conflicting literals, each term assigned by unit propagation since
-- the most recent decision gets removed by resolution and replaced by the
-- negation of its antecedent clause

-- Uses the Variable State Independent Decaying Sum heuristic from
-- "Chaff: Engineering an Efficient SAT Solver" (2001)
-- https://dl.acm.org/citation.cfm?doid=378239.379017
-- Each new clause (including conflict clauses) bumps the priority of a literal
-- by 1. Each new conflict reduces the priority of all literals by a constant
-- (here, approximately 93.3%). Branching selects (approximately) the literal
-- with the highest priority

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

		-- Statistics for VSIDS
		_termQueueRead = 1,
		_termGeneration = 0,
		_termQueue = {},
		_termQueueIndex = {},
	}

	return setmetatable(instance, {__index = ClauseDatabase})
end

function ClauseDatabase:_bumpTerm(term, truth)
	local f = self._termQueueIndex[term][truth]
	local moving = self._termQueue[f]

	-- Decay and bump
	moving.count = moving.count / 2 ^ (self._termGeneration - moving.generation) + 1
	moving.generation = self._termGeneration

	-- Do a Shell-sort like update, moving the updated term towards the front
	-- of the queue
	for stepIndex = 10, 0, -1 do
		local step = 2 ^ stepIndex
		while self._termQueueRead <= f - step do
			-- Decay
			local previous = self._termQueue[f - step]
			previous.count = previous.count / 2 ^ (self._termGeneration - previous.count)
			previous.generation = self._termGeneration

			if previous.count < moving.count then
				-- Swap
				self._termQueue[f - step], self._termQueue[f] = self._termQueue[f], self._termQueue[f - step]

				-- Update the index
				self._termQueueIndex[previous.term][previous.assignment] = f
				self._termQueueIndex[term][truth] = f - step

				-- Move the cursor back
				f = f - step
			else
				-- Stop
				break
			end
		end
	end
end

function ClauseDatabase:_initTerm(term)
	if not self._termQueueIndex[term] then
		self._termIndex[term] = {}
		local index = #self._termQueue + 1
		self._termQueue[index] = {
			term = term,
			assignment = false,
			count = 0,
			generation = self._termGeneration,
		}
		self._termQueue[index + 1] = {
			term = term,
			assignment = true,
			count = 0,
			generation = self._termGeneration,
		}
		self._termQueueIndex[term] = {
			[false] = index,
			[true] = index + 1,
		}
	end
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

	-- Decay all previous statistics
	self._termGeneration = self._termGeneration + 0.1

	-- Make the reverse index
	for term, truth in pairs(literals) do
		self:_initTerm(term)
		self._termIndex[term][clause] = true
		if self._assignment[term] == nil then
			clause.nYet = clause.nYet + 1
		elseif self._assignment[term] == truth then
			clause.nSat = clause.nSat + 1
		end

		self:_bumpTerm(term, truth)
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
	self:_initTerm(changeTerm)

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
-- RETURNS a term, an antecedent clause otherwise
function ClauseDatabase:_unitLiteral()
	local unitClause = next(self._clauses.unit)
	if not unitClause then
		return false
	end

	for term, truth in pairs(unitClause.literals) do
		if self._assignment[term] == nil then
			return term, unitClause
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
function ClauseDatabase:branchVSIDS()
	assert(not self:isSatisfied())
	assert(not self:isContradiction())

	local top
	repeat
		top = self._termQueue[self._termQueueRead]
		assert(top)
		self._termQueueRead = self._termQueueRead + 1
	until self._assignment[top.term] == nil
	return top.term, top.assignment
end

-- RETURNS an unassigned term to branch on
-- REQUIRES this is not satisfied nor a contradiction
function ClauseDatabase:branchingAny()
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

-- RETURNS a conflict clause that simply uses all of the decision terms
function ClauseDatabase:_diagnoseDecision(stack)

	local conflict = {}
	for _, e in ipairs(stack) do
		if e.decision then
			table.insert(conflict, {e.term, not e.assignment})
		end
	end
	return conflict
end

-- RETURNS a conflict clause corresponding to "rel sat" algorithm:
-- Back up the conflicting literals until there is no mention of the current
-- decision level (other the decision term for the current level)
function ClauseDatabase:_diagnoseRelSat(stack, antecedents)
	assert(stack[#stack], "stack must not be empty")
	
	local conflictTerm = stack[#stack].term
	local currentDecisionLevel = antecedents[conflictTerm].decisionLevel
	local conflictingClause = next(self._clauses.contradiction)
	assert(conflictingClause.literals[conflictTerm] ~= nil)

	local seen = {}
	local frontier = {}

	for otherTerm, otherTruth in pairs(conflictingClause.literals) do
		if otherTerm ~= conflictTerm then
			if not seen[otherTerm] then
				seen[otherTerm] = true
				table.insert(frontier, otherTerm)
			end
		end
	end

	for otherTerm, otherTruth in pairs(antecedents[conflictTerm].clause.literals) do
		if otherTerm ~= conflictTerm then
			if not seen[otherTerm] then
				seen[otherTerm] = true
				table.insert(frontier, otherTerm)
			end
		end
	end

	local conflictClause = {}
	while #frontier ~= 0 do
		local top = table.remove(frontier)
		local antecedent = antecedents[top]
		if antecedent.decisionLevel < currentDecisionLevel or not antecedent.clause then
			table.insert(conflictClause, {top, not self._assignment[top]})
		else
			-- "Back up" into the antecedent
			for otherTerm, otherTruth in pairs(antecedent.clause.literals) do
				if otherTerm ~= top then
					if not seen[otherTerm] then
						seen[otherTerm] = true
						table.insert(frontier, otherTerm)
					end
				end
			end
		end
	end

	return conflictClause
end

-- RETURNS false when this this database is not satisfiable (with respect to
-- the current assignment)
-- RETURNS a satisfying assignment map {term => boolean} otherwise
function ClauseDatabase:isSatisfiable()
	if self:isContradiction() then
		return false
	end

	-- State
	local stack = {}
	local decisionLevel = 0
	local antecedents = {}

	-- Run DPLL loop with CDCL
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
			local conflict = self:_diagnoseRelSat(stack, antecedents)
			self:addClause(conflict)

			local badLevel = 0
			for _, literal in ipairs(conflict) do
				badLevel = math.max(badLevel, antecedents[literal[1]].decisionLevel)
			end

			if badLevel == 0 then
				-- Undo all assignments made by this search
				for _, e in ipairs(stack) do
					self:assign(e.term, nil)
				end

				-- This CNF is not satisfiable, since there is a contradiction
				-- even with no decisions
				return false
			end

			-- Backtrack
			while badLevel <= decisionLevel do
				assert(#stack ~= 0)

				local top = table.remove(stack)
				if top.decision then
					decisionLevel = decisionLevel - 1
					repeat
						self._termQueueRead = self._termQueueRead - 1
						local head = self._termQueue[self._termQueueRead]
					until head.term == top.term and head.assignment == top.assignment
				end
				antecedents[top.term] = nil
				self:assign(top.term, nil)
			end
		else
			local unitTerm, unitAntecedent = self:_unitLiteral()
			if unitTerm then
				-- Unit assignments are not branching
				local truth = unitAntecedent.literals[unitTerm]
				table.insert(stack, {
					term = unitTerm,
					assignment = truth,
					decision = false,
				})
				self:assign(unitTerm, truth)

				-- Update implication graph
				antecedents[unitTerm] = {
					clause = unitAntecedent,
					decisionLevel = decisionLevel,
				}
			else
				-- Pick an arbitrary term and branch
				local term, value = self:branchVSIDS()
				assert(value == true or value == false)
				table.insert(stack, {
					decision = true,
					term = term,
					assignment = value,
				})

				decisionLevel = decisionLevel + 1
				antecedents[term] = {
					decisionLevel = decisionLevel,
				}
				self:assign(term, value)
			end
		end
	end
end

return ClauseDatabase
