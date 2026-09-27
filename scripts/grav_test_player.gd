extends CharacterBody2D


const SPEED = 300.0
const JUMP_VELOCITY = -700.0

var icon_rotation := 0.0
@export var icon_rotation_speed : float

@onready var area_2d: Area2D = $Area2D
@onready var ray_cast_2d: RayCast2D = $RayCast2D
@onready var air_flip_timer: Timer = $"../Air_flip_timer"
@onready var icon: Sprite2D = $Icon

func _ready() -> void:
	icon_rotation = global_rotation

func _physics_process(delta: float) -> void:
	
	up_direction = Vector2.UP.rotated(rotation)
	print(velocity.length())
	
	
	var arr_wo_player : Array[Node2D] = area_2d.get_overlapping_bodies()
	if(arr_wo_player.has(self)):
		arr_wo_player.remove_at(arr_wo_player.find(self))
		
	
	
	# Add the gravity.
	if (!arr_wo_player.is_empty() and velocity.length() >= 200): 
		if (Input.is_action_pressed("down")):
			snap_to_track()
		else:
			velocity += get_gravity().rotated(rotation) *  delta
	else:
		velocity += Vector2.DOWN * get_gravity().length() * delta


	# Handle jump.
	if Input.is_action_just_pressed("jump") and !area_2d.get_overlapping_bodies().is_empty():
		velocity -= Vector2.UP.rotated(rotation)*JUMP_VELOCITY

	# Get the input direction and handle the movement/deceleration.
	# As good practice, you should replace UI actions with custom gameplay actions.
	var direction := Input.get_axis("left", "right")
	if direction:
		if (!arr_wo_player.is_empty()):
			velocity += Vector2.RIGHT.rotated(rotation) * direction * SPEED*10 * delta
		else: velocity.x = move_toward(velocity.x, direction*1500,SPEED*delta*10)
	else:
		# velocity.x = move_toward(velocity.x, 0, SPEED)
		velocity -= velocity.project(Vector2.RIGHT.rotated(rotation)) * delta
	
	
	
	move_and_slide()
	
	if (get_last_slide_collision()):
		if (!arr_wo_player.is_empty()):
			rotation = Vector2.UP.angle_to(get_last_slide_collision().get_normal())
	
	if(air_flip_timer):
		if (air_flip_timer.time_left <= 0 and arr_wo_player.is_empty()):
			rotation = 0
		elif (!arr_wo_player.is_empty()):
			air_flip_timer.start(0.2)
	
	icon_rotation = rotate_toward(icon_rotation, rotation, icon_rotation_speed*delta)
	
	icon.global_rotation = icon_rotation
	
func snap_to_track():
	var snap_direction = Vector2.DOWN.rotated(rotation)
	var snap_distance = 50.0

	var collision = move_and_collide(
		snap_direction * snap_distance,
		true
	)

	if collision:
		var normal = collision.get_normal()

		# Actually move to the detected surface
		global_position += collision.get_travel()

		# Rotate to match the surface
		var target_rotation = Vector2.UP.angle_to(normal)
		rotation = target_rotation
		up_direction = normal

		# Remove velocity going away from / into the floor
		# Keep only movement along the surface
		velocity = velocity.slide(normal)
	
