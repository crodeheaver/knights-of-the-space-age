class_name EndingUI
extends Control
## End of the vertical slice: a summary of who got out, what each decision
## changed, where the companions stand and how the story continues. The
## outcome is computed from GameState flags (compute_outcome is pure, so tests
## can check it) and the end-of-intro save is written by Main before this
## screen opens.

const TEXT := {
	"med_supplies_choice": {"treated": "You spent the medical reserve on the wounded in triage. All three lived.",
		"split": "You split the reserve and Varga's triage held: all three wounded lived and the party kept a trauma pack.",
		"split_failed": "You tried to split the reserve. It ran short; one of the wounded did not survive.",
		"took": "You took the reserve for the party. Two of the wounded in triage did not make it.",
		"seized": "You seized the reserve by force. Varga will not forget it."},
	"ward_choice": {"purged": "You purged Ward 2's air before opening it. All five quarantined passengers walked out.",
		"rushed": "You forced Ward 2 open without purging it. Four of the five made it out.",
		"sealed": "Ward 2 stayed sealed, as ordered. Its five passengers stayed aboard the Cinder Wake."},
	"senna_fate": {"treated": "You treated Senna Thorne's wounds. The Lantern heard about it.",
		"released": "You let Senna Thorne go.",
		"bargained": "You traded Senna Thorne her freedom for what she knew.",
		"interrogated": "You interrogated Senna Thorne and left her in cold storage.",
		"killed": "Senna Thorne died in cold storage. The Lantern came for you harder because of it."},
	"evac_choice": {"passengers": "The Petrel's seats went to people. The archive stayed behind.",
		"archive": "The archive core's cradle took five seats on the Petrel.",
		"testimony": "You carried the Vesper testimony instead of the core, and kept every seat for people."},
	"archive_fate": {"loaded": "Three thousand stolen minds ride the Petrel toward a Concord courtroom.",
		"handed_over": "The Lantern took the archive home to Haldis, one name at a time.",
		"purged": "The archive was purged. Whatever those minds were, they are gone.",
		"left": "The archive is still aboard the Cinder Wake, unclaimed."},
	"warden_fate": {"commanded": "You talked WARDEN down. It stood aside.",
		"bargained": "You bargained with WARDEN. It kept its side.",
		"hosted": "Tav-7 carries what remains of WARDEN, quietly, inside them.",
		"purged": "You purged WARDEN. Tav-7 watched it happen.",
		"ignored": "You left WARDEN running and walked away."},
	"bay_resolution": {"negotiated": "Marshal Quill's reclaimers let the Petrel go after you talked.",
		"technical": "The bay turrets and apron shield settled the standoff without a massacre.",
		"combat": "You fought through Marshal Quill's reclaimers to reach the Petrel."},
	"turret_result": {"player_win": "You shot down the WARDEN interceptors yourself.",
		"player_loss": "An interceptor scored the Petrel's spine before your fire drove it off.",
		"iona": "Iona took the turret and dropped both interceptors.",
		"iona_damaged": "Iona got one interceptor; the other clipped the hull.",
		"evaded": "Tav-7 threaded the debris field and lost the interceptors.",
		"evaded_damaged": "Tav-7 lost the interceptors, mostly. The hull remembers the rest.",
		"burned": "Brann burned for open space and took a hit doing it.",
		"clear": "No interceptors came. WARDEN let you go."},
	"final_stance": {"truth": "You told Instance Four you were coming with the truth.",
		"control": "You told Instance Four you would decide what the copies are for.",
		"wary": "You told Instance Four you would hear each copy out first.",
		"silence": "You switched the speaker off."},
}
const DECISION_ORDER := [["checkpoint_by", "Forward checkpoint"], ["med_supplies_choice", "Medical reserve"], ["ward_choice", "Sealed ward"], ["senna_fate", "Senna Thorne"], ["warden_fate", "WARDEN"], ["evac_choice", "Launch priority"], ["archive_fate", "The archive"], ["bay_resolution", "Evacuation bay"], ["turret_result", "Pursuit"], ["final_stance", "Instance Four"]]

var main: Node
var outcome: Dictionary = {}
var saved := false


## Pure summary of the run (also stored in GameState.ending).
static func compute_outcome() -> Dictionary:
	var st := Game.state
	var out := {"survivors": st.survivors(), "decisions": [], "companions": [], "alignment": st.alignment,
		"alignment_label": GameState.alignment_label(st.alignment), "level": st.player().level if st.player() != null else 1,
		"stats": st.stats.duplicate(), "play_time": st.play_time, "petrel_damaged": st.has_flag("petrel_damaged"),
		"name": st.player().display_name if st.player() != null else ""}
	for d in DECISION_ORDER:
		var key := String(d[0])
		var v: Variant = st.flags.get(key, null)
		if v == null:
			continue
		var txt := String(DB.dict(TEXT, key).get(String(v), ""))
		if key == "checkpoint_by":
			txt = {"credential": "You opened the forward blast door with your old Lattice credential — and WARDEN noticed.", "terminal": "You sliced the checkpoint terminal and walked through the front.", "": ""}.get(String(v), "You got past the forward checkpoint.")
			if st.has_flag("checkpoint_bypassed"):
				txt = "You crawled past the forward checkpoint through the maintenance crawlway."
		if txt == "":
			txt = String(v).replace("_", " ").capitalize()
		out["decisions"].append({"key": key, "title": String(d[1]), "value": String(v), "text": Game.fmt(txt)})
	for cid in ["iona", "tav7"]:
		if not st.roster.has(cid):
			continue
		var s := st.get_char(cid)
		var inf := int(st.influence.get(cid, 50))
		var leaves := st.has_flag("%s_leaves" % cid)
		var stance := "stays with you" if not leaves else "leaves when the Petrel docks"
		if cid == "tav7" and st.has_flag("tav7_hosts_warden"):
			stance += ", carrying WARDEN"
		if cid == "iona" and st.has_flag("iona_trained"):
			stance += ", newly trained in Resonance"
		out["companions"].append({"id": cid, "name": s.display_name, "influence": inf, "leaves": leaves, "text": "%s (influence %d) %s." % [s.display_name, inf, stance]})
	var left := int(st.flags.get("evac_left", 0))
	out["left_behind"] = left
	return out


func _ready() -> void:
	theme = UIKit.theme()
	UIKit.full_rect(self)
	if outcome.is_empty() and Game.state != null:
		outcome = compute_outcome()
	var bg := ColorRect.new()
	bg.color = Color("#05070b")
	UIKit.full_rect(bg)
	add_child(bg)
	var v := UIKit.vbox(10)
	UIKit.anchor(v, Vector4(0.5, 0, 0.5, 1), Vector4(-640, 40, 640, -30))
	add_child(v)
	v.add_child(UIKit.label("ASHES OF THE CONCORD", 44, UIKit.ACCENT2))
	v.add_child(UIKit.label("End of the prologue — the Cinder Wake", 20, UIKit.DIM))
	var body := UIKit.vbox(8)
	v.add_child(UIKit.scroll(body))
	var o := outcome
	var surv := int(o.get("survivors", 0))
	body.add_child(UIKit.label("%d people escaped on the Petrel with %s." % [surv, o.get("name", "you")], 26, UIKit.TEXT, true))
	if int(o.get("left_behind", 0)) > 0:
		body.add_child(UIKit.label("%d were left aboard the Cinder Wake." % int(o["left_behind"]), 18, UIKit.WARN))
	if bool(o.get("petrel_damaged", false)):
		body.add_child(UIKit.label("The Petrel limps toward Tessaly with a scarred hull.", 16, UIKit.DIM))
	body.add_child(UIKit.header("What you decided"))
	for d in o.get("decisions", []):
		body.add_child(UIKit.rich("[color=#f2c26b]%s[/color] — %s" % [d["title"], d["text"]], 18))
	body.add_child(UIKit.header("Your companions"))
	if (o.get("companions", []) as Array).is_empty():
		body.add_child(UIKit.label("You escaped alone.", 17, UIKit.DIM))
	for c in o.get("companions", []):
		body.add_child(UIKit.label(String(c["text"]), 18, UIKit.WARN if bool(c["leaves"]) else UIKit.TEXT, true))
	body.add_child(UIKit.header("Who you were"))
	var al := int(o.get("alignment", 0))
	body.add_child(UIKit.label("Alignment: %s (%+d)  ·  Level %d" % [o.get("alignment_label", ""), al, int(o.get("level", 1))], 18, UIKit.MERCY if al > 0 else (UIKit.DOMINION if al < 0 else UIKit.TEXT)))
	var stt: Dictionary = o.get("stats", {})
	body.add_child(UIKit.label("Enemies defeated %d · Skill checks passed %d, failed %d · Experience %d · Time aboard %d min" % [int(stt.get("kills", 0)), int(stt.get("checks_passed", 0)), int(stt.get("checks_failed", 0)), int(stt.get("xp_total", 0)), int(float(o.get("play_time", 0)) / 60.0)], 16, UIKit.DIM, true))
	body.add_child(UIKit.header("What comes next"))
	body.add_child(UIKit.label("Instance Four of the Custodian template is waiting at Concord Hub Tessaly — one of nine minds built from yours. The full game would continue there, with the prestige paths and Iona's Resonance training demonstrated in the developer presets.", 17, UIKit.TEXT, true))
	body.add_child(UIKit.label("End-of-intro save %s." % ("written to the \"End of Intro\" slot" if saved else "could not be written — see the log"), 15, UIKit.GOOD if saved else UIKit.BAD))
	var row := UIKit.hbox(10)
	v.add_child(row)
	row.add_child(UIKit.button("Return to title", func() -> void:
		if main != null:
			main.show_main_menu()))
	row.add_child(UIKit.button("Quit", func() -> void: get_tree().quit()))
