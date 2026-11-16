extends Node3D
## Small pooled-free mesh sparks and synthesized placeholder impact sounds.

var particles: Array[Dictionary] = []
var sounds: Dictionary = {}
var voices: Array[AudioStreamPlayer] = []
var voice_index := 0
var muted := false

func _ready() -> void:
	for kind in ["punch", "kick", "block", "round"]:
		sounds[kind] = _make_sound(kind)
	for i in range(4):
		var voice = AudioStreamPlayer.new()
		voice.volume_db = -19.0
		add_child(voice)
		voices.append(voice)

func impact(at: Vector3, blocked: bool, kind: String) -> void:
	var color = Color("7cdeee") if blocked else Color("ffbf53")
	var material = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.no_depth_test = false
	for i in range(8):
		var spark = MeshInstance3D.new()
		var mesh = SphereMesh.new()
		mesh.radius = 0.045 if blocked else 0.06
		mesh.height = mesh.radius * 2.0
		mesh.radial_segments = 6
		mesh.rings = 3
		spark.mesh = mesh
		spark.material_override = material
		spark.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(spark)
		spark.position = at
		var angle = float(i) / 8.0 * TAU
		particles.append({"node": spark, "velocity": Vector3(cos(angle), sin(angle), 0) * 3.5, "age": 0.0})
	play_cue("block" if blocked else kind)

func step(delta: float) -> void:
	for i in range(particles.size() - 1, -1, -1):
		var particle: Dictionary = particles[i]
		particle.age += delta
		if particle.age >= 0.22:
			particle.node.queue_free()
			particles.remove_at(i)
		else:
			particle.node.position += particle.velocity * delta
			particle.node.scale = Vector3.ONE * (1.0 - particle.age / 0.22)

func clear() -> void:
	for particle in particles:
		particle.node.queue_free()
	particles.clear()
	for voice in voices:
		voice.stop()

func play_cue(kind: String) -> void:
	if muted or not sounds.has(kind):
		return
	var voice = voices[voice_index % voices.size()]
	voice_index += 1
	voice.stream = sounds[kind]
	voice.play()

func _make_sound(kind: String) -> AudioStreamWAV:
	var rate := 22050
	var length := 0.13 if kind != "round" else 0.3
	var frames := int(rate * length)
	var data := PackedByteArray()
	data.resize(frames * 2)
	var rng = RandomNumberGenerator.new()
	rng.seed = 810
	var low_noise := 0.0
	for i in range(frames):
		var time = float(i) / rate
		var envelope = pow(1.0 - float(i) / frames, 3.0) * minf(time * 1000.0, 1.0)
		low_noise = lerpf(low_noise, rng.randf_range(-1.0, 1.0), 0.4)
		var frequency: float = {"punch": 95.0, "kick": 65.0, "block": 520.0, "round": 330.0}[kind]
		var tone = sin(TAU * frequency * time) * (0.7 if kind == "round" else 0.45)
		var sample = int(clampf((tone + low_noise * 0.5) * envelope, -1.0, 1.0) * 32767.0)
		data.encode_s16(i * 2, sample)
	var stream = AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.data = data
	return stream
