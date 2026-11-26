extends CharacterBody2D
# Two states, nothing else:
#
#   ON A TRACK (track != null)
#       Position = a distance along the Curve2D (track_offset).
#       Momentum = ONE number (track_speed, px/s along the curve).
#       Gravity, input, jumping and "do I fly off?" all work on that number.
#
#   FREE (track == null)
#       Ordinary velocity + move_and_slide() against the collision polygons,
#       cubes, plain floors, air, etc. Touching a track's polygon attaches us.
#
# The player's origin must be at his FEET (that's the rotation pivot).


# ---------------------------------------------------------------
# WALKING
# ---------------------------------------------------------------
@export var walk_max_speed := 300.0
@export var walk_acceleration := 1800.0
@export var walk_decerelation := 1800.0 # (sic) name kept so your inspector values survive
## Above walk_max_speed, momentum bleeds off this slowly instead of stopping at once.
@export var overspeed_drag := 150.0
@export var uphill_speed_reduction := 0.0 # relative, 0.0 .. 1.0
@export var jump_speed := 400.0
@export var running_jump_speed_divisor := 1000.0
@export var terminal_velocity := 1500.0


# ---------------------------------------------------------------
# TRACKS
# ---------------------------------------------------------------
## Collision layer NUMBER (1-32) that Curved_terrain's generated polygon lives on.
@export_range(1, 32, 1) var curved_terrain_collision_layer := 2
## How close (px) a polygon contact must be to the curve to attach to it.
@export var track_contact_distance := 16.0
## Holding "down" grabs tracks up to this far away (px).
@export var track_snap_distance := 60.0
## At the end of a curve, hop onto another curve closer than this (px).
@export var track_transition_distance := 20.0
## Steeper than this (degrees from flat) you need traction_min_speed to stay on.
@export var traction_start_angle_degrees := 45.0
## Speed needed on steep surfaces (walls, loops, ceilings).
## Bigger than walk_max_speed on purpose: you need a run-up.
@export var traction_min_speed := 350.0
## Extra pull toward the surface (px/s^2) when deciding if a crest launches you.
## Higher = harder to launch. 0 = pure physics.
@export var track_grip := 200.0
## Curvature is measured this far (px) before/after the player. Use ~2-3x the Curve2D bake interval.
@export var curvature_sample_distance := 16.0


# ---------------------------------------------------------------
# SPEEDOMETERS / SPRITE
# ---------------------------------------------------------------
@export var spedometer_max_showable_h := 1500.0
@export var spedometer_max_showable_v := 1500.0
@export var sprite_rotation_speed := 10.0

var max_speed_h := 0.0
var max_speed_v := 0.0
var sprite_rotation := 0.0
var PDrotation: float
var SHrotation: float
var SVrotation: float


# ---------------------------------------------------------------
# STATE
# ---------------------------------------------------------------
var track: Curved_terrain = null
var track_offset := 0.0
var track_speed := 0.0
var attach_lockout := 0.0 # seconds during which we may not (re)attach
var floor_normal := Vector2.UP

# Ignore "I'm touching it" attaches while moving AWAY from the surface faster than this.
const ATTACH_MAX_OUTWARD_SPEED := 50.0


## Everything we know about one point on a track.
class TrackSample:
	var track: Curved_terrain
	var offset := 0.0
	var point := Vector2.ZERO
	var tangent := Vector2.RIGHT # direction of increasing offset
	var normal := Vector2.UP     # points out of the terrain
	## + = concave (valley / inside of a loop), - = convex (crest). Units: 1/px
	var curvature := 0.0
	## +1 if walking "right" (relative to the character) means increasing offset, else -1
	var right_sign := 1.0
	var distance := 0.0          # only filled by sample_closest()


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
@onready var hammer_cooldown: Timer = $Hammer_cooldown
@onready var no_grav_time: Timer = $No_Grav_Time
@onready var speed_limit_h_decay_timer: Timer = $Spedometer_H/Speed_Limit_H_Decay_Timer
@onready var speed_limit_v_decay_timer: Timer = $Spedometer_V/Speed_Limit_V_Decay_Timer
@onready var air_flip_timer: Timer = $Air_Flip_Timer


func _ready() -> void:
	sprite_rotation = global_rotation
	PDrotation = $Proximity_Detector.global_rotation
	SHrotation = $Spedometer_H.global_rotation
	SVrotation = $Spedometer_V.global_rotation


func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("reload map"):
		get_tree().reload_current_scene()

	ray_cast_2d.global_rotation = (
		ray_cast_2d.global_position
		.direction_to(get_global_mouse_position())
		.angle()
	)

	proximity_detector_routine() # TODO improve proximity detector, because it's very useless right now
	spedometers_routines()

	# some hammer cooldown code
	if (
		track != null
		or is_on_floor()
		or is_on_ceiling()
		or is_on_wall()
	):
		if hammer_cooldown.time_left > 0:
			hammer_cooldown.stop()


func _physics_process(delta: float) -> void:
	attach_lockout = maxf(attach_lockout - delta, 0.0)
	var force_snap := Input.is_action_pressed("down")

	hammer_boosting_routine()

	if track != null:
		step_on_track(delta, force_snap)
	else:
		step_free(delta, force_snap)

	handle_max_speed_decay(delta)

	# Visual rotation lags behind the body so snapping looks smooth.
	sprite_rotation = rotate_toward(
		sprite_rotation,
		global_rotation,
		sprite_rotation_speed * delta
	)
	animated_sprite_2d.global_rotation = sprite_rotation

	# UI should not rotate with the body.
	$Proximity_Detector.global_rotation = PDrotation
	$Spedometer_H.global_rotation = SHrotation
	$Spedometer_V.global_rotation = SVrotation


# ===============================================================
# STATE 1: ON A TRACK
# ===============================================================

func step_on_track(delta: float, force_snap: bool) -> void:
	air_flip_timer.start(0.2) # (keeps the body rotated for a moment after we leave)

	var here := sample_track(track, track_offset)
	if here == null:
		detach_from_track(velocity)
		return

	# 1. Gravity pulls us along the slope. This is what makes downhill fast
	#    and uphill slow, and it's what lets a run-up carry you through a loop.
	if no_grav_time.is_stopped():
		track_speed += world_gravity().dot(here.tangent) * delta

	# 2. Input.
	track_speed = apply_track_input(track_speed, here, delta)
	track_speed = clampf(track_speed, -terminal_velocity, terminal_velocity)

	# 3. Jump.
	if Input.is_action_just_pressed("jump"):
		var boost := jump_speed * (1.0 + absf(track_speed) / running_jump_speed_divisor)
		detach_from_track(here.tangent * track_speed + here.normal * boost)
		return

	# 4. Do we leave the surface? Holding "down" overrides both rules.
	if not force_snap:
		if should_launch(here, track_speed) or lacks_traction(track_speed, here.normal):
			detach_from_track(here.tangent * track_speed)
			return

	# 5. Move along the curve.
	var length := track.curve.get_baked_length()
	var next_offset := track_offset + track_speed * delta

	if track.closed_loop:
		next_offset = fposmod(next_offset, length)
	elif next_offset < 0.0 or next_offset > length:
		leave_track_end(next_offset)
		return

	var next := sample_track(track, next_offset)
	if next == null:
		detach_from_track(velocity)
		return

	if move_to_point(next.point):
		track_offset = next_offset
		apply_track_pose(next)
		velocity = next.tangent * track_speed
	else:
		# A normal solid (cube, wall...) is in the way: stop dead, stay put.
		track_speed = 0.0
		apply_track_pose(here)
		velocity = Vector2.ZERO


## Ramp launch. A crest bends away from us; gravity (+grip) has to pull us down
## onto it. If our speed makes the crest bend away FASTER than that, we fly off.
## (centripetal acceleration = speed^2 * curvature). Works for any curve shape,
## shallow ramps included, as long as you're fast enough.
func should_launch(s: TrackSample, speed: float) -> bool:
	var convexity := maxf(-s.curvature, 0.0)
	var pull := maxf(-world_gravity().dot(s.normal), 0.0) + track_grip
	return speed * speed * convexity > pull


## Steep surfaces (walls, loops, ceilings) need speed to stay on.
func lacks_traction(speed: float, normal: Vector2) -> bool:
	var steepness := absf(Vector2.UP.angle_to(normal))
	return (
		steepness >= deg_to_rad(traction_start_angle_degrees)
		and absf(speed) < traction_min_speed
	)


func apply_track_input(speed: float, s: TrackSample, delta: float) -> float:
	var axis := Input.get_axis("left", "right")
	if axis == 0.0:
		return coast(speed, delta)

	# "Right" is relative to the CHARACTER. Upside down that's screen-left,
	# so holding the same key keeps pushing you around a loop.
	var dir_sign := signf(axis) * s.right_sign

	var move_dir := s.tangent * dir_sign
	var uphill := maxf(-move_dir.y, 0.0) # 0 = flat/downhill ... 1 = straight up
	var target := walk_max_speed * (1.0 - uphill_speed_reduction * uphill)

	return approach_walk_speed(speed, dir_sign, target, delta, true)


## Leaving the end of an open curve: hop onto a nearby curve or fly off.
func leave_track_end(next_offset: float) -> void:
	var length := track.curve.get_baked_length()
	var end_sample := sample_track(track, clampf(next_offset, 0.0, length))
	if end_sample == null:
		detach_from_track(velocity)
		return

	move_to_point(end_sample.point)
	var exit_velocity := end_sample.tangent * track_speed

	var hop := find_nearest_track(end_sample.point, track_transition_distance, track)
	if hop != null and can_attach(hop, exit_velocity, Input.is_action_pressed("down")):
		attach_to_track(hop, exit_velocity)
	else:
		detach_from_track(exit_velocity)


## Moves the body to a point on the curve. The curved terrain's own (coarse)
## polygon is ignored for this move, but cubes and other solids still block us.
## Returns false if something blocked the move.
func move_to_point(target: Vector2) -> bool:
	var motion := target - global_position
	if motion.length_squared() < 0.000001:
		return true

	var had_layer := get_collision_mask_value(curved_terrain_collision_layer)
	set_collision_mask_value(curved_terrain_collision_layer, false)
	var hit := move_and_collide(motion)
	set_collision_mask_value(curved_terrain_collision_layer, had_layer)

	return hit == null


func apply_track_pose(s: TrackSample) -> void:
	floor_normal = s.normal
	up_direction = s.normal
	rotation = Vector2.UP.angle_to(s.normal)


# ===============================================================
# STATE 2: FREE (air, cubes, ordinary floors)
# ===============================================================

func step_free(delta: float, force_snap: bool) -> void:
	if no_grav_time.is_stopped():
		velocity += world_gravity() * delta

	handle_free_jump()
	handle_free_walking(delta)
	handle_physics_rotation()

	var approach_velocity := velocity # before collisions eat it
	move_and_slide()

	try_attach_from_free(force_snap, approach_velocity)

	if track == null:
		handle_fallback_rotation()


func handle_free_jump() -> void:
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = -jump_speed * (1.0 + absf(velocity.x) / running_jump_speed_divisor)


func handle_free_walking(delta: float) -> void:
	var axis := Input.get_axis("left", "right")
	var on_floor := is_on_floor()

	if axis == 0.0:
		if on_floor:
			velocity.x = coast(velocity.x, delta)
		return

	# In the air we never pull earned speed back down to walking speed.
	velocity.x = approach_walk_speed(velocity.x, signf(axis), walk_max_speed, delta, on_floor)


## Touching a Curved_terrain's polygon (or holding "down" near one) attaches us.
func try_attach_from_free(force_snap: bool, approach_velocity: Vector2) -> void:
	if attach_lockout > 0.0:
		return

	var best: TrackSample = null

	for i in get_slide_collision_count():
		var body := get_slide_collision(i).get_collider() as Node
		if body == null:
			continue
		var owner_track := body.get_parent() as Curved_terrain # polygon body is a child of the terrain
		if owner_track == null:
			continue
		var s := sample_closest(owner_track, global_position)
		if s != null and s.distance <= track_contact_distance:
			if best == null or s.distance < best.distance:
				best = s

	if best == null and force_snap:
		best = find_nearest_track(global_position, track_snap_distance)

	if best == null:
		return

	# Moving away from the surface (just jumped, just launched)? Don't grab it again.
	if not force_snap and approach_velocity.dot(best.normal) > ATTACH_MAX_OUTWARD_SPEED:
		return

	if can_attach(best, approach_velocity, force_snap):
		attach_to_track(best, approach_velocity)


func can_attach(s: TrackSample, approach_velocity: Vector2, force_snap: bool) -> bool:
	# Never grab a track from INSIDE the terrain.
	if (global_position - s.point).dot(s.normal) < -track_contact_distance:
		return false
	if force_snap:
		return true
	# Too slow for a steep surface? Then it's just a wall/floor for normal physics.
	return not lacks_traction(approach_velocity.dot(s.tangent), s.normal)


func attach_to_track(s: TrackSample, approach_velocity: Vector2) -> void:
	track = s.track
	track_offset = s.offset
	# Keep the part of our momentum that points along the new track.
	track_speed = clampf(approach_velocity.dot(s.tangent), -terminal_velocity, terminal_velocity)
	apply_track_pose(s)
	global_position = s.point # the ONE snap
	velocity = s.tangent * track_speed


func detach_from_track(exit_velocity: Vector2, lockout := 0.12) -> void:
	track = null
	velocity = exit_velocity
	attach_lockout = lockout


# ===============================================================
# TRACK MATH
# ===============================================================

## Samples the curve at `offset`: position, direction, outward normal, curvature.
## Everything comes from three points on the curve, so it doesn't depend on
## the polygon or on the Bake Interval beyond smoothness.
func sample_track(t: Curved_terrain, offset: float) -> TrackSample:
	if t == null or t.curve == null:
		return null

	var length := t.curve.get_baked_length()
	if length < 1.0:
		return null

	var step := minf(curvature_sample_distance, length * 0.25)
	var o0 := offset - step
	var o2 := offset + step
	var ends_clipped := false

	if t.closed_loop:
		offset = fposmod(offset, length)
		o0 = fposmod(o0, length)
		o2 = fposmod(o2, length)
	else:
		ends_clipped = o0 < 0.0 or o2 > length
		offset = clampf(offset, 0.0, length)
		o0 = clampf(o0, 0.0, length)
		o2 = clampf(o2, 0.0, length)

	var p0 := t.to_global(t.curve.sample_baked(o0, true))
	var p1 := t.to_global(t.curve.sample_baked(offset, true))
	var p2 := t.to_global(t.curve.sample_baked(o2, true))

	var chord := p2 - p0
	if chord.length_squared() < 0.0001:
		return null

	var s := TrackSample.new()
	s.track = t
	s.offset = offset
	s.point = p1
	s.tangent = chord.normalized()
	s.normal = t.get_outward_normal(s.tangent)
	s.right_sign = signf(s.tangent.dot(s.normal.rotated(PI / 2.0)))
	if s.right_sign == 0.0:
		s.right_sign = 1.0

	# Second difference points toward the centre of curvature.
	# On the outward side of the surface => concave. Clipped at an open end => unknown, call it straight.
	if not ends_clipped:
		var half_chord := chord.length() * 0.5
		s.curvature = (p2 - 2.0 * p1 + p0).dot(s.normal) / (half_chord * half_chord)

	return s


func sample_closest(t: Curved_terrain, world_position: Vector2) -> TrackSample:
	if t == null or t.curve == null:
		return null
	var offset := t.curve.get_closest_offset(t.to_local(world_position))
	var s := sample_track(t, offset)
	if s != null:
		s.distance = world_position.distance_to(s.point)
	return s


func find_nearest_track(world_position: Vector2, max_distance: float, excluded: Curved_terrain = null) -> TrackSample:
	var best: TrackSample = null
	for node in get_tree().get_nodes_in_group("curved_track"):
		var t := node as Curved_terrain
		if t == null or t == excluded:
			continue
		var s := sample_closest(t, world_position)
		if s != null and s.distance <= max_distance:
			if best == null or s.distance < best.distance:
				best = s
	return best


# ===============================================================
# WALKING HELPERS (used by BOTH states)
# ===============================================================

func world_gravity() -> Vector2:
	return Vector2.DOWN * get_gravity().length()


## One step of "walk in direction dir (+1/-1)" on a signed 1D speed.
## - Moving against the input: brake first, and the moment we hit zero we
##   keep going and accelerate the other way in the same step.
## - Faster than walking speed: keep the momentum (optionally bleeding it slowly).
func approach_walk_speed(current: float, dir: float, target: float, delta: float, bleed_overspeed: bool) -> float:
	if current * dir < 0.0:
		current = move_toward(current, 0.0, walk_decerelation * delta)
		if current * dir < 0.0:
			return current # still braking

	if current * dir > target:
		if bleed_overspeed:
			return move_toward(current, dir * target, overspeed_drag * delta)
		return current

	return move_toward(current, dir * target, walk_acceleration * delta)


## No input: stop quickly at walking speeds, coast down slowly above them.
func coast(current: float, delta: float) -> float:
	var rate := walk_decerelation if absf(current) <= walk_max_speed else overspeed_drag
	return move_toward(current, 0.0, rate * delta)


# ===============================================================
# ROTATION FOR NON-TRACK FLOORS (unchanged from before)
# ===============================================================

func handle_physics_rotation() -> void:
	if air_flip_timer.time_left <= 0 and track == null:
		rotation = 0
		floor_normal = Vector2.UP
		up_direction = Vector2.UP


func get_average_floor_normal() -> Vector2:
	var total_normal := Vector2.ZERO
	var count := 0

	for i in get_slide_collision_count():
		var normal := get_slide_collision(i).get_normal()
		# Only normals reasonably related to our current floor
		if normal.dot(up_direction) > 0.0:
			total_normal += normal
			count += 1

	if count > 0:
		return (total_normal / count).normalized()

	return floor_normal


func handle_fallback_rotation() -> void:
	if get_slide_collision_count() > 0:
		var normal := get_average_floor_normal()
		if normal != Vector2.ZERO:
			floor_normal = normal
			up_direction = normal
			rotation = Vector2.UP.angle_to(normal)
	else:
		floor_normal = Vector2.UP
		up_direction = Vector2.UP


# ===============================================================
# HAMMER, SPEEDOMETERS, PROXIMITY (your code; hammer now leaves the track)
# ===============================================================

func hammer_boosting_routine() -> void:
	var hitbox_array: Array[Node2D] = hammer_hurtbox.get_overlapping_bodies()
	if hitbox_array.has(self):
		hitbox_array.erase(self)

	if (ray_cast_2d.is_colliding() or !hitbox_array.is_empty()) and !hammer_cooldown.time_left > 0:
		if Input.is_action_just_pressed("attack"):
			var hammer_direction := Vector2.RIGHT.rotated(ray_cast_2d.global_rotation)
			var boost_direction := -hammer_direction

			# Longest boost whose x and y parts stay within the preserved speeds.
			# (An axis with no component imposes no limit.)
			var Sx := INF
			var Sy := INF
			if boost_direction.x != 0.0:
				Sx = max_speed_h / absf(boost_direction.x)
			if boost_direction.y != 0.0:
				Sy = max_speed_v / absf(boost_direction.y)
			var s := minf(Sx, Sy)

			var boost_velocity := boost_direction * s
			if track != null:
				detach_from_track(boost_velocity, 0.2)
			velocity = boost_velocity
			hammer_cooldown.start()
			start_NoGravTimer(0.2)


func start_NoGravTimer(time: float) -> void:
	no_grav_time.start(time)


func handle_max_speed_decay(delta: float) -> void:
	# H
	var H_decay_rate := 100.0
	if absf(velocity.x) >= max_speed_h:
		max_speed_h = absf(velocity.x)
		speed_limit_h_decay_timer.start(1.0)
	elif speed_limit_h_decay_timer.is_stopped():
		max_speed_h = move_toward(max_speed_h, absf(velocity.x), H_decay_rate * delta)

	# V
	var V_decay_rate := 100.0
	if absf(velocity.y) >= max_speed_v:
		max_speed_v = absf(velocity.y)
		speed_limit_v_decay_timer.start(1.0)
	elif speed_limit_v_decay_timer.is_stopped():
		max_speed_v = move_toward(max_speed_v, absf(velocity.y), V_decay_rate * delta)


func spedometers_routines() -> void:
	# Spedometer_H_routine
	speed_meter_h.size.x = clamp(background_h.size.x / spedometer_max_showable_h * abs(velocity.x), 0.0, background_h.size.x)
	speed_limit_h.position.x = background_h.position.x + clamp(background_h.size.x / spedometer_max_showable_h * max_speed_h, 0.0, background_h.size.x)

	# Spedometer_V_routine
	speed_meter_v.size.x = clamp(background_v.size.x / spedometer_max_showable_v * abs(velocity.y), 0.0, background_v.size.x)
	speed_limit_v.position.x = background_v.position.x + clamp(background_v.size.x / spedometer_max_showable_v * max_speed_v, 0.0, background_v.size.x)

	if abs(velocity.x) >= spedometer_max_showable_h: speed_meter_h.color = Color(1, 1, 0)
	else: speed_meter_h.color = Color(1, 0, 0)
	if abs(velocity.y) >= spedometer_max_showable_v: speed_meter_v.color = Color(1, 1, 0)
	else: speed_meter_v.color = Color(1, 0, 0)

	# increasing limits and limit feedback
	if abs(velocity.x) >= max_speed_h and max_speed_h != 0:
		speed_limit_h.modulate = Color(1.0, 1.0, 0.0, 1.0)
		speed_limit_h.scale = Vector2(0.4, 0.4)
	else:
		speed_limit_h.modulate = Color(0.0, 1.0, 0.0, 1.0)
		speed_limit_h.scale = Vector2(0.232, 0.248)
	if abs(velocity.y) >= max_speed_v and max_speed_v != 0:
		speed_limit_v.modulate = Color(1.0, 1.0, 0.0, 1.0)
		speed_limit_v.scale = Vector2(0.4, 0.4)
	else:
		speed_limit_v.modulate = Color(0.0, 1.0, 0.0, 1.0)
		speed_limit_v.scale = Vector2(0.221, 0.251)


func proximity_detector_routine() -> void:
	# TargetPoint Distance Calculation
	var distanceFromTargetPoint := 0.0
	if ray_cast_2d.is_colliding():
		var targetPoint := ray_cast_2d.get_collision_point()
		distanceFromTargetPoint = (collision_shape_2d.global_position - targetPoint).length()

	# Shine and light management
	# max shine = 0.907
	# min shine = 0.35
	var hitbox_overlappers := hammer_hurtbox.get_overlapping_bodies()
	if hitbox_overlappers.has(self):
		hitbox_overlappers.erase(self)
	if !hitbox_overlappers.is_empty(): prox_light.modulate = Color(1, 1, 1, 1)
	else: prox_light.modulate = Color(1, 1, 1, 0)

	if ray_cast_2d.is_colliding():
		if distanceFromTargetPoint <= 100.0:
			prox_shine.scale = Vector2(0.907, 0.907)
		else:
			var newShineScale := 0.907 - (distanceFromTargetPoint - 100.0) / 100
			prox_shine.scale = Vector2(newShineScale, newShineScale)
	else:
		prox_shine.scale = Vector2(0.35, 0.35)
