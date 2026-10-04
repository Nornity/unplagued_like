extends CharacterBody3D

const WALK_SPEED := 5.4
const SPRINT_SPEED := 8.1
const JUMP_VELOCITY := 5.4
const LOOK_SENSITIVITY := 0.0022

var game: Node
var peer_id := 1
var camera: Camera3D
var ray: RayCast3D
var health := 100.0
var _pitch := 0.0
var _send_timer := 0.0
var _remote_goal := Vector3.ZERO
var _remote_yaw := 0.0
var _remote_pitch := 0.0
var _spray_cooldown := 0.0
var _breath_time := 0.0
var _weapon: Node3D
var _muzzle: OmniLight3D
var _body_visual: Node3D
var _callsign: Label3D
var _weapon_flash := 0.0


func _ready() -> void:
	_build_actor()
	_remote_goal = global_position


func configure(owner_game: Node, id: int) -> void:
	game = owner_game
	peer_id = id
	name = str(id)
	if id == multiplayer.get_unique_id():
		if _body_visual:
			_body_visual.visible = false
		if _callsign:
			_callsign.visible = false
	if _callsign:
		_callsign.text = "ДОЗОРНЫЙ %02d" % id


func _build_actor() -> void:
	var collision := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.36
	capsule.height = 1.8
	collision.shape = capsule
	collision.position.y = 0.92
	add_child(collision)
	var visuals := Node3D.new()
	visuals.name = "BodyVisual"
	add_child(visuals)
	_body_visual = visuals
	var coat := MeshInstance3D.new()
	var coat_mesh := CapsuleMesh.new()
	coat_mesh.radius = 0.34
	coat_mesh.height = 1.2
	coat.mesh = coat_mesh
	coat.position.y = 0.92
	coat.material_override = _material(Color("48594b"))
	visuals.add_child(coat)
	var hood := MeshInstance3D.new()
	var hood_mesh := SphereMesh.new()
	hood_mesh.radius = 0.27
	hood_mesh.height = 0.5
	hood.mesh = hood_mesh
	hood.position = Vector3(0, 1.66, 0)
	hood.material_override = _material(Color("bd9d71"))
	visuals.add_child(hood)
	var scarf := MeshInstance3D.new()
	var scarf_mesh := BoxMesh.new()
	scarf_mesh.size = Vector3(0.43, 0.18, 0.36)
	scarf.mesh = scarf_mesh
	scarf.position.y = 1.32
	scarf.material_override = _material(Color("a64f3b"))
	visuals.add_child(scarf)
	var lantern := OmniLight3D.new()
	lantern.name = "Lantern"
	lantern.position = Vector3(0.4, 1.15, -0.45)
	lantern.light_color = Color("efc879")
	lantern.light_energy = 1.05
	lantern.omni_range = 9.0
	lantern.shadow_enabled = true
	add_child(lantern)
	var camera_pivot := Node3D.new()
	camera_pivot.name = "Head"
	camera_pivot.position = Vector3(0, 1.57, 0)
	add_child(camera_pivot)
	camera = Camera3D.new()
	camera.name = "FirstPersonCamera"
	camera.current = false
	camera.fov = 79.0
	camera.near = 0.08
	camera.far = 130.0
	camera_pivot.add_child(camera)
	ray = RayCast3D.new()
	ray.name = "CureRay"
	ray.target_position = Vector3(0, 0, -8)
	ray.collision_mask = 1
	ray.enabled = true
	camera.add_child(ray)
	_weapon = Node3D.new()
	_weapon.name = "HerbalSprayer"
	_weapon.position = Vector3(0.34, -0.28, -0.58)
	_weapon.rotation_degrees = Vector3(-4, -3, 0)
	camera.add_child(_weapon)
	var body_mesh := MeshInstance3D.new()
	var body_shape := CylinderMesh.new()
	body_shape.top_radius = 0.095
	body_shape.bottom_radius = 0.13
	body_shape.height = 0.42
	body_mesh.mesh = body_shape
	body_mesh.rotation_degrees.x = 88
	body_mesh.material_override = _material(Color("565847"))
	_weapon.add_child(body_mesh)
	var flask := MeshInstance3D.new()
	var flask_mesh := SphereMesh.new()
	flask_mesh.radius = 0.12
	flask_mesh.height = 0.23
	flask.mesh = flask_mesh
	flask.position = Vector3(0.01, 0.13, 0.04)
	flask.material_override = _material(Color("739776"), Color("426549"))
	_weapon.add_child(flask)
	var nozzle := MeshInstance3D.new()
	var nozzle_mesh := CylinderMesh.new()
	nozzle_mesh.top_radius = 0.035
	nozzle_mesh.bottom_radius = 0.05
	nozzle_mesh.height = 0.22
	nozzle.mesh = nozzle_mesh
	nozzle.rotation_degrees.x = 88
	nozzle.position.z = -0.25
	nozzle.material_override = _material(Color("b6a77a"))
	_weapon.add_child(nozzle)
	_muzzle = OmniLight3D.new()
	_muzzle.light_color = Color("b0e49a")
	_muzzle.light_energy = 0.0
	_muzzle.omni_range = 3.5
	_muzzle.position.z = -0.36
	_weapon.add_child(_muzzle)
	var name_label := Label3D.new()
	name_label.name = "Callsign"
	name_label.text = "ДОЗОРНЫЙ %02d" % peer_id
	name_label.font_size = 30
	name_label.pixel_size = 0.009
	name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	name_label.position.y = 2.3
	name_label.modulate = Color("d5caa5")
	name_label.outline_size = 6
	name_label.outline_modulate = Color("151a16")
	add_child(name_label)
	_callsign = name_label


func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		global_position = global_position.lerp(_remote_goal, minf(1.0, delta * 12.0))
		rotation.y = lerp_angle(rotation.y, _remote_yaw, minf(1.0, delta * 12.0))
		if camera:
			camera.rotation.x = lerp_angle(
				camera.rotation.x, _remote_pitch, minf(1.0, delta * 12.0)
			)
		return
	if not camera.current:
		camera.current = true
	_spray_cooldown = maxf(0.0, _spray_cooldown - delta)
	_weapon_flash = maxf(0.0, _weapon_flash - delta)
	if _muzzle:
		_muzzle.light_energy = 1.8 if _weapon_flash > 0.0 else 0.0
	_breath_time += delta
	var input_vector := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var wish_dir := (transform.basis * Vector3(input_vector.x, 0, input_vector.y)).normalized()
	var speed := SPRINT_SPEED if Input.is_key_pressed(KEY_SHIFT) else WALK_SPEED
	if not is_on_floor():
		velocity.y -= 18.0 * delta
	elif Input.is_key_pressed(KEY_SPACE):
		velocity.y = JUMP_VELOCITY
	velocity.x = move_toward(velocity.x, wish_dir.x * speed, 22.0 * delta)
	velocity.z = move_toward(velocity.z, wish_dir.z * speed, 22.0 * delta)
	move_and_slide()
	if _weapon:
		var moving := input_vector.length() > 0.1
		_weapon.position.y = (
			-0.28 + (sin(_breath_time * (11.0 if moving else 2.0)) * (0.009 if moving else 0.004))
		)
	if game and game.game_active and not game.game_over:
		if Input.is_key_pressed(KEY_F) or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			if _spray_cooldown <= 0.0:
				_use_sprayer()
		_update_prompt()
		_send_timer -= delta
		if _send_timer <= 0.0:
			_send_timer = 0.09
			if multiplayer.is_server():
				game.rpc("sync_player_state", peer_id, global_position, rotation.y, _pitch)
			else:
				game.rpc_id(1, "submit_player_state", global_position, rotation.y, _pitch)


func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority() or not camera:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * LOOK_SENSITIVITY)
		_pitch = clampf(
			_pitch - event.relative.y * LOOK_SENSITIVITY, deg_to_rad(-82), deg_to_rad(82)
		)
		camera.rotation.x = _pitch
	elif (
		event is InputEventKey
		and event.pressed
		and event.keycode == KEY_ESCAPE
		and game
		and game.game_active
	):
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	elif (
		event is InputEventMouseButton
		and event.pressed
		and event.button_index == MOUSE_BUTTON_LEFT
		and game
		and game.game_active
	):
		if Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		elif _spray_cooldown <= 0.0:
			_use_sprayer()


func _use_sprayer() -> void:
	if not ray:
		return
	ray.force_raycast_update()
	if not ray.is_colliding():
		return
	var collider := ray.get_collider()
	if not collider is Node:
		return
	var root := collider.get_meta("villager_root", null) as Node3D
	if root == null:
		return
	if not bool(root.get_meta("infected", false)):
		return
	_spray_cooldown = 0.8
	_weapon_flash = 0.16
	if game:
		game.request_local_cure(root.name)


func has_infected_in_sight() -> bool:
	if not ray:
		return false
	ray.force_raycast_update()
	if not ray.is_colliding():
		return false
	var collider := ray.get_collider()
	if collider is Node:
		var root := collider.get_meta("villager_root", null) as Node3D
		return root != null and bool(root.get_meta("infected", false))
	return false


func _update_prompt() -> void:
	if not game or not game.cure_prompt:
		return
	if has_infected_in_sight():
		game.cure_prompt.text = "[F]  ИСЦЕЛИТЬ ЖИТЕЛЯ"
	else:
		game.cure_prompt.text = ""


func apply_network_state(at: Vector3, yaw: float, pitch: float) -> void:
	_remote_goal = at
	_remote_yaw = yaw
	_remote_pitch = pitch


func _material(color: Color, emission: Color = Color.BLACK) -> StandardMaterial3D:
	var result := StandardMaterial3D.new()
	result.albedo_color = color
	result.roughness = 0.86
	if emission != Color.BLACK:
		result.emission_enabled = true
		result.emission = emission
		result.emission_energy_multiplier = 1.7
	return result
