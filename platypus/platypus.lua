--- Defold platformer engine

local M = {}

local CONTACT_POINT_RESPONSE = hash("contact_point_response")
local POST_UPDATE = hash("platypus_post_update")
local RAY_CAST_MISSED = hash("ray_cast_missed")
local RAY_CAST_RESPONSE = hash("ray_cast_response")

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
	allow_double_jump = true,
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
	local state = {
		current = { wall_contact = vmath.vector3(), ground_contact = false, rays = {} },
		previous = { rays = {} },
	}

	-- movement based on user input
	local movement = vmath.vector3()

	local RAY_CAST_LEFT_ID = 1
	local RAY_CAST_RIGHT_ID = 2
	local RAY_CAST_DOWN_ID = 3
	local RAY_CAST_UP_ID = 4
	local RAY_CAST_DOWN_LEFT_ID = 5
	local RAY_CAST_DOWN_RIGHT_ID = 6

	local RAY_CAST_LEFT = vmath.vector3(-platypus.collisions.left - 1, 0, 0)
	local RAY_CAST_RIGHT = vmath.vector3(platypus.collisions.right + 1, 0, 0)
	local RAY_CAST_DOWN = vmath.vector3(0, -platypus.collisions.bottom - 1, 0)
	local RAY_CAST_UP = vmath.vector3(0, platypus.collisions.top + 1, 0)
	local RAY_CAST_DOWN_LEFT = vmath.vector3(-platypus.collisions.left + 1, -platypus.collisions.bottom - 1, 0)
	local RAY_CAST_DOWN_RIGHT = vmath.vector3(platypus.collisions.right - 1, -platypus.collisions.bottom - 1, 0)

	local RAYS = {
		[RAY_CAST_LEFT_ID] = RAY_CAST_LEFT,
		[RAY_CAST_RIGHT_ID] = RAY_CAST_RIGHT,
		[RAY_CAST_DOWN_ID] = RAY_CAST_DOWN,
		[RAY_CAST_UP_ID] = RAY_CAST_UP,
		[RAY_CAST_DOWN_LEFT_ID] = RAY_CAST_DOWN_LEFT,
		[RAY_CAST_DOWN_RIGHT_ID] = RAY_CAST_DOWN_RIGHT,
	}

	local function check_group_direction(group, direction)
		return bit.band(config.collisions.groups[group], direction) > 0
	end

	local function separate_ray(ray, message)
		if platypus.collisions.separation == M.SEPARATION_RAYS then
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
				--separation.y = math.ceil(separation.y)
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
			if message.normal.y > 0 and not check_group_direction(message.group, M.DIR_DOWN) then
				return
			elseif message.normal.y < 0 and not check_group_direction(message.group, M.DIR_UP) then
				return
			elseif message.normal.x > 0 and not check_group_direction(message.group, M.DIR_LEFT) then
				return
			elseif message.normal.x < 0 and not check_group_direction(message.group, M.DIR_RIGHT) then
				return
			end
			-- separate collision objects
			if not state.current.ground_contact then
				message.normal.y = 0
			end
			local proj = vmath.dot(correction, message.normal)
			local comp = (message.distance - proj) * message.normal
			correction = correction + comp
			go.set_position(go.get_position() + comp)
		end
	end

	local function ray_cast(id, from, to)
		if platypus.debug then
			msg.post("@render:", "draw_line", { start_point = from, end_point = to, color = RAY_COLOR } )
		end
		physics.ray_cast(from, to, collision_groups_list, id)
	end

	local function jumping_up()
		return (platypus.velocity.y > 0 and platypus.gravity < 0) or (platypus.velocity.y < 0 and platypus.gravity > 0)
	end

	-- Move the game object left
	-- @param velocity Horizontal velocity
	function platypus.left(velocity)
		assert(velocity, "You must provide a velocity")
		if state.current.wall_contact ~= 1 then
			movement.x = -velocity
		end
	end

	--- Move the game object right
	-- @param velocity Horizontal velocity
	function platypus.right(velocity)
		assert(velocity, "You must provide a velocity")
		if state.current.wall_contact ~= -1 then
			movement.x = velocity
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

	--- Try to make the game object jump.
	-- @param power The power of the jump (ie how high)
	function platypus.jump(power)
		assert(power, "You must provide a jump takeoff power")
		if state.current.ground_contact then
			platypus.velocity.y = power
			msg.post("#", M.JUMP)
		elseif state.current.wall_contact and platypus.allow_wall_jump then
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

	--- Forward any on_message calls here to resolve physics collisions
	-- @param message_id
	-- @param message
	function platypus.on_message(message_id, message)
		assert(message_id, "You must provide a message_id")
		assert(message, "You must provide a message")
		if message_id == POST_UPDATE then
			-- reset transient state
			movement.x = 0
			movement.y = 0
			correction = vmath.vector3()
			state.previous, state.current = state.current, state.previous
			state.current.wall_contact = false
			state.current.falling = false
		elseif message_id == CONTACT_POINT_RESPONSE then
			separate_collision(message)
		elseif message_id == RAY_CAST_RESPONSE then
			state.current.rays[message.request_id] = message
			if message.request_id == RAY_CAST_LEFT_ID then
				if check_group_direction(message.group, M.DIR_LEFT) then
					state.current.wall_contact = 1
					separate_ray(RAY_CAST_LEFT, message)
				end
			elseif message.request_id == RAY_CAST_RIGHT_ID then
				if check_group_direction(message.group, M.DIR_RIGHT) then
					state.current.wall_contact = -1
					separate_ray(RAY_CAST_RIGHT, message)
				end
			elseif (message.request_id == RAY_CAST_DOWN_LEFT_ID
			or message.request_id == RAY_CAST_DOWN_RIGHT_ID
			or message.request_id == RAY_CAST_DOWN_ID)
			and message.normal.y > 0.7
			and check_group_direction(message.group, M.DIR_DOWN)
			then
				if not state.current.ground_contact then
					local moving_down = platypus.velocity.y <= 0
					local moving_down_and_in_air = moving_down and not state.previous.rays[message.request_id]
					if moving_down_and_in_air or state.previous.ground_contact then
						state.current.ground_contact = true
						state.current.double_jumping = false
						msg.post(".", "set_parent", { parent_id = message.id })
						platypus.parent_id = message.id
						separate_ray(RAYS[message.request_id], message)
					end
				elseif state.current.ground_contact and platypus.parent_id ~= message.id then
					msg.post(".", "set_parent", { parent_id = message.id })
					platypus.parent_id = message.id
				end
			elseif message.request_id == RAY_CAST_UP_ID then
				if check_group_direction(message.group, M.DIR_UP) then
					if platypus.velocity.y > 0 then
						platypus.velocity.y = 0
					end
					separate_ray(RAY_CAST_UP, message)
				end
			end
		elseif message_id == RAY_CAST_MISSED then
			state.current.rays[message.request_id] = nil
			-- if neither down, down left or down right hit anything this
			-- or the last frame then we don't have ground contact anymore
			if not state.current.rays[RAY_CAST_DOWN_LEFT_ID] and
			not state.current.rays[RAY_CAST_DOWN_RIGHT_ID] and
			not state.current.rays[RAY_CAST_DOWN_ID] and
			not state.previous.rays[RAY_CAST_DOWN_LEFT_ID] and
			not state.previous.rays[RAY_CAST_DOWN_RIGHT_ID] and
			not state.previous.rays[RAY_CAST_DOWN_ID]
			then
				state.current.ground_contact = false
				platypus.parent_id = nil
				msg.post(".", "set_parent", { parent_id = nil })
			end
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
				go.set_position(go.get_position() + state.current.world_position - state.current.position)
			end
		end

		-- notify ground or air state change
		if state.current.ground_contact and not state.previous.ground_contact then
			msg.post("#", M.GROUND_CONTACT)
			platypus.velocity.x = 0
			platypus.velocity.y = 0
		end

		-- notify wall contact state change
		if state.current.wall_contact and not state.previous.wall_contact then
			msg.post("#", M.WALL_CONTACT)
		end

		-- apply gravity if not standing on the ground
		if not state.current.ground_contact then
			platypus.velocity.y = platypus.velocity.y + platypus.gravity * dt
		end

		-- update and clamp velocity
		if platypus.max_velocity then
			platypus.velocity.x = clamp(platypus.velocity.x, -platypus.max_velocity, platypus.max_velocity)
			platypus.velocity.y = clamp(platypus.velocity.y, -platypus.max_velocity, platypus.max_velocity)
		end

		-- set and notify falling state
		if not state.current.ground_contact and not state.previous.ground_contact and platypus.velocity.y < 0 then
			state.current.falling = true
		end
		if state.current.falling and not state.previous.falling then
			msg.post("#", M.FALLING)
		end

		-- move the game object
		local distance = (platypus.velocity * dt) + (movement * dt)
		local position = go.get_position()
		local world_position = go.get_world_position()
		state.current.position = position
		state.current.world_position = world_position
		go.set_position(position + distance)

		msg.post("#", POST_UPDATE)

		-- ray cast left, right and down to detect level geometry
		local raycast_origin = world_position + distance
		ray_cast(RAY_CAST_LEFT_ID, raycast_origin, raycast_origin + RAY_CAST_LEFT)
		ray_cast(RAY_CAST_RIGHT_ID, raycast_origin, raycast_origin + RAY_CAST_RIGHT)
		ray_cast(RAY_CAST_UP_ID, raycast_origin, raycast_origin + RAY_CAST_UP)
		ray_cast(RAY_CAST_DOWN_LEFT_ID, raycast_origin, raycast_origin + RAY_CAST_DOWN_LEFT)
		ray_cast(RAY_CAST_DOWN_RIGHT_ID, raycast_origin, raycast_origin + RAY_CAST_DOWN_RIGHT)
		ray_cast(RAY_CAST_DOWN_ID, raycast_origin, raycast_origin + RAY_CAST_DOWN)
	end


	function platypus.toggle_debug()
		platypus.debug = not platypus.debug
	end

	return platypus
end

return M
