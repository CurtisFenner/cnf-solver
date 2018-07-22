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

do
	local cnf = CNF.new()
	cnf:addClause {{"b", false}, {"c", true}}
	cnf:assign("b", true)
	cnf:assign("c", true)
	cnf:assign("c", nil)
	assert(not cnf:isSatisfied())
end

do
	local cnf = CNF.new()
	cnf:addClause {{"x", true}, {"y", true}}
	cnf:addClause {{"x", true}, {"y", false}}
	cnf:addClause {{"x", false}, {"y", true}}
	cnf:addClause {{"x", false}, {"y", false}}
	assert(not cnf:isSatisfiable())
end

do
	local cnf = CNF.new()
	cnf:addClause {{"a", true}, {"b", true}, {"c", true}, {"d", true}}
	cnf:addClause {{"a", false}, {"b", false}, {"c", false}}
	cnf:addClause {{"a", false}, {"b", false}, {"c", true}}
	cnf:addClause {{"a", false}, {"b", true}, {"c", false}}
	cnf:addClause {{"a", false}, {"b", true}, {"c", true}}
	cnf:addClause {{"a", true}, {"d", false}, {"c", true}, {"b", true}}
	cnf:addClause {{"a", true}, {"d", false}, {"c", false}, {"b", true}}

	local sat = cnf:isSatisfiable()
end
