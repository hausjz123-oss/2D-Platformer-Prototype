extends CharacterBody2D


const SPEED = 300.0
const JUMP_VELOCITY = -400.0
var max_speed_h = 0
var max_speed_v = 0
const slide_speed_min = 300
@onready var ray_cast_2d: RayCast2D = $RayCast2D
@onready var collision_shape_2d: CollisionShape2D = $CollisionShape2D
@onready var prox_light: Polygon2D = $Proximity_Detector/Prox_Light
@onready var prox_shine: Polygon2D = $Proximity_Detector/Prox_Shine
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

func _process(delta: float) -> void:
	# Raycast
	ray_cast_2d.rotation = collision_shape_2d.global_position.direction_to(get_global_mouse_position()).angle()
	
	# Proximity_Detector
	proximity_detector_routine()	
	
	#spedometers routnines
	spedometers_routines()
	
	# some hammer cooldown code
	if ((is_on_floor() or is_on_ceiling() or is_on_wall()) and hammer_cooldown.time_left > 0): 
		hammer_cooldown.stop()
	
	# get closest hurtbox collider
	# TODO: Maybe you want the closest points of ALL colliders to make sure you can still boost in a way the code might think you're not allowed to eventhough you should be able to (example, at a ceiling, but next to a wall allowing upward boosts, but the ceiling is closer, disallowing upward boosts, but we want to boost up)
	
	

func _physics_process(delta: float) -> void:
	# Add the gravity.
	if (no_grav_time.is_stopped()):
		if not is_on_floor():
			velocity += get_gravity() * delta

	# Handle jump.
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	# Get the input direction and handle the movement/deceleration.
	var direction := Input.get_axis("left", "right")
	if direction:
		# velocity.x = direction * SPEED
		var v = max(SPEED, max_speed_h)
		velocity.x = move_toward(velocity.x, direction*v, 30)
	else:
		if (is_on_floor()):
			if (!Input.is_action_pressed("down") or abs(velocity.x) < slide_speed_min):
				velocity.x = move_toward(velocity.x, 0, 30)
				
	
	# Hammer boosting
	hammer_boosting_routine()
	
	handle_max_speed_decay() # TODO: The vertical part and understanding the 2 variations and using the better one
	
	move_and_slide()
	

func proximity_detector_routine():	
	# TargetPoint Distance Calculation
	var distanceFromTargetPoint: float
	if (ray_cast_2d.is_colliding()):
		var targetPoint = ray_cast_2d.get_collision_point()
		distanceFromTargetPoint = (collision_shape_2d.global_position-targetPoint).length()
	
	# Shine and light management
	# max shine = 0.907
	# min shine = 0.35
	if (ray_cast_2d.is_colliding()):
		if (distanceFromTargetPoint <= 100.0):
			prox_shine.scale = Vector2(0.907, 0.907)
			prox_light.modulate = Color(1,1,1,1)
		else:
			var newShineScale: float
			newShineScale = 0.907 - (distanceFromTargetPoint- 100.0)/100
			prox_shine.scale = Vector2(newShineScale, newShineScale)
			prox_light.modulate = Color(1,1,1,(100.0 -(distanceFromTargetPoint - 100.0))/100.0)
	else:
		prox_shine.scale = Vector2(0.35, 0.35)
		prox_light.modulate = Color(1,1,1,0)

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
	var velocity_proj_h = velocity.project(Vector2.RIGHT)
	var velocity_proj_v = velocity.project(Vector2.DOWN)
	
	# Spedometer_H_routine
	speed_meter_h.scale.x = abs(velocity_proj_h.x) / 100
	
	if (max_speed_h < abs(velocity_proj_h.x)):
		max_speed_h = abs(velocity_proj_h.x)
	speed_limit_h.position.x = -41 + max_speed_h/10
	
	
	# Spedometer_V_routine
	speed_meter_v.scale.x = abs(velocity_proj_v.y) / 100
	if (max_speed_v < abs(velocity_proj_v.y)):
		max_speed_v = abs(velocity_proj_v.y)
	speed_limit_v.position.x = -42 + max_speed_v/10
	
	# reaching limits feedback
	if (abs(velocity.x) >= max_speed_h && max_speed_h != 0): speed_limit_h.modulate = Color(1.0, 1.0, 0.0, 1.0)
	else: speed_limit_h.modulate = Color(0.0, 1.0, 0.0, 1.0)
	if (abs(velocity.y) >= max_speed_v && max_speed_v != 0): speed_limit_v.modulate = Color(1.0, 1.0, 0.0, 1.0)
	else: speed_limit_v.modulate = Color(0.0, 1.0, 0.0, 1.0)

func start_NoGravTimer(time : float):
	no_grav_time.start(time)

func handle_max_speed_decay():
	var H_is_decaying : bool
	var V_is_decaying : bool
	var H_decay_rate = 10
	var V_decay_rate = 10
	# H
	if (max_speed_h == 0): 
		H_is_decaying = false
	else:
		if (abs(velocity.x) >= max_speed_h):
			H_is_decaying = false
			speed_limit_h_decay_timer.paused = true
			
		else:
			if (!H_is_decaying and speed_limit_h_decay_timer.paused == true):
				speed_limit_h_decay_timer.paused = false
				speed_limit_h_decay_timer.start(1.0)
			elif(!H_is_decaying and speed_limit_h_decay_timer.is_stopped()):
				H_is_decaying = true
	if (H_is_decaying == true): max_speed_h -= H_decay_rate
	
func handle_max_speed_decay(delta):
	var H_decay_rate = 100.0
	
	if abs(velocity.x) >= max_speed_h:
		# We're at the current max, so don't decay it yet.
		speed_limit_h_decay_timer.start(1.0)
	
	elif speed_limit_h_decay_timer.is_stopped():
		# We've been below the max for 1 second.
		max_speed_h = move_toward(
			max_speed_h,
			abs(velocity.x),
			H_decay_rate * delta
		)
