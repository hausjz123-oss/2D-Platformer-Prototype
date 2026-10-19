extends CharacterBody2D


@export var walk_max_speed = 300.0
@export var walk_decerelation := 1800.0
@export var walk_acceleration := 1800.0
@export var uphill_speed_reduction := 0.00 # relative (from 0.0 to 1.0)
@export var running_jump_speed_divisor := 1000.0

@export var track_contact_distance := 12.0
@export var track_snap_distance := 60.0
#TODO: make it so the Floor_detector's size automatically gets scaled to 
#	   the same length as track_snap_distance
@export var track_transition_distance := 20.0
var current_track: Curved_terrain = null
var current_track_offset := 0.0
var nearby_tracks: Array[Curved_terrain] = []
var floor_normal := Vector2.UP
var track_tangent := Vector2.RIGHT
# Positive velocity along the outward normal required
# to naturally launch away from the track.
@export var track_detach_normal_speed := 100.0
# Traction:
@export var traction_start_angle_degrees := 45.0
@export var traction_min_speed := 200.0
# Collision layer NUMBER used by Curved_terrain polygons.
@export_range(1, 32, 1) var curved_terrain_collision_layer := 2

# Useful later if we want impact/ramp rewards.
# Negative = we slammed INTO the terrain.
var last_track_impact_normal_speed := 0.0

@export var jump_speed := 400.0
var max_speed_h = 0
var max_speed_v = 0
@export var spedometer_max_showable_h = 1500.0
@export var spedometer_max_showable_v = 1500.0
var sprite_rotation := 5.0
@export var sprite_rotation_speed := 10.0
@export var terminal_velocity := 1500.0

@onready var animated_sprite_2d: AnimatedSprite2D = $AnimatedSprite2D
@onready var ray_cast_2d: RayCast2D = $RayCast2D
@onready var collision_shape_2d: CollisionShape2D = $CollisionShape2D
@onready var prox_light: Polygon2D = $Proximity_Detector/Prox_Light
@onready var prox_shine: Polygon2D = $Proximity_Detector/Prox_Shine
@onready var background_h: ColorRect = $Spedometer_H/Background_H
@onready var background_v: ColorRect = $Spedometer_V/Background_V
@onready var speed_meter_h: ColorRect = $Spedometer_H/Speed_Meter_H
@onready var speed_meter_v: ColorRect = $Spedometer_V/Speed_Meter_V
@onready var speed_limit_h: Sprite2D = $Spedometer_H/Speed_Limit_H
@onready var speed_limit_v: Sprite2D = $Spedometer_V/Speed_Limit_V
@onready var hammer_hurtbox: Area2D = $Hammer_Hurtbox
@onready var hammer_collision_shape_2d: CollisionShape2D = $Hammer_Hurtbox/CollisionShape2D
@onready var hammer_cooldown: Timer = $Hammer_cooldown
@onready var no_grav_time: Timer = $No_Grav_Time
@onready var speed_limit_h_decay_timer: Timer = $Spedometer_H/Speed_Limit_H_Decay_Timer
@onready var speed_limit_v_decay_timer: Timer = $Spedometer_V/Speed_Limit_V_Decay_Timer
@onready var floor_detector: Area2D = $Floor_detector
@onready var air_flip_timer: Timer = $Air_Flip_Timer
var PDrotation : float
var SHrotation : float
var SVrotation : float



func _ready() -> void:
	sprite_rotation = global_rotation
	PDrotation = $Proximity_Detector.global_rotation
	SHrotation = $Spedometer_H.global_rotation
	SVrotation = $Spedometer_V.global_rotation

func _process(_delta: float) -> void:	
	# restart
	if (Input.is_action_just_pressed("reload map")): get_tree().reload_current_scene()
	# Raycast
	ray_cast_2d.global_rotation = (
	ray_cast_2d.global_position
	.direction_to(get_global_mouse_position())
	.angle()
 )
	
	# Proximity_Detector
	proximity_detector_routine() # TODO improve proximity detector, because it's very useless right now
	
	#spedometers routnines
	spedometers_routines()
	
	# some hammer cooldown code
	if (
		current_track != null
		or is_on_floor()
		or is_on_ceiling()
		or is_on_wall()
	 ):
		if hammer_cooldown.time_left > 0:
			hammer_cooldown.stop()

func _physics_process(delta: float) -> void:
	var force_snap := Input.is_action_pressed("down")


	# Needed for transitions between nearby tracks.
	# TODO dude... we do this EVERY tick?!?!?!?! wasteful, why not only when tracks nearby or something?
	#      surely there's a cheaper way...
	refresh_nearby_tracks()


	# ====================================================
	# ATTACHED TO CURVED TERRAIN
	# ====================================================

	if current_track != null:

		var sample := sample_track_at_offset(
			current_track,
			current_track_offset
		)

		if sample.is_empty():
			detach_from_track()

		else:
			apply_track_sample(sample)


	# ====================================================
	# TRACK STATE
	# ====================================================

	if current_track != null:
		
		# TODO wait so we just put hammer_boosting routine here also? 
		#      This code is so difficult to keep track of
		hammer_boosting_routine()


		# Hammer / external force may already be trying
		# to launch us outward.
		if (
			!force_snap
			and velocity.dot(floor_normal)
				> track_detach_normal_speed
		):
			detach_from_track()

			move_and_slide()

			handle_fallback_rotation()

		# TODO why do we handle jumping off tracks so unintuitively in the code? 
		#      isn't there any better way?
		elif handle_track_jump():
			move_and_slide()

			handle_fallback_rotation()


		else:
			handle_track_movement(
				delta,
				# TODO WHY IS force_snap ALSO HERE? DIDN'T WE ALREADY CHECK FOR IT?!?!?!
				# TODO: Why does so much code feel unnecessary and like it's all doing the same thing...
				force_snap
			)

			# Traction loss / ramp launch / track end
			# might have detached us.
			if current_track == null:
				move_and_slide()

				handle_fallback_rotation()


	# ====================================================
	# FREE STATE
	# ====================================================
	
	# TODO look at how simpel and clean the free sate is handeled! 
	#      why would track movement be unnecessarily complicated?
	else:
		handle_free_state(
			delta,
			force_snap
		)


	# ====================================================
	# BODY ROTATION
	# ====================================================

	handle_physics_rotation()


	# ====================================================
	# PRESERVED SPEED LIMITS
	# ====================================================

	handle_max_speed_decay(delta)


	# ====================================================
	# VISUAL ROTATION
	# ====================================================

	sprite_rotation = rotate_toward(
		sprite_rotation,
		global_rotation,
		sprite_rotation_speed * delta
	)

	animated_sprite_2d.global_rotation = (
		sprite_rotation
	)


	# ====================================================
	# UI SHOULD NOT ROTATE
	# ====================================================

	$Proximity_Detector.global_rotation = PDrotation
	$Spedometer_H.global_rotation = SHrotation
	$Spedometer_V.global_rotation = SVrotation

func proximity_detector_routine():	
	# TargetPoint Distance Calculation
	var distanceFromTargetPoint: float
	if (ray_cast_2d.is_colliding()):
		var targetPoint = ray_cast_2d.get_collision_point()
		distanceFromTargetPoint = (collision_shape_2d.global_position-targetPoint).length()
	
	# Shine and light management
	# max shine = 0.907
	# min shine = 0.35
	var hitbox_overlappers = hammer_hurtbox.get_overlapping_bodies()
	if (hitbox_overlappers.has(self)): 
		hitbox_overlappers.remove_at(hitbox_overlappers.find(self))
	if (!hitbox_overlappers.is_empty()): prox_light.modulate = Color(1,1,1,1)
	else: prox_light.modulate = Color(1,1,1,0)
	if (ray_cast_2d.is_colliding()):
		if (distanceFromTargetPoint <= 100.0):
			prox_shine.scale = Vector2(0.907, 0.907)
			# prox_light.modulate = Color(1,1,1,1)
		else:
			var newShineScale: float
			newShineScale = 0.907 - (distanceFromTargetPoint- 100.0)/100
			prox_shine.scale = Vector2(newShineScale, newShineScale)
			# prox_light.modulate = Color(1,1,1,(100.0 -(distanceFromTargetPoint - 100.0))/100.0)
	else:
		prox_shine.scale = Vector2(0.35, 0.35)
		# prox_light.modulate = Color(1,1,1,0)

func hammer_boosting_routine():
	var hitbox_array : Array[Node2D] = hammer_hurtbox.get_overlapping_bodies()
	if (hitbox_array.has(self)): 
		hitbox_array.remove_at(hitbox_array.find(self))
		
	if ((ray_cast_2d.is_colliding() or !hitbox_array.is_empty()) and !hammer_cooldown.time_left > 0):
		if (Input.is_action_just_pressed("attack")):
			var hammer_direction = Vector2.RIGHT.rotated(ray_cast_2d.global_rotation)
			var boost_direction = -hammer_direction
			
			velocity = boost_direction * 1000.0
			var Sx : float
			var Sy : float
			if (boost_direction.x != 0.0):
				Sx = max_speed_h/abs(boost_direction.x)
			else: Sx = 0.0
			if (boost_direction.y != 0.0): 
				Sy = max_speed_v/abs(boost_direction.y)
			else : Sy = 0.0
			var s = min(Sx, Sy)
			velocity = boost_direction * s
			hammer_cooldown.start()
			start_NoGravTimer(0.2)

func spedometers_routines():	
	# Spedometer_H_routine
	speed_meter_h.size.x = clamp(background_h.size.x / spedometer_max_showable_h * abs(velocity.x), 0.0, background_h.size.x)
	speed_limit_h.position.x = background_h.position.x + clamp(background_h.size.x / spedometer_max_showable_h * max_speed_h, 0.0, background_h.size.x)
	
	# Spedometer_V_routine
	speed_meter_v.size.x = clamp(background_v.size.x / spedometer_max_showable_v * abs(velocity.y), 0.0, background_v.size.x)
	speed_limit_v.position.x = background_v.position.x + clamp(background_v.size.x / spedometer_max_showable_v * max_speed_v, 0.0, background_v.size.x)

	if (abs(velocity.x) >= spedometer_max_showable_h): speed_meter_h.color = Color(1,1,0)
	else: speed_meter_h.color = Color(1,0,0)
	if (abs(velocity.y) >= spedometer_max_showable_v): speed_meter_v.color = Color(1,1,0)
	else: speed_meter_v.color = Color(1,0,0)
	
	# increasing limits and limit feedback
	if (abs(velocity.x) >= max_speed_h && max_speed_h != 0): 
		speed_limit_h.modulate = Color(1.0, 1.0, 0.0, 1.0)
		speed_limit_h.scale = Vector2(0.4,0.4)
	else: 
		speed_limit_h.modulate = Color(0.0, 1.0, 0.0, 1.0)
		speed_limit_h.scale = Vector2(0.232,0.248)
	if (abs(velocity.y) >= max_speed_v && max_speed_v != 0): 
		speed_limit_v.modulate = Color(1.0, 1.0, 0.0, 1.0)
		speed_limit_v.scale = Vector2(0.4,0.4)
	else: 
		speed_limit_v.modulate = Color(0.0, 1.0, 0.0, 1.0)
		speed_limit_v.scale = Vector2(0.221,0.251)

func start_NoGravTimer(time : float):
	no_grav_time.start(time)

func handle_max_speed_decay(delta):
	# H
	var H_decay_rate = 100.0
	
	if abs(velocity.x) >= max_speed_h:
		max_speed_h = abs(velocity.x)
		speed_limit_h_decay_timer.start(1.0)
		
	elif speed_limit_h_decay_timer.is_stopped():
		max_speed_h = move_toward(
			max_speed_h,
			abs(velocity.x),
			H_decay_rate * delta
		)
	# V
	var V_decay_rate = 100.0
	
	if abs(velocity.y) >= max_speed_v:
		max_speed_v = abs(velocity.y)
		speed_limit_v_decay_timer.start(1.0)
		
	elif speed_limit_v_decay_timer.is_stopped():
		max_speed_v = move_toward(
			max_speed_v,
			abs(velocity.y),
			V_decay_rate * delta
		)

func handle_physics_rotation():
	if (air_flip_timer.time_left <= 0 and current_track == null):
		rotation = 0
		floor_normal = Vector2.UP
		up_direction = Vector2.UP
		
	elif (current_track != null):
		air_flip_timer.start(0.2)

func get_average_floor_normal() -> Vector2:
	var total_normal = Vector2.ZERO
	var count = 0

	for i in get_slide_collision_count():
		var collision = get_slide_collision(i)
		var normal = collision.get_normal()

		# Only normals reasonably related to our current floor
		if normal.dot(up_direction) > 0.0:
			total_normal += normal
			count += 1

	if count > 0:
		return (total_normal / count).normalized()

	return floor_normal

func sample_track_at_offset(
	track: Curved_terrain,
	offset: float
 ) -> Dictionary:

	if track == null or track.curve == null:
		return {}

	# TODO: isn't there a memory cheaper way of getting this same job done differently?
	var length := track.curve.get_baked_length()

	if length <= 0.0:
		return {}

	offset = clamp(offset, 0.0, length)

	var track_transform := (
		track.curve.sample_baked_with_rotation(
			offset,
			true #TODO: could set to false (for performance), cuz linear might be good enough 
		)
	)

	var local_point := track_transform.origin
	var global_point := track.to_global(local_point)

	var local_tangent := track_transform.x.normalized()

	var global_tangent := (
		track.to_global(local_point + local_tangent)
		- global_point
	).normalized()

	if global_tangent == Vector2.ZERO:
		return {}

	var local_normal := track.get_outward_normal_local(
		local_point,
		local_tangent
	)

	var global_normal := (
		track.to_global(local_point + local_normal)
		- global_point
	).normalized()

	return {
		"track": track,
		"offset": offset,
		"point": global_point,
		"tangent": global_tangent,
		"normal": global_normal
	}

func sample_closest_track_point(
	track: Curved_terrain,
	world_position: Vector2
) -> Dictionary:

	if track == null or track.curve == null:
		return {}

	var local_position := track.to_local(world_position)

	var offset := track.curve.get_closest_offset(
		local_position
	)

	var sample := sample_track_at_offset(
		track,
		offset
	)

	if sample.is_empty():
		return {}

	sample["distance"] = world_position.distance_to(
		sample["point"]
	)

	return sample

func find_nearest_track(
	world_position: Vector2,
	max_distance: float,
	excluded_track: Curved_terrain = null
) -> Dictionary:

	var best_sample := {}
	var best_distance := max_distance

	for track in nearby_tracks:
		if track == excluded_track:
			continue

		var sample := sample_closest_track_point(
			track,
			world_position
		)

		if sample.is_empty():
			continue

		var distance: float = sample["distance"]

		if distance <= best_distance:
			best_distance = distance
			best_sample = sample

	return best_sample

func try_attach_to_track(
	force_snap: bool,
	approach_velocity: Vector2
) -> void:

	if current_track != null:
		return

	var search_distance := (
		track_snap_distance
		if force_snap
		else track_contact_distance
	)

	var sample := find_nearest_track(
		global_position,
		search_distance
	)

	if sample.is_empty():
		return

	var normal: Vector2 = sample["normal"]
	var tangent: Vector2 = sample["tangent"]

	last_track_impact_normal_speed = (
		approach_velocity.dot(normal)
	)


	# ----------------------
	# TRACTION REQUIREMENT
	# ----------------------

	if !force_snap:
		var steepness : float = abs(
			rad_to_deg(
				Vector2.UP.angle_to(normal)
			)
		)

		var incoming_track_speed : float = abs(
			approach_velocity.dot(tangent)
		)

		if (
			steepness >= traction_start_angle_degrees
			and incoming_track_speed < traction_min_speed
		):
			return


	# ----------------------
	# APPROACH DIRECTION
	# ----------------------
	# TODO: is this even what I want? 
	var can_attach := (
		force_snap
		or approach_velocity.length() < 20.0
		or approach_velocity.dot(normal) < 0.0
		or get_slide_collision_count() > 0
	)

	if !can_attach:
		return

	attach_to_track(
		sample,
		approach_velocity
	)

func get_surface_right() -> Vector2:
	return floor_normal.rotated(PI / 2.0)

func get_walk_target_speed(
	direction: float
 ) -> float:

	var movement_direction := (
		get_surface_right() * direction
	).normalized()

	var downhill_amount := (
		movement_direction.dot(Vector2.DOWN)
	)

	var slope_target : float = walk_max_speed

	if downhill_amount >= 0.0:
		slope_target = lerp(
			walk_max_speed,
			terminal_velocity,
			downhill_amount
		)

	else:
		var uphill_amount := -downhill_amount

		slope_target = lerp(
			walk_max_speed,
			walk_max_speed
			* (1.0 - uphill_speed_reduction),
			uphill_amount
		)

	var preserved_target := (
		get_preserved_speed_for_direction(
			movement_direction
		)
	)

	return max(
		slope_target,
		preserved_target
	)

func handle_walking(delta: float) -> void:
	var direction := Input.get_axis("left", "right")

	if current_track != null:
		var surface_right = get_surface_right()

		var tangent_speed = velocity.dot(surface_right)
		var normal_speed = velocity.dot(floor_normal)

		if direction:
			var target_speed = get_walk_target_speed(direction)

			# Don't destroy existing momentum just because normal walking
			# has a lower maximum.
			if (
				sign(tangent_speed) == sign(direction)
				and abs(tangent_speed) > target_speed
			):
				target_speed = abs(tangent_speed)

			tangent_speed = move_toward(
				tangent_speed,
				direction * target_speed,
				walk_acceleration * delta
			)

		else:
			tangent_speed = move_toward(
				tangent_speed,
				0.0,
				walk_decerelation * delta
			)
		# TODO: what if walk acceleration is slower than walk decelleration? 
		# Then it would be best to hold neutral until standstill before holding the 
		# other direction to go faster. 
		# That sounds like bad tech and could be changed so walk decelleration is used when 
		# switching directions first until standstill and then accelerating 
		# into that new direction.

		velocity = (
			surface_right * tangent_speed
			+ floor_normal * normal_speed
		)

		return

	# ----------------------------
	# FALLBACK: ordinary terrain
	# ----------------------------

	if direction:
		velocity.x = move_toward(
			velocity.x,
			direction * walk_max_speed,
			walk_acceleration * delta
		)

	elif is_on_floor():
		velocity.x = move_toward(
			velocity.x,
			0.0,
			walk_decerelation * delta
		)

func handle_track_jump() -> bool:
	if !Input.is_action_just_pressed("jump"):
		return false

	if current_track == null:
		return false
	
	# TODO, like, at this point why don't we definte this variable as a field with a setter?
	#       we use track_speed, like, everywhere
	var track_speed : float = abs(
		velocity.dot(track_tangent)
	)

	velocity += (
		floor_normal
		* jump_speed
		* (
			1.0
			+ track_speed
			/ running_jump_speed_divisor
		)
	)

	detach_from_track()

	return true

func handle_fallback_rotation() -> void:
	if get_slide_collision_count() > 0:
		var normal = get_average_floor_normal()

		if normal != Vector2.ZERO:
			floor_normal = normal
			up_direction = normal
			rotation = Vector2.UP.angle_to(normal)

	else:
		floor_normal = Vector2.UP
		up_direction = Vector2.UP

func refresh_nearby_tracks() -> void:
	nearby_tracks.clear()

	for body in floor_detector.get_overlapping_bodies():
		if body == self:
			continue

		var node: Node = body
		#TODO: isn't this dumb and needlessly expensive?
		# Generated StaticBody2D is a child of Curved_terrain.
		while node != null and !(node is Curved_terrain):
			node = node.get_parent()

		if node is Curved_terrain:
			var track := node as Curved_terrain

			if !nearby_tracks.has(track):
				nearby_tracks.append(track)

func apply_track_sample(sample: Dictionary) -> void:
	floor_normal = sample["normal"]
	track_tangent = sample["tangent"]

	up_direction = floor_normal

	rotation = Vector2.UP.angle_to(
		floor_normal
	)

func attach_to_track(
	sample: Dictionary,
	incoming_velocity: Vector2
 ) -> void:

	current_track = sample["track"]
	current_track_offset = sample["offset"]

	apply_track_sample(sample)

	# Snap ONCE when attaching.
	global_position = sample["point"]

	# Preserve the part of our incoming momentum
	# that lies along the new track.
	var track_speed := incoming_velocity.dot(
		track_tangent
	)

	velocity = track_tangent * track_speed

func detach_from_track() -> void:
	current_track = null

func move_to_track_point(
	target_point: Vector2
 ) -> bool:

	var motion := target_point - global_position

	if motion.length_squared() <= 0.000001:
		return true

	var curved_collision_was_enabled := (
		get_collision_mask_value(
			curved_terrain_collision_layer
		)
	)

	# Ignore Curved_terrain's coarse polygon during this one
	# curve-following movement.
	# TODO: wasteful, expensive??
	set_collision_mask_value(
		curved_terrain_collision_layer,
		false
	)

	var collision := move_and_collide(motion)

	set_collision_mask_value(
		curved_terrain_collision_layer,
		curved_collision_was_enabled
	)

	return collision == null

func get_preserved_speed_for_direction(
	world_direction: Vector2
 ) -> float:

	if world_direction == Vector2.ZERO:
		return walk_max_speed

	var direction := world_direction.normalized()

	var x_weight : float = abs(direction.x)
	var y_weight : float = abs(direction.y)

	var weight_sum := x_weight + y_weight

	if weight_sum <= 0.0001:
		return walk_max_speed

	var preserved_speed : float = (
		x_weight * max_speed_h
		+ y_weight * max_speed_v
	) / weight_sum

	return max(
		walk_max_speed,
		preserved_speed
	)

func apply_track_input(
	track_speed: float,
	delta: float
 ) -> float:

	var direction := Input.get_axis(
		"left",
		"right"
	)
	
	#TODO account for controller dead zones
	if direction == 0.0:
		return move_toward(
			track_speed,
			0.0,
			walk_decerelation * delta
		)


	var surface_right := get_surface_right()

	# track_tangent points in the direction of increasing
	# Curve2D offset. Surface-right might point the opposite way.
	var right_sign := 1.0

	if track_tangent.dot(surface_right) < 0.0:
		right_sign = -1.0

	var desired_sign : float = sign(direction) * right_sign

	var target_speed := get_walk_target_speed(
		direction
	)


	# If trying to reverse direction:
	# BRAKE first using walk_decerelation.
	if (
		abs(track_speed) > 0.001
		and sign(track_speed) != sign(desired_sign)
	):
		track_speed = move_toward(
			track_speed,
			0.0,
			walk_decerelation * delta
		)

		# If we are still moving in the old direction after braking,
		# stop here for this frame.
		if abs(track_speed) > 0.001:
			return track_speed

		# We reached (approximately) zero this frame.
		# Continue below so input can immediately accelerate us
		# into the requested direction instead of getting stuck at 0.
		track_speed = 0.0


	# Don't punish already-earned momentum.
	#TODO: You sure we want the track_speed to be able to go higher than target_speed? maybe...
	if (
		sign(track_speed) == sign(desired_sign)
		and abs(track_speed) > target_speed
	):
		return track_speed


	return move_toward(
		track_speed,
		desired_sign * target_speed,
		walk_acceleration * delta
	)

#TODO this might not be at all what I want. you're telling me we're completely
# magnetized if we only walk fast enough? But I want the player to be able to fly off
# even if the angle is very shallow, if the player is going super fast enough.
func has_track_traction(
	track_speed: float,
	force_snap: bool
 ) -> bool:

	if force_snap:
		return true

	var steepness : float = abs(
		rad_to_deg(
			Vector2.UP.angle_to(floor_normal)
		)
	)

	if steepness < traction_start_angle_degrees:
		return true

	return abs(track_speed) >= traction_min_speed

func try_transition_to_nearby_track(
	old_velocity: Vector2
 ) -> bool:

	var sample := find_nearest_track(
		global_position,
		track_transition_distance,
		current_track
	)

	if sample.is_empty():
		return false

	attach_to_track(
		sample,
		old_velocity
	)

	return true

func handle_track_movement(
	delta: float,
	force_snap: bool
 ) -> void:

	if current_track == null:
		return

	var current_sample := sample_track_at_offset(
		current_track,
		current_track_offset
	)

	if current_sample.is_empty():
		detach_from_track()
		return

	apply_track_sample(current_sample)


	# Scalar speed along increasing Curve2D offset.
	var track_speed := velocity.dot(
		track_tangent
	)


	# ====================================================
	# GRAVITY ALONG THE TRACK
	# ====================================================
	
	#TODO bruh I might get rid of no_grav_time
	if no_grav_time.is_stopped():
		var gravity := (
			Vector2.DOWN
			* get_gravity().length()
		)
		
		#TODO do I even want gravity to influence the player when walking on track?
		#     we already have slope speed varaibles to determine that...
		track_speed += (
			gravity.dot(track_tangent)
			* delta
		)


	# ====================================================
	# PLAYER INPUT
	# ====================================================

	track_speed = apply_track_input(
		track_speed,
		delta
	)


	# ====================================================
	# TRACTION
	# ====================================================

	if !has_track_traction(
		track_speed,
		force_snap
	):
		velocity = (
			track_tangent
			* track_speed
		)

		detach_from_track()
		return


	# ====================================================
	# NEXT OFFSET
	# ====================================================

	var curve_length := (
		current_track.curve.get_baked_length()
	)
	
	#TODO, wait, what if curve very steep all of a sudden? won't we zip up too fast?
	#      this part might be ugly, we might need to reevaluate
	var next_offset := (
		current_track_offset
		+ track_speed * delta
	)


	# ====================================================
	# END OF THIS CURVE
	# ====================================================
	# TODO What even is all this garbage? what if I want a circle in mid-air
	#      that I can infinitely round around on? why do you want to kick me out for no reason?
	if (
		next_offset < 0.0
		or next_offset > curve_length
	):
		var end_offset : float = clamp(
			next_offset,
			0.0,
			curve_length
		)

		var end_sample := sample_track_at_offset(
			current_track,
			end_offset
		)

		if end_sample.is_empty():
			detach_from_track()
			return

		var old_velocity := (
			track_tangent
			* track_speed
		)

		move_to_track_point(
			end_sample["point"]
		)

		current_track_offset = end_offset
		apply_track_sample(end_sample)

		velocity = (
			track_tangent
			* track_speed
		)

		if try_transition_to_nearby_track(
			old_velocity
		):
			return

		detach_from_track()
		return


	# ====================================================
	# SAMPLE NEXT CURVE POSITION
	# ====================================================

	var next_sample := sample_track_at_offset(
		current_track,
		next_offset
	)

	if next_sample.is_empty():
		detach_from_track()
		return


	var next_normal: Vector2 = next_sample["normal"]

	# IMPORTANT:
	# Velocity still follows the OLD tangent here.
	#
	# This lets us detect whether the terrain is curving
	# away from our existing momentum.
	# TODO do we only do this outward_speed stuff when going from one track to another?
	#      But I want it to work regardless...
	var pre_reorientation_velocity := (
		track_tangent
		* track_speed
	)

	var outward_speed := (
		pre_reorientation_velocity
		.dot(next_normal)
	)


	# ====================================================
	# NATURAL RAMP LAUNCH
	# ====================================================

	if (
		!force_snap
		and outward_speed > track_detach_normal_speed
		#TODO will all this even work? isn't there some other part of the code ruining this?
	):
		velocity = pre_reorientation_velocity

		detach_from_track()
		return


	# ====================================================
	# FOLLOW THE CURVE
	# ====================================================

	var reached_target := move_to_track_point(
		next_sample["point"]
	)

	if !reached_target:
		# We hit some NON-curved solid, e.g. a cube.
		#
		# Rare case: resynchronise our curve offset
		# to where physics actually stopped us.
		current_track_offset = (
			current_track.curve.get_closest_offset(
				current_track.to_local(
					global_position
				)
			)
		)

		var blocked_sample := sample_track_at_offset(
			current_track,
			current_track_offset
		)

		if !blocked_sample.is_empty():
			apply_track_sample(blocked_sample)

		# TODO why do we get to a complete standstill? what if I run into a spring on the track?
		#      what if I wanna bounce away from the thing I collided with?
		velocity = Vector2.ZERO
		return


	current_track_offset = next_offset
	apply_track_sample(next_sample)


	# THIS is the Fancy Pants bit:
	#
	# Keep the scalar speed and rotate its vector with
	# the new curve tangent.
	#
	# We do NOT continually project velocity and lose
	# speed every time the terrain bends.
	velocity = (
		track_tangent
		* track_speed
	)

#TODO why 2 different functions for walking? why not 2 in 1 function?!?!
func handle_free_walking(delta: float) -> void:
	var direction := Input.get_axis(
		"left",
		"right"
	)

	if direction != 0.0:
		var target_speed : float = max(
			walk_max_speed,
			max_speed_h
		)

		# Brake before reversing.
		if (
			abs(velocity.x) > 0.001
			and sign(velocity.x) != sign(direction)
		):
			velocity.x = move_toward(
				velocity.x,
				0.0,
				walk_decerelation * delta
			)

		# Don't destroy earned speed.
		elif (
			sign(velocity.x) == sign(direction)
			and abs(velocity.x) > target_speed
		):
			pass

		else:
			velocity.x = move_toward(
				velocity.x,
				direction * target_speed,
				walk_acceleration * delta
			)

	elif is_on_floor():
		velocity.x = move_toward(
			velocity.x,
			0.0,
			walk_decerelation * delta
		)

func handle_free_jump() -> void:
	if (
		Input.is_action_just_pressed("jump")
		and is_on_floor()
	):
		velocity.y = (
			-jump_speed
			* (
				1.0
				+ abs(velocity.x)
				/ running_jump_speed_divisor
			)
		)

func handle_free_state(
	delta: float,
	force_snap: bool
) -> void:

	# WORLD GRAVITY
	if no_grav_time.is_stopped():
		velocity += (
			Vector2.DOWN
			* get_gravity().length()
			* delta
		)

	handle_free_jump()

	handle_free_walking(delta)
	
	# TODO: what is this doing here? I want to always be able to hammer boost
	hammer_boosting_routine()


	# Save PRE-COLLISION velocity.
	#
	# This is useful both for proper attachment and
	# your possible future "hard ramp impact" reward.
	var approach_velocity := velocity


	# Real polygon physics while airborne/free.
	move_and_slide()


	#TODO shouldn't we only do this part when we're actually approaching a track? to save performance
	# Now we're on the SAFE side of collision geometry.
	refresh_nearby_tracks()

	try_attach_to_track(
		force_snap,
		approach_velocity
	)


	if current_track == null:
		handle_fallback_rotation()
