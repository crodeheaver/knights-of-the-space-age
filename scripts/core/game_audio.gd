extends Node
## Audio playback: one-shot sounds, positional sounds, ambient bed and music,
## routed through separate buses (Music, SFX, Ambience, UI) with independent
## volume settings. Sounds are original procedurally generated WAVs in
## res://assets/audio (see tools/gen_audio.py and docs/ASSETS_AUDIO.md).

const AUDIO_DIR := "res://assets/audio/"
const BUSES := ["Music", "SFX", "Ambience", "UI", "Voice"]
const UI_SOUNDS := ["ui_click", "ui_open", "ui_error", "ui_confirm", "quest", "level_up", "save",
	"infl_up", "infl_down", "align_mercy", "align_dominion"]
## Natural syllable spacing per voice bank, in seconds (see tools/gen_audio.py).
const VOICE_PACE := {"hlo": 0.17, "hhi": 0.15, "syn": 0.12, "wrd": 0.24}
const VOICE_CHANNELS := ["dialogue", "world", "ship"]

## Emitted for every babble syllable as it plays (speaker glow, mouth flap).
signal voice_syllable(channel: String, amp: float)

var _cache: Dictionary = {}
var _voice_players: Dictionary = {}  # channel -> Array[AudioStreamPlayer]
var _voice_rr: Dictionary = {}  # channel -> next player index
var _voice_sched: Dictionary = {}  # channel -> {"t", "i", "items", "bus", "db"}
var _pool: Array[AudioStreamPlayer] = []
var _music: AudioStreamPlayer
var _music2: AudioStreamPlayer
var _ambient: AudioStreamPlayer
var _music_id := ""
var _ambient_id := ""
var _ambient2: AudioStreamPlayer
var _music_tw: Tween
var _amb_tw: Tween
## Where each track was when it faded out, so exploration music picks up
## where it left off after a fight instead of restarting.
var _music_pos: Dictionary = {}
var _steps: Array[AudioStreamPlayer] = []
var _step_i := 0
var _loops: Array[AudioStreamPlayer3D] = []
const MAX_LOOPS := 12
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
	_ambient2 = AudioStreamPlayer.new()
	_ambient2.bus = "Ambience"
	add_child(_ambient2)
	# Footsteps get their own players so they never crowd out combat sounds.
	for i in 2:
		var sp := AudioStreamPlayer.new()
		sp.bus = "SFX"
		add_child(sp)
		_steps.append(sp)
	_setup_voice()
	apply_volumes()
	Events.event.connect(_on_event)


## Voice bus (volume slider) plus an intercom/radio bus feeding it: band-passed
## and lightly overdriven, for WARDEN, ship announcements and comm calls.
func _setup_voice() -> void:
	if AudioServer.get_bus_index("VoiceRadio") < 0:
		AudioServer.add_bus()
		var idx := AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, "VoiceRadio")
		AudioServer.set_bus_send(idx, "Voice")
		var bp := AudioEffectBandPassFilter.new()
		bp.cutoff_hz = 1700.0
		bp.resonance = 0.55
		AudioServer.add_bus_effect(idx, bp)
		var dist := AudioEffectDistortion.new()
		dist.mode = AudioEffectDistortion.MODE_OVERDRIVE
		dist.drive = 0.25
		dist.post_gain = -3.0
		AudioServer.add_bus_effect(idx, dist)
	for ch in VOICE_CHANNELS:
		var ps: Array[AudioStreamPlayer] = []
		for i in 3:
			var p := AudioStreamPlayer.new()
			p.bus = "Voice"
			add_child(p)
			ps.append(p)
		_voice_players[ch] = ps
		_voice_rr[ch] = 0


func apply_volumes() -> void:
	var map := {"Master": "master_volume", "Music": "music_volume", "SFX": "sfx_volume", "Ambience": "ambience_volume", "UI": "ui_volume",
		"Voice": "voice_volume"}
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


## Crossfades to a music track (two players: the old one fades out while
## the new one fades in). A track that was interrupted resumes where it was.
func music(id: String) -> void:
	if id == _music_id:
		return
	if _music_id != "" and _music.playing:
		_music_pos[_music_id] = _music.get_playback_position()
	_music_id = id
	if _music_tw != null and _music_tw.is_valid():
		_music_tw.kill()
	var old := _music
	_music = _music2
	_music2 = old
	var s := stream(id)
	_music_tw = create_tween().set_parallel(true)
	if s != null:
		make_looping(s)
		_music.stream = s
		_music.volume_db = -40.0
		var from := float(_music_pos.get(id, 0.0))
		_music.play(from if from < s.get_length() - 1.0 else 0.0)
		_music_tw.tween_property(_music, "volume_db", -6.0, 1.6)
	else:
		_music.stop()
	if old.playing:
		_music_tw.tween_property(old, "volume_db", -40.0, 1.6)
		_music_tw.chain().tween_callback(old.stop)


func stop_music() -> void:
	_music_id = ""
	if _music_tw != null and _music_tw.is_valid():
		_music_tw.kill()
	_music.stop()
	_music2.stop()
	_music_pos.clear()


## Silences everything (music, ambience, pooled one-shots), e.g. before quit.
func stop_all() -> void:
	stop_music()
	ambient("")
	_ambient.stop()
	_ambient2.stop()
	for p in _pool:
		p.stop()
	for ch in VOICE_CHANNELS:
		voice_stop(ch)


## Crossfades the ambience bed ("" fades it out).
func ambient(id: String) -> void:
	if id == _ambient_id:
		return
	_ambient_id = id
	if _amb_tw != null and _amb_tw.is_valid():
		_amb_tw.kill()
	var s := stream(id)
	if s == null:
		# Silence (menus, the ending): stop at once.
		_ambient.stop()
		_ambient2.stop()
		return
	var old := _ambient
	_ambient = _ambient2
	_ambient2 = old
	make_looping(s)
	_ambient.stream = s
	_ambient.volume_db = -30.0 if old.playing else -8.0
	_ambient.play()
	if old.playing:
		_amb_tw = create_tween().set_parallel(true)
		_amb_tw.tween_property(_ambient, "volume_db", -8.0, 1.2)
		_amb_tw.tween_property(old, "volume_db", -40.0, 1.2)
		_amb_tw.chain().tween_callback(old.stop)


## A looping positional sound on a prop (reactor hum, sparking cable...).
## Capped; returns null when the cap is reached or the sound is missing.
func loop_at(id: String, pos: Vector3, parent: Node, max_dist: float = 20.0, volume_db: float = 0.0) -> AudioStreamPlayer3D:
	var live: Array[AudioStreamPlayer3D] = []
	for lp in _loops:
		if is_instance_valid(lp):
			live.append(lp)
	_loops = live
	if not enabled or parent == null or _loops.size() >= MAX_LOOPS:
		return null
	var s := stream(id)
	if s == null:
		return null
	make_looping(s)
	var p := AudioStreamPlayer3D.new()
	p.stream = s
	p.bus = "Ambience"
	p.volume_db = volume_db
	p.unit_size = 4.0
	p.max_distance = max_dist
	p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	parent.add_child(p)
	p.global_position = pos
	p.play(randf() * maxf(0.0, s.get_length() - 0.1))
	_loops.append(p)
	return p


## A footstep (its own small pool, quiet, slightly varied).
func step(volume_db: float = -16.0) -> void:
	if not enabled:
		return
	var s := stream("step")
	if s == null:
		return
	var p := _steps[_step_i]
	_step_i = (_step_i + 1) % _steps.size()
	p.stream = s
	p.volume_db = volume_db
	p.pitch_scale = randf_range(0.9, 1.1)
	p.play()


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


# ================================================================ voices
## Babbles `text` on a channel ("dialogue" or "world") in the given voice
## (DB.voice_for: bank, count, pitch, rate, bus). The same text and seed
## always produce the same sounds; words map to fixed syllables, so repeated
## words sound alike, like a real language. `cps` (text reveal speed, chars per
## second) gently paces the voice to the text. Returns the line's length in
## seconds (0 when the voice is silent).
func voice_line(channel: String, text: String, voice: Dictionary, seed_v: int, cps: float = 0.0, volume_db: float = 0.0) -> float:
	voice_stop(channel)
	var items := voice_schedule(text, voice, seed_v, cps)
	if items.is_empty():
		return 0.0
	var bus := "VoiceRadio" if String(voice.get("bus", "")) == "radio" else "Voice"
	_voice_sched[channel] = {"t": 0.0, "i": 0, "items": items, "bus": bus, "db": volume_db}
	var last: Dictionary = items[items.size() - 1]
	return float(last["t"]) + float(last["len"])


## Pure scheduling (testable without audio): [{t, id, pitch, db, len}].
static func voice_schedule(text: String, voice: Dictionary, seed_v: int, cps: float = 0.0) -> Array:
	var bank := String(voice.get("bank", ""))
	var count := int(voice.get("count", 0))
	if bank == "" or count <= 0 or text.strip_edges() == "":
		return []
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var pace := float(VOICE_PACE.get(bank, 0.16)) / maxf(0.3, float(voice.get("rate", 1.0)))
	# Words → syllables (vowel groups, 1-3 per word) and pauses after punctuation.
	var words := text.replace("—", " — ").replace("…", "… ").split(" ", false)
	var plan: Array = []  # [syllables, pause_after, word_hash, emphasis]
	var syl_total := 0
	for w in words:
		var word := String(w)
		var core := word.to_lower().strip_edges()
		var groups := 0
		var in_v := false
		for ch in core:
			var v := "aeiouy".contains(ch)
			if v and not in_v:
				groups += 1
			in_v = v
		var syl := clampi(groups, 1 if core.length() > 0 and core != "—" and core != "…" else 0, 3)
		var pause := 0.0
		var tail := word.right(1)
		if tail in [",", ";", ":"]:
			pause = 0.18
		elif tail in [".", "!", "?"]:
			pause = 0.32
		elif tail == "—" or tail == "…" or word == "—":
			pause = 0.25
		plan.append([syl, pause, hash(core.trim_suffix(tail) if pause > 0.0 else core), tail == "!"])
		syl_total += syl
	if syl_total == 0:
		return []
	# Pace towards the text reveal: never faster than 0.7× or slower than
	# 1.3× the bank's natural rate; long lines are capped at about 9 s.
	if cps > 0.0:
		var want := clampf(float(text.length()) / cps, 0.4, 9.0)
		pace = clampf(want / float(syl_total), pace * 0.7, pace * 1.3)
	pace = clampf(pace, 0.07, 0.3)
	var base_pitch := float(voice.get("pitch", 1.0))
	var question := text.strip_edges().ends_with("?")
	var out: Array = []
	var t := 0.0
	var prev := -1
	var n_done := 0
	for wi in plan.size():
		var p: Array = plan[wi]
		for k in int(p[0]):
			# Word-stable syllable choice (a "vocabulary"), never the same twice in a row.
			var idx := absi(int(p[2]) + k * 7919) % count
			if idx == prev:
				idx = (idx + 1 + rng.randi_range(0, count - 2)) % count
			prev = idx
			var frac := float(n_done) / float(maxi(1, syl_total - 1))
			var contour := lerpf(1.04, 0.95, frac)  # declination across the line
			if question and syl_total - n_done <= 2:
				contour *= 1.12 if syl_total - n_done == 2 else 1.2
			var pitch := base_pitch * contour * rng.randf_range(0.96, 1.04)
			var db := (1.5 if bool(p[3]) else 0.0) + rng.randf_range(-1.5, 0.5)
			var step := pace * rng.randf_range(0.88, 1.12)
			out.append({"t": t, "id": "vox_%s_%02d" % [bank, idx + 1], "pitch": pitch, "db": db, "len": step})
			t += step
			n_done += 1
			if t > 9.0:
				return out
		t += float(p[1])
	return out


func voice_stop(channel: String) -> void:
	_voice_sched.erase(channel)
	for p in _voice_players.get(channel, []):
		(p as AudioStreamPlayer).stop()


func voice_active(channel: String) -> bool:
	return _voice_sched.has(channel)


func _process(delta: float) -> void:
	for ch in _voice_sched.keys():
		var s: Dictionary = _voice_sched[ch]
		s["t"] = float(s["t"]) + delta
		var items: Array = s["items"]
		while int(s["i"]) < items.size() and float(items[int(s["i"])]["t"]) <= float(s["t"]):
			var it: Dictionary = items[int(s["i"])]
			s["i"] = int(s["i"]) + 1
			_play_syllable(String(ch), it, String(s["bus"]), float(s["db"]))
		if int(s["i"]) >= items.size():
			var last: Dictionary = items[items.size() - 1]
			if float(s["t"]) >= float(last["t"]) + float(last["len"]):
				_voice_sched.erase(ch)


func _play_syllable(channel: String, it: Dictionary, bus: String, volume_db: float) -> void:
	voice_syllable.emit(channel, clampf(1.0 + float(it["db"]) / 6.0, 0.3, 1.0))
	if not enabled:
		return
	var s := stream(String(it["id"]))
	var ps: Array = _voice_players.get(channel, [])
	if s == null or ps.is_empty():
		return
	var i := int(_voice_rr.get(channel, 0))
	_voice_rr[channel] = (i + 1) % ps.size()
	var p: AudioStreamPlayer = ps[i]
	p.stream = s
	p.bus = bus
	p.pitch_scale = clampf(float(it["pitch"]), 0.5, 2.0)
	p.volume_db = volume_db + float(it["db"]) - 4.0
	p.play()


func _on_event(name: String, data: Dictionary) -> void:
	match name:
		"quest_updated":
			if data.has("state"):
				play("quest", -4.0)
		"level_up":
			play("level_up", -4.0)
		"game_saved":
			play("save", -8.0)
