local dimacs = require "dimacs"

local ALLOWED_FLAGS = {
	["--show-cnf"] = true,
	["--hide-cnf"] = true,
	["--show-model"] = true,
	["--hide-model"] = true,
	["--help"] = true,
	["--show-learned-clauses"] = true,
	["--hide-learned-clauses"] = true,
}

local HELP = [[
USAGE:
	lua run_dimacs.lua [--show-cnf] [--hide-cnf] [--show-model] [--hide-model] [--show-learned-clauses] [--hide-learned-clauses]
		Solve a DIMACS-style .cnf formula given on standard input
		Default: --hide-cnf --show-model --hide-learned-clauses

	lua run_dimacs.lua --help
		Show this help message
]]

local flags = {}
for i = 1, #arg do
	if flags[arg[i]] then
		-- No repeated flags
		print(HELP)
		os.exit(1)
	elseif not ALLOWED_FLAGS[arg[i]] then
		-- Invalid flag
		print(HELP)
		os.exit(1)
	end

	flags[arg[i]] = true
end

if flags["--show-cnf"] and flags["--hide-cnf"] then
	print(HELP)
	os.exit(1)
elseif flags["--show-model"] and flags["--hide-model"] then
	print(HELP)
	os.exit(1)
elseif flags["--show-learned-clauses"] and flags["--hide-learned-clauses"] then
	print(HELP)
	os.exit(1)
elseif flags["--help"] then
	print(HELP)
	os.exit(0)
end

--------------------------------------------------------------------------------
table.unpack = table.unpack or unpack

local source = io.read "*all"
local cnf = dimacs(source)

if flags["--show-cnf"] and not flags["--show-learned-clauses"] then
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

local before = #cnf:clauseList()

local log = {}
local sat = cnf:isSatisfiable(log)
print("SAT:", not not sat)

if not flags["--hide-model"] then
	if sat then
		for k, v in pairs(sat) do
			print("", k, "=>", v)
		end
	end
end

if flags["--show-learned-clauses"] then
	for row, clause in ipairs(cnf:clauseList()) do
		local s = {}
		for i = 1, 200 do
			s[i] = " "
		end
		for _, literal in ipairs(clause) do
			s[tonumber(literal[1]:sub(2))] = literal[2] and "T" or "~"
		end
		print(table.concat(s))
		if row == before then
			print(string.rep("-", 80))
		end
	end

	print("# Original: " .. before)
	print("# Learned:  " .. #cnf:clauseList() - before)
end
