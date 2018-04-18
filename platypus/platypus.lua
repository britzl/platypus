--- Defold platformer engine

local M = {}

local CONTACT_POINT_RESPONSE = hash("contact_point_response")
local POST_UPDATE = hash("platypus_post_update")
local RAY_CAST_MISSED = hash("ray_cast_missed")
local RAY_CAST_RESPONSE = hash("ray_cast_response")

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

--- Create a platypus instance.
-- This will provide all the functionality to control a game object in a
-- platformer game. The functions will operate on the game object attached
-- to the script calling the functions.
-- @param config Configuration table. Refer to documentation for details
-- @return Platypus instance
function M.create(config)
	assert(config, "You must provide a config")
	assert(config.collisions, "You must provide a collisions config")
	assert(config.collisions.ground, "You must provide a list of ground collision hashes")
	assert(config.collisions.left, "You must provide distance to left edge of collision shape")
	assert(config.collisions.right, "You must provide distance to right edge of collision shape")
	assert(config.collisions.top, "You must provide distance to top edge of collision shape")
	assert(config.collisions.bottom, "You must provide distance to bottom edge of collision shape")

	-- get collision group lists and convert to sets
	local collisions = {
		ground = {}
	}
	for _,h in ipairs(config.collisions.ground) do
		collisions.ground[h] = true
	end

	-- track current and previous state to detect state changes
	local state = {
		current = {},
		previous = {},
	}

	-- public instance
	local platypus = {
		velocity = vmath.vector3(),
		gravity = config.gravity or -100,
		max_velocity = config.max_velocity,
		wall_jump_power_ratio_y = config.wall_jump_power_ratio_y or 0.75,
		wall_jump_power_ratio_x = config.wall_jump_power_ratio_x or 0.35,
	}

	-- for geometry separation during collisions
	local correction = vmath.vector3()

	-- movement based on user input
	local movement = vmath.vector3()

	local RAY_CAST_LEFT_ID = 1
	local RAY_CAST_RIGHT_ID = 2
	local RAY_CAST_DOWN_ID = 3
	local RAY_CAST_UP_ID = 4

	local RAY_CAST_LEFT = vmath.vector3(-config.collisions.left - 1, 0, 0)
	local RAY_CAST_RIGHT = vmath.vector3(config.collisions.right + 1, 0, 0)
	local RAY_CAST_DOWN = vmath.vector3(1, -config.collisions.bottom - 1, 0)
	local RAY_CAST_UP = vmath.vector3(1, config.collisions.top + 1, 0)


	local function jumping_up()
		return (platypus.velocity.y > 0 and platypus.gravity < 0) or (platypus.velocity.y < 0 and platypus.gravity > 0)
	end

	-- Move the game object left
	-- @param velocity Horizontal velocity
	function platypus.left(velocity)
		movement.x = -velocity
	end

	--- Move the game object right
	-- @param velocity Horizontal velocity
	function platypus.right(velocity)
		movement.x = velocity
	end

	-- Move the game object up
	-- @param velocity Vertical velocity
	function platypus.up(velocity)
		movement.y = velocity
	end

	--- Move the game object down
	-- @param velocity Vertical velocity
	function platypus.down(velocity)
		movement.y = -velocity
	end

	--- Move the game object
	-- @param velocity Velocity as a vector3
	function platypus.move(velocity)
		movement = velocity
	end

	--- Try to make the game object jump.
	-- @param power The power of the jump (ie how high)
	-- @param allow_double_jump True if double-jump should be allowed
	-- @param allow_wall_jump True if wall-jump should be allowed
	function platypus.jump(power, allow_double_jump, allow_wall_jump)
		if state.current.ground_contact then
			platypus.velocity.y = power
		elseif state.current.wall_contact and allow_wall_jump then
			platypus.velocity.y = power * platypus.wall_jump_power_ratio_y
			platypus.velocity.x = state.current.wall_contact * power * platypus.wall_jump_power_ratio_x
		elseif allow_double_jump and jumping_up() and not state.current.double_jumping then
			platypus.velocity.y = platypus.velocity.y + power
			state.current.double_jumping = true
		else
			print("no ground contact")
		end
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
		if message_id == CONTACT_POINT_RESPONSE then
			if collisions.ground[message.group] then
				-- separate collision objects and adjust velocity
				local proj = vmath.dot(correction, message.normal)
				local comp = (message.distance - proj) * message.normal
				correction = correction + comp
				go.set_position(go.get_position() + comp)
				proj = vmath.dot(platypus.velocity, message.normal)
				if proj < 0 then
					--platypus.velocity = platypus.velocity - (proj * message.normal)
				end
				platypus.normal = message.normal
			end
		elseif message_id == POST_UPDATE then
			-- reset transient state
			correction = vmath.vector3()
			movement.x = 0
			movement.y = 0
			state.previous, state.current = state.current, state.previous
			state.current.ground_contact = false
			state.current.wall_contact = false
			state.current.falling = false
		elseif message_id == RAY_CAST_RESPONSE then
			if message.request_id == RAY_CAST_LEFT_ID then
				state.current.wall_contact = 1
			elseif message.request_id == RAY_CAST_RIGHT_ID then
				state.current.wall_contact = -1
			elseif message.request_id == RAY_CAST_DOWN_ID then
				state.current.ground_contact = true
				state.current.double_jumping = false
				msg.post(".", "set_parent", { parent_id = message.id })
			elseif message.request_id == RAY_CAST_UP_ID then
				if platypus.velocity.y > 0 then
					platypus.velocity.y = 0
				end
			end
		elseif message_id == RAY_CAST_MISSED then
			if message.request_id == RAY_CAST_DOWN_ID then
				state.current.ground_contact = false
				msg.post(".", "set_parent", { parent_id = nil })
			end
		end
	end

	--- Call this every frame to update the platformer physics
	-- @param dt
	function platypus.update(dt)
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
		if not state.current.ground_contact and platypus.velocity.y < 0 then
			state.current.falling = true
		end
		if state.current.falling and not state.previous.falling then
			msg.post("#", M.FALLING)
		end

		-- move the game object
		local distance = (platypus.velocity * dt) + (movement * dt)
		go.set_position(go.get_position() + distance)

		msg.post("#", POST_UPDATE)

		-- ray cast left, right and down to detect level geometry
		local world_pos = go.get_world_position() + distance
		physics.ray_cast(world_pos, world_pos + RAY_CAST_LEFT, config.collisions.ground, RAY_CAST_LEFT_ID)
		physics.ray_cast(world_pos, world_pos + RAY_CAST_RIGHT, config.collisions.ground, RAY_CAST_RIGHT_ID)
		physics.ray_cast(world_pos, world_pos + RAY_CAST_DOWN, config.collisions.ground, RAY_CAST_DOWN_ID)
		physics.ray_cast(world_pos, world_pos + RAY_CAST_UP, config.collisions.ground, RAY_CAST_UP_ID)
		--msg.post("@render:", "draw_line", { start_point = world_pos, end_point = world_pos + RAY_CAST_LEFT, color = vmath.vector4(1)})
		--msg.post("@render:", "draw_line", { start_point = world_pos, end_point = world_pos + RAY_CAST_RIGHT, color = vmath.vector4(1)})
		--msg.post("@render:", "draw_line", { start_point = world_pos, end_point = world_pos + RAY_CAST_DOWN, color = vmath.vector4(1)})
		--msg.post("@render:", "draw_line", { start_point = world_pos, end_point = world_pos + RAY_CAST_UP, color = vmath.vector4(1)})
	end

	return platypus
end

return M
