class_name AudioManager
extends Node
## ============================================================================
## AudioManager — Lecture des SFX/musique (GDD §11.5 : noeud AudioManager).
##
## SQUELETTE : un AudioStreamPlayer pour la musique + un pool de joueurs pour
## les SFX (dés, capture, victoire). Les streams réels seront déposés dans
## res://assets/audio/ puis assignés dans l'inspecteur.
## ============================================================================

@export var music_streams: Array[AudioStream] = []
@export var sfx_roll: AudioStream
@export var sfx_capture: AudioStream
@export var sfx_victory: AudioStream

var _music: AudioStreamPlayer
var _sfx_pool: Array[AudioStreamPlayer] = []
const _SFX_POOL_SIZE: int = 6
var _sfx_index: int = 0


func _ready() -> void:
	_music = AudioStreamPlayer.new()
	_music.bus = "Master"
	add_child(_music)
	for i in range(_SFX_POOL_SIZE):
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		_sfx_pool.append(p)

	# Branchement au bus global pour déclencher les sons depuis n'importe où.
	GameEvents.dice_rolled.connect(_on_dice_rolled)
	GameEvents.pawn_captured.connect(_on_pawn_captured)
	GameEvents.victory.connect(_on_victory)


func play_music(index: int = 0) -> void:
	if index < 0 or index >= music_streams.size():
		return
	_music.stream = music_streams[index]
	_music.play()


func play_sfx(stream: AudioStream) -> void:
	if stream == null:
		return
	var p: AudioStreamPlayer = _sfx_pool[_sfx_index]
	_sfx_index = (_sfx_index + 1) % _SFX_POOL_SIZE
	p.stream = stream
	p.play()


func _on_dice_rolled(_a: int, _b: int, _is_double: bool) -> void:
	play_sfx(sfx_roll)

func _on_pawn_captured(_victim: Dictionary, _attacker: Dictionary) -> void:
	play_sfx(sfx_capture)

func _on_victory(_winner: int) -> void:
	play_sfx(sfx_victory)
