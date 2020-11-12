--- Defold platformer engine

local M = {}

local CONTACT_POINT_RESPONSE = hash("contact_point_response")

local RAY_COLOR_HIT = vmath.vector4(0.5, 0.9, 1, 1)
local RAY_COLOR_MISS = vmath.vector4(1.0, 0.5, 0, 1)

local function clamp(v, min, max)
	if v < min then
		return min
	elseif v > max then
		return max
	else
		return v
	end
end


M.FALLING = hash("platypus_falling")
M.GROUND_CONTACT = hash("platypus_ground_contact")
M.WALL_CONTACT = hash("platypus_wall_contact")
M.WALL_JUMP = hash("platypus_wall_jump")
M.WALL_SLIDE = hash("platypus_wall_slide")
M.DOUBLE_JUMP = hash("platypus_double_jump")
M.JUMP = hash("platypus_jump")

M.SEPARATION_RAYS = hash("separation_rays")
M.SEPARATION_SHAPES = hash("separation_shapes")

local ALLOWED_CONFIG_KEYS = {
	collisions = true,
	separation = true,
	wall_jump_power_ratio_y = true,
	wall_jump_power_ratio_x = true,
	allow_wall_jump = true,
	const_wall_jump = true,
	allow_double_jump = true,
	allow_wall_slide = true,
	wall_slide_gravity = true,
	max_velocity = true,
	gravity = true,
	debug = true,
	reparent = true,
}

M.DIR_UP = 0x01
M.DIR_LEFT = 0x02
M.DIR_RIGHT = 0x04
M.DIR_DOWN = 0x08
M.DIR_ALL = M.DIR_UP + M.DIR_LEFT + M.DIR_RIGHT + M.DIR_DOWN

--- Create a platypus instance.
-- This will provide all the functionality to control a game object in a
-- platformer game. The functions will operate on the game object attached
-- to the script calling the functions.
-- @param config Configuration table. Refer to documentation for details
-- @return Platypus instance
function M.create(config)
	assert(config, "You must provide a config")
	assert(config.collisions, "You must provide a collisions config")
	assert(config.collisions.ground or config.collisions.groups, "You must provide a list of collision hashes")
	assert(config.collisions.left, "You must provide distance to left edge of collision shape")
	assert(config.collisions.right, "You must provide distance to right edge of collision shape")
	assert(config.collisions.top, "You must provide distance to top edge of collision shape")
	assert(config.collisions.bottom, "You must provide distance to bottom edge of collision shape")
	config.collisions.offset = config.collisions.offset or vmath.vector3(0, 0, 0)

	-- validate configuration
	for config_key,_ in pairs(config) do
		if not ALLOWED_CONFIG_KEYS[config_key] then
			error(("Unknown config key %s"):format(config_key))
		end
	end

	-- warn for deprecations
	if config.separation then
		print("WARNING! Config key 'separation' is deprecated and should be moved to the 'collisions' table!")
		config.collisions.separation = config.collisions.separation or config.separation or M.SEPARATION_SHAPES
	end
	if config.collisions.ground then
		print("WARNING! Config key 'collisions.ground' is deprecated. Use 'collisions.groups' key-value pairs instead!")
		config.collisions.groups = {}
		for _,id in ipairs(config.collisions.ground) do
			config.collisions.groups[id] = M.DIR_ALL
		end
	end
	if config.collisions.separation == M.SEPARATION_SHAPES then
		print("WARNING! Config key 'SEPARATION_SHAPES' is no longer supported for 'collisions.separation'. Only raycast separation is supported!")
	end

	if config.reparent == nil then config.reparent = true end

	-- public instance
	local platypus = {
		velocity = vmath.vector3(),
		gravity = config.gravity or -100,
		max_velocity = config.max_velocity,
		wall_jump_power_ratio_y = config.wall_jump_power_ratio_y or 0.75,
		wall_jump_power_ratio_x = config.wall_jump_power_ratio_x or 0.35,
		allow_double_jump = config.allow_double_jump or false,
		allow_wall_jump = config.allow_wall_jump or false,
		const_wall_jump = config.const_wall_jump or false,
		allow_wall_slide = config.allow_wall_slide or false,
		wall_slide_gravity = config.wall_slide_gravity or -50,
		collisions = config.collisions,
		debug = config.debug,
		reparent = config.reparent,
	}
	-- get collision group set and convert to list for ray casts
	local collision_groups_list = {}
	for id,_ in pairs(platypus.collisions.groups) do
		collision_groups_list[#collision_groups_list + 1] = id
	end

	-- collision shape correction vector
	local correction = vmath.vector3()

	local state = {
		wall_contact = false,
		wall_jump = false,
		wall_slide = false,
		ground_contact = false,
		rays = {},
		down_rays = {},
		parent_id = nil,
	}

	-- movement based on user input
	local movement = vmath.vector3()

	local BOUNDS_BOTTOM = vmath.vector3(0, -platypus.collisions.bottom, 0)
	local BOUNDS_TOP = vmath.vector3(0, platypus.collisions.top, 0)
	local BOUNDS_LEFT = vmath.vector3(-platypus.collisions.left, 0, 0)
	local BOUNDS_RIGHT = vmath.vector3(platypus.collisions.right, 0, 0)

	local RAY_CAST_LEFT_ID = 1
	local RAY_CAST_RIGHT_ID = 2
	local RAY_CAST_UP_ID = 3
	local RAY_CAST_UP_LEFT_ID = 4
	local RAY_CAST_UP_RIGHT_ID = 5
	local RAY_CAST_DOWN_ID = 6
	local RAY_CAST_DOWN_LEFT_ID = 7
	local RAY_CAST_DOWN_RIGHT_ID = 8

	local RAY_CAST_LEFT = BOUNDS_LEFT + vmath.vector3(-1, 0, 0)
	local RAY_CAST_RIGHT = BOUNDS_RIGHT + vmath.vector3(1, 0, 0)
	local RAY_CAST_DOWN = BOUNDS_BOTTOM + vmath.vector3(0, -1, 0)
	local RAY_CAST_UP = BOUNDS_TOP + vmath.vector3(0, 1, 0)
	local RAY_CAST_DOWN_LEFT = RAY_CAST_LEFT + RAY_CAST_DOWN
	local RAY_CAST_DOWN_RIGHT = RAY_CAST_RIGHT + RAY_CAST_DOWN
	local RAY_CAST_UP_LEFT = RAY_CAST_UP + RAY_CAST_LEFT
	local RAY_CAST_UP_RIGHT = RAY_CAST_UP + RAY_CAST_RIGHT

	-- order of ray casts is important!
	-- we need to check for wall contact before checking ground
	-- contact to be able to handle collision separation properly
	local RAYS = {
		{ id = RAY_CAST_LEFT_ID, ray = RAY_CAST_LEFT },
		{ id = RAY_CAST_RIGHT_ID, ray = RAY_CAST_RIGHT },
		{ id = RAY_CAST_UP_ID, ray = RAY_CAST_UP },
		{ id = RAY_CAST_UP_LEFT_ID, ray = RAY_CAST_UP_LEFT },
		{ id = RAY_CAST_UP_RIGHT_ID, ray = RAY_CAST_UP_RIGHT },
		{ id = RAY_CAST_DOWN_ID, ray = RAY_CAST_DOWN },
		{ id = RAY_CAST_DOWN_LEFT_ID, ray = RAY_CAST_DOWN_LEFT },
		{ id = RAY_CAST_DOWN_RIGHT_ID, ray = RAY_CAST_DOWN_RIGHT },
	}

	local function check_group_direction(group, direction)
		return bit.band(config.collisions.groups[group], direction) > 0
	end

	local function jumping_up()
		return (platypus.velocity.y > 0 and platypus.gravity < 0) or (platypus.velocity.y < 0 and platypus.gravity > 0)
	end

	-- Move the game object left
	-- @param velocity Horizontal velocity
	function platypus.left(velocity)
		assert(velocity, "You must provide a velocity")
		if state.wall_contact ~= 1 then
			state.wall_slide = false
			if (platypus.const_wall_jump and not state.wall_jump) or (not platypus.const_wall_jump) then
				movement.x = -velocity
			end
			-- down-hill
			if state.slope_right then
				movement.y = -velocity * math.abs(state.slope_right.y)
			-- up-hill
			elseif state.slope_left then
				movement.y = -velocity * math.abs(state.slope_left.y)
				movement.x = -velocity * math.abs(state.slope_left.x)
			end
		elseif state.wall_contact ~= -1 and platypus.allow_wall_slide and platypus.is_falling() and not state.wall_slide then
			state.wall_slide = true
			msg.post("#", M.WALL_SLIDE)			-- notify about starting wall slide
			platypus.velocity.y = 0				-- reduce vertical speed
		end
	end

	--- Move the game object right
	-- @param velocity Horizontal velocity
	function platypus.right(velocity)
		assert(velocity, "You must provide a velocity")
		if state.wall_contact ~= -1 then
			state.wall_slide = false
			if (platypus.const_wall_jump and not state.wall_jump) or (not platypus.const_wall_jump) then
				movement.x = velocity
			end
			-- up-hill
			if state.slope_right then
				movement.y = -velocity * math.abs(state.slope_right.y)
				movement.x = velocity * math.abs(state.slope_right.x)
			-- down-hill
			elseif state.slope_left then
				movement.y = -velocity * math.abs(state.slope_left.y)
			end
		elseif state.wall_contact ~= 1 and platypus.allow_wall_slide and platypus.is_falling() and not state.wall_slide then
			state.wall_slide = true
			msg.post("#", M.WALL_SLIDE)			-- notify about starting wall slide
			platypus.velocity.y = 0				-- reduce vertical speed
		end
	end

	-- Move the game object up
	-- @param velocity Vertical velocity
	function platypus.up(velocity)
		assert(velocity, "You must provide a velocity")
		movement.y = velocity
	end

	--- Move the game object down
	-- @param velocity Vertical velocity
	function platypus.down(velocity)
		assert(velocity, "You must provide a velocity")
		movement.y = -velocity
	end

	--- Move the game object
	-- @param velocity Velocity as a vector3
	function platypus.move(velocity)
		assert(velocity, "You must provide a velocity")
		movement = velocity
	end

	--- Abort a wall slide
	function platypus.abort_wall_slide()
		state.wall_slide = false
	end

	--- Try to make the game object jump.
	-- @param power The power of the jump (ie how high)
	function platypus.jump(power)
		assert(power, "You must provide a jump takeoff power")
		if state.ground_contact then
			if config.reparent then
				state.parent_id = nil
				msg.post(".", "set_parent", { parent_id = nil })
			end
			state.ground_contact = false
			platypus.velocity.y = power
			msg.post("#", M.JUMP)
		elseif state.wall_contact and platypus.allow_wall_jump then
			state.wall_jump = true
			platypus.abort_wall_slide()		-- abort wall sliding when jumping from wall
			platypus.velocity.y = power * platypus.wall_jump_power_ratio_y
			platypus.velocity.x = state.wall_contact * power * platypus.wall_jump_power_ratio_x
			msg.post("#", M.WALL_JUMP)
		elseif platypus.allow_double_jump and jumping_up() and not state.double_jumping then
			platypus.velocity.y = platypus.velocity.y + power
			state.double_jumping = true
			msg.post("#", M.DOUBLE_JUMP)
		end
	end

	--- Make the game object jump, regardless of state
	-- Useful when creating rope mechanics or other functionality that requires a jump without
	-- ground or wall contact
	function platypus.force_jump(power)
		assert(power, "You must provide a jump takeoff power")
		platypus.velocity.y = power
		msg.post("#", M.JUMP)
	end

	--- Abort a jump by "cutting it short"
	-- @param reduction The amount to reduce the vertical speed (default 0.5)
	function platypus.abort_jump(reduction)
		if jumping_up() then
			platypus.velocity.y = platypus.velocity.y * (reduction or 0.5)
		end
	end

	--- Check if this object is jumping
	-- @return true if jumping
	function platypus.is_jumping()
		return not state.ground_contact and jumping_up()
	end

	--- Check if this object is jumping from wall
	-- @return true if jumping from wall
	function platypus.is_wall_jumping()
		return state.wall_jump and jumping_up()
	end

	--- Check if this object is sliding on a wall
	-- @return true if sliding on a wall
	function platypus.is_wall_sliding()
		return state.wall_slide
	end

	--- Check if this object is falling
	-- @return true if falling
	function platypus.is_falling()
		return not state.ground_contact and not jumping_up()
	end

	--- Check if this object has contact with the ground
	-- @return true if ground contact
	function platypus.has_ground_contact()
		return state.ground_contact
	end

	--- Check if this object has contact with a wall
	-- @return true if wall contact
	function platypus.has_wall_contact()
		return state.wall_contact
	end

	local function raycast(id, from, to)
		local result = physics.raycast(from, to, collision_groups_list)
		if result then
			result.request_id = id
			if platypus.debug then
				msg.post("@render:", "draw_line", { start_point = from, end_point = to, color = RAY_COLOR_HIT } )
			end
		else
			if platypus.debug then
				msg.post("@render:", "draw_line", { start_point = from, end_point = to, color = RAY_COLOR_MISS } )
			end
		end
		return result
	end

	local function handle_collisions(raycast_origin)
		local offset = vmath.vector3()
		local previous_ground_contact = state.ground_contact
		local previous_wall_contact = state.wall_contact
		state.wall_contact = nil
		state.ground_contact = false
		for _,r in ipairs(RAYS) do
			local ray = r.ray
			local id = r.id
			local result = raycast(id, raycast_origin + offset, raycast_origin + offset + ray)
			if result then
				local separation = ray * (1 - result.fraction)
				state.slope_left = id == RAY_CAST_DOWN_LEFT_ID and result.normal.x ~= 0 and result.normal.y ~= 0 and result.normal
				state.slope_right = id == RAY_CAST_DOWN_RIGHT_ID and result.normal.x ~= 0 and result.normal.y ~= 0 and result.normal
				local down = id == RAY_CAST_DOWN_ID or id == RAY_CAST_DOWN_LEFT_ID or id == RAY_CAST_DOWN_RIGHT_ID
				if down then
					local collide_down = check_group_direction(result.group, M.DIR_DOWN)
					if collide_down and result.normal.y > 0.7 then
						if not state.ground_contact then
							state.ground_contact = true
							-- change parent if needed
							if config.reparent and state.parent_id ~= result.id then
								msg.post(".", "set_parent", { parent_id = result.id })
								state.parent_id = result.id
							end
						end
						separation.x = 0
					elseif collide_down and result.normal.x ~= 0 then
						-- down-left or right hit a wall
						-- if we don't have proper wall contact we separate to
						-- prevent from sliding into for instance a moving platform
						if state.wall_contact then
							separation.x = 0
							separation.y = 0
						else
							separation.y = 0
						end
					else
						separation.x = 0
						separation.y = 0
					end
					
				elseif id == RAY_CAST_UP_ID or id == RAY_CAST_UP_LEFT_ID or id == RAY_CAST_UP_RIGHT_ID then
					local collide_up = check_group_direction(result.group, M.DIR_UP)
					if collide_up and result.normal.y < -0.7 then
						platypus.velocity.y = 0
					elseif collide_up and result.normal.x ~= 0 then
						-- up-left or up hit a wall
						-- if we don't have proper wall contact we separate to
						-- prevent from sliding into for instance a moving platform
						if state.wall_contact then
							separation.x = 0
							separation.y = 0
						else
							separation.y = 0
						end
					else
						separation.x = 0
						separation.y = 0
					end
				elseif id == RAY_CAST_LEFT_ID then
					state.wall_contact = nil
					if check_group_direction(result.group, M.DIR_LEFT) then
						state.wall_contact = 1
					else
						separation.x = 0
						separation.y = 0
					end
				elseif id == RAY_CAST_RIGHT_ID then
					state.wall_contact = nil
					if check_group_direction(result.group, M.DIR_RIGHT) then
						state.wall_contact = -1
					else
						separation.x = 0
						separation.y = 0
					end
				else
					separation.x = 0
					separation.y = 0
				end
				offset = offset - separation
			end
		end

		-- lost ground contact
		if config.reparent and previous_ground_contact and not state.ground_contact then
			state.parent_id = nil
			msg.post(".", "set_parent", { parent_id = nil })
		end

		-- gained ground contact
		if not previous_ground_contact and state.ground_contact then
			platypus.velocity.x = 0
			platypus.velocity.y = 0
			state.falling = false
			state.double_jumping = false
			state.wall_jump = false
			platypus.abort_wall_slide()
			msg.post("#", M.GROUND_CONTACT)
		end

		-- gained wall contact
		if state.wall_contact and not previous_wall_contact then
			msg.post("#", M.WALL_CONTACT)
		end

		return offset
	end

	--- Call this every frame to update the platformer physics
	-- @param dt
	function platypus.update(dt)
		assert(dt, "You must provide a delta time")

		-- was the ground we're standing on removed?
		if config.reparent and state.parent_id then
			local ok,_ = pcall(go.get_position, state.parent_id)
			if not ok then
				state.parent_id = nil
				state.ground_contact = false
				go.set_position(go.get_position() + state.world_position - state.position + BOUNDS_BOTTOM)
			end
		end

		-- apply wall slide gravity or normal gravity if not standing on the ground
		if state.wall_slide then
			platypus.velocity.y = platypus.velocity.y + platypus.wall_slide_gravity * dt
		elseif not state.ground_contact then
			platypus.velocity.y = platypus.velocity.y + platypus.gravity * dt
		else
			platypus.velocity.y = platypus.gravity * dt
		end

		-- update and clamp velocity
		if platypus.max_velocity then
			platypus.velocity.x = clamp(platypus.velocity.x, -platypus.max_velocity, platypus.max_velocity)
			platypus.velocity.y = clamp(platypus.velocity.y, -platypus.max_velocity, platypus.max_velocity)
		end

		-- move the game object
		local distance = (platypus.velocity * dt) + (movement * dt)
		local position = go.get_position()
		local world_position = go.get_world_position()
		state.position = position
		state.world_position = world_position
		local origin = world_position + distance + platypus.collisions.offset
		local offset = handle_collisions(origin)
		go.set_position(position + distance + offset)

		-- falling?
		local previous_falling = state.falling
		if platypus.velocity.y < 0 and not state.ground_contact and not previous_falling then
			state.falling = true
			msg.post("#", M.FALLING)
		end

		-- reset transient state
		movement.x = 0
		movement.y = 0
		correction = vmath.vector3()
	end

	--- Forward any on_message calls here to resolve physics collisions
	-- @param message_id
	-- @param message
	function platypus.on_message(message_id, message)
		assert(message_id, "You must provide a message_id")
		assert(message, "You must provide a message")
	end


	function platypus.toggle_debug()
		platypus.debug = not platypus.debug
	end

	return platypus
end

return M
