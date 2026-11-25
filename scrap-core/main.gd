extends Node3D
## Sun House: Scrap Core demo (The Server World).
## Everything is built from primitive shapes in code. Placeholder art only.

const GEN_COST := 20
const WALL_COST := 10
const FUEL_COST := 5
const FUEL_ADD := 60.0
const FUEL_MAX := 180.0
const SCAV_AMOUNT := 5
const PILE_CHARGES := 4
const PILE_RESPAWN := 25.0
const GEN_RATE := 1.0
const WALL_DRAIN := 0.25
const IDLE_DRAIN := 0.05
const WORLD_RADIUS := 56.0
const WALK_SPEED := 6.0
const SPRINT_SPEED := 10.0
const GRAVITY := 22.0
const JUMP_VEL := 8.0

var rng := RandomNumberGenerator.new()
var scrap := 0
var power := 0.0
var power_cap := 25.0
var power_rate := 0.0
var started := false
var time_acc := 0.0

var player: CharacterBody3D
var player_vis: Node3D
var arm_l: Node3D
var arm_r: Node3D
var leg_l: Node3D
var leg_r: Node3D
var walk_t := 0.0
var punch_t := 0.0

var cam_yaw: Node3D
var cam_pitch: Node3D
var spring: SpringArm3D
var camera: Camera3D
var yaw := 0.0
var pitch := -0.38
var zoom := 7.5

var blockers: Array = []   # {pos: Vector2, r: float}
var piles: Array = []
var structures: Array = []
var build_mode := ""
var build_rot := 0.0
var ghost: Node3D
var ghost_mat: StandardMaterial3D
var scav_cd := 0.0
var core_mat: StandardMaterial3D

var touches := {}
var joy_id := -1
var joy_center := Vector2.ZERO
var joy_vec := Vector2.ZERO
var cam_touch_id := -1
var mouse_dragging := false
var drag_dist := 0.0

var ui: CanvasLayer
var lbl_scrap: Label
var lbl_power: Label
var lbl_goals: Label
var lbl_prompt: Label
var lbl_hint: Label
var title_overlay: Control
var joy_ctrl: Control
var ui_buttons: Array = []
var flash_msg := ""
var flash_t := 0.0
var total_scavenged := 0
var goal_gen := false
var goal_fuel := false
var goal_wall := false

# ---------------------------------------------------------------- setup

func _ready() -> void:
	rng.seed = 1111
	_setup_input()
	_build_environment()
	_build_ground()
	_build_dome()
	_build_core_landmark()
	_build_perimeter()
	_build_rubble()
	_build_piles()
	blockers = blockers.filter(func(b): return not b.has("spawn"))
	blockers.append({"pos": Vector2.ZERO, "r": 1.2})
	_build_player()
	_build_camera()
	_build_ui()
	if "--autotest" in OS.get_cmdline_user_args():
		_autotest.call_deferred()

func _add_keys(action: String, keys: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(action, ev)

func _setup_input() -> void:
	_add_keys("move_forward", [KEY_W, KEY_UP])
	_add_keys("move_back", [KEY_S, KEY_DOWN])
	_add_keys("move_left", [KEY_A, KEY_LEFT])
	_add_keys("move_right", [KEY_D, KEY_RIGHT])
	_add_keys("jump", [KEY_SPACE])
	_add_keys("sprint", [KEY_SHIFT])
	_add_keys("interact", [KEY_E])
	_add_keys("build_gen", [KEY_1])
	_add_keys("build_wall", [KEY_2])
	_add_keys("rotate", [KEY_R])
	_add_keys("place", [KEY_F, KEY_ENTER])
	_add_keys("cancel", [KEY_X, KEY_ESCAPE])
	_add_keys("cam_left", [KEY_Q])
	_add_keys("cam_right", [KEY_C])

# ---------------------------------------------------------------- helpers

func mat(c: Color, metal := 0.2, rough := 0.7, emit := Color.BLACK, emit_e := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = metal
	m.roughness = rough
	if emit_e > 0.0:
		m.emission_enabled = true
		m.emission = emit
		m.emission_energy_multiplier = emit_e
	return m

func box(parent: Node, size: Vector3, pos: Vector3, m: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = m
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	return mi

func cyl(parent: Node, top_r: float, bot_r: float, h: float, pos: Vector3, m: Material, rot := Vector3.ZERO, segs := 16) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = top_r
	cm.bottom_radius = bot_r
	cm.height = h
	cm.radial_segments = segs
	cm.rings = 1
	mi.mesh = cm
	mi.material_override = m
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	return mi

func add_box_col(body: Node, size: Vector3, pos: Vector3, rot := Vector3.ZERO) -> CollisionShape3D:
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	cs.position = pos
	cs.rotation = rot
	body.add_child(cs)
	return cs

func free_spot(rmin: float, rmax: float, clearance: float) -> Vector2:
	for i in 60:
		var a := rng.randf() * TAU
		var r := rng.randf_range(rmin, rmax)
		var p := Vector2(cos(a), sin(a)) * r
		var ok := true
		for b in blockers:
			if p.distance_to(b.pos) < b.r + clearance:
				ok = false
				break
		if ok:
			return p
	return Vector2.INF

# ---------------------------------------------------------------- world

func _build_environment() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.03, 0.02, 0.06)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.5, 0.42, 0.65)
	env.ambient_light_energy = 0.75
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = Color(0.22, 0.15, 0.28)
	env.fog_density = 0.006
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.86, 0.62)
	sun.light_energy = 1.15
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 55.0
	# light comes from the crack in the firmament (toward +Z, high up)
	sun.rotation_degrees = Vector3(-40, 8, 0)
	add_child(sun)

func _build_ground() -> void:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(240, 240)
	mi.mesh = pm
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
varying vec3 wpos;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 g = abs(fract(wpos.xz / 4.0) - 0.5);
	float line = smoothstep(0.47, 0.5, max(g.x, g.y));
	float n = hash(floor(wpos.xz * 1.3));
	float n2 = hash(floor(wpos.xz * 0.25) + 7.0);
	vec3 rust = vec3(0.20, 0.13, 0.09);
	vec3 steel = vec3(0.13, 0.13, 0.15);
	vec3 c = mix(rust, steel, n2) * (0.75 + 0.5 * n);
	float d = length(wpos.xz);
	ALBEDO = c;
	ROUGHNESS = 0.85;
	METALLIC = 0.3;
	EMISSION = vec3(0.1, 0.65, 0.75) * line * 0.35 * (1.0 - smoothstep(10.0, 60.0, d));
}
"""
	var sm := ShaderMaterial.new()
	sm.shader = sh
	mi.material_override = sm
	add_child(mi)
	var sb := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	cs.shape = WorldBoundaryShape3D.new()
	sb.add_child(cs)
	add_child(sb)
	# spawn pad
	var pad := cyl(self, 2.2, 2.2, 0.06, Vector3(0, 0.03, 0), mat(Color(0.1, 0.1, 0.12), 0.8, 0.3, Color(1.0, 0.55, 0.2), 0.6), Vector3.ZERO, 32)
	pad.name = "SpawnPad"

func _build_dome() -> void:
	var mi := MeshInstance3D.new()
	var sp := SphereMesh.new()
	sp.radius = 150.0
	sp.height = 300.0
	sp.radial_segments = 64
	sp.rings = 32
	mi.mesh = sp
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode unshaded, cull_front, shadows_disabled;
varying vec3 ldir;
void vertex() { ldir = VERTEX; }
void fragment() {
	vec3 d = normalize(ldir);
	float elev = asin(clamp(d.y, -1.0, 1.0));
	float phi = atan(d.x, d.z);
	float h = clamp(d.y, 0.0, 1.0);
	vec3 horizon = vec3(0.26, 0.11, 0.30);
	vec3 zenith = vec3(0.02, 0.03, 0.11);
	vec3 col = mix(horizon, zenith, pow(h, 0.55));
	// firmament panels
	vec2 uv = vec2(phi * 12.0 / 3.14159, elev * 16.0 / 3.14159);
	vec2 g = abs(fract(uv) - 0.5);
	float line = smoothstep(0.46, 0.5, max(g.x, g.y));
	col += vec3(0.15, 0.4, 0.55) * line * 0.45 * (0.25 + h);
	// 11's crack: a jagged seam of light leaking through
	float cphi = atan(-d.x, -d.z); // crack hangs over the machine core (north, -Z)
	float z1 = abs(fract(cphi * 2.3 + 0.2) - 0.5) * 4.0 - 1.0;
	float z2 = abs(fract(cphi * 7.1 + 0.6) - 0.5) * 4.0 - 1.0;
	float z3 = abs(fract(cphi * 23.0) - 0.5) * 4.0 - 1.0;
	float c = 0.5 + 0.06 * z1 + 0.025 * z2 + 0.008 * z3;
	float dist = abs(elev - c);
	float mask = smoothstep(-1.1, -0.7, cphi) * (1.0 - smoothstep(0.6, 1.0, cphi));
	float pulse = 0.8 + 0.15 * sin(TIME * 2.2) + 0.08 * sin(TIME * 7.3);
	float core = (1.0 - smoothstep(0.0, 0.007, dist)) * mask;
	float glow = exp(-dist * 35.0) * mask * 0.7;
	col += vec3(1.0, 0.88, 0.6) * (core * 3.0 + glow) * pulse;
	ALBEDO = col;
}
"""
	var sm := ShaderMaterial.new()
	sm.shader = sh
	mi.material_override = sm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	# beam of light falling from the crack onto the far scrap field
	var a := Vector3(0, 70, -128)
	var b := Vector3(-6, 0, -72)
	var beam := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 7.0
	cm.bottom_radius = 3.0
	cm.height = a.distance_to(b)
	cm.cap_top = false
	cm.cap_bottom = false
	beam.mesh = cm
	var bm := StandardMaterial3D.new()
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	bm.cull_mode = BaseMaterial3D.CULL_DISABLED
	bm.albedo_color = Color(1.0, 0.85, 0.55, 0.10)
	beam.material_override = bm
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var up := (a - b).normalized()
	var x := up.cross(Vector3.FORWARD).normalized()
	var z := x.cross(up)
	beam.transform = Transform3D(Basis(x, up, z), (a + b) * 0.5)
	add_child(beam)

func _build_core_landmark() -> void:
	# The broken machine core: the heart of the scrap core, north of spawn.
	var sb := StaticBody3D.new()
	sb.position = Vector3(0, 0, -16)
	add_child(sb)
	var metal := mat(Color(0.18, 0.18, 0.2), 0.9, 0.35)
	core_mat = mat(Color(1.0, 0.45, 0.12), 0.0, 0.4, Color(1.0, 0.45, 0.12), 2.0)
	cyl(sb, 3.2, 3.8, 9.0, Vector3(0, 4.5, 0), metal, Vector3.ZERO, 24)
	cyl(sb, 3.35, 3.35, 0.4, Vector3(0, 2.5, 0), core_mat, Vector3.ZERO, 24)
	cyl(sb, 3.25, 3.25, 0.25, Vector3(0, 6.2, 0), core_mat, Vector3.ZERO, 24)
	cyl(sb, 2.4, 3.2, 2.5, Vector3(0.6, 10.0, 0.3), metal, Vector3(0.25, 0, 0.18), 24)
	for i in 6:
		var a := i * TAU / 6.0
		box(sb, Vector3(0.6, 4.0, 0.6), Vector3(cos(a) * 4.4, 2.0, sin(a) * 4.4), metal, Vector3(0, -a, 0.25 * sin(a * 3.0)))
	var lbl := Label3D.new()
	lbl.text = "MACHINE CORE"
	lbl.font_size = 96
	lbl.pixel_size = 0.01
	lbl.modulate = Color(1, 0.7, 0.4)
	lbl.outline_size = 12
	lbl.position = Vector3(0, 12.5, 0)
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sb.add_child(lbl)
	var cs := CollisionShape3D.new()
	var cshape := CylinderShape3D.new()
	cshape.radius = 3.8
	cshape.height = 11.0
	cs.shape = cshape
	cs.position.y = 5.5
	sb.add_child(cs)
	blockers.append({"pos": Vector2(0, -16), "r": 5.0})
	blockers.append({"pos": Vector2.ZERO, "r": 4.0, "spawn": true})  # keep spawn clear while generating

func _build_perimeter() -> void:
	# Walls of stacked dead hardware ring the scrap core.
	var cols := [Color(0.16, 0.16, 0.18), Color(0.24, 0.17, 0.12), Color(0.12, 0.13, 0.16), Color(0.3, 0.28, 0.25)]
	var n := 56
	for i in n:
		var a := i * TAU / n + rng.randf_range(-0.03, 0.03)
		var r := 61.0 + rng.randf_range(-1.5, 2.5)
		var sb := StaticBody3D.new()
		sb.position = Vector3(cos(a) * r, 0, sin(a) * r)
		sb.rotation.y = -a + rng.randf_range(-0.3, 0.3)
		add_child(sb)
		var y := 0.0
		var layers := rng.randi_range(2, 5)
		for l in layers:
			var s := Vector3(rng.randf_range(4, 7), rng.randf_range(2, 4.5), rng.randf_range(3, 5))
			box(sb, s, Vector3(rng.randf_range(-0.6, 0.6), y + s.y / 2.0, rng.randf_range(-0.6, 0.6)),
				mat(cols[rng.randi() % cols.size()], 0.7, 0.55), Vector3(0, rng.randf_range(-0.3, 0.3), rng.randf_range(-0.06, 0.06)))
			if rng.randf() < 0.5:
				var led := Color(0.2, 1.0, 0.6) if rng.randf() < 0.6 else Color(1.0, 0.25, 0.2)
				box(sb, Vector3(s.x * 0.7, 0.08, 0.05), Vector3(0, y + s.y * 0.6, -s.z / 2.0 - 0.6), mat(led, 0, 0.5, led, 2.0))
			y += s.y
		add_box_col(sb, Vector3(6.5, y, 5), Vector3(0, y / 2.0, 0))

func _build_rubble() -> void:
	var dark := mat(Color(0.12, 0.12, 0.14), 0.85, 0.4)
	var rack := mat(Color(0.2, 0.21, 0.24), 0.8, 0.45)
	var rust := mat(Color(0.33, 0.18, 0.1), 0.5, 0.8)
	# server racks
	for i in 26:
		var p := free_spot(10, 52, 3.5)
		if p == Vector2.INF:
			continue
		var sb := StaticBody3D.new()
		sb.position = Vector3(p.x, 0, p.y)
		sb.rotation.y = rng.randf() * TAU
		add_child(sb)
		var w := rng.randf_range(1.2, 2.4)
		var d := rng.randf_range(1.0, 1.8)
		var h := rng.randf_range(2.0, 5.5)
		var tilt := rng.randf_range(-0.12, 0.12)
		box(sb, Vector3(w, h, d), Vector3(0, h / 2.0, 0), rack if rng.randf() < 0.6 else rust, Vector3(0, 0, tilt))
		var rows := int(h / 0.5)
		for k in rows:
			if rng.randf() < 0.55:
				var led: Color = [Color(0.2, 1.0, 0.7), Color(0.3, 0.6, 1.0), Color(1.0, 0.3, 0.2), Color(1.0, 0.8, 0.2)][rng.randi() % 4]
				box(sb, Vector3(rng.randf_range(0.15, w * 0.6), 0.06, 0.04), Vector3(rng.randf_range(-0.2, 0.2), 0.35 + k * 0.5, d / 2.0 + 0.02), mat(led, 0, 0.5, led, 2.5), Vector3(0, 0, tilt))
		add_box_col(sb, Vector3(w, h, d), Vector3(0, h / 2.0, 0), Vector3(0, 0, tilt))
		blockers.append({"pos": p, "r": max(w, d) * 0.75})
	# fallen slabs / dead monitors
	for i in 9:
		var p := free_spot(12, 50, 5.0)
		if p == Vector2.INF:
			continue
		var sb := StaticBody3D.new()
		sb.position = Vector3(p.x, 0, p.y)
		sb.rotation.y = rng.randf() * TAU
		add_child(sb)
		var s := Vector3(rng.randf_range(4, 7), 0.4, rng.randf_range(3, 4.5))
		var rot := Vector3(rng.randf_range(0.25, 0.6), 0, rng.randf_range(-0.1, 0.1))
		box(sb, s, Vector3(0, 1.0, 0), dark, rot)
		box(sb, Vector3(s.x * 0.85, 0.05, s.z * 0.8), Vector3(0, 1.0, 0), mat(Color(0.05, 0.25, 0.3), 0, 0.2, Color(0.1, 0.5, 0.6), 0.5), rot + Vector3(0, 0, 0)).translate_object_local(Vector3(0, 0.21, 0))
		add_box_col(sb, s, Vector3(0, 1.0, 0), rot)
		blockers.append({"pos": p, "r": 3.2})
	# cable coils (decor only)
	for i in 18:
		var p := free_spot(6, 54, 1.0)
		if p == Vector2.INF:
			continue
		var mi := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = rng.randf_range(0.4, 0.9)
		tm.outer_radius = tm.inner_radius + 0.18
		mi.mesh = tm
		mi.material_override = mat([Color(0.1, 0.1, 0.1), Color(0.6, 0.15, 0.1), Color(0.1, 0.3, 0.6)][rng.randi() % 3], 0.1, 0.6)
		mi.position = Vector3(p.x, 0.1, p.y)
		mi.rotation = Vector3(rng.randf_range(-0.2, 0.2), rng.randf() * TAU, rng.randf_range(-0.2, 0.2))
		add_child(mi)
	# antenna masts
	for i in 7:
		var p := free_spot(14, 52, 2.0)
		if p == Vector2.INF:
			continue
		var sb := StaticBody3D.new()
		sb.position = Vector3(p.x, 0, p.y)
		add_child(sb)
		var h := rng.randf_range(8, 14)
		cyl(sb, 0.08, 0.25, h, Vector3(0, h / 2.0, 0), dark, Vector3(rng.randf_range(-0.08, 0.08), 0, rng.randf_range(-0.08, 0.08)), 8)
		for k in 3:
			box(sb, Vector3(1.4 - k * 0.35, 0.06, 0.06), Vector3(0, h * (0.55 + k * 0.13), 0), dark)
		var blink := mat(Color(1, 0.2, 0.15), 0, 0.5, Color(1, 0.2, 0.15), 3.0)
		cyl(sb, 0.15, 0.15, 0.3, Vector3(0, h + 0.1, 0), blink, Vector3.ZERO, 8)
		var cs := CollisionShape3D.new()
		var c := CylinderShape3D.new()
		c.radius = 0.3
		c.height = h
		cs.shape = c
		cs.position.y = h / 2.0
		sb.add_child(cs)
		blockers.append({"pos": p, "r": 0.8})

func _build_piles() -> void:
	var cols := [Color(0.45, 0.3, 0.2), Color(0.35, 0.36, 0.38), Color(0.55, 0.35, 0.15), Color(0.25, 0.26, 0.3), Color(0.6, 0.45, 0.2)]
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.albedo_color = Color(1.0, 0.5, 0.1)
	var beacon_mat := StandardMaterial3D.new()
	beacon_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	beacon_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	beacon_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	beacon_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	beacon_mat.albedo_color = Color(1.0, 0.5, 0.15, 0.22)
	var made := 0
	for i in 40:
		if made >= 16:
			break
		var p := free_spot(5.5 if made < 3 else 8.0, 48, 2.4)
		if p == Vector2.INF:
			continue
		var root := Node3D.new()
		root.position = Vector3(p.x, 0, p.y)
		add_child(root)
		var mound := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 1.3
		sm.height = 1.1
		mound.mesh = sm
		mound.material_override = mat(Color(0.22, 0.16, 0.12), 0.4, 0.9)
		mound.position.y = 0.05
		root.add_child(mound)
		for k in 9:
			var s := Vector3(rng.randf_range(0.2, 0.7), rng.randf_range(0.1, 0.5), rng.randf_range(0.2, 0.7))
			var a := rng.randf() * TAU
			var r := rng.randf_range(0.0, 1.0)
			if rng.randf() < 0.3:
				cyl(root, s.x * 0.4, s.x * 0.4, s.z, Vector3(cos(a) * r, 0.45 + rng.randf() * 0.3, sin(a) * r), mat(cols[rng.randi() % cols.size()], 0.8, 0.4), Vector3(PI / 2, rng.randf() * TAU, 0), 10)
			else:
				box(root, s, Vector3(cos(a) * r, 0.4 + rng.randf() * 0.35, sin(a) * r), mat(cols[rng.randi() % cols.size()], 0.7, 0.5), Vector3(rng.randf_range(-0.6, 0.6), rng.randf() * TAU, rng.randf_range(-0.6, 0.6)))
		var g := box(root, Vector3(0.35, 0.35, 0.35), Vector3(0, 0.95, 0), glow, Vector3(0.5, 0.3, 0.7))
		g.name = "Glow"
		var beacon := MeshInstance3D.new()
		var bcm := CylinderMesh.new()
		bcm.top_radius = 0.05
		bcm.bottom_radius = 0.35
		bcm.height = 5.0
		bcm.cap_top = false
		bcm.cap_bottom = false
		beacon.mesh = bcm
		beacon.material_override = beacon_mat
		beacon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		beacon.position.y = 3.2
		root.add_child(beacon)
		var sb := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var c := CylinderShape3D.new()
		c.radius = 0.9
		c.height = 1.0
		cs.shape = c
		cs.position.y = 0.5
		sb.add_child(cs)
		root.add_child(sb)
		piles.append({"node": root, "charges": PILE_CHARGES, "timer": 0.0, "col": cs, "glow": g})
		blockers.append({"pos": p, "r": 1.4})
		made += 1

# ---------------------------------------------------------------- player: Agent 12 (Kong DNA, 0 traits)

func _build_player() -> void:
	player = CharacterBody3D.new()
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.45
	cap.height = 2.0
	cs.shape = cap
	cs.position.y = 1.0
	player.add_child(cs)
	player.position = Vector3(0, 0.05, 0)
	add_child(player)
	player_vis = Node3D.new()
	player.add_child(player_vis)
	# Dark, slightly metallic "fur" and tan face/chest, like Agent 12's 0-trait Kong body.
	var fur := mat(Color(0.07, 0.07, 0.08), 0.55, 0.45)
	var skin := mat(Color(0.85, 0.6, 0.45), 0.15, 0.6)
	var white := mat(Color(0.98, 0.98, 0.98), 0.0, 0.5)
	var black := mat(Color(0.02, 0.02, 0.02), 0.0, 0.5)
	leg_l = Node3D.new()
	leg_l.position = Vector3(-0.22, 0.7, 0)
	player_vis.add_child(leg_l)
	box(leg_l, Vector3(0.28, 0.62, 0.3), Vector3(0, -0.31, 0), fur)
	box(leg_l, Vector3(0.3, 0.09, 0.42), Vector3(0, -0.655, 0.06), skin)
	leg_r = Node3D.new()
	leg_r.position = Vector3(0.22, 0.7, 0)
	player_vis.add_child(leg_r)
	box(leg_r, Vector3(0.28, 0.62, 0.3), Vector3(0, -0.31, 0), fur)
	box(leg_r, Vector3(0.3, 0.09, 0.42), Vector3(0, -0.655, 0.06), skin)
	box(player_vis, Vector3(0.92, 0.86, 0.56), Vector3(0, 1.12, 0), fur)
	box(player_vis, Vector3(0.6, 0.55, 0.06), Vector3(0, 1.17, 0.29), skin)
	box(player_vis, Vector3(0.7, 0.66, 0.62), Vector3(0, 1.9, 0), fur)
	box(player_vis, Vector3(0.52, 0.44, 0.06), Vector3(0, 1.85, 0.32), skin)
	box(player_vis, Vector3(0.14, 0.14, 0.03), Vector3(-0.13, 1.93, 0.36), white)
	box(player_vis, Vector3(0.14, 0.14, 0.03), Vector3(0.13, 1.93, 0.36), white)
	box(player_vis, Vector3(0.07, 0.07, 0.03), Vector3(-0.1, 1.9, 0.375), black)
	box(player_vis, Vector3(0.07, 0.07, 0.03), Vector3(0.16, 1.9, 0.375), black)
	box(player_vis, Vector3(0.12, 0.22, 0.18), Vector3(-0.39, 1.9, 0), fur)
	box(player_vis, Vector3(0.12, 0.22, 0.18), Vector3(0.39, 1.9, 0), fur)
	box(player_vis, Vector3(0.05, 0.12, 0.1), Vector3(-0.46, 1.9, 0), skin)
	box(player_vis, Vector3(0.05, 0.12, 0.1), Vector3(0.46, 1.9, 0), skin)
	arm_l = Node3D.new()
	arm_l.position = Vector3(-0.6, 1.48, 0)
	player_vis.add_child(arm_l)
	box(arm_l, Vector3(0.25, 0.96, 0.27), Vector3(0, -0.47, 0), fur)
	box(arm_l, Vector3(0.23, 0.18, 0.23), Vector3(0, -1.03, 0), skin)
	arm_r = Node3D.new()
	arm_r.position = Vector3(0.6, 1.48, 0)
	player_vis.add_child(arm_r)
	box(arm_r, Vector3(0.25, 0.96, 0.27), Vector3(0, -0.47, 0), fur)
	box(arm_r, Vector3(0.23, 0.18, 0.23), Vector3(0, -1.03, 0), skin)
	var tag := Label3D.new()
	tag.text = "AGENT 12"
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.position.y = 2.6
	tag.font_size = 48
	tag.pixel_size = 0.005
	tag.modulate = Color(1, 0.88, 0.6)
	tag.outline_size = 10
	player.add_child(tag)
	player_vis.rotation.y = PI  # face north toward the machine core

func _build_camera() -> void:
	cam_yaw = Node3D.new()
	add_child(cam_yaw)
	cam_pitch = Node3D.new()
	cam_yaw.add_child(cam_pitch)
	spring = SpringArm3D.new()
	spring.spring_length = zoom
	spring.margin = 0.3
	var sph := SphereShape3D.new()
	sph.radius = 0.3
	spring.shape = sph
	spring.add_excluded_object(player.get_rid())
	cam_pitch.add_child(spring)
	camera = Camera3D.new()
	camera.far = 500.0
	camera.fov = 65.0
	spring.add_child(camera)
	cam_yaw.position = player.position + Vector3(0, 1.7, 0)
	camera.make_current()

# ---------------------------------------------------------------- structures

func make_structure(kind: String, is_ghost: bool) -> Node3D:
	var root: Node3D = Node3D.new() if is_ghost else StaticBody3D.new()
	var info := {"type": kind, "node": root}
	if kind == "gen":
		var steel := mat(Color(0.26, 0.27, 0.3), 0.85, 0.35)
		var accent := mat(Color(0.9, 0.5, 0.15), 0.6, 0.4)
		box(root, Vector3(1.8, 0.35, 1.8), Vector3(0, 0.175, 0), steel)
		for sx in [-0.75, 0.75]:
			for sz in [-0.75, 0.75]:
				box(root, Vector3(0.18, 1.9, 0.18), Vector3(sx, 1.1, sz), steel)
		var cm := mat(Color(0.2, 0.9, 1.0), 0.0, 0.3, Color(0.2, 0.9, 1.0), 2.5)
		var core := cyl(root, 0.42, 0.52, 1.5, Vector3(0, 1.1, 0), cm, Vector3.ZERO, 16)
		var ring := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.62
		tm.outer_radius = 0.8
		ring.mesh = tm
		ring.material_override = accent
		ring.position.y = 1.2
		root.add_child(ring)
		box(root, Vector3(1.8, 0.2, 1.8), Vector3(0, 2.1, 0), steel)
		info["core"] = core
		info["core_mat"] = cm
		info["ring"] = ring
		info["fuel"] = FUEL_ADD
		if not is_ghost:
			add_box_col(root, Vector3(1.8, 2.2, 1.8), Vector3(0, 1.1, 0))
			var l := Label3D.new()
			l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			l.font_size = 40
			l.pixel_size = 0.005
			l.outline_size = 8
			l.position.y = 2.7
			root.add_child(l)
			info["label"] = l
	else:
		var steel := mat(Color(0.22, 0.23, 0.26), 0.85, 0.35)
		var tipm := mat(Color(0.3, 0.9, 1.0), 0.0, 0.4, Color(0.3, 0.9, 1.0), 2.0)
		for sx in [-1.6, 1.6]:
			box(root, Vector3(0.35, 2.2, 0.35), Vector3(sx, 1.1, 0), steel)
			box(root, Vector3(0.45, 0.15, 0.45), Vector3(sx, 2.25, 0), tipm)
		var fm := StandardMaterial3D.new()
		fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		fm.cull_mode = BaseMaterial3D.CULL_DISABLED
		fm.albedo_color = Color(0.3, 0.85, 1.0, 0.4)
		var field := box(root, Vector3(3.0, 1.9, 0.08), Vector3(0, 1.15, 0), fm)
		field.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		info["field"] = field
		info["field_mat"] = fm
		if not is_ghost:
			add_box_col(root, Vector3(0.35, 2.2, 0.35), Vector3(-1.6, 1.1, 0))
			add_box_col(root, Vector3(0.35, 2.2, 0.35), Vector3(1.6, 1.1, 0))
			info["field_col"] = add_box_col(root, Vector3(3.0, 2.0, 0.3), Vector3(0, 1.0, 0))
	if is_ghost:
		_ghostify(root)
	root.set_meta("info", info)
	return root

func _ghostify(n: Node) -> void:
	for c in n.get_children():
		if c is MeshInstance3D:
			c.material_override = ghost_mat
			c.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_ghostify(c)

func set_build(mode: String) -> void:
	if not started:
		return
	if mode == build_mode:
		mode = ""
	build_mode = mode
	if ghost:
		ghost.queue_free()
		ghost = null
	if mode != "":
		if ghost_mat == null:
			ghost_mat = StandardMaterial3D.new()
			ghost_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			ghost_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			ghost_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		ghost = make_structure(mode, true)
		add_child(ghost)
		ghost.global_transform = ghost_transform()

func cam_forward() -> Vector3:
	var f := -cam_yaw.global_transform.basis.z
	f.y = 0
	return f.normalized()

func ghost_transform() -> Transform3D:
	var p := player.global_position + cam_forward() * 3.5
	p.x = round(p.x)
	p.z = round(p.z)
	p.y = 0
	var r := snappedf(yaw, PI / 2.0) + build_rot
	return Transform3D(Basis(Vector3.UP, r), p)

func placement_problem(pos: Vector3, cost: int) -> String:
	if scrap < cost:
		return "Need %d Scrap (you have %d)" % [cost, scrap]
	var p2 := Vector2(pos.x, pos.z)
	if p2.length() > WORLD_RADIUS - 2.0:
		return "Too close to the junk wall"
	for b in blockers:
		if p2.distance_to(b.pos) < b.r + 1.3:
			return "Blocked: find open ground"
	for s in structures:
		var sp: Vector3 = s.node.global_position
		if p2.distance_to(Vector2(sp.x, sp.z)) < 2.2:
			return "Too close to another build"
	return ""

func try_place() -> void:
	if build_mode == "" or not started:
		return
	var cost := GEN_COST if build_mode == "gen" else WALL_COST
	var xf := ghost_transform()
	var why := placement_problem(xf.origin, cost)
	if why != "":
		flash(why)
		return
	scrap -= cost
	var n := make_structure(build_mode, false)
	add_child(n)
	n.global_transform = xf
	var info: Dictionary = n.get_meta("info")
	structures.append(info)
	if build_mode == "gen":
		power_cap += 50.0
		goal_gen = true
		popup(xf.origin + Vector3(0, 2.8, 0), "Generator online", Color(0.4, 0.95, 1.0))
	else:
		goal_wall = true
		popup(xf.origin + Vector3(0, 2.8, 0), "Shield raised", Color(0.4, 0.95, 1.0))
	set_build("")

# ---------------------------------------------------------------- scavenging & fuel

func nearest_pile():
	var best = null
	var bd := 3.0
	for p in piles:
		if p.charges <= 0:
			continue
		var pos: Vector3 = p.node.position
		var d := Vector2(pos.x - player.position.x, pos.z - player.position.z).length()
		if d < bd:
			bd = d
			best = p
	return best

func nearest_gen():
	var best = null
	var bd := 3.2
	for s in structures:
		if s.type != "gen":
			continue
		var pos: Vector3 = s.node.global_position
		var d := Vector2(pos.x - player.position.x, pos.z - player.position.z).length()
		if d < bd:
			bd = d
			best = s
	return best

func interact() -> void:
	if not started or scav_cd > 0.0:
		return
	var p = nearest_pile()
	if p != null:
		scav_cd = 0.35
		punch_t = 0.25
		p.charges -= 1
		scrap += SCAV_AMOUNT
		total_scavenged += SCAV_AMOUNT
		var node: Node3D = p.node
		popup(node.position + Vector3(0, 1.8, 0), "+%d Scrap" % SCAV_AMOUNT, Color(1.0, 0.72, 0.35))
		var target_s := 0.55 + 0.45 * float(p.charges) / float(PILE_CHARGES)
		var tw := create_tween()
		tw.tween_property(node, "scale", Vector3(1.15, 0.8, 1.15) * target_s, 0.06)
		tw.tween_property(node, "scale", Vector3.ONE * target_s, 0.12)
		if p.charges <= 0:
			p.timer = PILE_RESPAWN
			p.col.set_deferred("disabled", true)
			tw.tween_property(node, "scale", Vector3(0.05, 0.05, 0.05), 0.3)
			tw.tween_callback(node.hide)
			flash("Pile picked clean. It regrows in %ds." % int(PILE_RESPAWN))
		return
	var g = nearest_gen()
	if g != null:
		if g.fuel >= FUEL_MAX - 1.0:
			flash("Generator tank is full")
			return
		if scrap < FUEL_COST:
			flash("Need %d Scrap to fuel the generator" % FUEL_COST)
			return
		scav_cd = 0.35
		scrap -= FUEL_COST
		g.fuel = min(FUEL_MAX, g.fuel + FUEL_ADD)
		goal_fuel = true
		popup(g.node.global_position + Vector3(0, 2.4, 0), "+%ds fuel" % int(FUEL_ADD), Color(0.4, 0.95, 1.0))
		return
	flash("Nothing in reach. Look for glowing scrap piles.")

func popup(pos: Vector3, text: String, col: Color) -> void:
	var l := Label3D.new()
	l.text = text
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.font_size = 64
	l.pixel_size = 0.005
	l.modulate = col
	l.outline_size = 12
	l.no_depth_test = true
	l.position = pos
	add_child(l)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(l, "position", pos + Vector3(0, 1.3, 0), 1.1)
	tw.tween_property(l, "modulate:a", 0.0, 1.1)
	tw.chain().tween_callback(l.queue_free)

func flash(msg: String) -> void:
	flash_msg = msg
	flash_t = 2.2

# ---------------------------------------------------------------- loop

func _physics_process(delta: float) -> void:
	var iv := Vector2.ZERO
	if started:
		iv = Input.get_vector("move_left", "move_right", "move_back", "move_forward")
		if joy_vec.length() > 0.12:
			iv = Vector2(joy_vec.x, -joy_vec.y)
	var fwd := cam_forward()
	var right := cam_yaw.global_transform.basis.x
	right.y = 0
	right = right.normalized()
	var dir := right * iv.x + fwd * iv.y
	if dir.length() > 1.0:
		dir = dir.normalized()
	var spd := SPRINT_SPEED if Input.is_action_pressed("sprint") else WALK_SPEED
	player.velocity.x = dir.x * spd
	player.velocity.z = dir.z * spd
	if not player.is_on_floor():
		player.velocity.y -= GRAVITY * delta
	elif started and Input.is_action_just_pressed("jump"):
		player.velocity.y = JUMP_VEL
	player.move_and_slide()
	var flat := Vector2(player.position.x, player.position.z)
	if flat.length() > WORLD_RADIUS:
		flat = flat.normalized() * WORLD_RADIUS
		player.position.x = flat.x
		player.position.z = flat.y
	if player.position.y < -10.0:
		player.position = Vector3(0, 1, 0)
	if dir.length() > 0.05:
		player_vis.rotation.y = lerp_angle(player_vis.rotation.y, atan2(dir.x, dir.z), clamp(12.0 * delta, 0.0, 1.0))
		walk_t += delta * spd * 1.5
		var s := sin(walk_t) * 0.7
		arm_l.rotation.x = s
		arm_r.rotation.x = -s
		leg_l.rotation.x = -s
		leg_r.rotation.x = s
	else:
		var k := clampf(10.0 * delta, 0.0, 1.0)
		arm_l.rotation.x = lerp(arm_l.rotation.x, 0.0, k)
		arm_r.rotation.x = lerp(arm_r.rotation.x, 0.0, k)
		leg_l.rotation.x = lerp(leg_l.rotation.x, 0.0, k)
		leg_r.rotation.x = lerp(leg_r.rotation.x, 0.0, k)
	if punch_t > 0.0:
		punch_t -= delta
		arm_r.rotation.x = -1.7 * (punch_t / 0.25)
		arm_l.rotation.x = -1.2 * (punch_t / 0.25)

func _process(delta: float) -> void:
	time_acc += delta
	if started:
		if Input.is_action_pressed("cam_left"):
			yaw += 2.0 * delta
		if Input.is_action_pressed("cam_right"):
			yaw -= 2.0 * delta
		if Input.is_action_just_pressed("interact"):
			interact()
		if Input.is_action_just_pressed("build_gen"):
			set_build("gen")
		if Input.is_action_just_pressed("build_wall"):
			set_build("wall")
		if Input.is_action_just_pressed("rotate"):
			build_rot += PI / 2.0
		if Input.is_action_just_pressed("place"):
			try_place()
		if Input.is_action_just_pressed("cancel"):
			set_build("")
	else:
		yaw += delta * 0.08  # slow orbit behind the title screen
	cam_yaw.position = cam_yaw.position.lerp(player.position + Vector3(0, 1.7, 0), clamp(10.0 * delta, 0.0, 1.0))
	cam_yaw.rotation.y = yaw
	cam_pitch.rotation.x = pitch
	spring.spring_length = lerp(spring.spring_length, zoom, clamp(8.0 * delta, 0.0, 1.0))
	scav_cd = max(0.0, scav_cd - delta)
	flash_t = max(0.0, flash_t - delta)
	_update_economy(delta)
	_update_piles(delta)
	_update_ghost()
	if core_mat:
		core_mat.emission_energy_multiplier = 1.6 + 0.6 * sin(time_acc * 1.7)
	_update_ui()

func _update_economy(delta: float) -> void:
	var gen_on := 0
	var n_struct := structures.size()
	var walls := 0
	for s in structures:
		if s.type == "gen":
			if s.fuel > 0.0:
				s.fuel = max(0.0, s.fuel - delta)
				gen_on += 1
			var running: bool = s.fuel > 0.0
			s.ring.rotation.y += delta * (3.0 if running else 0.0)
			s.core_mat.emission_energy_multiplier = (2.2 + 0.5 * sin(time_acc * 6.0)) if running else 0.1
			var lbl: Label3D = s.label
			if running:
				lbl.text = "FUEL %ds" % int(ceil(s.fuel))
				lbl.modulate = Color(0.5, 1.0, 1.0) if s.fuel > 20.0 else Color(1.0, 0.7, 0.3)
			else:
				lbl.text = "NO FUEL  [E] +%d Scrap" % FUEL_COST
				lbl.modulate = Color(1.0, 0.35, 0.3)
		else:
			walls += 1
	var shields_on := power > 0.01
	power_rate = gen_on * GEN_RATE - n_struct * IDLE_DRAIN - (walls * WALL_DRAIN if shields_on else 0.0)
	power = clamp(power + power_rate * delta, 0.0, power_cap)
	for s in structures:
		if s.type != "gen":
			var flicker := power < 5.0 and shields_on and fmod(time_acc * 13.0, 1.0) < 0.2
			s.field.visible = shields_on and not flicker
			s.field_col.disabled = not shields_on
			s.field_mat.albedo_color.a = 0.32 + 0.12 * sin(time_acc * 3.0)

func _update_piles(delta: float) -> void:
	for p in piles:
		var node: Node3D = p.node
		var g: Node3D = p.glow
		g.rotation.y += delta * 1.5
		g.position.y = 0.95 + 0.08 * sin(time_acc * 2.0 + node.position.x)
		if p.charges <= 0:
			p.timer -= delta
			if p.timer <= 0.0:
				p.charges = PILE_CHARGES
				node.show()
				p.col.set_deferred("disabled", false)
				var tw := create_tween()
				tw.tween_property(node, "scale", Vector3.ONE, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _update_ghost() -> void:
	if ghost == null:
		return
	ghost.global_transform = ghost_transform()
	var cost := GEN_COST if build_mode == "gen" else WALL_COST
	var ok := placement_problem(ghost.global_position, cost) == ""
	ghost_mat.albedo_color = Color(0.3, 1.0, 0.45, 0.45) if ok else Color(1.0, 0.3, 0.25, 0.45)

# ---------------------------------------------------------------- input

func _start() -> void:
	started = true
	title_overlay.hide()
	yaw = 0.0
	flash("Find the glowing scrap piles. Press E to scavenge.")

func _over_button(pos: Vector2) -> bool:
	for b in ui_buttons:
		if b.visible and b.get_global_rect().has_point(pos):
			return true
	return false

func _input(event: InputEvent) -> void:
	if not started:
		var go := false
		if event is InputEventKey and event.pressed and not event.echo:
			go = true
		elif event is InputEventMouseButton and event.pressed:
			go = true
		elif event is InputEventScreenTouch and event.pressed:
			go = true
		if go:
			_start()
			get_viewport().set_input_as_handled()
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			touches[event.index] = event.position
			if _over_button(event.position):
				return
			var vs := get_viewport().get_visible_rect().size
			if event.position.x < vs.x * 0.4 and joy_id == -1:
				joy_id = event.index
				joy_center = event.position
				joy_vec = Vector2.ZERO
			elif cam_touch_id == -1:
				cam_touch_id = event.index
		else:
			touches.erase(event.index)
			if event.index == joy_id:
				joy_id = -1
				joy_vec = Vector2.ZERO
			if event.index == cam_touch_id:
				cam_touch_id = -1
		joy_ctrl.queue_redraw()
	elif event is InputEventScreenDrag:
		if event.index == joy_id:
			joy_vec = ((event.position - joy_center) / 70.0).limit_length(1.0)
			joy_ctrl.queue_redraw()
		elif event.index == cam_touch_id:
			yaw -= event.relative.x * 0.008
			pitch = clamp(pitch - event.relative.y * 0.006, -1.2, 0.35)

func _unhandled_input(event: InputEvent) -> void:
	if not started or not touches.is_empty():
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			zoom = max(3.5, zoom - 0.6)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			zoom = min(15.0, zoom + 0.6)
		elif event.button_index == MOUSE_BUTTON_LEFT or event.button_index == MOUSE_BUTTON_RIGHT:
			if event.pressed:
				mouse_dragging = true
				drag_dist = 0.0
			else:
				var was := mouse_dragging
				mouse_dragging = false
				if was and event.button_index == MOUSE_BUTTON_LEFT and drag_dist < 6.0 and build_mode != "":
					try_place()
	elif event is InputEventMouseMotion and mouse_dragging:
		drag_dist += event.relative.length()
		yaw -= event.relative.x * 0.006
		pitch = clamp(pitch - event.relative.y * 0.005, -1.2, 0.35)

# ---------------------------------------------------------------- UI

func _label(parent: Node, text: String, size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 6)
	parent.add_child(l)
	return l

func _panel_style(alpha := 0.72) -> StyleBoxFlat:
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.05, 0.04, 0.1, alpha)
	st.set_corner_radius_all(10)
	st.set_content_margin_all(12)
	st.border_color = Color(1.0, 0.7, 0.35, 0.5)
	st.set_border_width_all(1)
	return st

func _build_ui() -> void:
	ui = CanvasLayer.new()
	add_child(ui)
	# resources panel
	var panel := PanelContainer.new()
	panel.position = Vector2(16, 16)
	panel.add_theme_stylebox_override("panel", _panel_style())
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vb := VBoxContainer.new()
	panel.add_child(vb)
	lbl_scrap = _label(vb, "", 26, Color(1.0, 0.72, 0.35))
	lbl_power = _label(vb, "", 26, Color(0.45, 0.95, 1.0))
	lbl_goals = _label(vb, "", 16, Color(0.88, 0.86, 0.92))
	ui.add_child(panel)
	# watermark
	var wm := _label(ui, "SUN HOUSE  ·  gM Records", 22, Color(1.0, 0.85, 0.55, 0.85))
	wm.anchor_left = 1.0
	wm.anchor_right = 1.0
	wm.offset_left = -460
	wm.offset_right = -18
	wm.offset_top = 14
	wm.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var sub := _label(ui, "The Server World · Scrap Core · demo", 14, Color(0.8, 0.8, 0.9, 0.7))
	sub.anchor_left = 1.0
	sub.anchor_right = 1.0
	sub.offset_left = -460
	sub.offset_right = -18
	sub.offset_top = 44
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	# prompt
	lbl_prompt = _label(ui, "", 22, Color(1, 1, 1))
	lbl_prompt.anchor_top = 1.0
	lbl_prompt.anchor_bottom = 1.0
	lbl_prompt.anchor_right = 1.0
	lbl_prompt.offset_top = -110
	lbl_prompt.offset_bottom = -76
	lbl_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# control hint
	lbl_hint = _label(ui, "WASD/arrows move · Shift sprint · Space jump · drag mouse or Q/C to look · wheel zoom · E scavenge/fuel · 1 generator · 2 shield · R rotate · F/click place · X cancel", 14, Color(0.85, 0.85, 0.9, 0.75))
	lbl_hint.anchor_top = 1.0
	lbl_hint.anchor_bottom = 1.0
	lbl_hint.anchor_right = 1.0
	lbl_hint.offset_top = -34
	lbl_hint.offset_bottom = -10
	lbl_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# action buttons (mouse + touch)
	var col := VBoxContainer.new()
	col.anchor_left = 1.0
	col.anchor_right = 1.0
	col.anchor_top = 0.5
	col.anchor_bottom = 0.5
	col.offset_left = -200
	col.offset_right = -16
	col.offset_top = -170
	col.offset_bottom = 170
	col.add_theme_constant_override("separation", 8)
	ui.add_child(col)
	_button(col, "Scavenge / Fuel  [E]", interact)
	_button(col, "Generator %d  [1]" % GEN_COST, func(): set_build("gen"))
	_button(col, "Shield wall %d  [2]" % WALL_COST, func(): set_build("wall"))
	_button(col, "Rotate  [R]", func(): build_rot += PI / 2.0)
	_button(col, "Place  [F]", try_place)
	_button(col, "Cancel  [X]", func(): set_build(""))
	# touch joystick layer
	joy_ctrl = Control.new()
	joy_ctrl.set_anchors_preset(Control.PRESET_FULL_RECT)
	joy_ctrl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	joy_ctrl.draw.connect(_draw_joy)
	ui.add_child(joy_ctrl)
	# title
	title_overlay = ColorRect.new()
	(title_overlay as ColorRect).color = Color(0.02, 0.01, 0.05, 0.62)
	title_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.add_child(title_overlay)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_overlay.add_child(center)
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", 10)
	center.add_child(tv)
	var t1 := _label(tv, "SUN HOUSE", 84, Color(1.0, 0.82, 0.45))
	t1.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var t2 := _label(tv, "THE SERVER WORLD  ·  SCRAP CORE", 26, Color(0.55, 0.95, 1.0))
	t2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var t3 := _label(tv, "You are Agent 12. Scavenge Scrap, build a Power generator,\nkeep it fueled, and raise a shield before the core goes dark.", 20, Color(0.92, 0.9, 0.95))
	t3.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var t4 := _label(tv, "WASD / arrows move  ·  drag to look  ·  E scavenge  ·  1 generator  ·  2 shield  ·  F place\nTouch: left thumb moves, right thumb looks, buttons on the right", 16, Color(0.8, 0.8, 0.88))
	t4.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var t5 := _label(tv, "Click, tap or press any key to start", 22, Color(1, 1, 1))
	t5.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t5.name = "Blink"
	var t6 := _label(tv, "gM Records  ·  demo build, placeholder art", 14, Color(0.7, 0.7, 0.8, 0.7))
	t6.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var tw := create_tween().set_loops()
	tw.tween_property(t5, "modulate:a", 0.25, 0.8)
	tw.tween_property(t5, "modulate:a", 1.0, 0.8)

func _button(parent: Node, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(184, 48)
	b.add_theme_font_size_override("font_size", 17)
	var st := _panel_style(0.7)
	st.set_content_margin_all(6)
	b.add_theme_stylebox_override("normal", st)
	var sth := _panel_style(0.9)
	sth.set_content_margin_all(6)
	sth.bg_color = Color(0.2, 0.12, 0.3, 0.9)
	b.add_theme_stylebox_override("hover", sth)
	b.add_theme_stylebox_override("pressed", sth)
	b.pressed.connect(cb)
	parent.add_child(b)
	ui_buttons.append(b)
	return b

func _draw_joy() -> void:
	if joy_id == -1:
		return
	joy_ctrl.draw_circle(joy_center, 72.0, Color(1, 1, 1, 0.12))
	joy_ctrl.draw_arc(joy_center, 72.0, 0, TAU, 48, Color(1, 0.8, 0.5, 0.5), 2.0)
	joy_ctrl.draw_circle(joy_center + joy_vec * 70.0, 30.0, Color(1, 0.8, 0.5, 0.45))

func _update_ui() -> void:
	lbl_scrap.text = "SCRAP  %d" % scrap
	var sign: String = "+" if power_rate >= 0.0 else ""
	lbl_power.text = "POWER  %d / %d   (%s%.2f/s)" % [int(power), int(power_cap), sign, power_rate]
	var g1 := "[x]" if total_scavenged >= GEN_COST else "[ ]"
	var g2 := "[x]" if goal_gen else "[ ]"
	var g3 := "[x]" if goal_fuel else "[ ]"
	var g4 := "[x]" if goal_wall else "[ ]"
	var txt := "%s Scavenge %d Scrap (%d/%d)\n%s Build a Power generator  [1]\n%s Refuel it with Scrap  [E]\n%s Raise a shield wall  [2]" % [g1, GEN_COST, min(total_scavenged, GEN_COST), GEN_COST, g2, g3, g4]
	if goal_gen and goal_fuel and goal_wall:
		txt += "\nOutpost online. Keep fuel up or the shield drops."
	lbl_goals.text = txt
	var prompt := ""
	if flash_t > 0.0:
		prompt = flash_msg
	elif build_mode != "":
		var cost := GEN_COST if build_mode == "gen" else WALL_COST
		var nm := "Power generator" if build_mode == "gen" else "Shield wall"
		var why := placement_problem(ghost_transform().origin, cost)
		prompt = "Placing %s (%d Scrap)  ·  F / click / Place to build  ·  R rotate  ·  X cancel" % [nm, cost]
		if why != "":
			prompt += "\n" + why
	elif started:
		var p = nearest_pile()
		if p != null:
			prompt = "[E] Scavenge scrap pile  (%d left)" % p.charges
		else:
			var g = nearest_gen()
			if g != null:
				prompt = "[E] Fuel generator: %d Scrap for +%ds" % [FUEL_COST, int(FUEL_ADD)]
	lbl_prompt.text = prompt
	if power <= 0.01 and goal_wall:
		lbl_power.add_theme_color_override("font_color", Color(1.0, 0.35, 0.3))
	else:
		lbl_power.add_theme_color_override("font_color", Color(0.45, 0.95, 1.0))

# ---------------------------------------------------------------- self-test (run with: -- --autotest)

func _shot(name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img:
		img.save_png("user://" + name + ".png")
		print("shot: ", ProjectSettings.globalize_path("user://" + name + ".png"))

func _wait(t: float) -> void:
	await get_tree().create_timer(t).timeout

func _autotest() -> void:
	await _wait(1.0)
	await _shot("01_title")
	_start()
	await _wait(0.5)
	var p = piles[0]
	var pp: Vector3 = p.node.position
	var away := Vector3(pp.x, 0, pp.z).normalized()
	if away == Vector3.ZERO:
		away = Vector3.BACK
	player.position = pp - away * 2.0 + Vector3(0, 0.1, 0)
	yaw = atan2(-away.x, -away.z) + PI  # camera behind the player, looking at the pile
	await _wait(0.6)
	for i in 4:
		interact()
		await _wait(0.45)
	p = piles[1]
	pp = p.node.position
	player.position = pp + Vector3(2.0, 0.1, 0)
	await _wait(0.4)
	for i in 4:
		interact()
		await _wait(0.45)
	print("after scavenging: scrap=", scrap)
	player.position = Vector3(0, 0.1, 6)
	yaw = 0.0
	await _wait(0.6)
	set_build("gen")
	await _wait(0.3)
	await _shot("02_ghost")
	print("gen placement check: '", placement_problem(ghost_transform().origin, GEN_COST), "'")
	try_place()
	print("after generator: scrap=", scrap, " structures=", structures.size())
	await _wait(0.3)
	var gp: Vector3 = structures[0].node.global_position
	player.position = gp + Vector3(0, 0.1, 2.3)
	await _wait(0.4)
	interact()
	print("after fuel: scrap=", scrap, " fuel=", structures[0].fuel)
	player.position = Vector3(3, 0.1, 6)
	await _wait(0.3)
	set_build("wall")
	await _wait(0.2)
	try_place()
	print("after wall: scrap=", scrap, " structures=", structures.size())
	yaw = 0.25
	pitch = -0.4
	zoom = 9.0
	player.position = Vector3(-4, 0.1, 9)
	await _wait(4.0)
	print("power=", power, " rate=", power_rate, " cap=", power_cap)
	await _shot("03_outpost")
	player.position = Vector3(0, 0.1, 4)
	pitch = 0.05
	yaw = 0.0
	zoom = 9.0
	await _wait(1.0)
	await _shot("04_firmament")
	print("AUTOTEST DONE goals:", goal_gen, goal_fuel, goal_wall)
	get_tree().quit()
