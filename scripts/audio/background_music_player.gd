class_name BackgroundMusicPlayer
extends AudioStreamPlayer

## Background Music Player for Medieval Bergen 1360
## Handles seamless looping, volume balance, smooth fade-in, and Web Audio unlock on browser interaction.

@export var music_track: AudioStream
@export var base_volume_db: float = -9.0
@export var fade_in_time: float = 2.0
@export var auto_start: bool = true

var _fade_tween: Tween = null
var _user_interacted: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	bus = &"Master"
	
	if music_track != null and stream == null:
		stream = music_track
	elif stream != null and music_track == null:
		music_track = stream

	if stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = true

	finished.connect(_on_finished)

	if auto_start and stream != null:
		_start_playback()

func _start_playback() -> void:
	volume_db = -45.0
	play()
	if fade_in_time > 0.0:
		if _fade_tween and _fade_tween.is_valid():
			_fade_tween.kill()
		_fade_tween = create_tween()
		_fade_tween.tween_property(self, "volume_db", base_volume_db, fade_in_time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	else:
		volume_db = base_volume_db

func _unhandled_input(event: InputEvent) -> void:
	if not _user_interacted:
		if event is InputEventKey or event is InputEventMouseButton:
			_user_interacted = true
			if not playing and stream != null:
				play()

func _on_finished() -> void:
	# Fallback replay ensuring seamless looping across all platforms
	if not playing:
		play()

## Utility helper to fade music volume smoothly
func fade_to(target_db: float, duration: float = 1.5) -> void:
	if _fade_tween and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = create_tween()
	_fade_tween.tween_property(self, "volume_db", target_db, duration)
