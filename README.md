# Platypus
Defold platformer engine.

# Setup
You can use the extension in your own project by adding this project as a [Defold library dependency](http://www.defold.com/manuals/libraries/). Open your game.project file and in the dependencies field under project add:

https://github.com/britzl/Platypus/archive/master.zip

Or point to the ZIP file of a [specific release](https://github.com/britzl/Platypus/releases).

# Example
See an example of Platypus in action by running the `grottoescape.collection` of this project or try [the HTML5 demo](https://britzl.github.io/Platypus/).


# Usage

## Creating an instance
Use `platypus.create()` to create a Platypus instance. Use this to control a single game object. Each frame you need to call `platypus.update()` and `platypus.on_message()`.

	function init(self)
		self.platypus = platypus.create(config)
	end

	function update(self, dt)
		self.platypus.update(dt)
	end

	function on_message(self, message_id, message, sender)
		self.platypus.on_message(message_id, message)
	end


## Player movement
Use `platypus.left()`, `platypus.right()`, `platypus.up()`, `platypus.down()` and  `platypus.move()` to move the player. The movement will happen during the next call to `platypus.update()`.

	function init(self)
		self.platypus = platypus.create(config)
	end

	function update(self, dt)
		self.platypus.update(dt)
	end

	function on_message(self, message_id, message, sender)
		self.platypus.on_message(message_id, message)
	end

	function on_input(self, action_id, action)
		if action_id == hash("left") then
			self.platypus.left(250)
		elseif action_id == hash("right") then
			self.platypus.right(250)
		end
	end

## Jumping
Platypus supports normal jumps when standing on the ground, wall jumps when in contact with a wall in the air and double jumps. You can also perform a "forced" jump that will perform a jump regardless of state. This can be useful when implementing rope mechanics and other such functions where there is no ground or wall contact.

Use `platypus.jump()` to perform a jump and `platypus.abort_jump()` to reduce the height of a jump that is already in progress.

	function init(self)
		self.platypus = platypus.create(config)
	end

	function update(self, dt)
		self.platypus.update(dt)
	end

	function on_message(self, message_id, message, sender)
		self.platypus.on_message(message_id, message)
	end

	function on_input(self, action_id, action)
		if action_id == hash("jump") then
			if action.pressed then
				self.platypus.jump(800)
			elseif action.released then
				self.platypus.abort_jump(0.5)
			end
		end
	end

## Double jump, wall jump and wall slide
Platypus supports double jumps when config.allow_double_jump is set to true. A double jump is performed automatically when a second jump is done before and up until reaching the apex of the first jump. It is not possible to perform a double jump when falling

Platypus supports wall jumps when config.allow_wall_jump is set to true. A wall jump is performed automatically when jumping while having wall contact while falling or wall sliding. The wall jump pushes the player out from the wall in question.
Normally, user can alter your movement right after bounced from a wall, but when you set config.const_wall_jump - the bounce will be always the same and user won't be able to alter it.

Platypus supports wall slide when config.allow_wall_slide is set to true. A wall slide will be performed automatically when the player has wall contact while falling and moving (using platypus.left() or platypus.right()) in the direction of the wall. Platypus offers also to abort_wall_slide(), for example, when the control key is released, so user is no longer pushing toward the wall.


## Collision detection
Platypus uses ray casts to detect collisions (configured when creating a Platypus instance).

## State changes
Platypus will send messages for certain state changes so that scripts can react, for instance by changing animation.

	function init(self)
		self.platypus = platypus.create(config)
	end

	function update(self, dt)
		self.platypus.update(dt)
	end

	function on_message(self, message_id, message, sender)
		self.platypus.on_message(message_id, message)
		if message_id == platypus.FALLING then
			print("I'm falling")
		elseif message_id == platypus.GROUND_CONTACT then
			print("Phew! Solid ground")
		elseif message_id == platypus.WALL_CONTACT then
			print("Ouch!")
		elseif message_id == platypus.WALL_JUMP then
			print("Doing a wall jump!")
		elseif message_id == platypus.DOUBLE_JUMP then
			print("Doing a double jump!")
		elseif message_id == platypus.JUMP then
			print("Jumping!")
        elseif message_id == platypus.WALL_SLIDE then
			print("Sliding down a wall!")
		end
	end


# Platypus API

## Functions

### platypus.create(config)
Create an instance of Platypus. This will provide all the functionality to control a game object in a platformer game. The functions will operate on the game object attached to the script calling the functions.

**PARAMETERS**
* `config` (table) - Table with configuration values

The ```config``` table can have the following values:

* `collisions` (table) - Lists of collision groups and bounding box size (REQUIRED)
* `debug` (boolean) - True to draw ray casts
* `gravity` (number) - Gravity (pixels/s) (OPTIONAL)
* `max_velocity` (number) - Maximum velocity of the game object (pixels/s). Set this to limit speed and prevent full penetration of game object into level geometry (OPTIONAL)
* `wall_jump_power_ratio_x` (number) - Amount to multiply the jump power with when applying horizontal velocity during a wall jump (OPTIONAL)
* `wall_jump_power_ratio_y` (number) - Amount to multiply the jump power with when applying vertical velocity during a wall jump (OPTIONAL)
* `allow_double_jump` (boolean) - If double jumps are allowed (OPTIONAL)
* `allow_wall_jump` (boolean) - If wall jumps are allowed (OPTIONAL)
* `const_wall_jump` (boolean) - If true - prevents user from changing velocity while bounced from a wall. Set to false by default, to keep legacy behavior. (OPTIONAL)
* `allow_wall_slide` (boolean) - If true - wall slide is allowed (by pushing forward on a wall while falling) (OPTIONAL)
* `wall_slide_velocity` (number) - "gravity" that applies when sliding down the wall (generally should be lower than overall gravity, to simulate sliding) (OPTIONAL)

The `collisions` table can have the following values:

* `groups` (table) - List with collision groups. Used when separating collisions.
* `left` (number) - Distance from game object center to left edge of collision area. Used by ray casts to detect ground and wall contact and when separating collisions using rays.
* `right` (number) - Distance from game object center to right edge of collision area. Used by ray casts to detect ground and wall contact and when separating collisions using rays.
* `top` (number) - Distance from game object center to top edge of collision area. Used by ray casts to detect ground and wall contact and when separating collisions using rays.
* `bottom` (number) - Distance from game object center to bottom edge of collision area. Used by ray casts to detect ground and wall contact and when separating collisions using rays.
* `offset` (vector3) - Offset from the game object center to the center of the collision area. Use this when your sprite and collision area isn't centered around the game object center. Defaults to (0, 0, 0).

The `groups` table should map collision group hashes as keys to which collision directions to detect collisions with:

	{
		[hash("ground")] = platypus.DIR_ALL,
		[hash("onewayplatform")] = platypus.DIR_DOWN,
		[hash("onewaydoor")] = platypus.DIR_LEFT,
	}

**RETURN**
* `instance` (table) - The created Platypus instance

The `instance` table has all of the instance functions describe below in addition to the values from `config` (either provided values or defaults) and the following fields:

* `velocity` - The current velocity of the game object

You can modify any of the instance values at runtime to change the behavior of the platypus instance.


### instance.update(dt)
Update the Platypus instance. This will move the game object and send out state changes.

**PARAMETERS**
* `dt` (number) - Delta time


### instance.on_message(message_id, message)
Forward received messages from the on_message lifecycle function to this instance function. This will handle collision messages and custom messages generated by the Platypus instance itself

**PARAMETERS**
* `message_id` (hash) - Id of the received message
* `message` (table) - The message data


### instance.left(velocity)
Move the game object to the left during next update. This will override any previous call to `instance.left()` or `instance.right()` as well as the horizontal velocity of `instance.move()`.

**PARAMETERS**
* `velocity` (number) - Amount to move left (pixels/s)


### instance.right(velocity)
Move the game object to the right during next update. This will override any previous call to `instance.left()` or `instance.right()` as well as the horizontal velocity of `instance.move()`.

**PARAMETERS**
* `velocity` (number) - Amount to move right (pixels/s)


### instance.up(velocity)
Move the game object up during next update. This will override any previous call to `instance.up()` or `instance.down()` as well as the vertical velocity of `instance.move()`.

**PARAMETERS**
* `velocity` (number) - Amount to move up (pixels/s)


### instance.down(velocity)
Move the game object down during next update. This will override any previous call to `instance.up()` or `instance.down()` as well as the vertical velocity of `instance.move()`.

**PARAMETERS**
* `velocity` (number) - Amount to move down (pixels/s)


### instance.move(velocity)
Move the game object during next update. This will override any previous call to `instance.left()`, `instance.right()`, `instance.up()`, `instance.down()` and `instance.move()`.

**PARAMETERS**
* `velocity` (vector3) - Amount to move (pixels/s)


### instance.jump(power)
Make the game object perform a jump. Depending on state and configuration, this can either be a normal jump from standing on the ground, a wall jump if having wall contact and no ground contact, or a double jump if jumping up and not falling down.

**PARAMETERS**
* `power` (number) - Initial takeoff speed (pixels/s)


### instance.force_jump(power)
Make the game object perform a jump, regardless of current state.

**PARAMETERS**
* `power` (number) - Initial takeoff speed (pixels/s)


### instance.abort_jump(reduction)
Abort a jump by "cutting it short". This will reduce the vertical speed by some fraction.

**PARAMETERS**
* `reduction` (number) - Amount to multiply vertical velocity with


### instance.abort_wall_slide()
Abort a slide down a wall (could be used when releasing the pushing control key)


### instance.has_ground_contact()
Check if the game object is standing on the ground

**RETURN**
* `ground_contact` (boolean) - True if standing on the ground


### instance.has_wall_contact()
Check if the game object is in contact with a wall

**RETURN**
* `wall_contact` (boolean) - True if in contact with a wall


### instance.is_falling()
Check if the game object is falling. The game object is considered falling if not having ground contact and velocity is pointing down.

**RETURN**
* `falling` (boolean) - True if falling


### instance.is_jumping()
Check if the game object is jumping. The game object is considered falling if not having ground contact and velocity is pointing up.

**RETURN**
* `jumping` (boolean) - True if jumping


### instance.is_wall_jumping()
Check if the game object is jumping after a bounce from a wall. The game object is considered falling if not having ground contact and velocity is pointing up.

**RETURN**
* `wall_jump` (boolean) - True if jumping after a bounce from a wall.


### instance.is_wall_sliding()
Check if the game object is sliding down a wall.

**RETURN**
* `wall_slide` (boolean) - True if sliding down a wall.


### instance.toggle_debug()
Toggle debug draw of ray casts.


## Messages

### platypus.FALLING
Sent once when the game object starts to fall

### platypus.GROUND_CONTACT
Sent once when the game object detects ground contact

### platypus.WALL_CONTACT
Sent once when the game object detects wall contact

### platypus.JUMP
Sent when the game object jumps

### platypus.WALL_JUMP
Sent when the game object performs a wall jump

### platypus.DOUBLE_JUMP
Sent when the game object performs a double jump

### platypus.WALL_SLIDE
Sent when the game object starts sliding down a wall


# Credits
* Grotto Escape tiles - Ansimuz (https://ansimuz.itch.io/grotto-escape-game-art-pack)
