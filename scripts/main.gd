extends Node3D

const Survivor = preload("res://scripts/survivor.gd")
const PORT := 24560
const MAX_PLAYERS := 4
const VILLAGE_NAMES := ["ВЕРЕСКОВО", "СЕРЫЙ БРОД", "ТИХАЯ ПРИСТАНЬ"]
const VILLAGE_CENTERS := [Vector3(-34, 0, -25), Vector3(34, 0, -22), Vector3(0, 0, 38)]

var players: Node3D
var world_root: Node3D
var infected := {}
var villages_cleansed := 0
var game_active := false
var game_over := false
var husks: Array[Dictionary] = []
var _net_timer := 0.0
var menu_layer: CanvasLayer
var menu_panel: Control
var menu_overlay: ColorRect
var menu_camera: Camera3D
var lobby_label: Label
var objective_label: Label
var status_label: Label
var ip_entry: LineEdit
var spray_flash: ColorRect
var crosshair: Label
var cure_prompt: Label
var end_panel: PanelContainer
var hud_layer: CanvasLayer
var player_count_label: Label
var network_hint: Label
var hud_health: ProgressBar
var hud_cure: ProgressBar
var hud_action: Label
var _hud_message_timer := 0.0
var _ambient_time := 0.0
var _screen_shake := 0.0


func _ready() -> void:
	_setup_input_map()
	_build_world()
	_build_ui()
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	_refresh_objective()


func _process(delta: float) -> void:
	_ambient_time += delta
	_hud_message_timer = maxf(0.0, _hud_message_timer - delta)
	if game_active and not game_over:
		_update_villager_ambience()
		if multiplayer.is_server():
			_update_husks(delta)
			_net_timer -= delta
			if _net_timer <= 0.0:
				_net_timer = 0.12
				_broadcast_world_state()
		if _hud_message_timer <= 0.0 and hud_action:
			hud_action.text = (
				"F / ЛКМ  ·  ИСЦЕЛИТЬ ЖИТЕЛЯ"
				if _can_see_infected()
				else "WASD · ДВИЖЕНИЕ     SHIFT · БЕГ     SPACE · ПРЫЖОК"
			)
	if _screen_shake > 0.0:
		_screen_shake = maxf(0.0, _screen_shake - delta * 4.0)
		if hud_layer:
			hud_layer.offset = Vector2(
				randf_range(-_screen_shake, _screen_shake),
				randf_range(-_screen_shake, _screen_shake)
			)
	else:
		if hud_layer:
			hud_layer.offset = Vector2.ZERO


func _setup_input_map() -> void:
	for action in ["move_left", "move_right", "move_forward", "move_back"]:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
	var bindings := {
		"move_left": KEY_A, "move_right": KEY_D, "move_forward": KEY_W, "move_back": KEY_S
	}
	for action in bindings:
		var key_event := InputEventKey.new()
		key_event.physical_keycode = bindings[action]
		InputMap.action_add_event(action, key_event)


func _build_world() -> void:
	world_root = Node3D.new()
	world_root.name = "World"
	add_child(world_root)
	_add_environment()
	_add_ground()
	_add_forest()
	_add_villages()
	_add_ruins()
	menu_camera = Camera3D.new()
	menu_camera.name = "MenuCamera"
	menu_camera.position = Vector3(0, 8.5, 24)
	menu_camera.fov = 62.0
	menu_camera.look_at(Vector3(0, 3, -2), Vector3.UP)
	menu_camera.current = true
	add_child(menu_camera)
	menu_camera.make_current()
	players = Node3D.new()
	players.name = "Players"
	add_child(players)
	_add_husks()


func _mat(color: Color, roughness := 0.92, emission := Color.BLACK) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	if emission != Color.BLACK:
		material.emission_enabled = true
		material.emission = emission
		material.emission_energy_multiplier = 1.4
	return material


func _mesh_node(
	parent: Node,
	node_name: String,
	mesh: Mesh,
	at: Vector3,
	material: Material,
	scale := Vector3.ONE
) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.position = at
	instance.scale = scale
	instance.material_override = material
	parent.add_child(instance)
	return instance


func _add_environment() -> void:
	var world_env := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color("101c24")
	sky_material.sky_horizon_color = Color("6d6c5a")
	sky_material.ground_bottom_color = Color("111714")
	sky_material.ground_horizon_color = Color("363b32")
	sky_material.sun_angle_max = 0.5
	sky.sky_material = sky_material
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("849087")
	environment.ambient_light_energy = 0.34
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_BG
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.fog_enabled = true
	environment.fog_light_color = Color("64685b")
	environment.fog_density = 0.008
	environment.fog_sky_affect = 0.48
	environment.volumetric_fog_enabled = true
	environment.volumetric_fog_density = 0.018
	environment.volumetric_fog_albedo = Color("777866")
	world_env.environment = environment
	world_root.add_child(world_env)
	var moon := DirectionalLight3D.new()
	moon.name = "Moonlight"
	moon.rotation_degrees = Vector3(-42, -35, 0)
	moon.light_color = Color("b5c6d2")
	moon.light_energy = 0.42
	moon.shadow_enabled = true
	moon.directional_shadow_max_distance = 95.0
	world_root.add_child(moon)


func _add_ground() -> void:
	var ground_body := StaticBody3D.new()
	ground_body.name = "Ground"
	world_root.add_child(ground_body)
	var plane := PlaneMesh.new()
	plane.size = Vector2(240, 240)
	_mesh_node(ground_body, "Wet Earth", plane, Vector3(0, -0.16, 0), _mat(Color("30372e"), 1.0))
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = Vector3(240, 0.3, 240)
	shape.shape = box_shape
	shape.position.y = -0.17
	ground_body.add_child(shape)
	# Muddy track connecting the three settlements.
	var road_mat := _mat(Color("48483a"), 1.0)
	for i in range(12):
		var z := -48.0 + i * 9.0
		var patch := BoxMesh.new()
		patch.size = Vector3(9.5, 0.1, 10.5)
		var curve_x := sin(z * 0.035) * 7.0
		_mesh_node(
			world_root,
			"Old road %02d" % i,
			patch,
			Vector3(curve_x, -0.095, z),
			road_mat,
			Vector3(1.0, 1.0, 1.0)
		)
	# A little standing water catches the moonlight.
	var water_mat := _mat(Color("252f30", 0.18), 0.22, Color("101b1d"))
	for i in range(12):
		var puddle := CylinderMesh.new()
		puddle.top_radius = 1.2 + fposmod(float(i) * 1.7, 1.3)
		puddle.bottom_radius = puddle.top_radius
		puddle.height = 0.035
		_mesh_node(
			world_root,
			"Puddle %02d" % i,
			puddle,
			Vector3(sin(i * 4.1) * 30, -0.08, cos(i * 2.7) * 31),
			water_mat
		)


func _add_forest() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 721035
	var trunk_mat := _mat(Color("393a30"))
	var leaf_mats := [_mat(Color("293b34")), _mat(Color("334237")), _mat(Color("414637"))]
	for i in range(170):
		var x := rng.randf_range(-104, 104)
		var z := rng.randf_range(-98, 98)
		var too_near := false
		for center in VILLAGE_CENTERS:
			if Vector2(x - center.x, z - center.z).length() < 19:
				too_near = true
		if too_near:
			continue
		var tree := Node3D.new()
		tree.name = "Ash Tree %03d" % i
		tree.position = Vector3(x, 0, z)
		world_root.add_child(tree)
		var tree_body := StaticBody3D.new()
		var tree_collider := CollisionShape3D.new()
		var tree_shape := CapsuleShape3D.new()
		tree_shape.radius = 0.45
		tree_shape.height = 3.4
		tree_collider.shape = tree_shape
		tree_collider.position.y = 1.7
		tree_body.add_child(tree_collider)
		tree.add_child(tree_body)
		var scale_factor := rng.randf_range(0.72, 1.45)
		var trunk := CylinderMesh.new()
		trunk.top_radius = 0.18
		trunk.bottom_radius = 0.38
		trunk.height = 3.4
		_mesh_node(tree, "Trunk", trunk, Vector3(0, 1.7, 0), trunk_mat, Vector3.ONE * scale_factor)
		for j in range(3):
			var crown := SphereMesh.new()
			crown.radius = 1.6 - j * 0.13
			crown.height = 3.7 - j * 0.18
			var crown_node := _mesh_node(
				tree,
				"Crown %d" % j,
				crown,
				Vector3(rng.randf_range(-0.35, 0.35), 3.4 + j * 0.75, rng.randf_range(-0.35, 0.35)),
				leaf_mats[rng.randi_range(0, 2)],
				Vector3(1.0, 0.86, 1.0) * scale_factor
			)
			crown_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		# Small pale stones and dead grass around the roots.
		if i % 3 == 0:
			var stone := SphereMesh.new()
			stone.radius = rng.randf_range(0.22, 0.55)
			stone.height = 0.42
			_mesh_node(
				world_root,
				"Root stone",
				stone,
				Vector3(x + rng.randf_range(-2, 2), 0.14, z + rng.randf_range(-2, 2)),
				_mat(Color("55564a"))
			)


func _add_villages() -> void:
	var wall_mat := _mat(Color("696353"))
	var wall_light := _mat(Color("77705d"))
	var roof_mat := _mat(Color("383a33"))
	var window_mat := _mat(Color("d6a653"), 0.35, Color("d68c3b"))
	var wood_mat := _mat(Color("554837"))
	var lantern_mat := _mat(Color("e1b96a"), 0.25, Color("edb756"))
	var npc_index := 0
	for vi in range(VILLAGE_CENTERS.size()):
		var center: Vector3 = VILLAGE_CENTERS[vi]
		var village := Node3D.new()
		village.name = "Village_%02d" % (vi + 1)
		world_root.add_child(village)
		# A ring of homes, a well, a bell post and a readable settlement sign.
		for hi in range(4):
			var angle := TAU * float(hi) / 4.0 + float(vi) * 0.24
			var home_pos := center + Vector3(cos(angle) * 10.0, 0, sin(angle) * 8.0)
			var house := Node3D.new()
			house.name = "House_%d" % hi
			house.position = home_pos
			house.rotation.y = -angle + PI / 2.0
			village.add_child(house)
			var body_mesh := BoxMesh.new()
			body_mesh.size = Vector3(6.2, 3.4, 5.0)
			_mesh_node(
				house,
				"Limewashed walls",
				body_mesh,
				Vector3(0, 1.75, 0),
				wall_mat if hi % 2 == 0 else wall_light
			)
			var house_body := StaticBody3D.new()
			house_body.position.y = 1.75
			house.add_child(house_body)
			var house_collider := CollisionShape3D.new()
			var house_shape := BoxShape3D.new()
			house_shape.size = Vector3(6.2, 3.5, 5.0)
			house_collider.shape = house_shape
			house_body.add_child(house_collider)
			var roof_mesh := CylinderMesh.new()
			roof_mesh.top_radius = 0.12
			roof_mesh.bottom_radius = 4.25
			roof_mesh.height = 2.6
			roof_mesh.radial_segments = 4
			_mesh_node(house, "Old roof", roof_mesh, Vector3(0, 4.5, 0), roof_mat)
			var door := BoxMesh.new()
			door.size = Vector3(1.15, 2.15, 0.15)
			_mesh_node(house, "Door", door, Vector3(0, 1.08, 2.56), wood_mat)
			var window := BoxMesh.new()
			window.size = Vector3(0.82, 0.9, 0.12)
			for side in [-1, 1]:
				_mesh_node(
					house, "Warm window", window, Vector3(float(side) * 1.8, 2.1, 2.56), window_mat
				)
			var glow := OmniLight3D.new()
			glow.light_color = Color("e9a64f")
			glow.light_energy = 0.65
			glow.omni_range = 6.0
			glow.position = Vector3(0, 2.1, 3.1)
			house.add_child(glow)
		# Villagers wait along the lane between the homes.
		for k in range(3):
			var name := "Villager_%02d" % (npc_index + 1)
			var offset := Vector3(
				cos(float(k) * 2.1 + vi) * (5.0 + k * 1.4),
				0,
				sin(float(k) * 2.1 + vi) * (5.0 + k * 1.4)
			)
			_add_villager(village, name, center + offset, npc_index)
			npc_index += 1
		_add_well(village, center + Vector3(-2.2, 0, 0))
		_add_bell(village, center + Vector3(0, 0, -14.0))
		var sign_text := Label3D.new()
		sign_text.text = VILLAGE_NAMES[vi]
		sign_text.font_size = 42
		sign_text.pixel_size = 0.008
		sign_text.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		sign_text.modulate = Color("e4d4a7")
		sign_text.position = center + Vector3(0, 5.2, -15.4)
		sign_text.outline_size = 8
		sign_text.outline_modulate = Color("20231e")
		world_root.add_child(sign_text)


func _add_villager(parent: Node3D, node_name: String, at: Vector3, index: int) -> void:
	var npc := Node3D.new()
	npc.name = node_name
	npc.position = at
	npc.add_to_group("villagers")
	parent.add_child(npc)
	var is_infected := true  # Every initial resident is sick; no healthy NPC is silently counted.
	npc.set_meta("infected", is_infected)
	npc.set_meta("index", index)
	var body_color := Color("6d6250") if index % 2 == 0 else Color("626854")
	var body_mesh := CapsuleMesh.new()
	body_mesh.radius = 0.34
	body_mesh.height = 1.45
	var body_material := _mat(
		Color("465144") if is_infected else body_color,
		0.95,
		Color("183d36") if is_infected else Color.BLACK
	)
	var body := _mesh_node(npc, "Wool cloak", body_mesh, Vector3(0, 0.88, 0), body_material)
	var head_mesh := SphereMesh.new()
	head_mesh.radius = 0.27
	head_mesh.height = 0.54
	var head_mat := _mat(Color("b89a75") if not is_infected else Color("8b9474"))
	_mesh_node(npc, "Face", head_mesh, Vector3(0, 1.72, 0), head_mat)
	var hood_mesh := SphereMesh.new()
	hood_mesh.radius = 0.3
	hood_mesh.height = 0.25
	_mesh_node(npc, "Hood", hood_mesh, Vector3(0, 1.89, -0.04), _mat(Color("383b31")))
	var collar := SphereMesh.new()
	collar.radius = 0.095
	collar.height = 0.12
	var eye_mat := _mat(
		Color("bde1a0") if is_infected else Color("c68d4e"),
		0.25,
		Color("81c889") if is_infected else Color("a96e30")
	)
	for side in [-1.0, 1.0]:
		_mesh_node(
			npc,
			"Sick glimmer",
			collar,
			Vector3(side * 0.105, 1.74, 0.222),
			eye_mat,
			Vector3(0.6, 0.7, 0.45)
		)
	var label := Label3D.new()
	label.name = "Condition"
	label.font_size = 32
	label.pixel_size = 0.008
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position.y = 2.35
	label.outline_size = 6
	label.outline_modulate = Color("151b17")
	label.text = "ЗАРАЖЁН" if is_infected else "ИСЦЕЛЁН"
	label.modulate = Color("a8cd9c") if is_infected else Color("e3ca8f")
	npc.add_child(label)
	var collision := StaticBody3D.new()
	collision.name = node_name
	collision.position.y = 0.88
	collision.add_to_group("villagers")
	npc.add_child(collision)
	var collider := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.48
	capsule.height = 1.8
	collider.shape = capsule
	collision.add_child(collider)
	collision.set_meta("villager_root", npc)
	infected[node_name] = npc


func _add_well(parent: Node3D, at: Vector3) -> void:
	var well := Node3D.new()
	well.name = "Village well"
	well.position = at
	parent.add_child(well)
	var stone := _mat(Color("77705c"))
	var dark := _mat(Color("1c2929"), 0.25)
	var ring := CylinderMesh.new()
	ring.top_radius = 1.0
	ring.bottom_radius = 1.2
	ring.height = 0.85
	_mesh_node(well, "Stone well", ring, Vector3(0, 0.4, 0), stone)
	var water := CylinderMesh.new()
	water.top_radius = 0.78
	water.bottom_radius = 0.78
	water.height = 0.08
	_mesh_node(well, "Black water", water, Vector3(0, 0.8, 0), dark)
	var post := BoxMesh.new()
	post.size = Vector3(0.2, 2.3, 0.2)
	_mesh_node(well, "Well post", post, Vector3(0, 1.7, 0), stone)
	var lamp := OmniLight3D.new()
	lamp.light_color = Color("8daa9b")
	lamp.light_energy = 0.2
	lamp.omni_range = 3.0
	lamp.position.y = 2.1
	well.add_child(lamp)


func _add_bell(parent: Node3D, at: Vector3) -> void:
	var bell_post := Node3D.new()
	bell_post.name = "Bell frame"
	bell_post.position = at
	parent.add_child(bell_post)
	var wood := _mat(Color("554532"))
	var metal := _mat(Color("aa8952"), 1.0, Color("6e552d"))
	var beam := BoxMesh.new()
	beam.size = Vector3(0.35, 5.5, 0.35)
	_mesh_node(bell_post, "Post L", beam, Vector3(-1.4, 2.7, 0), wood)
	_mesh_node(bell_post, "Post R", beam, Vector3(1.4, 2.7, 0), wood)
	var lintel := BoxMesh.new()
	lintel.size = Vector3(3.2, 0.35, 0.35)
	_mesh_node(bell_post, "Lintel", lintel, Vector3(0, 5.25, 0), wood)
	var bell_mesh := CylinderMesh.new()
	bell_mesh.top_radius = 0.18
	bell_mesh.bottom_radius = 0.62
	bell_mesh.height = 0.95
	_mesh_node(bell_post, "Bell", bell_mesh, Vector3(0, 4.55, 0), metal)
	var emissive := OmniLight3D.new()
	emissive.light_color = Color("dfbd70")
	emissive.light_energy = 0.45
	emissive.omni_range = 8.0
	emissive.position = Vector3(0, 4.5, 0.6)
	bell_post.add_child(emissive)


func _add_ruins() -> void:
	var stone := _mat(Color("53544a"))
	var moss := _mat(Color("394239"))
	for i in range(18):
		var angle := TAU * float(i) / 18.0
		var dist := 62.0 + float(i % 4) * 6.0
		var h := 1.0 + fposmod(float(i) * 1.73, 3.5)
		var pillar := BoxMesh.new()
		pillar.size = Vector3(1.4, h, 1.5)
		_mesh_node(
			world_root,
			"Old boundary stone",
			pillar,
			Vector3(cos(angle) * dist, h * 0.5, sin(angle) * dist),
			stone
		)
	# Abandoned chapel on the hill gives the three roads a shared landmark.
	var chapel := Node3D.new()
	chapel.name = "The abandoned chapel"
	chapel.position = Vector3(0, 0, -3)
	world_root.add_child(chapel)
	var wall := BoxMesh.new()
	wall.size = Vector3(12, 8, 9)
	_mesh_node(chapel, "Broken nave", wall, Vector3(0, 4, 0), moss)
	var roof := CylinderMesh.new()
	roof.top_radius = 0.05
	roof.bottom_radius = 8.0
	roof.height = 5.0
	roof.radial_segments = 4
	_mesh_node(chapel, "Collapsed roof", roof, Vector3(0, 9, 0), stone)
	var arch := BoxMesh.new()
	arch.size = Vector3(3.5, 5.4, 0.5)
	_mesh_node(chapel, "Door shadow", arch, Vector3(0, 2.7, 4.72), _mat(Color("1a211c")))
	var cross_v := BoxMesh.new()
	cross_v.size = Vector3(0.35, 3.3, 0.35)
	var cross_h := BoxMesh.new()
	cross_h.size = Vector3(1.7, 0.3, 0.35)
	_mesh_node(chapel, "Iron cross", cross_v, Vector3(0, 11.2, 0), stone)
	_mesh_node(chapel, "Cross arms", cross_h, Vector3(0, 11.7, 0), stone)


func _add_husks() -> void:
	var body_mat := _mat(Color("3f5445"), 0.9, Color("173528"))
	var head_mat := _mat(Color("606d54"))
	var eye_mat := _mat(Color("a5d17a"), 0.25, Color("74ca67"))
	var rng := RandomNumberGenerator.new()
	rng.seed = 41382
	for i in range(12):
		var husk := Node3D.new()
		husk.name = "Husk_%02d" % i
		husk.position = Vector3(rng.randf_range(-56, 56), 0, rng.randf_range(-53, 53))
		world_root.add_child(husk)
		var torso := CapsuleMesh.new()
		torso.radius = 0.42
		torso.height = 1.8
		_mesh_node(husk, "Rotting coat", torso, Vector3(0, 0.96, 0), body_mat)
		var head := SphereMesh.new()
		head.radius = 0.31
		head.height = 0.62
		_mesh_node(husk, "Mask", head, Vector3(0, 2.0, 0), head_mat)
		var eye := SphereMesh.new()
		eye.radius = 0.07
		eye.height = 0.12
		for side in [-1.0, 1.0]:
			_mesh_node(husk, "Fever eye", eye, Vector3(side * 0.13, 2.01, 0.255), eye_mat)
		husk.set_meta("attack_timer", 0.4 + float(i) * 0.12)
		husk.set_meta("seed", float(i) * 2.3)
		husks.append({"node": husk, "id": i})


func _update_villager_ambience() -> void:
	for node_name in infected:
		var npc: Node3D = infected[node_name]
		if npc and is_instance_valid(npc):
			var phase: float = float(npc.get_meta("index", 0)) * 1.7
			var head := npc.get_node_or_null("Face") as MeshInstance3D
			if head:
				head.position.y = 1.72 + sin(_ambient_time * 1.4 + phase) * 0.035


func _update_husks(delta: float) -> void:
	for item in husks:
		var husk: Node3D = item.node
		if not is_instance_valid(husk):
			continue
		var closest: Node3D = null
		var closest_distance := 100000.0
		for player_id in players.get_children():
			if not is_instance_valid(player_id):
				continue
			var distance := husk.global_position.distance_to(player_id.global_position)
			if distance < closest_distance:
				closest_distance = distance
				closest = player_id
		if closest == null:
			continue
		var direction := closest.global_position - husk.global_position
		direction.y = 0
		if closest_distance > 1.55:
			direction = direction.normalized()
			husk.global_position += direction * delta * 1.5
			husk.rotation.y = atan2(direction.x, direction.z)
		var timer := float(husk.get_meta("attack_timer", 0.0)) - delta
		husk.set_meta("attack_timer", timer)
		if closest_distance < 2.1 and timer <= 0.0:
			husk.set_meta("attack_timer", 1.8)
			var peer_id := int(closest.name)
			rpc("damage_player", peer_id, 12.0)


func _broadcast_world_state() -> void:
	for item in husks:
		var husk: Node3D = item.node
		if is_instance_valid(husk):
			rpc("sync_husk", int(item.id), husk.global_position, husk.rotation.y)


@rpc("authority", "call_local", "unreliable")
func sync_husk(id: int, at: Vector3, yaw: float) -> void:
	if multiplayer.is_server():
		return
	var target := world_root.get_node_or_null("Husk_%02d" % id) as Node3D
	if target:
		target.global_position = target.global_position.lerp(at, 0.58)
		target.rotation.y = yaw


@rpc("authority", "call_local", "reliable")
func spawn_player(peer_id: int) -> void:
	if players.has_node(str(peer_id)):
		return
	var actor := Survivor.new()
	actor.name = str(peer_id)
	actor.set_multiplayer_authority(peer_id)
	players.add_child(actor)
	actor.configure(self, peer_id)
	var spawn_at := Vector3(0, 0.1, 0)
	if peer_id != 1:
		spawn_at += Vector3(float((peer_id % 2) * 3 - 1), 0, float(peer_id * 2))
	actor.global_position = spawn_at
	if multiplayer.is_server() and peer_id != 1:
		var cured_names: Array[String] = []
		for villager_name in infected:
			if not bool((infected[villager_name] as Node3D).get_meta("infected", true)):
				cured_names.append(villager_name)
		rpc_id(peer_id, "sync_mission_state", cured_names)
	if peer_id == multiplayer.get_unique_id():
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		menu_overlay.visible = false
		menu_panel.visible = false
		hud_layer.visible = true
		game_active = true
		if multiplayer.is_server():
			network_hint.text = "HOST  ·  %s:%d  ·  UDP" % [_get_lan_ip(), PORT]
		else:
			network_hint.text = "СОЕДИНЕНО С ХОСТОМ  ·  %s:%d" % [ip_entry.text.strip_edges(), PORT]
		status_label.text = "СВЯЗЬ УСТАНОВЛЕНА · ИЩИТЕ ЗАРАЖЁННЫХ"
		status_label.modulate = Color("cbd2aa")
		_refresh_objective()
	_update_player_count()


@rpc("authority", "call_remote", "reliable")
func sync_mission_state(cured_names: Array[String]) -> void:
	for villager_name in cured_names:
		var npc: Node3D = infected.get(villager_name)
		if npc == null:
			continue
		npc.set_meta("infected", false)
		var label := npc.get_node_or_null("Condition") as Label3D
		if label:
			label.text = "ИСЦЕЛЁН"
			label.modulate = Color("e3ca8f")
		var body := npc.get_node_or_null("Wool cloak") as MeshInstance3D
		if body:
			body.material_override = _mat(Color("797360"))
		for eye in npc.find_children("Sick glimmer", "MeshInstance3D", true, false):
			(eye as MeshInstance3D).visible = false
	_refresh_objective()


@rpc("any_peer", "unreliable")
func submit_player_state(at: Vector3, yaw: float, pitch: float) -> void:
	if not multiplayer.is_server():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	if not players.has_node(str(peer_id)):
		return
	var actor: CharacterBody3D = players.get_node(str(peer_id))
	if actor.global_position.distance_to(at) > 5.0:
		return
	rpc("sync_player_state", peer_id, at, yaw, pitch)


@rpc("authority", "call_local", "unreliable")
func sync_player_state(peer_id: int, at: Vector3, yaw: float, pitch: float) -> void:
	var actor = players.get_node_or_null(str(peer_id))
	if actor and peer_id != multiplayer.get_unique_id():
		actor.apply_network_state(at, yaw, pitch)


@rpc("any_peer", "reliable")
func request_cure(villager_name: String) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	var actor := players.get_node_or_null(str(sender)) as Node3D
	var npc: Node3D = infected.get(villager_name)
	if actor == null or npc == null or not is_instance_valid(npc):
		return
	if not bool(npc.get_meta("infected", false)):
		return
	if actor.global_position.distance_to(npc.global_position) > 8.5:
		return
	npc.set_meta("infected", false)
	villages_cleansed += 1
	rpc("cure_broadcast", villager_name, sender)
	if villages_cleansed >= 9:
		game_over = true
		rpc("mission_complete")


@rpc("authority", "call_local", "reliable")
func cure_broadcast(villager_name: String, healer_id: int) -> void:
	var npc: Node3D = infected.get(villager_name)
	if npc == null or not is_instance_valid(npc):
		return
	npc.set_meta("infected", false)
	var label := npc.get_node_or_null("Condition") as Label3D
	if label:
		label.text = "ИСЦЕЛЁН"
		label.modulate = Color("e3ca8f")
	var body := npc.get_node_or_null("Wool cloak") as MeshInstance3D
	if body:
		var mat := _mat(Color("797360"))
		body.material_override = mat
	for child in npc.find_children("Sick glimmer", "MeshInstance3D", true, false):
		(child as MeshInstance3D).visible = false
	_refresh_objective()
	_screen_shake = 1.2
	if healer_id == multiplayer.get_unique_id():
		show_message("ЖИТЕЛЬ ИСЦЕЛЁН  ·  +1 К РАССВЕТУ")
	else:
		show_message("ЖИТЕЛЬ ИСЦЕЛЁН СОЮЗНИКОМ")


@rpc("authority", "call_local", "reliable")
func damage_player(peer_id: int, amount: float) -> void:
	var actor = players.get_node_or_null(str(peer_id))
	if actor == null:
		return
	actor.health = maxf(0.0, actor.health - amount)
	if peer_id == multiplayer.get_unique_id():
		_update_health(actor.health)
		_screen_shake = 3.0
	if actor.health <= 0.0:
		actor.health = 100.0
		actor.global_position = Vector3(0, 0.1, 0)
		if peer_id == multiplayer.get_unique_id():
			show_message("ПРОТИВОЯДИЕ ВЕРНУЛО ВАС К ЧАСОВНЕ")


@rpc("authority", "call_local", "reliable")
func mission_complete() -> void:
	game_over = true
	game_active = false
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	if end_panel:
		end_panel.visible = true
	if status_label:
		status_label.text = "ВСЕ ТРИ ДЕРЕВНИ ОЧИЩЕНЫ. КОЛОКОЛ ЗАЗВУЧАЛ ВНОВЬ."


func request_local_cure(villager_name: String) -> void:
	if not game_active or game_over:
		return
	if multiplayer.is_server():
		# The host has no remote sender id, so use a direct validation path.
		var actor := players.get_node_or_null(str(multiplayer.get_unique_id())) as Node3D
		var npc: Node3D = infected.get(villager_name)
		if (
			actor
			and npc
			and bool(npc.get_meta("infected", false))
			and actor.global_position.distance_to(npc.global_position) <= 8.5
		):
			npc.set_meta("infected", false)
			villages_cleansed += 1
			rpc("cure_broadcast", villager_name, multiplayer.get_unique_id())
			if villages_cleansed >= 9:
				game_over = true
				rpc("mission_complete")
	else:
		rpc_id(1, "request_cure", villager_name)


func show_message(message: String) -> void:
	if status_label:
		status_label.text = message
	_hud_message_timer = 2.2


func _refresh_objective() -> void:
	var healed := 0
	for node_name in infected:
		var npc: Node3D = infected[node_name]
		if is_instance_valid(npc) and not bool(npc.get_meta("infected", true)):
			healed += 1
	if objective_label:
		objective_label.text = (
			"ОЧИЩЕНО ДЕРЕВЕНЬ: %d / 3     ·     ИСЦЕЛЕНО ЖИТЕЛЕЙ: %d / 9"
			% [int(healed / 3), healed]
		)
	if hud_cure:
		hud_cure.value = healed
	if lobby_label and game_active:
		lobby_label.text = "ОТРЯД  ·  %d / %d" % [players.get_child_count(), MAX_PLAYERS]


func _update_health(value: float) -> void:
	if hud_health:
		hud_health.value = value


func _can_see_infected() -> bool:
	var local = players.get_node_or_null(str(multiplayer.get_unique_id()))
	return local != null and local.has_infected_in_sight()


func _on_peer_connected(peer_id: int) -> void:
	if multiplayer.is_server():
		rpc("spawn_player", peer_id)
	_update_player_count()


func _on_peer_disconnected(peer_id: int) -> void:
	var actor := players.get_node_or_null(str(peer_id))
	if actor:
		actor.queue_free()
	_update_player_count()


func _on_connected_to_server() -> void:
	status_label.text = "СОЕДИНЕНО · ОЖИДАНИЕ ХОСТА"
	status_label.modulate = Color("cbd2aa")


func _on_connection_failed() -> void:
	_show_error("НЕ УДАЛОСЬ ПОДКЛЮЧИТЬСЯ. ПРОВЕРЬТЕ IP И ПОРТ 24560.")
	_reset_network()


func _on_server_disconnected() -> void:
	_show_error("СВЯЗЬ С ХОСТОМ ПОТЕРЯНА.")
	_reset_network()


func _show_error(message: String) -> void:
	status_label.text = message
	status_label.modulate = Color("d98b73")
	menu_overlay.visible = true
	menu_panel.visible = true
	hud_layer.visible = false
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func _reset_network() -> void:
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	for child in players.get_children():
		child.queue_free()
	game_active = false
	game_over = false


func _update_player_count() -> void:
	if lobby_label and players:
		lobby_label.text = "ОТРЯД  ·  %d / %d" % [players.get_child_count(), MAX_PLAYERS]
	if player_count_label and players:
		player_count_label.text = "СОЮЗНИКИ  %d / %d" % [players.get_child_count(), MAX_PLAYERS]


func _get_lan_ip() -> String:
	for address in IP.get_local_addresses():
		if address.begins_with("192.168.") or address.begins_with("10."):
			return address
		if address.begins_with("172."):
			var parts := address.split(".")
			if parts.size() > 1 and int(parts[1]) >= 16 and int(parts[1]) <= 31:
				return address
	return "127.0.0.1"


func _on_host_pressed() -> void:
	_reset_world_state()
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_server(PORT, MAX_PLAYERS - 1)
	if error != OK:
		_show_error("НЕ УДАЛОСЬ СОЗДАТЬ СЕРВЕР · %s" % error_string(error))
		return
	multiplayer.multiplayer_peer = peer
	status_label.text = "КОМНАТА СОЗДАНА · %s:%d · ПЕРЕДАЙТЕ IP ДРУЗЬЯМ" % [_get_lan_ip(), PORT]
	status_label.modulate = Color("cbd2aa")
	network_hint.text = "HOST  ·  %s:%d  ·  UDP" % [_get_lan_ip(), PORT]
	game_active = true
	rpc("spawn_player", multiplayer.get_unique_id())
	if menu_panel.visible:
		menu_overlay.visible = false
		menu_panel.visible = false
		hud_layer.visible = true
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		var local = players.get_node_or_null(str(multiplayer.get_unique_id()))
		if local:
			local.configure(self, multiplayer.get_unique_id())
			local.global_position = Vector3(0, 0.1, 0)
	_refresh_objective()


func _on_join_pressed() -> void:
	_reset_world_state()
	var address := ip_entry.text.strip_edges()
	if address.is_empty():
		address = "127.0.0.1"
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_client(address, PORT)
	if error != OK:
		_show_error("НЕ УДАЛОСЬ НАЧАТЬ ПОДКЛЮЧЕНИЕ · %s" % error_string(error))
		return
	multiplayer.multiplayer_peer = peer
	status_label.text = "ПОДКЛЮЧАЕМСЯ К %s:%d…" % [address, PORT]
	status_label.modulate = Color("cbd2aa")


func _reset_world_state() -> void:
	villages_cleansed = 0
	game_over = false
	for node_name in infected:
		var npc: Node3D = infected[node_name]
		if not is_instance_valid(npc):
			continue
		npc.set_meta("infected", true)
		var label := npc.get_node_or_null("Condition") as Label3D
		if label:
			label.text = "ЗАРАЖЁН"
			label.modulate = Color("a8cd9c")
		var body := npc.get_node_or_null("Wool cloak") as MeshInstance3D
		if body:
			body.material_override = _mat(Color("465144"), 0.95, Color("183d36"))
		for child in npc.find_children("Sick glimmer", "MeshInstance3D", true, false):
			(child as MeshInstance3D).visible = true
	_refresh_objective()


func _build_ui() -> void:
	menu_layer = CanvasLayer.new()
	menu_layer.layer = 10
	add_child(menu_layer)
	menu_overlay = ColorRect.new()
	menu_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu_overlay.color = Color(0.035, 0.055, 0.052, 0.78)
	menu_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu_layer.add_child(menu_overlay)
	menu_panel = PanelContainer.new()
	menu_panel.name = "MainMenu"
	menu_panel.set_anchors_preset(Control.PRESET_CENTER)
	menu_panel.position = Vector2(-310, -310)
	menu_panel.size = Vector2(620, 620)
	menu_panel.custom_minimum_size = Vector2(620, 620)
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.055, 0.075, 0.067, 0.94)
	panel_style.border_color = Color(0.72, 0.69, 0.51, 0.46)
	panel_style.set_border_width_all(1)
	panel_style.set_corner_radius_all(3)
	panel_style.content_margin_left = 40
	panel_style.content_margin_right = 40
	panel_style.content_margin_top = 34
	panel_style.content_margin_bottom = 30
	menu_panel.add_theme_stylebox_override("panel", panel_style)
	menu_layer.add_child(menu_panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 13)
	menu_panel.add_child(column)
	var eyebrow := Label.new()
	eyebrow.text = "СЕВЕРНЫЙ КРАЙ   ·   КООПЕРАТИВ ДО 4 ИГРОКОВ"
	eyebrow.add_theme_font_size_override("font_size", 11)
	eyebrow.add_theme_color_override("font_color", Color("c7ba85"))
	eyebrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(eyebrow)
	var title := Label.new()
	title.text = "ПОСЛЕДНИЙ\nКОЛОКОЛ"
	title.add_theme_font_size_override("font_size", 42)
	title.add_theme_color_override("font_color", Color("eee7d2"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.custom_minimum_size.y = 112
	column.add_child(title)
	var sub := Label.new()
	sub.text = "Первая перспектива  ·  совместная игра"
	sub.add_theme_font_size_override("font_size", 14)
	sub.add_theme_color_override("font_color", Color("afb19d"))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(sub)
	var lore := Label.new()
	lore.text = (
		"Три деревни молчат под пепельным туманом.\n"
		+ "Найдите жителей и верните им здоровье —\n"
		+ "поодиночке или вместе с друзьями по сети."
	)
	lore.add_theme_font_size_override("font_size", 13)
	lore.add_theme_color_override("font_color", Color("c1c1ad"))
	lore.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lore.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lore.custom_minimum_size.y = 64
	column.add_child(lore)
	var rule := HSeparator.new()
	column.add_child(rule)
	var nick := Label.new()
	nick.text = "СОЗДАТЬ КОМНАТУ (ПОРТ 24560)"
	nick.add_theme_font_size_override("font_size", 10)
	nick.add_theme_color_override("font_color", Color("b6b599"))
	column.add_child(nick)
	var host_button := _make_button("СОЗДАТЬ ИГРУ  ·  HOST")
	host_button.pressed.connect(_on_host_pressed)
	column.add_child(host_button)
	var join_row := HBoxContainer.new()
	join_row.add_theme_constant_override("separation", 8)
	column.add_child(join_row)
	ip_entry = LineEdit.new()
	ip_entry.placeholder_text = "IP хоста · например 192.168.1.20"
	ip_entry.text = "127.0.0.1"
	ip_entry.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ip_entry.custom_minimum_size.y = 42
	ip_entry.add_theme_font_size_override("font_size", 12)
	join_row.add_child(ip_entry)
	var join_button := _make_button("ПОДКЛЮЧИТЬСЯ")
	join_button.custom_minimum_size.x = 176
	join_button.pressed.connect(_on_join_pressed)
	join_row.add_child(join_button)
	status_label = Label.new()
	status_label.text = "СОЗДАЙТЕ КОМНАТУ ИЛИ ВВЕДИТЕ IP ХОСТА"
	status_label.add_theme_font_size_override("font_size", 10)
	status_label.add_theme_color_override("font_color", Color("aaa991"))
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(status_label)
	var keys := Label.new()
	keys.text = "WASD · ходьба      SHIFT · бег      F / ЛКМ · исцелить"
	keys.add_theme_font_size_override("font_size", 10)
	keys.add_theme_color_override("font_color", Color("858c7e"))
	keys.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(keys)
	# HUD stays separate from the lobby and is shared by host and clients.
	hud_layer = CanvasLayer.new()
	hud_layer.layer = 5
	add_child(hud_layer)
	var hud_root := Control.new()
	hud_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_layer.add_child(hud_root)
	var top_panel := PanelContainer.new()
	top_panel.position = Vector2(24, 20)
	top_panel.custom_minimum_size = Vector2(475, 104)
	top_panel.size = Vector2(475, 104)
	hud_root.add_child(top_panel)
	var hud_style := StyleBoxFlat.new()
	hud_style.bg_color = Color(0.04, 0.06, 0.05, 0.82)
	hud_style.border_color = Color(0.7, 0.67, 0.49, 0.3)
	hud_style.set_border_width_all(1)
	hud_style.set_corner_radius_all(3)
	hud_style.content_margin_left = 16
	hud_style.content_margin_right = 16
	hud_style.content_margin_top = 9
	hud_style.content_margin_bottom = 9
	top_panel.add_theme_stylebox_override("panel", hud_style)
	var hud_v := VBoxContainer.new()
	hud_v.add_theme_constant_override("separation", 5)
	top_panel.add_child(hud_v)
	var top_line := HBoxContainer.new()
	hud_v.add_child(top_line)
	var game_name := Label.new()
	game_name.text = "ПОСЛЕДНИЙ КОЛОКОЛ"
	game_name.add_theme_font_size_override("font_size", 13)
	game_name.add_theme_color_override("font_color", Color("e5dfca"))
	top_line.add_child(game_name)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_line.add_child(spacer)
	player_count_label = Label.new()
	player_count_label.text = "ОТРЯД  0 / 4"
	player_count_label.add_theme_font_size_override("font_size", 10)
	player_count_label.add_theme_color_override("font_color", Color("c7ba85"))
	top_line.add_child(player_count_label)
	objective_label = Label.new()
	objective_label.text = "ОЧИЩЕНО ДЕРЕВЕНЬ: 0 / 3     ·     ИСЦЕЛЕНО ЖИТЕЛЕЙ: 0 / 9"
	objective_label.add_theme_font_size_override("font_size", 10)
	objective_label.add_theme_color_override("font_color", Color("c2c1ab"))
	hud_v.add_child(objective_label)
	network_hint = Label.new()
	network_hint.text = "СОЗДАЙТЕ КОМНАТУ ИЛИ ПОДКЛЮЧИТЕСЬ К ДРУГУ"
	network_hint.add_theme_font_size_override("font_size", 9)
	network_hint.add_theme_color_override("font_color", Color("a8ac98"))
	hud_v.add_child(network_hint)
	hud_cure = ProgressBar.new()
	hud_cure.min_value = 0
	hud_cure.max_value = 9
	hud_cure.value = 0
	hud_cure.show_percentage = false
	hud_cure.custom_minimum_size.y = 7
	hud_v.add_child(hud_cure)
	var bottom := PanelContainer.new()
	bottom.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	bottom.position = Vector2(-260, -66)
	bottom.custom_minimum_size = Vector2(520, 40)
	bottom.size = Vector2(520, 40)
	hud_root.add_child(bottom)
	var bottom_style := StyleBoxFlat.new()
	bottom_style.bg_color = Color(0.04, 0.06, 0.05, 0.74)
	bottom_style.set_corner_radius_all(4)
	bottom.add_theme_stylebox_override("panel", bottom_style)
	hud_action = Label.new()
	hud_action.text = "WASD · ДВИЖЕНИЕ     SHIFT · БЕГ     SPACE · ПРЫЖОК"
	hud_action.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud_action.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hud_action.add_theme_font_size_override("font_size", 11)
	hud_action.add_theme_color_override("font_color", Color("d5d0b8"))
	bottom.add_child(hud_action)
	var health_panel := PanelContainer.new()
	health_panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	health_panel.position = Vector2(-245, -78)
	health_panel.custom_minimum_size = Vector2(215, 45)
	health_panel.size = Vector2(215, 45)
	hud_root.add_child(health_panel)
	var health_style := StyleBoxFlat.new()
	health_style.bg_color = Color(0.04, 0.06, 0.05, 0.8)
	health_style.set_corner_radius_all(4)
	health_panel.add_theme_stylebox_override("panel", health_style)
	var health_box := VBoxContainer.new()
	health_box.add_theme_constant_override("separation", 1)
	health_panel.add_child(health_box)
	var health_label := Label.new()
	health_label.text = "ЖИЗНЕННАЯ СИЛА"
	health_label.add_theme_font_size_override("font_size", 9)
	health_label.add_theme_color_override("font_color", Color("c6b990"))
	health_box.add_child(health_label)
	hud_health = ProgressBar.new()
	hud_health.min_value = 0
	hud_health.max_value = 100
	hud_health.value = 100
	hud_health.show_percentage = false
	hud_health.custom_minimum_size.y = 11
	health_box.add_child(hud_health)
	crosshair = Label.new()
	crosshair.set_anchors_preset(Control.PRESET_CENTER)
	crosshair.position = Vector2(-8, -15)
	crosshair.custom_minimum_size = Vector2(16, 32)
	crosshair.size = Vector2(16, 32)
	crosshair.text = "·"
	crosshair.add_theme_font_size_override("font_size", 31)
	crosshair.add_theme_color_override("font_color", Color("f1dfad"))
	crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_root.add_child(crosshair)
	cure_prompt = Label.new()
	cure_prompt.set_anchors_preset(Control.PRESET_CENTER)
	cure_prompt.position = Vector2(-180, 30)
	cure_prompt.custom_minimum_size = Vector2(360, 25)
	cure_prompt.size = Vector2(360, 25)
	cure_prompt.text = ""
	cure_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cure_prompt.add_theme_font_size_override("font_size", 12)
	cure_prompt.add_theme_color_override("font_color", Color("d8d4b8"))
	cure_prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_root.add_child(cure_prompt)
	hud_layer.visible = false
	end_panel = PanelContainer.new()
	end_panel.set_anchors_preset(Control.PRESET_CENTER)
	end_panel.position = Vector2(-260, -130)
	end_panel.custom_minimum_size = Vector2(520, 260)
	end_panel.size = Vector2(520, 260)
	hud_root.add_child(end_panel)
	var end_style := StyleBoxFlat.new()
	end_style.bg_color = Color(0.05, 0.075, 0.06, 0.97)
	end_style.border_color = Color("c8bd8b")
	end_style.set_border_width_all(1)
	end_style.set_corner_radius_all(4)
	end_style.content_margin_left = 35
	end_style.content_margin_right = 35
	end_style.content_margin_top = 28
	end_style.content_margin_bottom = 28
	end_panel.add_theme_stylebox_override("panel", end_style)
	var end_box := VBoxContainer.new()
	end_box.add_theme_constant_override("separation", 13)
	end_panel.add_child(end_box)
	var end_title := Label.new()
	end_title.text = "РАССВЕТ ВЕРНУЛСЯ"
	end_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	end_title.add_theme_font_size_override("font_size", 26)
	end_title.add_theme_color_override("font_color", Color("e9dfbc"))
	end_box.add_child(end_title)
	var end_text := Label.new()
	end_text.text = "Все три деревни очищены.\nКолокол снова указывает дорогу домой."
	end_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	end_text.add_theme_font_size_override("font_size", 13)
	end_text.add_theme_color_override("font_color", Color("bdbba5"))
	end_box.add_child(end_text)
	var exit_button := _make_button("ВЕРНУТЬСЯ В МЕНЮ")
	exit_button.pressed.connect(_leave_game)
	end_box.add_child(exit_button)
	end_panel.visible = false


func _make_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 43
	button.add_theme_font_size_override("font_size", 12)
	button.add_theme_color_override("font_color", Color("1c211a"))
	button.add_theme_color_override("font_hover_color", Color("11160f"))
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color("c4bd91")
	normal.border_color = Color("e0d5a7")
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(2)
	normal.content_margin_left = 11
	normal.content_margin_right = 11
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color("e1d9ad")
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color("aaa27a")
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	return button


func _leave_game() -> void:
	_reset_network()
	menu_overlay.visible = true
	menu_panel.visible = true
	hud_layer.visible = false
	end_panel.visible = false
	menu_camera.current = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	status_label.text = "СОЗДАЙТЕ КОМНАТУ ИЛИ ВВЕДИТЕ IP ХОСТА"
	status_label.modulate = Color("aaa991")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and game_active and not game_over:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		show_message("НАЖМИТЕ ESC ЕЩЁ РАЗ, ЧТОБЫ ВЕРНУТЬ КУРСОР")
	elif (
		event is InputEventMouseButton
		and event.pressed
		and event.button_index == MOUSE_BUTTON_LEFT
		and game_active
		and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE
	):
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
