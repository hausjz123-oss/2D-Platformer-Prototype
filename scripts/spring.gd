@tool

extends Area2D

var spring_direction : Vector2
var STRENGTH
@onready var sprite_2d: Sprite2D = $Sprite2D
enum MODES {LIGHT, MEDIUM, STRONG}
@export var Strength_Mode: MODES:
	set(value):
		Strength_Mode = value
		if is_node_ready():
			update_strength_mode()


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	spring_direction = Vector2.RIGHT.rotated(global_rotation)
	update_strength_mode()


func _on_body_entered(body: Node2D) -> void:
	if (body.is_in_group("Players")): 
		print("yippee")
		body.velocity = spring_direction*STRENGTH
		body.start_NoGravTimer(0.2)

func update_strength_mode():
	if (Strength_Mode == MODES.LIGHT):
		sprite_2d.modulate = Color(0,1,0)
		STRENGTH = 700
	elif (Strength_Mode == MODES.MEDIUM):
		sprite_2d.modulate = Color(0.831, 0.69, 0.0, 1.0)
		STRENGTH = 1000
	elif (Strength_Mode == MODES.STRONG):
		sprite_2d.modulate = Color(0.522, 0.0, 0.71, 1.0)
		STRENGTH = 1500
	else: # impossible case
		sprite_2d.modulate = Color(0.0, 0.0, 0.0, 1.0)
		STRENGTH = 4000
