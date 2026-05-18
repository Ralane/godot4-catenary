"""
    Asset: Godot Dynamic Catenary
    File: catenary.gd
    Description: Node for drawing a catenary between two points using the catenary shader.
                 Based on algorithms from https://www.alanzucconi.com/2020/12/13/catenary-2/
    Instructions: The script will create a temporary mesh instance for the catenary.
                  The position of this node acts as the starting point for the catenary.
                  Assign the target path to another spatial node which will act as the end point.
    Repository: https://github.com/Ralane/godot4-catenary
    License: MIT License
"""
@icon("res://addons/godot-catenary/Catenary.svg")
@tool
extends Node3D
class_name Catenary

## The minimum number of binary search iterations to find the catenary "a" parameter.
const _a_search_min_iterations:int = 16

const _three_sqrt_three = 1.73205080756888;

var previousScale;
			
## The mesh with the rope-like object spanning the x-axis
@export var mesh:Mesh:
	set(value):
		if value != mesh:
			mesh = value

			_create_mesh_instance()
			_update_curve()
		
## The end point target
@export var target_path:NodePath:
	set(value):
		target_path = value
		_target_node = null

		_update_curve()

## Whether to track the target node ingame using process. In general, you should enable this for moving entities, and disable it for static props and map decor.
@export var track_target:bool = true:
	set(value):
		track_target = value
		set_process(track_target or Engine.is_editor_hint())

## The real-world length of the catenary (limited by the distance between the start/end point)
@export var length:float = 5.0:
	set(value):
		length = value
		_update_curve()

func get_scaled_length():
	var autoLength = length;
	if(use_auto_length):
		autoLength += _target_node.global_position.distance_to(self.global_position);
	
	if(use_scale and is_inside_tree()):
		return autoLength * global_basis.get_scale().length() / _three_sqrt_three;
	return autoLength;

## The scale multiplier of the yz-axes of the mesh
@export var width = 1.0:
	set(value):
		width = value
		if _material != null:
			_material.set_shader_parameter("width", get_scaled_width())

## If true, the length will be automatically set to the distance, and the `length` property will be added. Useful for map editors like Trenchbroom that can't easily preview the generated shape.
@export var use_auto_length:bool = false:
	set(value):
		use_auto_length = value
		_update_curve()

## Whether or not to apply the scale to the width and length
@export var use_scale = true:
	set(value):
		use_scale = value;
		if _material != null:
			_material.set_shader_parameter("width", get_scaled_width())
		_update_curve();

func get_scaled_width():
	if(use_scale and is_inside_tree()):
		return width * global_basis.get_scale().length() / _three_sqrt_three;
	return width;
	
## The catenary swing angle in radians
@export_range(0, 3.141593) var swing_angle:float = 0.5:
	set(value):
		swing_angle = value
		if _material != null:
			_material.set_shader_parameter("swing_angle", swing_angle)

## The catenary swing frequency
@export_range(0, 10) var swing_frequency:float = 2:
	set(value):
		swing_frequency = value
		if _material != null:
			_material.set_shader_parameter("swing_frequency", swing_frequency)

## For func_godot support, this is the name of the OTHER node when it is being used as a target
@export_group("func_godot")
@export var target_node_name:String = "":
	set(value):
		target_node_name = value

## For func_godot support, this is the name of THIS node when being used as a target
@export var target_name:String = "":
	set(value):
		target_name = value

## The target node instance
var _target_node:Node3D

## The last known target node position
var _target_position:Vector3

## A temporary catenary mesh instance
var _mesh_instance:MeshInstance3D

## A temporary catenary material
var _material:ShaderMaterial

func _notification(what) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED:
		_update_curve()

func _ready() -> void:
	previousScale = global_basis.get_scale()
	_material.set_shader_parameter("swing_angle", swing_angle)
	_material.set_shader_parameter("swing_frequency", swing_frequency)
	_material.set_shader_parameter("width", get_scaled_width())
	_update_curve()

func _process(_delta:float) -> void:
	if _target_node != null and (_target_position != _target_node.global_position or (use_scale and is_inside_tree() and global_basis.get_scale() != previousScale)):
		_material.set_shader_parameter("width", get_scaled_width())
		previousScale = global_basis.get_scale();
		_update_curve()

func _create_mesh_instance() -> void:
	# Enable transform notifications for this spatial
	set_notify_transform(true)
   
	# Create a catenary material
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = preload("res://addons/godot-catenary/shaders/catenary.tres")
		_material.set_shader_parameter("width", get_scaled_width())
		_material.set_shader_parameter("swing_phase_offset", randf_range(0, PI * 2))
		_material.set_shader_parameter("swing_angle", swing_angle)
		_material.set_shader_parameter("swing_frequency", swing_frequency)

	# Remove any old mesh instance (updating old instance doesn't work in editor)
	if _mesh_instance != null:
		remove_child(_mesh_instance)

	# Create the catenary mesh instance as a child node of this spatial.
	# The mesh instance is an orphan which will not be saved with the scene,
	# otherwise the override material (+ textures) would be saved with the scene in the editor.
	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.name = "Catenary"
	_mesh_instance.mesh = mesh
	_mesh_instance.material_override = _material

	add_child(_mesh_instance)

	# If no mesh is assigned, just create an empty mesh instance
	if mesh == null:
		return

	# The mesh size is required for scaling the catenary
	var aabb:AABB = mesh.get_aabb()
	_material.set_shader_parameter("minmax_x", Vector2(aabb.position.x, aabb.end.x))

	# You may need to replace these uniforms based on what kind of shader is used on the mesh.
	# These uniforms act as a standard SchlickGGX shader in Godot.
	var material:StandardMaterial3D = mesh.surface_get_material(0)
	_material.set_shader_parameter("albedo", material.albedo_color)
	_material.set_shader_parameter("texture_albedo", material.albedo_texture)
	_material.set_shader_parameter("specular", material.metallic_specular)
	_material.set_shader_parameter("metallic", material.metallic)
	_material.set_shader_parameter("alpha_scissor_threshold", material.alpha_scissor_threshold)
	_material.set_shader_parameter("roughness", material.roughness)
	_material.set_shader_parameter("texture_metallic", material.metallic_texture)
	_material.set_shader_parameter("texture_roughness", material.roughness_texture)
	_material.set_shader_parameter("texture_emission", material.emission_texture)
	_material.set_shader_parameter("emission", material.emission)
	_material.set_shader_parameter("emission_energy", material.emission_intensity)
	_material.set_shader_parameter("texture_normal", material.normal_texture)
	_material.set_shader_parameter("normal_scale", material.normal_scale)
	
func _update_curve() -> void:
	# Create a mesh instance if none exists
	if _mesh_instance == null:
		_create_mesh_instance()

	# Get the target node
	if _target_node == null:
		if is_inside_tree() and !target_path.is_empty():
			_target_node = get_node(target_path)
		else:
			return

	var start:Vector3 = global_position
	var target:Vector3 = _target_node.global_position

	_target_position = target

	# Flip start and end point so that p0 is always the lowest
	var flip:bool = target.y < start.y
	var p0:Vector3 = target if flip else start
	var p1:Vector3 = start if flip else target
	
	if(p0.x == p1.x and p0.z == p1.z):
		# If the 2 nodes share an XZ coordinate, the math doesn't work out. Offset them by an infintesimally small point to avoid errors.
		p0 = p0 + Vector3(0.0001, 0, 0.0001)

	# Get the catenary arc length
	var shift:Vector3 = p1 - p0
	var l:float = max(shift.length() * 1.0001, get_scaled_length())

	# Approximate the "a" parameter of the catenary expression
	# See formulas at https://www.alanzucconi.com/2020/12/13/catenary-2/

	var h:float = sqrt(shift.x * shift.x + shift.z * shift.z)
	var v:float = shift.y
	var c:float = sqrt(l * l - v * v)

	assert(h != 0, "Catenary target distance cannot be determined");

	# Exponentially grow "a" range to a maximum of 2^32
	
	var a_min:float = 0
	var a_max:float = 1

	var i:int = 0

	while i < 32 and c < 2 * a_max * sinh(h / (2 * a_max)):
		i += 1
		a_min = a_max
		a_max *= 2

	# Binary search for "a" parameter
	
	i += _a_search_min_iterations

	var a:float

	while i > 0:
		i -= 1
		a = (a_min + a_max) * 0.5
		if c < 2 * a * sinh(h / (2 * a)):
			a_min = a
		else:
			a_max = a

	# Calculate "p" and "q" parameters based on catenary arc length and "a"
	var p:float = (h - a * log((l + v) / (l - v))) / 2
	var q:float = (v - l * (1 / tanh(h / (2 * a)))) / 2

	# Add the catenary arc length to the cull margin (this size is often larger than required)
	var ref:Node = self
	if ref is MeshInstance3D:
		ref.extra_cull_margin = l + 1
	_mesh_instance.extra_cull_margin = l + 1

	# Set shader uniforms related to the catenary
	_material.set_shader_parameter("p0", p0)
	_material.set_shader_parameter("p1", p1)
	_material.set_shader_parameter("apq", Vector3(a, p, q))
	_material.set_shader_parameter("arc_length", l)
	_material.set_shader_parameter("flip_x", 1.0 if flip else 0.0)


func _func_godot_apply_properties(entity_properties: Dictionary):
	mesh = load(entity_properties.get("mesh_path"));
	use_scale = entity_properties.get("use_scale");
	track_target = entity_properties.get("track_target");
	length = entity_properties.get("length");
	use_auto_length = entity_properties.get("use_auto_length");
	swing_angle = entity_properties.get("swing_angle");
	width = entity_properties.get("width");
	swing_frequency = entity_properties.get("swing_frequency");
	target_name = entity_properties.get("targetname");
	target_node_name = entity_properties.get("target");
	if(target_name != "" and target_name != null):
		self.name = target_name;
	
func _func_godot_build_complete() -> void:
	if(target_node_name != null and target_node_name != ""):
		var possibleChildren = get_tree().get_root().find_child(target_node_name, true, false);
		if(possibleChildren != null):
			target_path = possibleChildren.get_path();
		assert(target_path != null, "Catenary entity " + self.name + " could not find target " + self.target_name);
