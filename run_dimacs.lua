local dimacs = require "dimacs"

--------------------------------------------------------------------------------

local source = io.read "*all"
local cnf = dimacs(source)
local sat = cnf:isSatisfiable()
print("SAT:", not not sat)
if sat then
	for k, v in pairs(sat) do
		print("", k, "=>", v)
	end
end
