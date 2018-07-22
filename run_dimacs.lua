local dimacs = require "dimacs"

--------------------------------------------------------------------------------
table.unpack = table.unpack or unpack

local source = io.read "*all"
local cnf = dimacs(source)
local log = {}
local sat = cnf:isSatisfiable(log)
print("SAT:", not not sat)
if sat then
	for k, v in pairs(sat) do
		print("", k, "=>", v)
	end
end

-- print("LOG:")
-- for i, element in ipairs(log) do
-- 	print("", i, table.unpack(element))
-- end
