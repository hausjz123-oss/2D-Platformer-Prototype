extends CharacterBody2D


const SPEED = 300.0
const JUMP_VELOCITY = -700.0

@onready var area_2d: Area2D = $Area2D

func _physics_process(delta: float) -> void:
	# Add the gravity.
	if not is_on_floor():
		if (!is_on_floor()): velocity += get_gravity() * delta
		else: velocity += get_floor_normal().rotated(PI) * delta

	# Handle jump.
	if Input.is_action_just_pressed("jump") and !area_2d.get_overlapping_bodies().is_empty():
		velocity.y = JUMP_VELOCITY

	# Get the input direction and handle the movement/deceleration.
	# As good practice, you should replace UI actions with custom gameplay actions.
	var direction := Input.get_axis("left", "right")
	if direction:
		velocity.x = direction * SPEED
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)
	
	if (!area_2d.get_overlapping_bodies().is_empty() and is_on_floor()):
		rotation = Vector2.UP.angle_to(get_floor_normal())
	
	move_and_slide()
	
	
