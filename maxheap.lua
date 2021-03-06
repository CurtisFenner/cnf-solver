local MaxHeap = {}

-- REQUIRES lt is a proper < relation
-- REQUIRES :update be called whenever the priority of an element in this
-- heap changes
function MaxHeap.new(lt)
	local instance = {
		_items = {},
		_index = {},
		_lt = lt,
	}

	return setmetatable(instance, {__index = MaxHeap})
end

-- RETURNS nothing
-- MODIFIES this
-- REQUIRES element not already be in the heap
function MaxHeap:push(element)
	assert(element ~= nil, "cannot push nil")
	assert(self._index[element] == nil, "element already in heap")

	self._index[element] = #self._items + 1
	self._items[#self._items + 1] = element

	self:_fixUp(#self._items)
end

-- RETURNS whether or not this heap contains the given element
function MaxHeap:contains(element)
	return self._index[element] ~= nil
end

-- RETURNS nothing
-- MODIFIES this
-- REQUIRES this be called WHENEVER the priority of element has changed
function MaxHeap:update(element)
	local index = self._index[element]
	assert(index, "element is not in this heap")

	self:_fixDown(index)
	self:_fixUp(index)
end

-- RETURNS nothing
-- MODIFIES this to no longer contain the specified element
-- REQUIRES element has been pushed and not yet popped or removed from the heap
function MaxHeap:remove(element)
	assert(self._index[element], "element is not in this heap")

	local i = self._index[element]
	if i == #self._items then
		self._items[#self._items] = nil
		self._index[element] = nil
	else
		-- Move the last item here and then fix invariant
		self._items[i] = self._items[#self._items]
		self._items[#self._items] = nil
		self._index[self._items[i]] = i
		self._index[element] = nil

		-- Fix invariants
		self:_fixUp(i)
		self:_fixDown(i)
	end
end

function MaxHeap:_left(i)
	return i * 2
end

function MaxHeap:_right(i)
	return i * 2 + 1
end

function MaxHeap:_parent(i)
	return math.floor(i / 2)
end

function MaxHeap:_fixUp(i)
	if i == 1 then
		return
	end

	local p = self:_parent(i)
	if self._lt(self._items[p], self._items[i]) then
		-- This is bigger than parent; i should be moved up
		self._items[i], self._items[p] = self._items[p], self._items[i]

		-- Fix index
		self._index[self._items[i]] = i
		self._index[self._items[p]] = p

		-- Fix invariant
		return self:_fixUp(p)
	end
end

function MaxHeap:_fixDown(i)
	local left = self:_left(i)
	local right = self:_right(i)

	if #self._items < left then
		return
	elseif #self._items < right then
		if self._lt(self._items[i], self._items[left]) then
			-- left is bigger that here; left should be moved up
			self._items[left], self._items[i] = self._items[i], self._items[left]

			-- Fix index
			self._index[self._items[i]] = i
			self._index[self._items[left]] = left
		end
		return
	end

	if self._lt(self._items[left], self._items[right]) then
		-- Right is bigger than left
		if self._lt(self._items[i], self._items[right]) then
			-- Right should be moved up
			self._items[right], self._items[i] = self._items[i], self._items[right]

			-- Fix index
			self._index[self._items[i]] = i
			self._index[self._items[right]] = right

			-- Fix invariant
			return self:_fixDown(right)
		end
	else
		-- Left is bigger than right
		if self._lt(self._items[i], self._items[left]) then
			-- Left should be moved up
			self._items[left], self._items[i] = self._items[i], self._items[left]

			-- Fix index
			self._index[self._items[i]] = i
			self._index[self._items[left]] = left

			-- Fix invariant
			return self:_fixDown(left)
		end
	end
end

-- RETURNS the largest item
-- MODIFIES nothing
-- REQUIRES this heap is not empty
function MaxHeap:top()
	assert(#self._items ~= 0, "cannot :top() from empty heap")
	return self._items[1]
end

-- RETURNS the largest item
-- MODIFIES this
-- REQUIRES this heap is not empty
function MaxHeap:pop()
	assert(#self._items ~= 0, "cannot :pop() from empty heap")

	local out = self._items[1]
	self._index[out] = nil

	self._items[1] = self._items[#self._items]
	self._items[#self._items] = nil
	
	if #self._items ~= 0 then
		-- Fix invariant and index
		self._index[self._items[1]] = 1
		self:_fixDown(1)
	end

	return out
end

-- RETURNS how many items are in this
function MaxHeap:size()
	return #self._items
end

function MaxHeap:_validate()
	for i = #self._items, 2, -1 do
		if self._lt(self._items[self:_parent(i)], self._items[i]) then
			print(unpack(self._items))
			error("Heap invariant violated at index " .. i .. " -> " .. self:_parent(i))
		end
	end

	for v, i in pairs(self._index) do
		assert(self._items[i] == v)
	end

	for i, v in pairs(self._items) do
		if self._index[v] ~= i then
			error(tostring(v) .. " is at " .. i .. ", but index puts it at " .. tostring(self._index[v]))
		end
	end
end

--------------------------------------------------------------------------------

do
	local t = MaxHeap.new(function(a, b) return a < b end)
	t:_validate()
	t:push(1)
	t:_validate()
	t:push(2)

	-- {2, 1}
	t:_validate()
	assert(t:pop() == 2)

	-- {1}
	t:_validate()
	t:push(3)
	t:_validate()
	t:push(2)

	-- {3, 2, 1}
	t:_validate()
	assert(t:pop() == 3)

	-- {2, 1}
	t:_validate()
	t:push(4)

	-- {4, 2, 1}
	t:_validate()
	assert(t:pop() == 4)

	-- {2, 1}
	t:_validate()
	assert(t:size() == 2)
	t:_validate()
	assert(t:pop() == 2)
	assert(t:pop() == 1)
	assert(t:size() == 0)
end

do
	local t = MaxHeap.new(function(a, b) return a < b end)
	t:push(7)
	t:push(8)
	t:push(3)
	t:push(2)
	t:push(4)
	t:push(1)
	t:push(5)
	t:push(6)
	t:push(9)
	t:_validate()
	t:remove(3)
	t:_validate()
	t:remove(6)
	t:_validate()
	assert(t:pop() == 9)
	t:_validate()
	assert(t:pop() == 8)
	assert(t:pop() == 7)
	assert(t:pop() == 5)
	assert(t:pop() == 4)
	assert(t:pop() == 2)
	assert(t:pop() == 1)
end

--------------------------------------------------------------------------------

return MaxHeap
