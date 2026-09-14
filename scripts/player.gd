extends CharacterBody2D


const SPEED = 300.0
const JUMP_VELOCITY = -400.0
var max_speed_h = 0
var max_speed_v = 0
@onready var ray_cast_2d: RayCast2D = $RayCast2D
@onready var collision_shape_2d: CollisionShape2D = $CollisionShape2D
@onready var prox_light: Polygon2D = $Proximity_Detector/Prox_Light
@onready var prox_shine: Polygon2D = $Proximity_Detector/Prox_Shine
@onready var speed_meter_h: ColorRect = $Spedometer_H/Speed_Meter_H
@onready var speed_meter_v: ColorRect = $Spedometer_V/Speed_Meter_V
@onready var speed_limit_h: Sprite2D = $Spedometer_H/Speed_Limit_H
@onready var speed_limit_v: Sprite2D = $Spedometer_V/Speed_Limit_V

func _process(delta: float) -> void:
	# Raycast
	ray_cast_2d.rotation = collision_shape_2d.global_position.direction_to(get_global_mouse_position()).angle()
	
	# Proximity_Detector
	proximity_detector_routine()	
	

func _physics_process(delta: float) -> void:
	# Add the gravity.
	if not is_on_floor():
		velocity += get_gravity() * delta

	# Handle jump.
	if Input.is_action_just_pressed("ui_accept") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	# Get the input direction and handle the movement/deceleration.
	# As good practice, you should replace UI actions with custom gameplay actions.
	var direction := Input.get_axis("ui_left", "ui_right")
	if direction:
		# velocity.x = direction * SPEED
		velocity.x = move_toward(velocity.x, direction*SPEED, 10)
	else:
		velocity.x = move_toward(velocity.x, 0, 10)
	
	# Hammer boosting
	if (ray_cast_2d.is_colliding()):
		if (Input.is_action_just_pressed("attack")):
			var hammer_direction = Vector2.RIGHT.rotated(ray_cast_2d.global_rotation)
			var boost_direction = -hammer_direction
			
			velocity += boost_direction * 1000.0
			#TODO
			if (velocity.x < max_speed_h): velocity.x = max_speed_h
			if (velocity.x > -max_speed_h): velocity.x = -max_speed_h
			if (velocity.y < max_speed_v): velocity.y = max_speed_v
			if (velocity.y > -max_speed_v): velocity.y = -max_speed_v
	
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
