--!strict
-- Loads the game's ModuleScripts outside Roblox. Builds a minimal stand-in
-- for the Instance tree from the source folders so modules keep their normal
-- `require(script.Parent.X)` calls and the tests run the shipped code.

local fs = require("@lune/fs")
local luau = require("@lune/luau")

local Loader = {}

-- Extra globals (Roblox datatypes, a stand-in `game`) given to loaded modules.
Loader.globals = {} :: { [string]: any }

local files: { [any]: string } = {}
local cache: { [string]: any } = {}
local loading: { [string]: boolean } = {}

-- Children are stored as plain fields, like indexing an Instance by name.
local function scan(name: string, parent: any, dir: string): any
	local node = { Name = name, Parent = parent }
	for _, entry in fs.readDir(dir) do
		local path = dir .. "/" .. entry
		if fs.isDir(path) then
			node[entry] = scan(entry, node, path)
		elseif entry == "init.luau" then
			files[node] = path
		elseif entry:match("%.luau$") then
			local child = { Name = (entry:gsub("%..*$", "")), Parent = node }
			files[child] = path
			node[child.Name] = child
		end
	end
	return node
end

local function fakeRequire(node: any): any
	local file = files[node]
	assert(file, "not a ModuleScript")
	if cache[file] ~= nil then
		return cache[file]
	end
	assert(not loading[file], `cyclic require of {file}`)
	loading[file] = true
	local environment: { [string]: any } = { script = node, require = fakeRequire }
	for name, value in Loader.globals do
		environment[name] = value
	end
	local chunk = luau.load(fs.readFile(file), {
		debugName = file,
		environment = environment,
	})
	local result = chunk()
	loading[file] = nil
	cache[file] = result
	return result
end

-- Returns the stand-in for the folder Rojo maps `dir` to.
function Loader.root(dir: string): any
	return scan("DrivingSim", nil, dir)
end

Loader.require = fakeRequire

return Loader
