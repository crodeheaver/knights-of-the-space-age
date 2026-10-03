# Who sounds like what. Lines are babbled in a made-up language from the
# syllable banks rendered by tools/gen_audio.py (vox_<bank>_NN). The player,
# the narrator and system text stay silent, as in the old d20 space RPGs.
#   bank   hlo (human, low) | hhi (human, high) | syn (synthetic) | wrd (WARDEN) | "" (silent)
#   pitch  playback pitch multiplier on the bank (about 0.8-1.25)
#   rate   speaking pace multiplier (1.0 = the bank's natural syllable rate)
#   bus    "radio" runs the voice through the band-passed intercom bus
# Speakers not listed get a voice derived from their id (machines get "syn").

VOICES = {
    "banks": {"hlo": 14, "hhi": 14, "syn": 12, "wrd": 12},
    "default": {"bank": "hlo", "pitch": 1.0, "rate": 1.0, "bus": ""},
    "speakers": {
        "player": {"bank": ""},
        "narrator": {"bank": ""},
        "system": {"bank": ""},
        "iona": {"bank": "hhi", "pitch": 0.94, "rate": 1.08},
        "tav7": {"bank": "syn", "pitch": 1.0, "rate": 1.1},
        "warden": {"bank": "wrd", "pitch": 1.0, "rate": 0.85, "bus": "radio"},
        "intercom": {"bank": "hlo", "pitch": 1.08, "rate": 1.1, "bus": "radio"},
        "terminal": {"bank": "syn", "pitch": 1.25, "rate": 1.2, "bus": "radio"},
        "steward": {"bank": "hlo", "pitch": 1.1, "rate": 1.15},
        "varr": {"bank": "hhi", "pitch": 0.86, "rate": 0.92},
        "quill": {"bank": "hlo", "pitch": 0.88, "rate": 0.9},
        "senna": {"bank": "hhi", "pitch": 1.06, "rate": 1.0},
        "varga": {"bank": "hhi", "pitch": 0.92, "rate": 1.12},
        "dalia": {"bank": "hhi", "pitch": 1.02, "rate": 1.05},
        "ilo": {"bank": "hhi", "pitch": 1.22, "rate": 1.15},
        "abeni": {"bank": "hlo", "pitch": 1.12, "rate": 1.05},
        "pell": {"bank": "hlo", "pitch": 1.0, "rate": 0.88},
        "ketterick": {"bank": "hlo", "pitch": 0.84, "rate": 1.05},
        "reclaimer": {"bank": "hlo", "pitch": 0.95, "rate": 1.1},
        "drone": {"bank": "syn", "pitch": 1.35, "rate": 1.3, "bus": "radio"},
    },
}

DIALOGUES = []
OUTPUTS = {"voices": VOICES}
