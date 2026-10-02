extends Node
## Audio playback: one-shot sounds, positional sounds, ambient bed and music,
## routed through separate buses (Music, SFX, Ambience, UI) with independent
## volume settings. Sounds are original procedurally generated WAVs in
## res://assets/audio (see tools/gen_audio.py and docs/ASSETS_AUDIO.md).

const AUDIO_DIR := "res://assets/audio/"
const BUSES := ["Music", "SFX", "Ambience", "UI"]
const UI_SOUNDS := ["ui_click", "ui_open", "ui_error", "ui_confirm", "quest", "level_up", "save"]

var _cache: Dictionary = {}
var _pool: Array[AudioStreamPlayer] = []
var _music: AudioStreamPlayer
var _music2: AudioStreamPlayer
var _ambient: AudioStreamPlayer
var _music_id := ""
var _ambient_id := ""
var _fade := 0.0
var enabled := true


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for b in BUSES:
		if AudioServer.get_bus_index(b) < 0:
			AudioServer.add_bus()
			var idx := AudioServer.bus_count - 1
			AudioServer.set_bus_name(idx, b)
			AudioServer.set_bus_send(idx, "Master")
	for i in 12:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_pool.append(p)
	_music = AudioStreamPlayer.new()
	_music.bus = "Music"
	add_child(_music)
	_music2 = AudioStreamPlayer.new()
	_music2.bus = "Music"
	add_child(_music2)
	_ambient = AudioStreamPlayer.new()
	_ambient.bus = "Ambience"
	add_child(_ambient)
	apply_volumes()
	Events.event.connect(_on_event)


func apply_volumes() -> void:
	var map := {"Master": "master_volume", "Music": "music_volume", "SFX": "sfx_volume", "Ambience": "ambience_volume", "UI": "ui_volume"}
	for b in map.keys():
		var idx := AudioServer.get_bus_index(b)
		if idx >= 0:
			var v := clampf(float(Settings.get_v(map[b])), 0.0, 1.0)
			AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(v, 0.0001)))
			AudioServer.set_bus_mute(idx, v <= 0.001)


func stream(id: String) -> AudioStream:
	if _cache.has(id):
		return _cache[id]
	var path := AUDIO_DIR + id + ".wav"
	var s: AudioStream = null
	if ResourceLoader.exists(path):
		s = load(path)
	_cache[id] = s
	return s


func play(id: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	if not enabled:
		return
	var s := stream(id)
	if s == null:
		return
	for p in _pool:
		if not p.playing:
			p.stream = s
			p.volume_db = volume_db
			p.pitch_scale = pitch
			p.bus = "UI" if UI_SOUNDS.has(id) else "SFX"
			p.play()
			return


func play_at(id: String, pos: Vector3, parent: Node, volume_db: float = 0.0) -> void:
	if not enabled or parent == null:
		return
	var s := stream(id)
	if s == null:
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = s
	p.bus = "SFX"
	p.volume_db = volume_db
	p.unit_size = 6.0
	p.max_distance = 40.0
	parent.add_child(p)
	p.global_position = pos
	p.finished.connect(p.queue_free)
	p.play()


func music(id: String) -> void:
	if id == _music_id:
		return
	_music_id = id
	var s := stream(id)
	if s == null:
		_music.stop()
		return
	make_looping(s)
	var tw := create_tween()
	if _music.playing:
		tw.tween_property(_music, "volume_db", -40.0, 1.2)
	tw.tween_callback(func() -> void:
		_music.stream = s
		_music.volume_db = -40.0
		_music.play()
	)
	tw.tween_property(_music, "volume_db", -6.0, 1.5)


func stop_music() -> void:
	_music_id = ""
	_music.stop()


## Silences everything (music, ambience, pooled one-shots), e.g. before quit.
func stop_all() -> void:
	stop_music()
	ambient("")
	for p in _pool:
		p.stop()


func ambient(id: String) -> void:
	if id == _ambient_id:
		return
	_ambient_id = id
	var s := stream(id)
	if s == null:
		_ambient.stop()
		return
	make_looping(s)
	_ambient.stream = s
	_ambient.volume_db = -8.0
	_ambient.play()


## WAVs import without loop points; music and ambience beds loop forward
## over the whole file. The generated loops end with one guard sample equal to
## sample 0 (the resampler interpolates one frame past the loop end), so the
## loop covers frames [0, frames - 1).
func make_looping(s: AudioStream) -> void:
	var w := s as AudioStreamWAV
	if w == null or w.loop_mode == AudioStreamWAV.LOOP_FORWARD:
		return
	var frames := 0
	if w.format == AudioStreamWAV.FORMAT_16_BITS:
		@warning_ignore("integer_division")
		frames = w.data.size() / (4 if w.stereo else 2)
	else:  # compressed (QOA / IMA-ADPCM) or 8-bit imports
		frames = roundi(w.get_length() * w.mix_rate)
	if frames < 2:
		return
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_begin = 0
	w.loop_end = frames - 1


func _on_event(name: String, data: Dictionary) -> void:
	match name:
		"quest_updated":
			if data.has("state"):
				play("quest", -4.0)
		"level_up":
			play("level_up", -4.0)
		"game_saved":
			play("save", -8.0)
