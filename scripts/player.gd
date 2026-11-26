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
	if ((is_on_floor() or is_on_ceiling() or is_on_wall()) and hammer_cooldown.time_left > 0): 
		hammer_cooldown.stop()

func _physics_process(delta: float) -> void:
	var force_snap = Input.is_action_pressed("down")
	
	# Find mathematical track if one is nearby.
	try_attach_to_track(force_snap)

	# UPDATE CURRENT TRACK ORIENTATION
	if current_track != null:
		var sample = sample_track(
			current_track,
			global_position,
			floor_normal
		)

		if !sample.is_empty():
			floor_normal = sample["normal"]
			up_direction = floor_normal

			rotation = Vector2.UP.angle_to(
				floor_normal
			)
			
	# GRAVITY
	if no_grav_time.is_stopped():
		velocity += (
			Vector2.DOWN
			* get_gravity().length()
			* delta
		)
	
	# JUMP
	handle_jump()

	# WALKING
	handle_walking(delta)
	
	# HAMMER
	hammer_boosting_routine()
	
	# handle physics rotation
	handle_physics_rotation()

	# NORMAL GODOT MOVE
	move_and_slide()
	
	# MATHEMATICAL TRACK
	if current_track != null:
		update_track_attachment(force_snap)
	else:
		handle_fallback_rotation()

	# SPEED LIMIT DATA
	handle_max_speed_decay(delta)

	# VISUAL ROTATION
	sprite_rotation = rotate_toward(
		sprite_rotation,
		global_rotation,
		sprite_rotation_speed * delta
	)
	animated_sprite_2d.global_rotation = sprite_rotation
	
	# DO NOT ROTATE UI
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

func sample_track(
	track: Curved_terrain,
	world_position: Vector2,
	preferred_normal := Vector2.ZERO
 ) -> Dictionary:

	if track == null or track.curve == null:
		return {}

	if track.curve.get_baked_length() <= 0.0:
		return {}

	var local_position = track.to_local(world_position)

	var offset = track.curve.get_closest_offset(local_position)

	var track_transform = track.curve.sample_baked_with_rotation(
		offset,
		true
	)

	var local_track_point = track_transform.origin
	var global_track_point = track.to_global(local_track_point)

	# sample_baked_with_rotation().x is the local tangent.
	var local_tangent = track_transform.x.normalized()

	var global_tangent = (
		track.to_global(local_track_point + local_tangent)
		- global_track_point
	).normalized()

	if global_tangent == Vector2.ZERO:
		return {}

	var normal = global_tangent.rotated(-PI / 2.0).normalized()

	# When already following a track, maintain the same side of it.
	if preferred_normal != Vector2.ZERO:
		if normal.dot(preferred_normal) < 0.0:
			normal = -normal

	# When first finding a track, choose the side facing the player.
	else:
		var toward_player = world_position - global_track_point

		if toward_player.length_squared() > 0.001:
			if normal.dot(toward_player) < 0.0:
				normal = -normal
		elif normal.dot(floor_normal) < 0.0:
			normal = -normal

	return {
		"track": track,
		"offset": offset,
		"point": global_track_point,
		"tangent": global_tangent,
		"normal": normal,
		"distance": world_position.distance_to(global_track_point)
	}

func find_nearest_track(
	world_position: Vector2,
	max_distance: float
 ) -> Dictionary:

	var best_sample := {}
	var best_distance := max_distance

	for node in get_tree().get_nodes_in_group("curved_track"):
		if !(node is Curved_terrain):
			continue

		var sample = sample_track(node, world_position)

		if sample.is_empty():
			continue

		var distance: float = sample["distance"]

		if distance <= best_distance:
			best_distance = distance
			best_sample = sample

	return best_sample

func try_attach_to_track(force_snap: bool) -> void:
	if current_track != null:
		return

	var search_distance = (
		track_snap_distance
		if force_snap
		else track_contact_distance
	)

	var sample = find_nearest_track(
		global_position,
		search_distance
	)

	if sample.is_empty():
		return

	var normal: Vector2 = sample["normal"]

	# Holding down means magnetically grab the track.
	#
	# Otherwise only attach if:
	# - we're basically stationary, or
	# - we're moving toward the track.
	var can_attach = (
		force_snap
		or velocity.length() < 20.0
		or velocity.dot(normal) < 0.0
	)

	if !can_attach:
		return

	current_track = sample["track"]
	floor_normal = normal

	global_position = sample["point"]

	var surface_right = floor_normal.rotated(PI / 2.0)

	velocity = velocity.project(surface_right)

	up_direction = floor_normal
	rotation = Vector2.UP.angle_to(floor_normal)

func get_surface_right() -> Vector2:
	return floor_normal.rotated(PI / 2.0)

func get_walk_target_speed(direction: float) -> float:
	var movement_direction = (get_surface_right() * direction).normalized()

	# +1 = straight downhill
	#  0 = flat
	# -1 = straight uphill
	var downhill_amount = movement_direction.dot(Vector2.DOWN)

	if downhill_amount >= 0.0:
		return lerp(
			walk_max_speed,
			terminal_velocity,
			downhill_amount
		)

	var steepness = -downhill_amount

	return lerp(
		walk_max_speed,
		walk_max_speed * (1.0 - uphill_speed_reduction),
		steepness
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

func handle_jump() -> void:
	if !Input.is_action_just_pressed("jump"):
		return

	if current_track != null:
		var surface_right = get_surface_right()

		var tangent_speed = abs(
			velocity.dot(surface_right)
		)

		velocity += floor_normal * jump_speed * (
			1.0 + tangent_speed / running_jump_speed_divisor
		)

		current_track = null
		return

	# Ordinary non-Curve2D fallback
	if is_on_floor():
		velocity.y = -jump_speed * (1.0 + velocity.x / running_jump_speed_divisor)

func update_track_attachment(force_snap: bool) -> void:
	if current_track == null:
		return

	var sample = sample_track(
		current_track,
		global_position,
		floor_normal
	)

	if sample.is_empty():
		current_track = null
		return

	var track_point: Vector2 = sample["point"]
	var normal: Vector2 = sample["normal"]
	var distance: float = sample["distance"]

	# TODO: mathematically, how does dot give us what we desire?
	var normal_distance = (
		global_position - track_point
	).dot(normal)

	if force_snap:
		# Holding down: actively stick to the terrain.
		if distance > track_snap_distance:
			current_track = null
			return

	else:
		# No magnetic sticking.
		#
		# If our natural motion takes us outward far enough,
		# release the track and let the player fly.
		if (
			# TODO: what's the point of having these 2 things if same?
			distance > track_follow_distance
			or normal_distance > track_release_distance
		):
			current_track = null
			return

	# We are still constrained to this track.
	global_position = track_point

	floor_normal = normal
	up_direction = normal

	rotation = Vector2.UP.angle_to(normal)

	# Keep only velocity along the track.
	var surface_right = get_surface_right()
	velocity = velocity.project(surface_right)

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
