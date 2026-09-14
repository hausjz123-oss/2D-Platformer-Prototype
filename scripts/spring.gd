extends Area2D

var spring_direction : Vector2
const STRENGTH = 1000

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	spring_direction = Vector2.RIGHT.rotated(global_rotation)


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	print(rad_to_deg(spring_direction.angle()))
	print("should be: " + str(global_rotation_degrees))

func _on_body_entered(body: Node2D) -> void:
	print("yippee")
	if (body.is_class("CharacterBody2D")): 
		# horizontal spring boost
		if (abs(body.velocity.x + spring_direction.x * STRENGTH) < abs(spring_direction.x * STRENGTH)):
			body.velocity.x = spring_direction.x * STRENGTH
		else: body.velocity.x += spring_direction.x * STRENGTH
		# vertical spring boost
		if (abs(body.velocity.y - spring_direction.y * STRENGTH) < abs(spring_direction.y * STRENGTH)):
			body.velocity.y = -(spring_direction.y * STRENGTH)
		else: body.velocity.y -= spring_direction.y * STRENGTH
		body.velocity = spring_direction*STRENGTH
