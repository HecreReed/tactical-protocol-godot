# weapons.gd — 武器数据表（移植自网页版 config.js）
class_name Weapons

const LIST := {
	"classic":  { "name":"Classic",  "cat":"pistol",  "cost":0,    "mag":12, "res":36, "fi":0.148, "rl":1.75, "dmg":{"h":78,  "b":26, "l":22}, "spread":0.35, "range":50 },
	"ghost":    { "name":"Ghost",    "cat":"pistol",  "cost":500,  "mag":15, "res":45, "fi":0.148, "rl":1.8,  "dmg":{"h":105, "b":30, "l":26}, "spread":0.3,  "range":60 },
	"sheriff":  { "name":"Sheriff",  "cat":"pistol",  "cost":800,  "mag":6,  "res":18, "fi":0.4,   "rl":2.3,  "dmg":{"h":159, "b":55, "l":47}, "spread":0.45, "range":60 },
	"frenzy":   { "name":"Frenzy",   "cat":"pistol",  "cost":450,  "mag":13, "res":39, "fi":0.1,   "rl":1.9,  "dmg":{"h":78,  "b":26, "l":22}, "spread":0.6,  "range":40 },
	"stinger":  { "name":"Stinger",  "cat":"smg",     "cost":950,  "mag":20, "res":60, "fi":0.0625,"rl":2.0,  "dmg":{"h":67,  "b":27, "l":23}, "spread":0.65, "range":45 },
	"spectre":  { "name":"Spectre",  "cat":"smg",     "cost":1600, "mag":30, "res":90, "fi":0.075, "rl":2.2,  "dmg":{"h":78,  "b":26, "l":22}, "spread":0.5,  "range":50 },
	"bucky":    { "name":"Bucky",    "cat":"shotgun", "cost":850,  "mag":5,  "res":10, "fi":0.9,   "rl":2.5,  "dmg":{"h":40,  "b":20, "l":17}, "spread":2.6,  "range":22, "pellets":8 },
	"judge":    { "name":"Judge",    "cat":"shotgun", "cost":1850, "mag":7,  "res":21, "fi":0.45,  "rl":2.6,  "dmg":{"h":34,  "b":17, "l":14}, "spread":2.4,  "range":20, "pellets":7 },
	"bulldog":  { "name":"Bulldog",  "cat":"rifle",   "cost":2050, "mag":24, "res":72, "fi":0.105, "rl":2.5,  "dmg":{"h":115, "b":35, "l":30}, "spread":0.4,  "range":90 },
	"guardian": { "name":"Guardian", "cat":"rifle",   "cost":2250, "mag":12, "res":36, "fi":0.165, "rl":2.5,  "dmg":{"h":195, "b":65, "l":49}, "spread":0.3,  "range":100 },
	"phantom":  { "name":"Phantom",  "cat":"rifle",   "cost":2900, "mag":30, "res":90, "fi":0.088, "rl":2.5,  "dmg":{"h":156, "b":39, "l":33}, "spread":0.35, "range":90 },
	"vandal":   { "name":"Vandal",   "cat":"rifle",   "cost":2900, "mag":25, "res":75, "fi":0.096, "rl":2.5,  "dmg":{"h":160, "b":40, "l":34}, "spread":0.4,  "range":100 },
	"marshal":  { "name":"Marshal",  "cat":"sniper",  "cost":950,  "mag":5,  "res":15, "fi":0.9,   "rl":2.5,  "dmg":{"h":202, "b":101,"l":85}, "spread":0.1,  "range":150, "scope":true },
	"operator": { "name":"Operator", "cat":"sniper",  "cost":4700, "mag":5,  "res":10, "fi":1.2,   "rl":3.7,  "dmg":{"h":255, "b":150,"l":120},"spread":0.05, "range":200, "scope":true },
	"ares":     { "name":"Ares",     "cat":"heavy",   "cost":1600, "mag":50, "res":100,"fi":0.082, "rl":3.2,  "dmg":{"h":72,  "b":30, "l":25}, "spread":0.7,  "range":70 },
	"odin":     { "name":"Odin",     "cat":"heavy",   "cost":3200, "mag":100,"res":100,"fi":0.063, "rl":3.7,  "dmg":{"h":95,  "b":38, "l":32}, "spread":0.65, "range":80 },
}

const BUY_ORDER := ["ghost","sheriff","frenzy","stinger","spectre","bucky","judge","bulldog","guardian","phantom","vandal","marshal","operator","ares","odin"]

static func make(id: String) -> Dictionary:
	var def: Dictionary = LIST[id]
	return {
		"id": id, "def": def,
		"ammo": def["mag"], "reserve": def["res"],
		"next_fire": 0.0, "reload_end": 0.0,
	}
