extends Node
## Playback controls shared by every scene type (native scenes, the opening, runner scenes, the Flutter map's launch and landing): cutscene_fast (Left Shift, held) fast-forwards, cutscene_rewind (Left Ctrl, held) goes back through the scene's keyframes and cutscene_pause (P) toggles pause. They only act while a scene has opened the controller with begin(); `speed` is 0 paused, 1 normal, FAST (a multiplier of the scene clock) or -REWIND.
## A scene (the owner) reads `speed` in its own clock and implements playback_root() -> Node (frozen with process_mode while paused), playback_hz() -> float, playback_ticks() -> int (clock counter), playback_back(count) -> int (restores count ticks earlier, returns the ticks actually stepped), playback_rewindable() -> bool, playback_voices() -> Array (players that follow the scene clock), playback_active() -> bool (false while a menu covers the scene; by default the tree must not be paused) and playback_resync() (called once the rewind ends, to start the voice at the restored tick); every one is optional.
const FAST := 4
const REWIND := 4
## Hard cap of ticks a scene may run (or step back) in one frame, so a slow frame never freezes the game.
const MAX_STEPS := 8
static var speed := 1
static var controller: Node
var owners: Array[Node] = []
var paused := false
var active := false
var quiet := false
var frozen: Node
var frozen_mode := Node.PROCESS_MODE_INHERIT
var held: Array[Node] = []
var pitched: Dictionary = {}
var rewound := false
var at_start := false
var back_clock := 0.0
var rate_time := 0.0
var rate_ticks := 0
var last_ticks := -1
var pitch := float(FAST)
var indicator: Control
class Indicator extends Control:
	const FONT := preload("res://assets/menu/native_font.fnt")
	const FRAME := preload("res://scripts/ui/common/native_menu_frame.gd")
	var layout: Dictionary = {}
	var label := ""
	## 0 hidden, 1 fast forward, 2 pause, 3 rewind
	var mode := 0
	func _draw() -> void:
		if mode == 0 or layout.is_empty(): return
		var factor := size.y / 240.0
		draw_set_transform(Vector2((size.x - 320.0 * factor) * 0.5, 0), 0, Vector2.ONE * factor)
		var width := 25.0 + (FONT.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + 4.0 if not label.is_empty() else 0.0)
		var rectangle := Rect2(312.0 - width, 8.0, width, 23.0)
		FRAME.draw(self, layout, "header", rectangle)
		var middle := rectangle.position.y + 11.5; var left := rectangle.position.x + 7.0
		if mode == 2: draw_rect(Rect2(left, middle - 5.0, 3.0, 10.0), Color.WHITE); draw_rect(Rect2(left + 6.0, middle - 5.0, 3.0, 10.0), Color.WHITE)
		else:
			var direction := 1.0 if mode == 1 else -1.0
			for index in 2:
				var x := left + 1.0 + 7.0 * float(index) + (4.0 if mode == 3 else 0.0)
				draw_colored_polygon(PackedVector2Array([Vector2(x, middle - 5.0), Vector2(x + 6.0 * direction, middle), Vector2(x, middle + 5.0)]), Color.WHITE)
		if not label.is_empty(): draw_string(FONT, Vector2(rectangle.position.x + 22.0, middle - 7.0 + FONT.get_ascent(12)), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE)
## A node's pose for a keyframe. A Node3D keeps either its matrix or its position, rotation and scale as the source of the other; putting back the one the scene wrote keeps the next tick bit for bit as it was (decomposing a matrix would shift the last digit).
static func pose(node: Node3D) -> Array:
	var basis := node.basis
	return [node.position, node.rotation, node.scale, basis, Basis.from_euler(node.rotation) * Basis.from_scale(node.scale) == basis]
static func apply(node: Node3D, state: Array) -> void:
	if state[4]:
		node.scale = state[2]; node.rotation = state[1]; node.position = state[0]
	else:
		node.transform = Transform3D(state[3], state[0])
## Opens the controller for a scene; every begin() is matched by an end() (a scene that is freed without one is dropped by the next frame).
static func begin(scene: Node) -> void:
	if controller == null or not is_instance_valid(controller):
		controller = (load("res://scripts/cinematics/scene_playback.gd") as GDScript).new(); controller.name = "ScenePlayback"; scene.get_tree().root.add_child.call_deferred(controller)
	if not controller.owners.has(scene): controller.owners.append(scene)
static func end(scene: Node) -> void:
	if controller != null and is_instance_valid(controller): controller.owners.erase(scene)
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS; process_priority = -1000
	var canvas := CanvasLayer.new(); canvas.layer = 90; add_child(canvas)
	indicator = Indicator.new(); indicator.mouse_filter = Control.MOUSE_FILTER_IGNORE; indicator.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); indicator.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST; canvas.add_child(indicator)
	var menu: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://assets/menu/manifest.json"))
	if menu is Dictionary: indicator.layout = menu.get("load_game_layout", {})
# The scene's own handlers (and the player's mouse release on Ctrl) never see these keys while a scene plays.
func _input(event: InputEvent) -> void:
	if not active: return
	# Esc or Enter ends a pause first (the scene's own handlers are frozen with it).
	if paused and (event.is_action_pressed("ui_cancel") or event.is_action_pressed("ui_accept")): paused = false; get_viewport().set_input_as_handled(); return
	for action in ["cutscene_fast", "cutscene_rewind", "cutscene_pause"]:
		if event.is_action(action) and Input.is_action_pressed(action): get_viewport().set_input_as_handled(); return
func _process(delta: float) -> void:
	owners = owners.filter(func(scene: Node) -> bool: return is_instance_valid(scene) and scene.is_inside_tree())
	var scene: Node = owners.back() if not owners.is_empty() else null
	# A scene that plays under a paused tree (the opening, behind the title menu) says itself when a menu covers it.
	var blocked: bool = not scene.playback_active() if scene != null and scene.has_method("playback_active") else get_tree().paused
	if scene == null or blocked:
		if active: _settle(scene != null)
		return
	active = true
	if Input.is_action_just_pressed("cutscene_pause"): paused = not paused
	var wanted := 1
	if Input.is_action_pressed("cutscene_rewind") and scene.has_method("playback_back") and (not scene.has_method("playback_rewindable") or scene.playback_rewindable()): wanted = -REWIND
	elif Input.is_action_pressed("cutscene_fast"): wanted = FAST
	elif paused: wanted = 0
	if wanted != speed: _change(scene, wanted)
	if speed < 0: _step_back(scene, delta)
	elif speed > 1: _follow_rate(scene, delta)
	var mode := 0 if speed == 1 else 2 if speed == 0 else 1 if speed > 0 else 3
	var text := "" if speed == 0 or speed < 0 and at_start else "x%d" % absi(speed)
	if indicator.mode != mode or indicator.label != text: indicator.mode = mode; indicator.label = text; indicator.queue_redraw()
func _change(scene: Node, wanted: int) -> void:
	if wanted == 0: _freeze(scene)
	else: _thaw()
	if wanted > 1: last_ticks = -1; rate_time = 0.0; rate_ticks = 0; pitch = float(FAST)
	else: _unpitch()
	if wanted < 0: back_clock = 0.0; at_start = false
	speed = wanted
	_quiet(scene, paused or wanted < 0)
func _freeze(scene: Node) -> void:
	var root: Node = scene.playback_root() if scene.has_method("playback_root") else null
	if root == null or not is_instance_valid(root) or frozen == root: return
	_thaw(); frozen = root; frozen_mode = root.process_mode; root.process_mode = Node.PROCESS_MODE_DISABLED
func _thaw() -> void:
	if is_instance_valid(frozen): frozen.process_mode = frozen_mode
	frozen = null
func _step_back(scene: Node, delta: float) -> void:
	back_clock += delta * (scene.playback_hz() if scene.has_method("playback_hz") else 25.0) * float(REWIND)
	var steps := mini(int(back_clock), MAX_STEPS); back_clock = minf(back_clock - float(steps), 1.0)
	if steps > 0:
		var done: int = scene.playback_back(steps)
		rewound = rewound or done > 0; at_start = done < steps
## Fast forward: the scene's voice follows the scene clock (pitched by the ticks it actually achieves, 4 at most), so a line stays on its picture.
func _follow_rate(scene: Node, delta: float) -> void:
	if not scene.has_method("playback_ticks"): return
	var ticks: int = scene.playback_ticks()
	if last_ticks >= 0: rate_ticks += maxi(ticks - last_ticks, 0)
	last_ticks = ticks; rate_time += delta
	if rate_time >= 0.4:
		pitch = clampf(float(rate_ticks) / rate_time / (scene.playback_hz() if scene.has_method("playback_hz") else 25.0), 1.0, float(FAST)); rate_time = 0.0; rate_ticks = 0
	for voice: Variant in scene.playback_voices() if scene.has_method("playback_voices") else []:
		if is_instance_valid(voice):
			if not pitched.has(voice): pitched[voice] = voice.pitch_scale
			voice.pitch_scale = pitch
func _unpitch() -> void:
	for voice: Variant in pitched:
		if is_instance_valid(voice): voice.pitch_scale = pitched[voice]
	pitched.clear()
## Every playing stream holds its position while the scene is paused or rewinding; afterwards the scene restarts its own voice for the restored tick.
func _quiet(scene: Node, silent: bool) -> void:
	if silent == quiet: return
	quiet = silent
	if silent:
		for kind in ["AudioStreamPlayer", "AudioStreamPlayer2D", "AudioStreamPlayer3D"]:
			for player: Node in get_tree().root.find_children("*", kind, true, false):
				if player.playing and not player.stream_paused: player.stream_paused = true; held.append(player)
		return
	for player: Node in held:
		if is_instance_valid(player): player.stream_paused = false
	held.clear()
	if rewound and scene != null and scene.has_method("playback_resync"): scene.playback_resync()
	rewound = false
## Back to normal when the last scene has ended (or a menu paused the tree).
func _settle(keep: bool) -> void:
	_thaw(); _unpitch(); _quiet(null, false)
	active = false; speed = 1; at_start = false; rewound = false
	if not keep: paused = false
	indicator.mode = 0; indicator.queue_redraw()
