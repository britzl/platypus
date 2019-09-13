--- Defold platformer engine

local M = {}

local CONTACT_POINT_RESPONSE = hash("contact_point_response")

local RAY_COLOR = vmath.vector4(0.5, 0.9, 1, 1)

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
	}
	-- get collision group set and convert to list for ray casts
	local collision_groups_list = {}
	for id,_ in pairs(platypus.collisions.groups) do
		collision_groups_list[#collision_groups_list + 1] = id
	end

	-- id of the collision object that this instance is parented to
	platypus.parent_id = nil

	-- collision shape correction vector
	local correction = vmath.vector3()

	-- track current and previous state to detect state changes
	local function create_state()
		return { wall_contact = false, wall_jump = false, wall_slide = false, ground_contact = false, rays = {}, down_rays = {} }
	end
	local state = {}
	state.current = create_state()
	state.previous = create_state()

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

	local RAY_CAST_DOWN_FRACTION = vmath.length(vmath.vector3(0, -platypus.collisions.bottom+1, 0)) / vmath.length(RAY_CAST_DOWN)

	local RAYS = {
		[RAY_CAST_LEFT_ID] = RAY_CAST_LEFT,
		[RAY_CAST_RIGHT_ID] = RAY_CAST_RIGHT,
		[RAY_CAST_DOWN_ID] = RAY_CAST_DOWN,
		[RAY_CAST_UP_ID] = RAY_CAST_UP,
		[RAY_CAST_UP_LEFT_ID] = RAY_CAST_UP_LEFT,
		[RAY_CAST_UP_RIGHT_ID] = RAY_CAST_UP_RIGHT,
		[RAY_CAST_DOWN_LEFT_ID] = RAY_CAST_DOWN_LEFT,
		[RAY_CAST_DOWN_RIGHT_ID] = RAY_CAST_DOWN_RIGHT,
	}

	local inside = {}

	local function is_inside(ray)
		if not ray then
			return false
		end
		return inside[ray.id]
	end


	local function check_group_direction(group, direction)
		return bit.band(config.collisions.groups[group], direction) > 0
	end

	local function separate_ray(ray, message, force)
		if platypus.collisions.separation == M.SEPARATION_RAYS or force then
			local pos = go.get_position()
			local separation
			if message.request_id == RAY_CAST_LEFT_ID then
				separation = ray * (1 - message.fraction)
			elseif message.request_id == RAY_CAST_RIGHT_ID then
				separation = ray * (1 - message.fraction)
			elseif message.request_id == RAY_CAST_DOWN_LEFT_ID
			or message.request_id == RAY_CAST_DOWN_RIGHT_ID
			or message.request_id == RAY_CAST_DOWN_ID
			then
				separation = ray * (1 - message.fraction)
				separation.x = 0
				separation.y = math.ceil(separation.y)
				pos.y = math.floor(pos.y)
			elseif message.request_id == RAY_CAST_UP_ID then
				separation = ray * (1 - message.fraction)
			end
			pos = pos - separation
			go.set_position(pos)
		end
	end

	local function separate_collision(message)
		if platypus.collisions.separation == M.SEPARATION_SHAPES and config.collisions.groups[message.group] then
			local check_down = check_group_direction(message.group, M.DIR_DOWN)
			local check_up = check_group_direction(message.group, M.DIR_UP)
			local check_left = check_group_direction(message.group, M.DIR_LEFT)
			local check_right = check_group_direction(message.group, M.DIR_RIGHT)
			if message.normal.y > 0 and not check_down then
				return
			elseif message.normal.y < 0 and not check_up then
				return
			elseif message.normal.x > 0 and not check_left then
				return
			elseif message.normal.x < 0 and not check_right then
				return
			end

			-- remove any jitter when falling next to a wall
			if not state.current.ground_contact then
				message.normal.y = 0
			end

			-- don't push out of walls
			if not check_left and message.normal.x < 0 then
				message.normal.x = 0
			elseif not check_right and message.normal.x > 0 then
				message.normal.x = 0
			end

			-- don't push out from platforms
			if not check_up and message.normal.y > 0 then
				message.normal.y = 0
			elseif not check_down and message.normal.y < 0 then
				message.normal.y = 0
			end

			-- separate collision objects
			local proj = vmath.dot(correction, message.normal)
			local comp = (message.distance - proj) * message.normal
			correction = correction + comp
			go.set_position(go.get_position() + comp)
		end
	end

	local function jumping_up()
		return (platypus.velocity.y > 0 and platypus.gravity < 0) or (platypus.velocity.y < 0 and platypus.gravity > 0)
	end

	-- Move the game object left
	-- @param velocity Horizontal velocity
	function platypus.left(velocity)
		assert(velocity, "You must provide a velocity")
		if state.current.wall_contact ~= 1 then
			local slope_normal = state.current.slope and state.current.slope.normal
			if slope_normal then
				-- moving up or down the slope?
				if slope_normal.x > 0 then
					-- moving up - push up
					-- the right amount depends on how the slope
					-- to much = airborne
					-- too little = pushing into slope
					local ratio = 1 - (slope_normal.x / slope_normal.y)
					movement.y = velocity * slope_normal.x * ratio
					movement.x = -velocity * slope_normal.y
				else
					-- moving down - push down
					movement.y = -velocity * math.abs(slope_normal.x)
					movement.x = -velocity * slope_normal.y
				end
			elseif (platypus.const_wall_jump and not state.current.wall_jump) or (not platypus.const_wall_jump) then
				movement.x = -velocity
			end
		elseif state.current.wall_contact ~= -1 and platypus.allow_wall_slide and platypus.is_falling() and not state.current.wall_slide then
			state.current.wall_slide = true
			state.previous.wall_slide = true
			msg.post("#", M.WALL_SLIDE)			-- notify about starting wall slide
			platypus.velocity.y = 0				-- reduce vertical speed
		end
	end

	--- Move the game object right
	-- @param velocity Horizontal velocity
	function platypus.right(velocity)
		assert(velocity, "You must provide a velocity")
		if state.current.wall_contact ~= -1 then
			local slope_normal = state.current.slope and state.current.slope.normal
			if slope_normal then
				-- moving up or down the slope?
				if slope_normal.x > 0 then
					-- moving down
					movement.y = -velocity * math.abs(slope_normal.x)
					movement.x = velocity * slope_normal.y
				else
					-- moving up
					local ratio = 1 - math.abs(slope_normal.x / slope_normal.y)
					movement.y = -velocity * slope_normal.x * ratio
					movement.x = velocity * slope_normal.y
				end
			elseif (platypus.const_wall_jump and not state.current.wall_jump) or (not platypus.const_wall_jump) then
				movement.x = velocity
			end
		elseif state.current.wall_contact ~= 1 and platypus.allow_wall_slide and platypus.is_falling() and not state.current.wall_slide then
			state.current.wall_slide = true
			state.previous.wall_slide = true
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
		if state.current.wall_slide then
			state.current.wall_slide = false
			state.previous.wall_slide = false
		end
	end

	--- Try to make the game object jump.
	-- @param power The power of the jump (ie how high)
	function platypus.jump(power)
		assert(power, "You must provide a jump takeoff power")
		if state.current.ground_contact then
			state.current.ground_contact = false
			state.previous.ground_contact = false
			platypus.velocity.y = power
			msg.post("#", M.JUMP)
		elseif state.current.wall_contact and platypus.allow_wall_jump then
			state.current.wall_jump = true
			state.previous.wall_jump = true
			platypus.abort_wall_slide()		-- abort wall sliding when jumping from wall
			platypus.velocity.y = power * platypus.wall_jump_power_ratio_y
			platypus.velocity.x = state.current.wall_contact * power * platypus.wall_jump_power_ratio_x
			msg.post("#", M.WALL_JUMP)
		elseif platypus.allow_double_jump and jumping_up() and not state.current.double_jumping then
			platypus.velocity.y = platypus.velocity.y + power
			state.current.double_jumping = true
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
		return not state.current.ground_contact and not state.previous.ground_contact and jumping_up()
	end

	--- Check if this object is jumping from wall
	-- @return true if jumping from wall
	function platypus.is_wall_jumping()
		return state.current.wall_jump and jumping_up()
	end

	--- Check if this object is sliding on a wall
	-- @return true if sliding on a wall
	function platypus.is_wall_sliding()
		return state.current.wall_slide
	end

	--- Check if this object is falling
	-- @return true if falling
	function platypus.is_falling()
		return not state.current.ground_contact and not state.previous.ground_contact and not jumping_up()
	end

	--- Check if this object has contact with the ground
	-- @return true if ground contact
	function platypus.has_ground_contact()
		return state.current.ground_contact and state.previous.ground_contact
	end

	--- Check if this object has contact with a wall
	-- @return true if wall contact
	function platypus.has_wall_contact()
		return state.current.wall_contact and state.previous.wall_contact
	end

	local function raycast(id, from, to)
		if platypus.debug then
			msg.post("@render:", "draw_line", { start_point = from, end_point = to, color = RAY_COLOR } )
		end
		local result = physics.raycast(from, to, collision_groups_list)
		if result then
			result.request_id = id
		end
		return result
	end

	local down_rays = {}
	local function raycast_and_handle(raycast_origin)
		local left = raycast(RAY_CAST_LEFT_ID, raycast_origin, raycast_origin + RAY_CAST_LEFT)
		local right = raycast(RAY_CAST_RIGHT_ID, raycast_origin, raycast_origin + RAY_CAST_RIGHT)
		local up = raycast(RAY_CAST_UP_ID, raycast_origin, raycast_origin + RAY_CAST_UP)
		local down_left = raycast(RAY_CAST_DOWN_LEFT_ID, raycast_origin, raycast_origin + RAY_CAST_DOWN_LEFT)
		local down_right = raycast(RAY_CAST_DOWN_RIGHT_ID, raycast_origin, raycast_origin + RAY_CAST_DOWN_RIGHT)
		local down = raycast(RAY_CAST_DOWN_ID, raycast_origin, raycast_origin + RAY_CAST_DOWN)

		if up and check_group_direction(up.group, M.DIR_UP) then
			if platypus.velocity.y > 0 then
				platypus.velocity.y = 0
			end
			separate_ray(RAY_CAST_UP, up)
		end
		if up_left and check_group_direction(up_left.group, M.DIR_UP) then
			if platypus.velocity.y > 0 then
				platypus.velocity.y = 0
			end
			separate_ray(RAY_CAST_UP_LEFT, up_left)
		end
		if up_right and check_group_direction(up_right.group, M.DIR_UP) then
			if platypus.velocity.y > 0 then
				platypus.velocity.y = 0
			end
			separate_ray(RAY_CAST_UP_RIGHT, up_right)
		end

		state.current.wall_contact = nil
		if left and check_group_direction(left.group, M.DIR_LEFT) then
			state.current.wall_contact = 1
			separate_ray(RAY_CAST_LEFT, left)
		end
		if right and check_group_direction(right.group, M.DIR_RIGHT) then
			state.current.wall_contact = -1
			separate_ray(RAY_CAST_RIGHT, right)
		end

		-- build map of downward facing rays that hit something we care about
		down_rays[RAY_CAST_DOWN_ID] = (down and down.normal.y > 0.7 and check_group_direction(down.group, M.DIR_DOWN)) and down or nil
		down_rays[RAY_CAST_DOWN_LEFT_ID] = (down_left and down_left.normal.y > 0.7 and check_group_direction(down_left.group, M.DIR_DOWN)) and down_left or nil
		down_rays[RAY_CAST_DOWN_RIGHT_ID] = (down_right and down_right.normal.y > 0.7 and check_group_direction(down_right.group, M.DIR_DOWN)) and down_right or nil

		local slope = nil
		if (down_rays[RAY_CAST_DOWN_LEFT_ID] and not down_rays[RAY_CAST_DOWN_ID] and not down_rays[RAY_CAST_DOWN_RIGHT_ID])
		or (down_rays[RAY_CAST_DOWN_RIGHT_ID] and not down_rays[RAY_CAST_DOWN_ID] and not down_rays[RAY_CAST_DOWN_LEFT_ID])
		then
			state.current.slope = down_rays[RAY_CAST_DOWN_LEFT_ID] or down_rays[RAY_CAST_DOWN_RIGHT_ID]
		else
			state.current.slope = nil
		end

		-- any downward facing ray that hit something?
		if next(down_rays) then
			-- on ground - check for change of parent
			if state.current.ground_contact then
				-- exit if any of the rays have the same parent as the current one
				for _,ray in pairs(down_rays) do
					if platypus.parent_id == ray.id then
						return
					end
				end
				-- get the new parent from any of the rays in the list
				local ray = down_rays[next(down_rays)]
				if ray.fraction < 0.8 then
					separate_ray(RAYS[ray.request_id], ray, true)
				end
				msg.post(".", "set_parent", { parent_id = ray.id })
				platypus.parent_id = ray.id
				-- no prior ground contact - landed!
			elseif not state.current.ground_contact then
				-- landed
				platypus.velocity.y = 0
				state.current.falling = false
				state.current.ground_contact = true
				state.current.double_jumping = false

				-- get one ray that hit and separate based on
				local ray = down_rays[next(down_rays)]
				msg.post(".", "set_parent", { parent_id = ray.id })
				platypus.parent_id = ray.id
				separate_ray(RAYS[ray.request_id], ray, true)
			end
			-- if neither down, down left or down right hit anything this
			-- frame then we don't have ground contact anymore
		else
			state.current.ground_contact = false
			platypus.parent_id = nil
			msg.post(".", "set_parent", { parent_id = nil })
		end
	end

	--- Call this every frame to update the platformer physics
	-- @param dt
	function platypus.update(dt)
		assert(dt, "You must provide a delta time")

		-- was the ground we're standing on removed?
		if platypus.parent_id then
			local ok, _ = pcall(go.get_position, platypus.parent_id)
			if not ok then
				platypus.parent_id = nil
				state.current.ground_contact = false
				go.set_position(go.get_position() + state.current.world_position - state.current.position + BOUNDS_BOTTOM)
			end
		end

		-- apply wall slide gravity or normal gravity if not standing on the ground
		if state.current.wall_slide then
			platypus.velocity.y = platypus.velocity.y + platypus.wall_slide_gravity * dt
		elseif not state.current.ground_contact then
			platypus.velocity.y = platypus.velocity.y + platypus.gravity * dt
		end

		-- reset wall slide and wall jump when standing on the ground
		if state.current.ground_contact then
			if state.current.wall_slide then
				state.current.wall_slide = false
				state.previous.wall_slide = false
			end
			if state.current.wall_jump then
				state.current.wall_jump = false
				state.previous.wall_jump = false
			end
		end

		-- update and clamp velocity
		if platypus.max_velocity then
			platypus.velocity.x = clamp(platypus.velocity.x, -platypus.max_velocity, platypus.max_velocity)
			platypus.velocity.y = clamp(platypus.velocity.y, -platypus.max_velocity, platypus.max_velocity)
		end

		-- set and notify falling state
		if not state.current.ground_contact and not state.previous.ground_contact and platypus.velocity.y < 0 then
			state.current.falling = true
			if state.current.falling and not state.previous.falling then
				msg.post("#", M.FALLING)
			end
		end

		-- move the game object
		local distance = (platypus.velocity * dt) + (movement * dt)
		local position = go.get_position()
		local world_position = go.get_world_position()
		state.current.position = position
		state.current.world_position = world_position
		go.set_position(position + distance)

		-- ray cast left, right and down to detect level geometry
		local raycast_origin = world_position + distance + platypus.collisions.offset
		raycast_and_handle(raycast_origin)

		-- notify wall contact state change
		if state.current.wall_contact and not state.previous.wall_contact then
			msg.post("#", M.WALL_CONTACT)
		end

		-- abort wall slide when lost contact with the wall while sliding
		if not state.current.wall_contact and state.current.wall_slide then
			state.current.wall_slide = false
			state.previous.wall_slide = false
		end

		-- notify ground or air state change
		if state.current.ground_contact and not state.previous.ground_contact then
			platypus.velocity.x = 0
			platypus.velocity.y = 0
			msg.post("#", M.GROUND_CONTACT)
		end

		-- reset transient state
		movement.x = 0
		movement.y = 0
		correction = vmath.vector3()
		state.previous, state.current = state.current, state.previous
	end

	--- Forward any on_message calls here to resolve physics collisions
	-- @param message_id
	-- @param message
	function platypus.on_message(message_id, message)
		assert(message_id, "You must provide a message_id")
		assert(message, "You must provide a message")
		if message_id == CONTACT_POINT_RESPONSE then
			separate_collision(message)
		end
	end


	function platypus.toggle_debug()
		platypus.debug = not platypus.debug
	end

	return platypus
end

return M
