extends TestCase
## Audio assets (tools/gen_audio.py): every sound id the game uses ships as an
## imported WAV of sensible length, sounds named by data resolve, one-shots do
## not loop, and music/ambience streams loop over their whole body once
## GameAudio has started them.

const SFX := [
	"ui_click", "ui_open", "ui_error", "ui_confirm", "quest", "level_up", "save",
	"alert", "alarm", "door", "loot", "bash", "blaster", "rifle", "ion", "drone", "heavy_blaster",
	"blade", "lumen", "punch", "baton", "heavy", "spider", "hit", "crit", "miss", "deflect",
	"explosion", "cast", "heal", "downed", "step",
	"infl_up", "infl_down", "align_mercy", "align_dominion", "pa_chime", "lumen_on", "lumen_off", "victory",
]
const AMBIENT := ["amb_ship", "amb_deep"]
const LOOP_FX := ["loop_reactor", "loop_sparks", "loop_machine"]
const MUSIC := ["music_menu", "music_explore", "music_tension", "music_combat", "music_ending"]


## Babble syllables for conversation voices (see data/voices.json).
func _voice_ids() -> Array[String]:
	var out: Array[String] = []
	var banks: Dictionary = DB.voices.get("banks", {})
	for b in banks.keys():
		for i in int(banks[b]):
			out.append("vox_%s_%02d" % [b, i + 1])
	return out


func test_voice_banks() -> void:
	var ids := _voice_ids()
	assert_gte(ids.size(), 40, "four voice banks")
	var total := 0
	for id in ids:
		assert_true(ResourceLoader.exists(_path(id)), "exists " + id)
		var s: AudioStream = load(_path(id))
		if s == null:
			fail("loads " + id)
			continue
		assert_gte(s.get_length(), 0.06, id + " has a syllable")
		assert_lte(s.get_length(), 0.45, id + " is one syllable")
		assert_ne((s as AudioStreamWAV).loop_mode, AudioStreamWAV.LOOP_FORWARD, id + " does not loop")
		total += FileAccess.get_file_as_bytes(_path(id)).size()
	assert_lte(total, 700 * 1024, "voice banks stay small (%d bytes)" % total)
	for sid in DB.voices.get("speakers", {}).keys():
		var v := DB.voice_for(String(sid))
		if String(v["bank"]) != "":
			assert_gte(int(v["count"]), 1, String(sid) + " has a bank")


func _path(id: String) -> String:
	return "res://assets/audio/%s.wav" % id


## Frame count of the source WAV, read from its RIFF header.
func _wav_frames(id: String) -> int:
	var f := FileAccess.open(_path(id), FileAccess.READ)
	if f == null:
		return -1
	f.seek(12)
	var channels := 1
	var bits := 16
	while f.get_position() + 8 <= f.get_length():
		var tag := f.get_buffer(4).get_string_from_ascii()
		var size := f.get_32()
		var start := f.get_position()
		if tag == "fmt ":
			f.get_16()
			channels = f.get_16()
			f.seek(start + 14)
			bits = f.get_16()
		elif tag == "data":
			@warning_ignore("integer_division")
			return size / (channels * bits / 8)
		f.seek(start + size + (size & 1))
	return -1


func test_every_id_loads() -> void:
	for id in SFX + AMBIENT + MUSIC + LOOP_FX:
		assert_true(ResourceLoader.exists(_path(id)), "exists " + id)
		var s: AudioStream = load(_path(id))
		assert_true(s != null, "loads " + id)
		if s != null:
			assert_true(s is AudioStreamWAV, id + " is an AudioStreamWAV")
			assert_gte(s.get_length(), 0.04, id + " has audio")


func test_lengths_within_budget() -> void:
	for id in SFX:
		var s: AudioStream = load(_path(id))
		if s != null:
			assert_lte(s.get_length(), 1.25, id + " is a short effect")
			assert_ne((s as AudioStreamWAV).loop_mode, AudioStreamWAV.LOOP_FORWARD, id + " does not loop")
	for aid in AMBIENT:
		var amb: AudioStream = load(_path(aid))
		assert_gte(amb.get_length(), 20.0, aid + " ambience loop length")
		assert_lte(amb.get_length(), 30.1, aid + " ambience loop length")
	for lid in LOOP_FX:
		var lp: AudioStream = load(_path(lid))
		assert_gte(lp.get_length(), 1.5, lid + " prop loop length")
		assert_lte(lp.get_length(), 8.0, lid + " prop loop length")
	for id in MUSIC:
		var m: AudioStream = load(_path(id))
		assert_gte(m.get_length(), 40.0, id + " length")
		assert_lte(m.get_length(), 75.1, id + " length")


func test_data_sound_ids_resolve() -> void:
	var ids := {}
	for k in DB.items.keys():
		var wp: Dictionary = DB.items[k].get("weapon", {})
		if wp.has("sound"):
			ids[String(wp["sound"])] = true
	var areas: Dictionary = DB.dict(DB.layout, "areas")
	for a in areas.keys():
		ids[String(areas[a].get("music", "music_explore"))] = true
		ids[String(areas[a].get("ambience", "amb_ship"))] = true
	assert_gte(ids.size(), 12, "data names weapon sounds and area music")
	for id in ids.keys():
		assert_true(GameAudio.stream(String(id)) != null, "GameAudio resolves " + String(id))


func _check_loop(id: String) -> void:
	var w := GameAudio.stream(id) as AudioStreamWAV
	assert_true(w != null, id + " stream")
	if w == null:
		return
	var frames := _wav_frames(id)
	assert_gte(frames, 2, id + " header frames")
	assert_eq(roundi(w.get_length() * w.mix_rate), frames, id + " imported frame count")
	assert_eq(w.loop_mode, AudioStreamWAV.LOOP_FORWARD, id + " loops forward")
	assert_eq(w.loop_begin, 0, id + " loop begin")
	# The last frame is a guard copy of frame 0, so the loop body is frames - 1.
	assert_eq(w.loop_end, frames - 1, id + " loop end")


func _wait(sec: float) -> void:
	await GameAudio.get_tree().create_timer(sec).timeout


func test_music_and_ambient_loop() -> void:
	GameAudio.stop_music()
	for id in MUSIC:
		GameAudio.music(id)
		_check_loop(id)
	GameAudio.ambient("amb_ship")
	_check_loop("amb_ship")
	assert_true(GameAudio._ambient.stream == GameAudio.stream("amb_ship"), "ambient player holds the bed")
	# music() swaps streams on a tween; let it run, then check the player.
	await _wait(1.7)
	assert_true(GameAudio._music.stream == GameAudio.stream(MUSIC[-1]), "music player holds the last track")
	assert_true(GameAudio._music.playing, "music playing")
	# Jump to just before the end of the bed: it must wrap and keep playing.
	var amb := GameAudio._ambient
	amb.seek(amb.stream.get_length() - 0.25)
	await _wait(0.6)
	assert_true(amb.playing, "ambience still playing past its end")
	assert_lte(amb.get_playback_position(), 1.0, "ambience wrapped to the start")
	GameAudio.stop_music()
	GameAudio.ambient("")
	assert_false(GameAudio._music.playing, "music stopped")
	assert_false(amb.playing, "ambience stopped")
	await _wait(0.2)  # let the mixer drop the stopped playbacks


func test_music_crossfades() -> void:
	GameAudio.stop_music()
	GameAudio.music("music_explore")
	var first := GameAudio._music
	GameAudio.music("music_combat")
	assert_true(GameAudio._music != first, "the new track gets the other player")
	assert_true(GameAudio._music.stream == GameAudio.stream("music_combat"), "combat on the active player")
	assert_true(first.playing, "the old track fades rather than cutting")
	GameAudio.music("music_explore")
	GameAudio.music("music_tension")
	assert_true(GameAudio._music.stream == GameAudio.stream("music_tension"), "rapid switches end on the last track")
	GameAudio.stop_music()
	assert_false(GameAudio._music.playing, "stopped")
	assert_false(GameAudio._music2.playing, "both stopped")


## Plays a stream on a private bus and returns what the mixer produced: at
## least sec seconds, starting at the first frame the player contributed.
func _capture(w: AudioStream, sec: float, from: float = 0.0) -> PackedVector2Array:
	AudioServer.add_bus()
	var bus := AudioServer.bus_count - 1
	AudioServer.set_bus_name(bus, "AudioLoopTest")
	var cap := AudioEffectCapture.new()
	cap.buffer_length = sec + 2.0
	AudioServer.add_bus_effect(bus, cap)
	var p := AudioStreamPlayer.new()
	p.bus = "AudioLoopTest"
	p.stream = w
	GameAudio.add_child(p)
	p.play(from)
	var need := int(AudioServer.get_mix_rate() * (sec + 0.1))
	var deadline := Time.get_ticks_msec() + int((sec + 3.0) * 1000.0)
	while cap.get_frames_available() < need and Time.get_ticks_msec() < deadline:
		await GameAudio.get_tree().process_frame
	var buf := cap.get_buffer(cap.get_frames_available())
	p.stop()
	await _wait(0.1)  # let the mixer drop the stopped playback
	p.queue_free()
	AudioServer.remove_bus(AudioServer.get_bus_index("AudioLoopTest"))
	var onset := 0
	while onset < buf.size() and absf(buf[onset].x) < 0.0005:
		onset += 1
	return buf.slice(onset)


## Largest frame-to-frame jump in buf[a, b).
func _max_step(buf: PackedVector2Array, a: int, b: int) -> float:
	var worst := 0.0
	for i in range(maxi(a, 1), mini(b, buf.size())):
		worst = maxf(worst, absf(buf[i].x - buf[i - 1].x))
	return worst


func test_loop_seam_is_continuous_in_mixer() -> void:
	var rate := AudioServer.get_mix_rate()
	# A cosine whose period is the loop length peaks exactly at the seam, so a
	# seam that interpolated towards silence would show as a large jump.
	var n := 2205
	var data := PackedByteArray()
	data.resize((n + 1) * 2)
	for i in n + 1:
		data.encode_s16(i * 2, roundi(16000.0 * cos(TAU * i / n)))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = 22050
	w.stereo = false
	w.data = data
	GameAudio.make_looping(w)
	assert_eq(w.loop_end, n, "loop body excludes the guard frame")
	var buf: PackedVector2Array = await _capture(w, 0.4)
	assert_gte(buf.size(), int(rate * 0.4), "mixer produced audio")
	# Five seams pass in 0.4 s; a smooth cosine changes <= ~0.0014 per frame.
	var step := _max_step(buf, int(rate * 0.01), buf.size())
	assert_lte(step, 0.01, "no discontinuity at the synthetic loop seam (max step %.4f)" % step)
	# Real loops: start 0.15 s before the end; the jump across the seam must
	# be no worse than the material's own transients nearby.
	for id in AMBIENT + MUSIC + LOOP_FX:
		var st := GameAudio.stream(id) as AudioStreamWAV
		GameAudio.make_looping(st)
		var b: PackedVector2Array = await _capture(st, 0.4, st.get_length() - 0.15)
		assert_gte(b.size(), int(rate * 0.4), id + " captured")
		var seam := int(rate * 0.15)
		var win := int(rate * 0.02)
		var near := _max_step(b, seam - win, seam + win)
		var away := maxf(_max_step(b, 1, seam - win), _max_step(b, seam + win, b.size()))
		assert_lte(near, maxf(away * 1.25, 0.05), "%s seam step %.4f vs %.4f elsewhere" % [id, near, away])
