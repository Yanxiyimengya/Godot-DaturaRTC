extends Control;
@onready var datura_audio_microphone: DaturaAudioMicrophone = $DaturaAudioMicrophone;
@onready var label: Label = $VBoxContainer/Label;
@onready var line_2d: Line2D = $Line2D;

var status : int = 0;

func _ready() -> void:
	%ListenningCheckButton.button_pressed = datura_audio_microphone.listenning;
	%PlayingCheckButton.button_pressed = datura_audio_microphone.playing;
	status = %StatusButton.selected;

func _on_start_button_pressed() -> void:
	if (status == 0) : 
		datura_audio_microphone.create_client(%AddressLineEdit.text ,%PortLineEdit.text.to_int());
	elif (status == 1) : 
		datura_audio_microphone.create_server(%PortLineEdit.text.to_int());
	label.text = "Success" if (datura_audio_microphone.is_network_connected()) else "Faild";

func _on_stop_button_pressed() -> void:
	datura_audio_microphone.network_disconnect();
	label.text = "Disconnected";

func _process(_delta: float) -> void:
	%StartButton.disabled = (datura_audio_microphone.is_network_connected());
	%StopButton.disabled = !%StartButton.disabled;
	
	var buffer : PackedFloat32Array = datura_audio_microphone.get_audio_buffer();
	if (!buffer.is_empty()) :
		var delta : float = get_viewport_rect().size.x / buffer.size();
		line_2d.clear_points();
		var xpos : float = 0.0;
		for i : float in buffer : 
			line_2d.add_point(Vector2(xpos, i * 50.0));
			xpos += delta;
	
	%FPSLabel.text = str(Engine.get_frames_per_second());

func _on_status_button_item_selected(index: int) -> void:
	status = index;


func _on_listenning_check_button_pressed() -> void:
	datura_audio_microphone.listenning = %ListenningCheckButton.button_pressed;

func _on_playing_check_button_toggled(toggled_on: bool) -> void:
	datura_audio_microphone.playing = %PlayingCheckButton.button_pressed;
