local CNF = require "clausedatabase"

do
	local cnf = CNF.new()
	cnf:addClause {{"a", true}, {"b", true}}
	cnf:addClause {{"b", false}}
	local sat = cnf:isSatisfiable()
	assert(sat)
	assert(sat.a == true)
	assert(sat.b == false)
end

do
	local cnf = CNF.new()
	cnf:addClause {{"a", true}}
	cnf:addClause {{"a", false}}
	local sat = cnf:isSatisfiable()
	assert(not sat)
end
