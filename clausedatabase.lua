-- A CNF satisfiability decider

-- Uses the "rel_sat" Conflict Driven Clause Learning method described in
-- "Efficient Conflict Driven Learning in a Boolean Satisfiability Solver"
-- http://dl.acm.org/citation.cfm?id=603095.603153 (2001)
-- From the conflicting literals, each term assigned by unit propagation since
-- the most recent decision gets removed by resolution and replaced by the
-- negation of its antecedent clause

--------------------------------------------------------------------------------

setmetatable(_G, {
	__index = function(_, key)
		error("Attempt to read global `" .. tostring(key) .. "`", 2)
	end,
	__newindex = function(_, key)
		error("Attempt to write global `" .. tostring(key) .. "`", 2)
	end,
})

local MaxHeap = require "maxheap"

--------------------------------------------------------------------------------

-- A CNF satisfiability decider
local ClauseDatabase = {}

-- RETURNS an empty ClauseDatabase
-- Invoke :addClause(list of literals) to add clauses
-- After adding all clauses, invoke :isSatisfiable() to check satisfiability
function ClauseDatabase.new()
	local stats = {}
	local function compare(a, b)
		local sa, sb = stats[a], stats[b]
		local na = sa.nPos * sa.nNeg
		if na == 0 then
			na = math.huge
		end
		local nb = sb.nPos * sb.nNeg
		if nb == 0 then
			nb = math.huge
		end
		return na < nb
	end

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

		-- Statistics for branching
		_termHeap = MaxHeap.new(compare),

		-- {term => {nPos = int, nNeg = int}}
		_termStats = stats,
	}

	return setmetatable(instance, {__index = ClauseDatabase})
end

function ClauseDatabase:_initTerm(term)
	if self._termStats[term] == nil then
		self._termStats[term] = {
			-- The number of appearances of this term positively in
			-- unsatisfied clauses (zero when assigned a value)
			nPos = 0,

			-- The number of appearances of this term negatively in
			-- unsatisfied clauses (zero when assigned a value)
			nNeg = 0,
		}
		self._termHeap:push(term)
		self._termIndex[term] = {}
	end
end

-- RETURNS nothing
-- MODIFIES this clause database
function ClauseDatabase:addClause(rawClause)
	self:_validate()

	local literals = {}
	local countPositive = 0
	
	for _, literal in ipairs(rawClause) do
		local term, truth = literal[1], literal[2]
		assert(literals[term] == nil, "terms cannot be repeated")
		assert(truth == true or truth == false)
		if truth then
			countPositive = countPositive + 1
		end

		literals[term] = truth
	end

	local clause = {literals = literals, nYet = 0, nSat = 0, nPos = 0}

	-- Make the reverse index
	for term, truth in pairs(literals) do
		self:_initTerm(term)
		self._termIndex[term][clause] = true
		if self._assignment[term] == nil then
			clause.nYet = clause.nYet + 1
			if truth then
				clause.nPos = clause.nPos + 1
			end
		elseif self._assignment[term] == truth then
			clause.nSat = clause.nSat + 1
		end
	end

	local class = (clause.nSat ~= 0 and "satisfied") or (clause.nYet == 0 and "contradiction") or (clause.nYet == 1 and "unit") or "other"

	-- Update the term statistics
	if class == "unit" or class == "other" then
		for term, truth in pairs(literals) do
			if self._assignment[term] == nil then
				if truth then
					self._termStats[term].nPos = self._termStats[term].nPos + 1
				else
					self._termStats[term].nNeg = self._termStats[term].nNeg + 1
				end
				self._termHeap:update(term)
			end
		end
	end

	self._clauses[class][clause] = true
	clause.class = class

	table.insert(self._inputClauses, rawClause)
	self:_validate()
end

-- RETURNS nothing
-- MODIFIES this clause database to update the current assignment
function ClauseDatabase:assign(changeTerm, truth)
	assert(truth == true or truth == false or truth == nil)
	assert(changeTerm ~= nil, "term must not be nil")
	assert(self._termStats[changeTerm] ~= nil, "term must be in a clause")
	assert(self._assignment[changeTerm] ~= truth)
	self:_validate()
	
	-- Don't transition directly true <-> false
	if self._assignment[changeTerm] ~= nil and truth ~= nil then
		self:assign(changeTerm, nil)
	end

	-- Update the assignment
	local oldAssignment = self._assignment[changeTerm]
	self._assignment[changeTerm] = truth

	-- Update all the clauses that use this literal
	local statDeltas = {
	}
	if truth == nil then
		-- Freeing a literal
		for clause in pairs(self._termIndex[changeTerm]) do
			local oldClass = clause.class

			clause.nYet = clause.nYet + 1
			if clause.literals[changeTerm] == true then
				clause.nPos = clause.nPos + 1
			end

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
				
			local wasUnsatisfied = oldClass == "unit" or oldClass == "other"
			local isUnsatisfied = newClass == "unit" or newClass == "other"
			if wasUnsatisfied ~= isUnsatisfied then
				assert(isUnsatisfied)
				-- Update term statistics
				for clauseTerm, clauseTruth in pairs(clause.literals) do
					if self._assignment[clauseTerm] == nil then
						statDeltas[clauseTerm] = statDeltas[clauseTerm] or {[true] = 0, [false] = 0}
						statDeltas[clauseTerm][clauseTruth] = statDeltas[clauseTerm][clauseTruth] + 1
					end
				end
			elseif isUnsatisfied then
				statDeltas[changeTerm] = statDeltas[changeTerm] or {[true] = 0, [false] = 0}
				statDeltas[changeTerm][clause.literals[changeTerm]] = statDeltas[changeTerm][clause.literals[changeTerm]] + 1
			end
		end

		-- Add the term from the term-heap
		self._termHeap:push(changeTerm)
		assert(self._termStats[changeTerm].nPos == 0)
		assert(self._termStats[changeTerm].nNeg == 0)
	else
		-- Remove the term from the term-heap
		if self._termHeap:contains(changeTerm) then
			self._termHeap:remove(changeTerm)
		end
		self._termStats[changeTerm].nPos = 0
		self._termStats[changeTerm].nNeg = 0

		-- Satisfying/contradicting a literal
		for clause in pairs(self._termIndex[changeTerm]) do
			local oldClass = clause.class
			local wasHorn = clause.nPos <= 1

			clause.nYet = clause.nYet - 1
			if clause.literals[changeTerm] == true then
				clause.nPos = clause.nPos - 1
			end

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

				local wasUnsatisfied = oldClass == "unit" or oldClass == "other"
				local isUnsatisfied = newClass == "unit" or newClass == "other"

				if wasUnsatisfied ~= isUnsatisfied then
					assert(wasUnsatisfied)
					-- Update term statistics
					for t, needed in pairs(clause.literals) do
						if self._assignment[t] == nil then
							statDeltas[t] = statDeltas[t] or {[true] = 0, [false] = 0}
							statDeltas[t][needed] = statDeltas[t][needed] - 1
						end
					end
				end
			end
		end
	end

	-- Update the term statistics
	for term, statDelta in pairs(statDeltas) do
		self._termStats[term].nPos = self._termStats[term].nPos + statDelta[true]
		self._termStats[term].nNeg = self._termStats[term].nNeg + statDelta[false]
		self._termHeap:update(term)
	end

	self:_validate()
end

-- RETURNS false if there is no unit clause
-- RETURNS a term, an antecedent clause otherwise
function ClauseDatabase:_unitLiteral()
	self:_validate()

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
function ClauseDatabase:branchHeap()
	assert(not self:isSatisfied())
	assert(not self:isContradiction())
	self:_validate()

	local top = self._termHeap:pop()
	local assignment = 1 <= self._termStats[top].nPos
	return top, assignment
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

-- RETURNS nothing
function ClauseDatabase:_validate()
	do
		return
	end

	-- Verify that each clause class is correct
	local expectedStats = {}
	for term in pairs(self._termIndex) do
		expectedStats[term] = {[true] = 0, [false] = 0}
	end

	for className, class in pairs(self._clauses) do
		for clause in pairs(class) do
			assert(clause.class == className, "clause.class")

			local nSat, nPos, nYet = 0, 0, 0
			for term, truth in pairs(clause.literals) do
				if self._assignment[term] == nil then
					nYet = nYet + 1
					if truth then
						nPos = nPos + 1
					end
				elseif truth == self._assignment[term] then
					nSat = nSat + 1
				end
			end

			if nSat == 0 then
				for term, truth in pairs(clause.literals) do
					if self._assignment[term] == nil then
						expectedStats[term][truth] = expectedStats[term][truth] + 1
					end
				end
			end

			assert(clause.nSat == nSat, "clause.nSat")
			assert(clause.nYet == nYet, "clause.nYet")
			assert(clause.nPos == nPos, "clause.nPos was " .. clause.nPos .. " but expected " .. nPos)
			local class = (nSat ~= 0 and "satisfied") or (nYet == 0 and "contradiction") or (nYet == 1 and "unit") or "other"
			assert(clause.class == class, "clause.class")
		end
	end

	for term, expected in pairs(expectedStats) do
		assert(
			self._termStats[term].nPos == expected[true],
			"expected " .. term .. " #pos=" .. expected[true] .. " but got " .. self._termStats[term].nPos
		)
		assert(
			self._termStats[term].nNeg == expected[false],
			"expected " .. term .. " #neg=" .. expected[false] .. " but got " .. self._termStats[term].nNeg
		)
	end
end

-- RETURNS false when this this database is not satisfiable (with respect to
-- the current assignment)
-- RETURNS a satisfying assignment map {term => boolean} otherwise
function ClauseDatabase:isSatisfiable()
	if self:isContradiction() then
		return false
	end
	self:_validate()

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
				local term, value = self:branchHeap()
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
