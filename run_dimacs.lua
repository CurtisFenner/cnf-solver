local dimacs = require "dimacs"

--------------------------------------------------------------------------------
table.unpack = table.unpack or unpack

local source = io.read "*all"
local cnf = dimacs(source)

if false then
	for _, clause in ipairs(cnf:clauseList()) do
		io.write("& (")
		for i, literal in ipairs(clause) do
			if i ~= 1 then
				io.write(" | ")
			end

			if literal[2] == false then
				io.write("~")
			end
			io.write(literal[1])
		end
		print(")")
	end
end

local log = {}
local sat = cnf:isSatisfiable(log)
print("SAT:", not not sat)

if false then
	if sat then
		for k, v in pairs(sat) do
			print("", k, "=>", v)
		end
	end
end
