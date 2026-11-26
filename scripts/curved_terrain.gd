@tool
class_name Curved_terrain
extends Path2D


@export var edge_texture: Texture2D
@export var center_texture: Texture2D
@export var visible_collision: bool = true

## Tick if the curve's first and last point are the same spot and you want to
## run around it forever (a full circle, a figure you can orbit...).
@export var closed_loop := false

## The player walks on the OUTSIDE of the filled shape (the side away from the fill).
## Tick this to make him walk on the other side, e.g. on the INSIDE of a
## loop-de-loop ring.
@export var invert_normals := false

# Visual curve quality.
# Higher stages = allows more subdivisions.
# Lower tolerance = follows the mathematical Bezier more closely.
@export_range(1, 10, 1) var visual_tessellation_stages := 5
@export_range(0.1, 20.0, 0.1) var visual_tolerance_degrees := 2.0

# Put generated curved-terrain collision on its own physics layer.
@export_flags_2d_physics var generated_collision_layer: int = 2


var polygon2d: Polygon2D
var line2d: Line2D
var collision_polygon2d: CollisionPolygon2D

# +1: the fill is on the RIGHT of the direction the curve is drawn (clockwise on screen).
# -1: the fill is on the LEFT.  Worked out once in generate_terrain().
var outward_sign := 1.0


func _ready() -> void:
	add_to_group("curved_track")

	# --------------------
	# CENTER / FILL
	# --------------------
	polygon2d = Polygon2D.new()
	polygon2d.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	add_child(polygon2d)

	# --------------------
	# EDGE
	# --------------------
	line2d = Line2D.new()
	line2d.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	line2d.texture_mode = Line2D.LINE_TEXTURE_TILE
	add_child(line2d)

	# --------------------
	# PHYSICAL COLLISION
	# --------------------
	var collision_staticbody := StaticBody2D.new()
	collision_staticbody.collision_layer = generated_collision_layer
	add_child(collision_staticbody)

	collision_polygon2d = CollisionPolygon2D.new()
	collision_staticbody.add_child(collision_polygon2d)

	generate_terrain()


func _process(_delta: float) -> void:
	# We only need to regenerate every frame while editing the terrain.
	if not Engine.is_editor_hint():
		set_process(false)
		return

	generate_terrain()


func generate_terrain() -> void:
	if curve == null or curve.point_count == 0:
		collision_polygon2d.polygon = PackedVector2Array()
		polygon2d.polygon = PackedVector2Array()
		line2d.points = PackedVector2Array()
		return

	# ============================================================
	# VISUAL GEOMETRY
	# Independent from the Curve2D Bake Interval.
	# ============================================================
	var visual_points: PackedVector2Array = curve.tessellate(
		visual_tessellation_stages,
		visual_tolerance_degrees
	)

	# ============================================================
	# COLLISION GEOMETRY
	# Uses the baked points, so Bake Interval controls physics complexity.
	# ============================================================
	var collider_points: PackedVector2Array = curve.get_baked_points()

	# --------------------
	# CENTER / FILL
	# --------------------
	polygon2d.polygon = visual_points
	polygon2d.texture = center_texture

	# --------------------
	# EDGE
	# --------------------
	var line_points := visual_points.duplicate()

	# Close the visual outline.
	if line_points.size() > 1:
		line_points.append(line_points[0])

	line2d.points = line_points
	line2d.texture = edge_texture

	# --------------------
	# COLLISION
	# --------------------
	if collider_points.size() > 2:
		collision_polygon2d.polygon = collider_points
	else:
		collision_polygon2d.polygon = PackedVector2Array()

	collision_polygon2d.visible = visible_collision

	# --------------------
	# WHICH SIDE IS "OUTSIDE"?
	# --------------------
	outward_sign = _compute_outward_sign(visual_points)


## Shoelace formula. Positive area (in Godot's y-down coordinates) means the
## shape is drawn clockwise on screen, so the fill is to the right of the
## drawing direction and "outside" is to the left.
func _compute_outward_sign(points: PackedVector2Array) -> float:
	var area2 := 0.0
	for i in points.size():
		var a := points[i]
		var b := points[(i + 1) % points.size()]
		area2 += a.x * b.y - b.x * a.y

	var result := 1.0 if area2 >= 0.0 else -1.0
	return -result if invert_normals else result


## Unit vector pointing out of the terrain, for a direction of travel along the
## curve given in WORLD space. Cheap: no polygon tests.
func get_outward_normal(global_tangent: Vector2) -> Vector2:
	# A mirrored (negatively scaled) node flips which side the fill is on.
	var mirrored := signf(global_transform.determinant())
	return global_tangent.rotated(-PI / 2.0 * outward_sign * mirrored).normalized()
