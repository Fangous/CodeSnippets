local include = require(game.ReplicatedStorage.ParisEngine).include

local GridM = include("GridM")
local SharedConstants = include("SharedConstants")
local Util = include("Util")
local Render = include("Render")

local RunService = game:GetService("RunService")

local GRID_SIZE = SharedConstants.GRID_SIZE
local CHUNK_SIZE = SharedConstants.CHUNK_SIZE
local RENDER_FRAME_RATE = SharedConstants.RENDER_FRAME_RATE
local LOAD_TIME_STATIC = SharedConstants.LOAD_TIME_STATIC

--constant chunk offsets to be rendered from the center chunk
local CHUNK_RENDER_OFFSETS = {
	Vector2.new(0,-1),
	Vector2.new(0,1),
	Vector2.new(1,-1),
	Vector2.new(1,0),
	Vector2.new(1,1),
	Vector2.new(-1,0),
	Vector2.new(-1,1),
	Vector2.new(-1,-1),
}

local player = game.Players.LocalPlayer
local character = player.Character or player.CharacterAdded:wait()
local root_part = character:WaitForChild("HumanoidRootPart")

local module = {}
module.__index = module

local function convert_to_chunk_space(num)
	return math.floor(num/(CHUNK_SIZE*GRID_SIZE))
end

local function get_chunk_coordinates(pos)
	return Vector2.new(convert_to_chunk_space(pos.X), convert_to_chunk_space(pos.Y))
end

function module:chunk_map(map_data)
	
	local chunk_cache = self.chunk_cache
	
	chunk_cache = {}
	
	for index, tile in pairs (map_data) do
		
		local pos = tile.pos
		
		local chunk_coordinate = get_chunk_coordinates(pos)
		
		local chunk_pointer = tostring(chunk_coordinate)
		
		if chunk_cache[chunk_pointer] then
			table.insert(chunk_cache[chunk_pointer], tile)
		else
			chunk_cache[chunk_pointer] = {tile}
		end
		
	end
	
	self.chunk_cache = chunk_cache
	
end

function module:load_chunk(chunk_pos)
	
	local chunk_cache = self.chunk_cache
	
	local chunk_pointer = tostring(chunk_pos)
	
	local chunk_data = chunk_cache[chunk_pointer]
	
	if not self.rendered_chunks then self.rendered_chunks = {} end
	
	if not self.rendered_chunks[chunk_pointer] and chunk_data then
		
		self.rendered_chunks[chunk_pointer] = chunk_pos
		
		for index, tile in pairs(chunk_data) do
			spawn(function()
				local status = self.rendered_chunks[chunk_pointer]
				
				if status == chunk_pos then
					GridM:load_tile(tile)
				end
			end)
		end
		
	end
	
end

function module:unload_chunk(chunk_pos)
	
	local chunk_cache = self.chunk_cache
	
	local chunk_pointer = tostring(chunk_pos)
	
	local chunk_data = chunk_cache[chunk_pointer]
	
	if self.rendered_chunks[chunk_pointer] ~= "LOADING" then
		
		self.rendered_chunks[chunk_pointer] = "UNLOADING"
		
		if chunk_data then
			
			for index, tile in pairs(chunk_data) do
				GridM:unload_tile(tile.pos)
			end
			
		end
		
		self.rendered_chunks[chunk_pointer] = nil
		
	end
	
end

local function get_chunks_to_render(vec)
	
	local results = {}
	
	for index, offset in pairs(CHUNK_RENDER_OFFSETS) do
		
		local new_vec = vec + offset
		
		results[tostring(new_vec)] = new_vec
		
	end
	
	return results
	
end

function module:update_rendering()
	
	local rendered_chunks = self.rendered_chunks
	
	local current_position = Util.vec3_to_vec2(root_part.Position)
	local current_chunk_coordinate = get_chunk_coordinates(current_position)
	local current_chunk_pointer = tostring(current_chunk_coordinate)
	
	local chunks_to_render = get_chunks_to_render(current_chunk_coordinate)
	
	self:load_chunk(current_chunk_coordinate)
	
	if rendered_chunks then
		
		chunks_to_render[current_chunk_pointer] = current_chunk_coordinate
		
		for index, chunk_pos in pairs (rendered_chunks) do
			
			local pos_key = tostring(chunk_pos)
			local is_rendered_this_frame = chunks_to_render[pos_key]
			local chunk_is_rendered = rendered_chunks[pos_key]
			
			if is_rendered_this_frame then
				
				if not chunk_is_rendered then
					chunks_to_render[index] = nil
					self:load_chunk(chunk_pos)
				end
				
			else
				
				if chunk_is_rendered then
					
					spawn(function()
						self:unload_chunk(chunk_pos)
					end)
					
				end
				
			end
			
		end
		
		for index, chunk_pos in pairs(chunks_to_render) do
			self:load_chunk(chunk_pos)
		end
		
	else
		
		for index, chunk_pos in pairs(chunks_to_render) do
			self:load_chunk(chunk_pos)
		end
		
	end
	
end

function module:add_connections(connections)
	
	local new_connections = self.connections or {}
	
	for index, connection in pairs(connections) do
		table.insert(new_connections, connection)
	end
	
	self.connections = new_connections
	
end

function module:clear_connections()
	
	local connections = self.connections
	
	if connections then
		
		for index, connection in pairs(connections) do
			
			connection:Disconnect()
			
		end
		
	end
	
end

function module:hook_connections()
	
	if self.render then self.render:Disconnect() end
	
	--local frame = RENDER_FRAME_RATE
	
	self:add_connections({
		Render.start(function()
			self:update_rendering()
		end, RENDER_FRAME_RATE)
--		RunService.RenderStepped:Connect(function()
--			if frame % RENDER_FRAME_RATE == 0 then
--				self:update_rendering()
--			end
--			frame = frame + 1
--		end)
	})
	
end

local function scrape_spawns(map_data)
	local results = {}
	
	for index, tile in pairs (map_data) do
		local prop = tile.prop
		
		if prop and prop == "Spawn" then
			table.insert(results, tile.pos)
		end
	end
	
	return results
end

local function move_player(coord)
	spawn(function()
		
		local new_pos = CFrame.new(coord.X, 4, coord.Y)
		
		root_part.Anchored = true
		character:SetPrimaryPartCFrame(new_pos)
		wait(LOAD_TIME_STATIC)
		root_part.Anchored = false
		
	end)
end

function module:teleport_player(map_data)
	local spawns = scrape_spawns(map_data)
	
	move_player(spawns[math.random(#spawns)])
end

function module:send_player_to_spawn()
	
	local spawn_location = workspace:FindFirstChild("MainSpawn")
	
	local pos = spawn_location.Position
	
	move_player(Vector2.new(pos.X, pos.Z))
	
end

function module:unload_map()
	
	self:clear_connections()
	
	local chunk_data = self.chunk_data
	
	if chunk_data then
		
		for index, chunk in pairs(chunk_data) do
			
			self:unload_chunk(index)
			
		end
		
	end
	
	self.rendered_chunks = {}
	self.chunk_data = {}
	
	self:send_player_to_spawn()
	
	GridM:clear_folders() --this is gross cus tiles / chunks are kinda out of sync...
	--basically makes sure no tiles stay rendered by accident when switching maps
	
	GridM:clear_all_tiles()
	
end

function module:load_map(map_data)
	
	self:unload_map()
	
	self:teleport_player(map_data)
	
	self:chunk_map(map_data)
	
	self:hook_connections()
	
end

function module:on_respawn()
	
	player = game.Players.LocalPlayer
	character = player.Character or player.CharacterAdded:wait()
	root_part = character:WaitForChild("HumanoidRootPart")
	
	self:clear_connections()
	
	self:unload_map()
	
end

return module