@tool
extends EditorPlugin;

const DATURA_AUDIO_MICROPHONE_SCRIPT : GDScript = preload("./datura_audio_microphone.gd");
const DATURA_AUDIO_MICROPHONE_ICON : Texture2D = preload("./icons/datura_audio_microphone_icon.svg");

var per_audio_driver_enable_input : bool = false;

func _enter_tree() -> void : 
	add_custom_type("DaturaAudioMicrophone", "Node", DATURA_AUDIO_MICROPHONE_SCRIPT, \
			DATURA_AUDIO_MICROPHONE_ICON);
	per_audio_driver_enable_input = (ProjectSettings.get("audio/driver/enable_input"));
	ProjectSettings.set("audio/driver/enable_input", true);
	

func _exit_tree() -> void:
	remove_custom_type("DaturaAudioMicrophone");
	ProjectSettings.set("audio/driver/enable_input", per_audio_driver_enable_input);
