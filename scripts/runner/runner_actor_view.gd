extends CharacterBody3D
## The port's body for one actor of the original code: the model, its animation control and a hit volume follow the actor record in emulated RAM, and hits received here are written back into the record.

const Machine := preload("res://scripts/runner/mips_machine.gd")
const NativeMaterial := preload("res://scripts/world/rendering/native_material.gd")
const HIT_WORD := 0x14C
const BOUNDS := 0x58
## Actors of the larger bosses keep their hit word in a separate record (pointer at +0x154, hit volumes at record +0x30) instead of +0x14C.
const RECORD_POINTER := 0x154
const RECORD_BOUNDS := 0x30
## Multi-part actors (the Manda ruins guardian) keep part positions at +0x158 and, 80 bytes further, a hit record in the model's part block at +0x15C (hit words at +0 and +8); their code reads those words (ST14 0x800F4510 and 0x800F4580) instead of +0x14C.
const PART_POSITIONS := 0x158
const PART_HIT := 0x15C
const MESH := 0xA4
## A solid body blocks the player's step-over: the volume reaches at least this high (raw units, the player's body is 0.7 m tall) from the object's floor.
const SOLID_HEIGHT := 192.0
## The collision list of an actor (GAME 0x800B93E4, category of the type byte at +2 through SLES 0x8003E408): a count word, then 16 byte records (x, z and y limits as halfword pairs in the actor's frame, y up is negative; low halfword of the last word the shape kind, high halfword the categories it blocks, the player is bit 0). Types 0x20..0x3F keep the list at +0xB8, types 0x60..0x9F at +0x9C; the others (enemies, 0x40) have none.
const BODY_LISTS := {0x20: 0xB8, 0x60: 0x9C}
const BODY_RECORD := 16
const BODY_PLAYER := 1
const BODY_LIMIT := 16
## A body registered with a parameter of 0 or more sits at a joint of the actor (SLES 0x8003EDEC: the parameter-th set bit of the mask at +0xCC picks a record of the 0xB0 byte pool at 0x8009C940; GAME 0x800BA200 reads its position halfwords at +0x80 + 8 * (parameter & 3)).
const JOINT_MASK := 0xCC
const JOINT_POOL := 0x8009C940
const JOINT_STRIDE := 0xB0
const JOINT_POSITION := 0x80
## Effect objects draw the model whose header is at +0x94 (GAME 0x80025540): the matrix is RotMatrix (SLES 0x80060824) of the angles at +0x28, +0x2A and +0x2C with its columns scaled by the halfwords at +0xB0, +0xB2 and +0xB4 (4096 is one).
const HEADER := 0x94
const ANGLES := 0x28
const SCALE := 0xB0
const ROT_MATRIX := 0x80060824
const SCRATCH := 0x801F0400
const CONTROL := 0xA0
const RECORD := 0xA3
const HEALTH := 0x70
const LIGHT := 0xE6
## The hierarchy table the actor keeps (4 bytes per model part from +0xEC; the flag byte at +0xEF hides the part with bit 0x80, SLES 0x80024894) and the face UV words (+0xD8 eyes, +0xDC mouth: parts with flag 1 or 2 add the low halfword to their texture coordinates, SLES 0x80025180); actor code swaps mouth, hand and head variants through them.
const PART_FLAGS := 0xEF
const FACE_WORDS := 0xD8

var machine: Machine
var address := 0
var clock: NativeAnimation
var model: Node3D
var shape: CollisionShape3D
var health := 0
var max_health := 0
var hittable := false
var hit_center := Vector3.ZERO
var control := -1
var model_index := -1
var removed := false
var passive := false
var materials: Array[ShaderMaterial] = []
var light := Vector3(128, 128, 128)
var queued_damage := 0
var queued_flags := 0
var base_scale := Vector3.ONE
var body := AABB()
var parts: Array[Dictionary] = []
## Liftable blocks (the attach rule's lift_classes) belong to the port's Lifter: the host drives the original block code through the player's lift fields.
var lift_host: Node
var blocker: StaticBody3D
var blocker_shapes: Array[CollisionShape3D] = []
var blocker_boxes: Array = []
## The kind of the solid body the actor registered this frame (GAME 0x800B8AA0), -1 when it has none: kinds 0 and 1 turn their boxes with the actor, kinds 2 and 3 keep them axis aligned.
var body_kind := -1
var body_param := -1


func configure(runner_machine: Machine, actor: int, path: String, animations: Array, scale_raw: Vector3, depth_cue: Dictionary, source_surfaces: Array = []) -> bool:
	machine = runner_machine
	address = actor
	var packed := load(path) as PackedScene
	if packed == null:
		return false
	model = packed.instantiate() as Node3D
	if model == null:
		return false
	add_child(model)
	model.scale = scale_raw / 512.0
	base_scale = model.scale
	NativeMaterial.apply(model, 128.0)
	var meshes := model.find_children("*", "MeshInstance3D", true, false)
	for mesh: MeshInstance3D in meshes:
		for surface in mesh.mesh.get_surface_count():
			var material := mesh.get_active_material(surface) as ShaderMaterial
			if material != null:
				materials.append(material)
				if mesh == meshes[0] and surface < source_surfaces.size():
					parts.append({"material": material, "part": int(source_surfaces[surface]["source_part"]), "stream": int(source_surfaces[surface]["uv_stream"])})
	if not depth_cue.is_empty():
		NativeMaterial.depth_cue(model, depth_cue)
	clock = NativeAnimation.new()
	clock.name = "NativeAnimationClock"
	add_child(clock)
	clock.configure(model.find_child("AnimationPlayer", true, false) as AnimationPlayer, animations)
	clock.automatic = false
	shape = CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	add_child(shape)
	collision_layer = 0
	collision_mask = 0
	return true


func make_lift(host: Node) -> void:
	lift_host = host
	_blocker()
	add_to_group("lift_targets")


## Kinematic bodies do not stop each other, so a solid actor carries a static body of its own for the player.
func _blocker() -> void:
	if blocker != null:
		return
	blocker = StaticBody3D.new()
	if lift_host == null:
		blocker.name = "NativeActorCollision"
	blocker.collision_layer = 0
	blocker.collision_mask = 0
	add_child(blocker)


## The block's own states (+8): 1 idle, 2 carried, 3 thrown, 4 broken.
func can_lift() -> bool:
	return lift_host != null and not removed and machine.u8(address + 8) == 1


func begin_lift(_carrier: Node3D) -> bool:
	return can_lift() and lift_host.lift_begin(self)


func release_lift(_direction: Vector3, _vertical_raw: int, _forward_raw: int) -> void:
	lift_host.lift_release(self)


## An idle block is solid for the port's player; its volume is the actor's bounds record (+0x58).
func _lift_body() -> void:
	var bounds := machine.u32(address + BOUNDS)
	if bounds == 0 or machine.u8(address + 8) != 1:
		_set_boxes([])
		return
	var low := Vector3(machine.s16(bounds), machine.s16(bounds + 4), machine.s16(bounds + 8))
	var high := Vector3(machine.s16(bounds + 2), machine.s16(bounds + 6), machine.s16(bounds + 10))
	var size := Vector3(high.x - low.x, maxf(high.y - low.y, SOLID_HEIGHT), high.z - low.z) / 256.0
	_set_boxes([[Vector3(-(low.x + high.x) * 0.5 / 256.0, -high.y / 256.0 + size.y * 0.5, (low.z + high.z) * 0.5 / 256.0), size]])


## An actor that registered a solid body this frame (GAME 0x800B8AA0) blocks the player in the boxes of its collision list: GAME 0x800B927C (kinds 0 and 2) and 0x800B8CAC (kinds 1 and 3) push the target out of them through the box shapes of the placement walls (kinds 0 to 3 are plain boxes). Kinds 0 and 1 turn the boxes with the actor, kinds 2 and 3 keep them axis aligned.
func _solid_body() -> void:
	var boxes := []
	var list := _body_list() if body_kind >= 0 else 0
	for index in mini(machine.u32(list), BODY_LIMIT) if list != 0 else 0:
		var record := list + 4 + index * BODY_RECORD
		if machine.u16(record + 14) & BODY_PLAYER == 0 or machine.u16(record + 12) > 3:
			continue
		var low := Vector3(machine.s16(record), machine.s16(record + 8), machine.s16(record + 4))
		var high := Vector3(machine.s16(record + 2), machine.s16(record + 10), machine.s16(record + 6))
		var size := (high - low) / 256.0
		if size.x > 0.0 and size.y > 0.0 and size.z > 0.0:
			boxes.append([Vector3(-(low.x + high.x), -(low.y + high.y), low.z + high.z) * 0.5 / 256.0, size])
	_set_boxes(boxes)
	if blocker != null:
		blocker.rotation.y = 0.0 if body_kind <= 1 else -rotation.y
		blocker.position = basis.inverse() * _joint_offset() if body_param >= 0 else Vector3.ZERO


## Where the body's joint lies relative to the actor (world axes).
func _joint_offset() -> Vector3:
	var seen := 0
	for bit in 32:
		if machine.u32(address + JOINT_MASK) & (0x80000000 >> bit) != 0:
			seen += 1
			if seen == body_param + 1:
				var joint := JOINT_POOL + bit * JOINT_STRIDE + JOINT_POSITION + 8 * (body_param & 3)
				return Vector3(-(machine.s16(joint) - machine.s16(address + 0x12)), -(machine.s16(joint + 2) - machine.s16(address + 0x16)), machine.s16(joint + 4) - machine.s16(address + 0x1A)) / 256.0
	return Vector3.ZERO


func _body_list() -> int:
	var type := machine.u8(address + 2)
	var category := type & 0x10 if type < 0x20 else type & 0xE0
	if category == 0x80:
		category = 0x60
	var list := machine.u32(address + int(BODY_LISTS[category])) if BODY_LISTS.has(category) else 0
	return list if list >= 0x80000000 and list < 0x80200000 else 0


## The static body carries one box shape per entry ([centre, size] in the actor's frame); a body taller than it is wide is not stood on (the port's player slides off it, as off the native NPCs' bodies).
func _set_boxes(boxes: Array) -> void:
	if boxes.is_empty() and blocker == null:
		return
	_blocker()
	if boxes != blocker_boxes:
		blocker_boxes = boxes
		while blocker_shapes.size() > boxes.size():
			var spare: CollisionShape3D = blocker_shapes.pop_back()
			blocker.remove_child(spare)
			spare.free()
		while blocker_shapes.size() < boxes.size():
			var added := CollisionShape3D.new()
			added.shape = BoxShape3D.new()
			blocker.add_child(added)
			blocker_shapes.append(added)
		for index in boxes.size():
			(blocker_shapes[index].shape as BoxShape3D).size = boxes[index][1]
			blocker_shapes[index].position = boxes[index][0]
		var first: Vector3 = boxes[0][1] if not boxes.is_empty() else Vector3.ZERO
		blocker.set_meta("native_unstandable", first.y > maxf(first.x, first.z))
	blocker.collision_layer = 1 if not boxes.is_empty() else 0


func class_id() -> int:
	return machine.u8(address + 4)


func sync() -> void:
	var x := machine.s16(address + 0x12)
	var y := machine.s16(address + 0x16)
	var z := machine.s16(address + 0x1A)
	position = Vector3(-x, -y, z) / 256.0
	if passive and machine.u32(address + HEADER) != 0:
		_orient()
	else:
		rotation.y = -float(machine.s16(address + 0x2A) & 4095) * TAU / 4096.0
	max_health = machine.s16(address + HEALTH + 2)
	health = machine.s16(address + HEALTH)
	var bounds := machine.u32(address + BOUNDS)
	hittable = not passive and (bounds != 0 or _part_hit() != 0) and max_health > 1 and health >= 0
	collision_layer = 8 if hittable else 0
	if hittable and not is_in_group("lock_targets"):
		add_to_group("lock_targets")
	elif not hittable and is_in_group("lock_targets"):
		remove_from_group("lock_targets")
	if hittable and bounds == 0:
		_body_shape()
	elif hittable:
		var box := shape.shape as BoxShape3D
		var low := Vector3(machine.s16(bounds), machine.s16(bounds + 4), machine.s16(bounds + 8))
		var high := Vector3(machine.s16(bounds + 2), machine.s16(bounds + 6), machine.s16(bounds + 10))
		box.size = Vector3(high.x - low.x, high.y - low.y, high.z - low.z) / 256.0
		shape.position = Vector3(-(low.x + high.x), -(low.y + high.y), low.z + high.z) * 0.5 / 256.0
		hit_center = to_global(shape.position)
	var tint := 0x4210 if passive else machine.u16(address + LIGHT)
	var color := Vector3((tint & 31) << 3, ((tint >> 5) & 31) << 3, ((tint >> 10) & 31) << 3)
	if color != light:
		light = color
		for material in materials:
			material.set_shader_parameter("light_rgb", color)
	if lift_host != null:
		_lift_body()
	elif not passive:
		_solid_body()
	if not passive:
		_parts()
	animate()


func _parts() -> void:
	for part in parts:
		var material := part["material"] as ShaderMaterial
		material.set_shader_parameter("part_visible", machine.u8(address + PART_FLAGS + 4 * int(part["part"])) & 0x80 == 0)
		if int(part["stream"]) != 0:
			material.set_shader_parameter("uv_word", machine.u16(address + FACE_WORDS + 4 * (int(part["stream"]) - 1)))


func _part_hit() -> int:
	var hit := machine.u32(address + PART_HIT)
	if hit < 0x80000000 or hit >= 0x80200000 or machine.u32(address + PART_POSITIONS) + 80 != hit:
		return 0
	return hit


## The part block carries no bounds record the port can read, so the hit volume is the model's own box (an approximation of the original volume).
func _body_shape() -> void:
	if body.size == Vector3.ZERO:
		var inverse := global_transform.affine_inverse()
		for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
			var box := (inverse * mesh.global_transform) * mesh.mesh.get_aabb()
			body = box if body.size == Vector3.ZERO else body.merge(box)
	(shape.shape as BoxShape3D).size = body.size
	shape.position = body.get_center()
	hit_center = to_global(shape.position)


func _orient() -> void:
	for index in 3:
		machine.put16(SCRATCH + 2 * index, machine.u16(address + ANGLES + 2 * index))
	machine.call_function(ROT_MATRIX, SCRATCH, SCRATCH + 8)
	var m := PackedFloat32Array()
	for index in 9:
		m.append(float(machine.s16(SCRATCH + 8 + 2 * index)) / 4096.0)
	basis = Basis(Vector3(m[0], m[3], -m[6]), Vector3(m[1], m[4], -m[7]), Vector3(-m[2], -m[5], m[8]))
	var factor := Vector3(machine.s16(address + SCALE), machine.s16(address + SCALE + 2), machine.s16(address + SCALE + 4)) / 4096.0
	model.scale = base_scale * (factor if factor.x != 0.0 and factor.y != 0.0 and factor.z != 0.0 else Vector3.ONE)


func animate() -> void:
	var wanted := machine.u8(address + CONTROL)
	if wanted != control:
		control = wanted
		clock.play_control(wanted, machine.u8(address + RECORD), true)
	else:
		clock.native_tick()


## Hits arrive between ticks; the next tick writes them into the actor's hit word.
func receive_hit(damage: int, hit_flags: int, _direction: Vector3 = Vector3.ZERO) -> bool:
	if not hittable:
		return false
	queued_damage += damage
	queued_flags |= hit_flags
	return true


func flush_hits() -> void:
	if queued_damage == 0 and queued_flags == 0:
		return
	var target := address + HIT_WORD
	# Actors that allocate a separate record (ST3C boss class 0x73, init 0x800EF7D0) keep a pointer to an entry of the joint pool (SLES 0x8003EDEC, +0x20) in the +0x14C slot; their code reads the hit word at the record's start.
	var inline_record := machine.u32(address + HIT_WORD)
	if inline_record >= JOINT_POOL + 0x20 and inline_record < JOINT_POOL + 32 * JOINT_STRIDE and (inline_record - JOINT_POOL - 0x20) % JOINT_STRIDE == 0:
		target = inline_record
	if machine.u32(address + BOUNDS) == 0 and _part_hit() != 0:
		target = _part_hit()
	var record := machine.u32(address + RECORD_POINTER)
	if record >= 0x80000000 and record < 0x80200000 and machine.u32(address + BOUNDS) == record + RECORD_BOUNDS:
		target = record
	var word := machine.u32(target)
	machine.put32(target, ((word | queued_flags) & 0xFFFFF000) | mini((word & 0xFFF) + queued_damage, 0xFFF))
	queued_damage = 0
	queued_flags = 0
