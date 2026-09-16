extends CharacterBody2D


@export var max_walk_speed = 300.0
const JUMP_VELOCITY = -400.0
var max_speed_h = 0
var max_speed_v = 0
@export var slide_speed_min = 500
@export var spedometer_max_showable_h = 1500.0
@export var spedometer_max_showable_v = 1500.0

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

func _process(delta: float) -> void:
	# restart
	if (Input.is_action_just_pressed("reload map")): get_tree().reload_current_scene()
	# Raycast
	ray_cast_2d.rotation = collision_shape_2d.global_position.direction_to(get_global_mouse_position()).angle()
	
	# Proximity_Detector
	proximity_detector_routine() # TODO improve proximity detector, because it's very useless right now
	
	#spedometers routnines
	spedometers_routines()
	
	# some hammer cooldown code
	if ((is_on_floor() or is_on_ceiling() or is_on_wall()) and hammer_cooldown.time_left > 0): 
		hammer_cooldown.stop()

func _physics_process(delta: float) -> void:
	# Add the gravity.
	if (no_grav_time.is_stopped()):
		if not is_on_floor():
			velocity += get_gravity() * delta

	# Handle jump.
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY - abs(velocity.x)/5

	# Get the input direction and handle the movement/deceleration.
	var direction := Input.get_axis("left", "right")
	if direction:
		# velocity.x = direction * SPEED
		var v = max(max_walk_speed, max_speed_h)
		var acceleration = 1800.0
		velocity.x = move_toward(velocity.x, direction * v, acceleration * delta)
		if (Input.is_action_pressed("down") and abs(velocity.x) >= slide_speed_min):
				animated_sprite_2d.modulate = Color(1,1,0,1)
		else: animated_sprite_2d.modulate = Color(1,1,1,1)
	else:
		if (is_on_floor()): # TODO: improve sliding visuals to actually work as intended
			if (!Input.is_action_pressed("down") or abs(velocity.x) < slide_speed_min):
				var deceleration = 1800.0
				velocity.x = move_toward(velocity.x, 0, deceleration * delta)
				animated_sprite_2d.modulate = Color(1,1,1,1)
			else: animated_sprite_2d.modulate = Color(1,1,0,1)
	
	# Hammer boosting
	hammer_boosting_routine()
	
	handle_max_speed_decay(delta)
	
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
