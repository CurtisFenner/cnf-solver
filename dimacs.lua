local ClauseDatabase = require "clausedatabase"

-- RETURNS a CNF ClauseDatabase
local function dimacs(str)
	local cnf = ClauseDatabase.new()
	local clause = {}
	for line in str:gmatch "[^\n]+" do
		if line:match "^[-0-9][-0-9%s]*$" then
			for d in line:gmatch "-?%d+" do
				local n = tonumber(d)
				if n < 0 then
					table.insert(clause, {"x" .. -n, false})
				elseif 0 < n then
					table.insert(clause, {"x" .. n, true})
				elseif n == 0 then
					cnf:addClause(clause)
					clause = {}
				end
			end
		end
	end
	if #clause ~= 0 then
		cnf:addClause(clause)
	end
	return cnf
end

return dimacs
