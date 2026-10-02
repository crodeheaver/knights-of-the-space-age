class_name StealthRules
extends RefCounted
## Stealth detection. An observer can only notice a target it can perceive:
## within sight range, with grid line of sight, and either inside its 120°
## view cone or within 2.5 m. Each second a perceivable sneaking target forces
## an opposed check:
##   d20 + observer Awareness - floor(distance / 2)  vs  10 + target Stealth
##   (+2 if the target stood still this second)
## A success adds suspicion (0.4, or 1.0 when beating the DC by 10+). At 1.0 the
## target is detected. Suspicion decays 0.25/s while the target is not
## perceivable. Non-sneaking targets are detected as soon as they are perceived.

const CONE_HALF_DEG := 60.0
const CLOSE_RADIUS := 2.5
const CHECK_INTERVAL := 1.0
const DECAY_PER_SEC := 0.25
const GAIN := 0.4
const GAIN_STRONG := 1.0


static func perceivable(obs_pos: Vector2, obs_facing: Vector2, sight: float, tgt_pos: Vector2, has_los: bool) -> bool:
	var to := tgt_pos - obs_pos
	var d := to.length()
	if d > sight or not has_los:
		return false
	if d <= CLOSE_RADIUS:
		return true
	if obs_facing.length_squared() < 0.0001:
		return true
	var ang := rad_to_deg(absf(obs_facing.normalized().angle_to(to.normalized())))
	return ang <= CONE_HALF_DEG


static func stealth_dc(target: CharacterSheet, still: bool) -> int:
	return 10 + target.skill_total("stealth") + (2 if still else 0)


static func check(observer: CharacterSheet, target: CharacterSheet, distance: float, still: bool, dice: Dice) -> Dictionary:
	var nat := dice.d20()
	var aw := observer.skill_total("awareness")
	var dist_pen := floori(distance / 2.0)
	var total := nat + aw - dist_pen
	var dc := stealth_dc(target, still)
	var gain := 0.0
	if total >= dc:
		gain = GAIN_STRONG if total >= dc + 10 else GAIN
	gain *= Prestige.detection_mult(target)
	return {"natural": nat, "awareness": aw, "distance_penalty": dist_pen, "total": total, "dc": dc, "success": total >= dc, "gain": gain}
