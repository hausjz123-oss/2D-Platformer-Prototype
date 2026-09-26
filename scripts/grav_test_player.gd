extends CharacterBody2D


const SPEED = 300.0
const JUMP_VELOCITY = -700.0

@onready var area_2d: Area2D = $Area2D
@onready var ray_cast_2d: RayCast2D = $RayCast2D
@onready var air_flip_timer: Timer = $"../Air_flip_timer"

func _physics_process(delta: float) -> void:
	var arr_wo_player : Array[Node2D] = area_2d.get_overlapping_bodies()
	if(arr_wo_player.has(self)):
		arr_wo_player.remove_at(arr_wo_player.find(self))
		
	# Add the gravity.
	if (is_on_floor() and velocity.length() >= 200): 
		velocity += get_gravity().rotated(rotation) *  delta
	else:
		velocity += Vector2.DOWN * get_gravity().length() * delta

	# Handle jump.
	if Input.is_action_just_pressed("jump") and !area_2d.get_overlapping_bodies().is_empty():
		velocity.y = JUMP_VELOCITY

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
			rotation = rotate_toward(rotation, Vector2.UP.angle_to(get_last_slide_collision().get_normal()), delta*4)
	
	if(air_flip_timer):
		if (air_flip_timer.time_left <= 0 and arr_wo_player.is_empty()):
			rotation = move_toward(rotation, 0, delta*2)
		elif (!arr_wo_player.is_empty()):
			air_flip_timer.start(0.2)
	
	up_direction = Vector2.UP.rotated(rotation)
	print(velocity.length())

	
