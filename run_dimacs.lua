local dimacs = require "dimacs"

local ALLOWED_FLAGS = {
	["--show-cnf"] = true,
	["--hide-cnf"] = true,
	["--show-model"] = true,
	["--hide-model"] = true,
	["--help"] = true,
}

local HELP = [[
USAGE:
	lua run_dimacs.lua [--show-cnf] [--hide-cnf] [--show-model] [--hide-model]
		Solve a DIMACS-style .cnf formula given on standard input
		Default: --hide-cnf --show-model

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
elseif flags["--help"] then
	print(HELP)
	os.exit(0)
end

--------------------------------------------------------------------------------
table.unpack = table.unpack or unpack

local source = io.read "*all"
local cnf = dimacs(source)

if flags["--show-cnf"] then
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

if not flags["--hide-model"] then
	if sat then
		for k, v in pairs(sat) do
			print("", k, "=>", v)
		end
	end
end
