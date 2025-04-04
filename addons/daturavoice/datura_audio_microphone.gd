## 用于DaturaAudio的网络麦克风节点
@icon("./icons/datura_audio_microphone_icon.svg")
class_name DaturaAudioMicrophone extends Node;

var _record_effect : AudioEffectCapture = null; # 音频总线中的捕获器音效
var _microphone_audio_player : AudioStreamPlayer = null; # 用于接收麦克风音频的节点
var _audio_generator_player : AudioStreamPlayer = null; # 音频构造器节点
var _audio_generator_playback : AudioStreamGeneratorPlayback = null; # 音频构造器回放对象
var _audio_receive_buffer : PackedFloat32Array = []; # 接收到的音频缓冲区
var _udp_service : Node = null; # Daturavoice UDP服务

@export var playing : bool = true; ## 是否将接收的数据播放出来
@export var listenning : bool = true; ## 是否监听麦克风输入
@export var input_threshold : float = 0.005; ## 声音输入的阈值,低于阈值的声音数据包将不会被传输
@export var bus : StringName = &"Master";  ## 声音输出的音频总线

func push_voice_local(data : PackedByteArray) -> void : 
	if (playing) : 
		_audio_receive_buffer.append_array(data.to_float32_array());
	# 向本地音频播放设备推送数据

func get_audio_buffer() -> PackedFloat32Array : ## 获得音频播放缓冲区的副本
	return _audio_receive_buffer.duplicate();

func create_server(port : int) -> void : ## 启用网络并创建服务器
	if (is_network_connected()) : return;
	_udp_service.create_server(port);

func create_client(address : String, port : int) -> void : ## 启用网络并创建客户端
	if (is_network_connected()) : return;
	_udp_service.create_client(address, port);

func is_network_connected() -> bool : ## 判断网络是否连接
	return _udp_service.is_socket_connected();

func network_disconnect() -> void : 
	_udp_service.socket_disconnect();

func _init() -> void : 
	pass;

func _ready() -> void : 
	var record_bus_index : int = AudioServer.bus_count;
	AudioServer.add_bus(record_bus_index);
	AudioServer.set_bus_mute(record_bus_index, true);
	var bus_name : String = "DaturaMicrophoneBus" + str(self.get_instance_id());
	if (AudioServer.get_bus_index(bus_name) == -1) : AudioServer.set_bus_name(record_bus_index, bus_name);
	else : 
		var _ind : int = 0;
		var _name : String = bus_name + "-";
		while (AudioServer.get_bus_index(_name + str(_ind))) : 
			_ind += 1;
			AudioServer.set_bus_name(record_bus_index, _name + str(_ind));
	# 建立音频总线
	
	var record_effect_index : int = AudioServer.get_bus_effect_count(record_bus_index);
	_record_effect = AudioEffectCapture.new();
	AudioServer.add_bus_effect(record_bus_index, _record_effect, record_effect_index);
	# 添加捕获器
	
	if (! is_instance_valid(_microphone_audio_player)) : 
		_microphone_audio_player = AudioStreamPlayer.new();
		_microphone_audio_player.stream = AudioStreamMicrophone.new();
		_microphone_audio_player.bus = AudioServer.get_bus_name(record_bus_index);
		self.add_child(_microphone_audio_player);
		_microphone_audio_player.play();
		# 新建麦克风输入节点
	
	if (! is_instance_valid(_audio_generator_player)) : 
		_audio_generator_player = AudioStreamPlayer.new();
		_audio_generator_player.stream = AudioStreamGenerator.new();
		self.add_child(_audio_generator_player);
		_audio_generator_player.play();
		_audio_generator_playback = _audio_generator_player.get_stream_playback();
		# 新建扬声器输出节点
	
	_udp_service = preload("./udp_service/daturavoice_udpsocket.gd").new();
	_udp_service.recived_data.connect(__push_voice_dv);
	self.add_child(_udp_service);
	# 初始化Datura网络系统

func _process(_delta: float) -> void : 
	if (_udp_service.is_socket_connected()) : 
		if (listenning) : 
			_process_record();
		_process_voice();

func _process_record() -> void : 
	var frames_available : int = _record_effect.get_frames_available();
	if (frames_available > 0) : 
		var buffer : PackedVector2Array = _record_effect.get_buffer(frames_available);
		var mono_pack : PackedFloat32Array = [];
		mono_pack.resize(frames_available);
		
		var value : Vector2;
		var max_value = -INF;
		var i = 0;
		while(i < frames_available) :  
			value = buffer[i];
			mono_pack[i] = (value.x + value.y) / 2.0;
			if (value.x > max_value) : max_value = value.x;
			i += 1;
		
		if (max_value > input_threshold) : 
			#self.rpc("__push_voice_rpc", mono_pack.to_byte_array());
			var a= mono_pack.to_byte_array();
			_udp_service.send_multicast(a);
			pass;

func _process_voice() : 
	var frames_available : int = _audio_generator_playback.get_frames_available();
	if (_audio_receive_buffer.size() > 0 && frames_available > 1) : 
		_audio_generator_player.bus = bus;
		var ind : int = 0;
		var push_count : int = min(frames_available, _audio_receive_buffer.size());
		while (ind < push_count) : 
			_audio_generator_playback.push_frame(Vector2(_audio_receive_buffer[ind], _audio_receive_buffer[ind]));
			ind += 1;
		_audio_receive_buffer.clear();

@rpc("any_peer", "call_remote")
func __push_voice_rpc(data : PackedByteArray) -> void : 
	push_voice_local(data);
	# RPC::以客户端身份向网络服务器推送数据

func __push_voice_dv(data : PackedByteArray) -> void : 
	push_voice_local(data);
	# UDP-DV::以客户端身份向网络服务器推送数据
#yanxiyimeng.top
