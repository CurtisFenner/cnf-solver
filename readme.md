# cnf-solver, a simple CNF-SAT solver

The CNF-SAT problem is a well-known and well-studied NP-complete problem. This
means computer scientists and mathematicians believe there is no algorithm that
is guaranteed to terminate in polynomial time (or even in sub-exponential time).

Despite this theoretical limitation, many approaches have been found to solve
many instances of the CNF-SAT problem very quickly. Two early methods have
proven extremely effective:

* Unit propagation (aka boolean constraint propagation):
    force an assignment whenever a clause has only one remaining literal
* Conflict Driven Clause Learning (CDCL):
    add additional clauses to prune the search space further

cnf-solver implements these in Lua with thorough documentation. Lua was chosen
because it is simple, readable, and portable. These features make this
cnf-solver very easy to run and learn from.

## Getting started

These instructions explain how to use the scripts provided to solve (small) CNF
instances.

### Prerequisites

You need a version of [Lua](https://lua.org) to run the CNF solver. You may
already have Lua installed on your system; try `lua -v` to see the version.

This project is compatible with Lua versions 5.1, 5.2, and 5.3, in addition to
LuaJIT. LuaJIT runs the solver 2x-3x faster than the standard Lua interpreter.

### Solving DIMACS .cnf files

The `run_dimacs.lua` script can read simple DIMACS-style .cnf files. Check out
[the example inputs](input) for what this format looks like.

    $ lua run_dimacs.lua < input/too_hard.cnf
    SAT:    true
            x7      =>      true
            x6      =>      false
            x5      =>      false
            x4      =>      true
            x2      =>      true
            x3      =>      true
            x1      =>      false
            x8      =>      false
            x9      =>      false

## Using the ClauseDatabase library

Require the Lua library as usual. A CNF formula is created by calling the
`CNF.new()` constructor.

    local CNF = require "clausedatabase"
    local formula = CNF.new()

Add clauses to the formula by invoking `:addClause`. Clauses are passed as lists
of *literals*, where each literal is a `{term, truth}` pair. For example,
"(not a) or b" can be encoded as

    formula:addClause {{"a", false}, {"b", true}}

Ask the formula for a satisfying assignment by invoking `:isSatisfiable()`:

    local model = formula:isSatisfiable()
    if model then
        -- The formula is satisfiable!
        print("Satisfiable:")
        for key, assignment in pairs(model) do
            print(key, "=>", assignment)
        end
    else
        -- The formula is NOT satisfiable (every possible assignment results in
        -- at least one clause being unsatisfied)
        print("Unsatisfiable")
    end

## License

This project is licensed under the LGPL-3.0 license. See
[LICENSE.txt](LICENSE.txt) for details.
