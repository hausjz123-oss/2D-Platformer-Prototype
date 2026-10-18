@tool
class_name Curved_terrain
extends Path2D


@export var edge_texture: Texture2D
@export var center_texture: Texture2D
@export var visible_collision: bool = true
@export var normal_test_distance := 2.0

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
	#
	# This is independent from the Curve2D Bake Interval.
	# tessellate() creates additional points where required so the
	# visible terrain can look smooth even with a coarse bake interval.
	# ============================================================

	var visual_points: PackedVector2Array = curve.tessellate(
		visual_tessellation_stages,
		visual_tolerance_degrees
	)


	# ============================================================
	# COLLISION GEOMETRY
	#
	# This intentionally uses the baked points.
	# Therefore Bake Interval controls physics complexity/performance
	# without forcing the visuals to use the same resolution.
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

func get_outward_normal_local(
	local_track_point: Vector2,
	local_tangent: Vector2
) -> Vector2:

	var normal := local_tangent.rotated(-PI / 2.0).normalized()

	if polygon2d == null or polygon2d.polygon.size() < 3:
		return normal

	var test_point := (
		local_track_point
		+ normal * normal_test_distance
	)

	# If this side points INTO the filled terrain,
	# then the opposite normal is the outward one.
	if Geometry2D.is_point_in_polygon(
		test_point,
		polygon2d.polygon
	):
		normal = -normal

	return normal
