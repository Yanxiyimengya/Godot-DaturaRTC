extends Node

# 专门用于以UDP形式传播数据的UDP服务

signal recived_data(data : PackedByteArray);
signal disconnect();

enum ProtocolType {
	HEARTBEAT = 1, # 心跳
	CONNECT, # 登入
	DISCONNECT, # 断开
	DATA, # 数据传递
	MULTICAST, # 来自客户端的多播请求
	ACK, # 确认信息
}; # 协议类型枚举
enum StatusCode {
	OK = 200,          # 操作成功
	INVALID_ID = 400,  # 无效客户端ID
	DUPLICATE = 409,   # 重复注册
	TIMEOUT = 408      # 心跳超时
}; # 协议状态码
enum SocketType { 
	CLIENT,
	SERVER,
}; # 套接字类型

@export_range(0.25, 10.0, 0.01) var client_timeout_time : float = 3.0;
## 客户端超时时间,这影响此对象做为客户端时发送心跳包的频率和此对象作为服务端的心跳检测时间

var _udp_peer : PacketPeerUDP = null; # 底层套接字
var _socket_type : SocketType = SocketType.CLIENT; # 套接字类型
var _heartbeat_timer : float = 0.0; # 心跳检测计时器
var _network_clients_list : Dictionary = {}; # 作为服务器时,连接的客户端列表
var _network_server_ip : Array = []; # 作为客户端时,连接的服务端IP
var _connecting : bool = false; # 连接有效性
var _reusable_protocol : Protocol = Protocol.new(); # 复用协议对象
var _send_sequence_number : int = 0; # 发送数据包的序列号
var _max_record_size = 255; # 最大记录数量
var _received_sequence_numbers : Dictionary = {}; # 已收到的数据包序列号
var _unacknowledged_packets : Dictionary = {}; # 未确认的数据包
var _ack_timeout : float = 1.0; # 确认超时时间
var _ack_timer : float = 0.0; # 确认计时器

func create_server(port : int) -> bool : 
	if (_connecting) : return false;
	_socket_type = SocketType.SERVER;
	_network_clients_list.clear();
	_udp_peer.bind(port);
	_connecting = true;
	return true;


func create_client(address : StringName, port : int) -> bool : 
	if (_connecting) : return false;
	_socket_type = SocketType.CLIENT;
	_network_server_ip = [address, port];
	var bind_err = _udp_peer.bind(0);
	if (bind_err != OK):
		_udp_peer.close();
		return false;
	_prepare_protocol(ProtocolType.CONNECT, 0, PackedByteArray());
	send_protocol(_reusable_protocol, address, port);
	_connecting = true;
	return true;


func send_protocol(protocol: Protocol, address: String, port: int) -> bool:
	var packet = _build_packet(protocol);
	_udp_peer.set_dest_address(address, port);
	if (protocol.type == ProtocolType.DATA) :
		_unacknowledged_packets[_send_sequence_number] = {
			"packet": packet,
			"send_time": Time.get_ticks_msec() / 1000.0
		};
		_send_sequence_number += 1;
		_cleanup_unacknowledged_packets();
	return _udp_peer.put_packet(packet) == OK;


func send_data(data : PackedByteArray, address : String, port: int) -> bool:
	_prepare_protocol(ProtocolType.DATA, 0, data);
	return send_protocol(_reusable_protocol, address, port);


func send_multicast(data : PackedByteArray, excludes : Array = []) -> bool :
	if (_connecting) :  
		match (_socket_type) : 
			SocketType.CLIENT : 
				_prepare_protocol(ProtocolType.MULTICAST, 0, data);
				send_protocol(_reusable_protocol, _network_server_ip[0], _network_server_ip[1]);
			SocketType.SERVER : 
				_prepare_protocol(ProtocolType.DATA, 0, data);
				for client_key in _network_clients_list.keys():
					if (client_key in excludes) : continue;
					var client_info = client_key.split(":");
					send_protocol(_reusable_protocol, client_info[0], int(client_info[1]));
		return true;
	return false;


func is_socket_connected() -> bool : 
	return _connecting;


func _ready() -> void : 
	_udp_peer = PacketPeerUDP.new();


func _exit_tree() -> void:
	socket_disconnect();


func _process(delta: float) -> void : 
	if (_connecting) :
		match (_socket_type) :
			SocketType.CLIENT :  
				if (_heartbeat_timer <= 0.0) : 
					_heartbeat_timer = (client_timeout_time*0.5);
					_prepare_protocol(ProtocolType.HEARTBEAT, 0, PackedByteArray())
					send_protocol(_reusable_protocol, _network_server_ip[0], _network_server_ip[1]);
				else : _heartbeat_timer -= delta;
				
				if (_ack_timer <= 0.0) :
					_ack_timer = _ack_timeout;
					for sequence_number in _unacknowledged_packets.keys() : 
						var packet_info = _unacknowledged_packets[sequence_number];
						var packet = packet_info["packet"];
						_udp_peer.put_packet(packet);
					_cleanup_unacknowledged_packets();
					_cleanup_received_numbers();
				else : _ack_timer -= delta; # 每秒检测一次未被服务器确认数据包
				
				
				while (_udp_peer.get_available_packet_count() > 0) : 
					var packet : PackedByteArray = _udp_peer.get_packet();
					var _protocol : Protocol = _parse_protocol(packet);
					
					if (_protocol.type == ProtocolType.DATA) : 
						_handle_data_packet(_protocol, _udp_peer.get_packet_ip(), _udp_peer.get_packet_port());
						_send_ack(_protocol, _udp_peer.get_packet_ip(), _udp_peer.get_packet_port());
					elif (_protocol.type == ProtocolType.DISCONNECT) : 
						_connecting = false;
						disconnect.emit();
						socket_disconnect();
					elif (_protocol.type == ProtocolType.ACK) : 
						var sequence_number = _get_sequence_number(_protocol.content);
						if (_unacknowledged_packets.has(sequence_number)) :
							_unacknowledged_packets.erase(sequence_number);
						# 处理确认包协议
			SocketType.SERVER : 
				
				if (_heartbeat_timer <= 0.0) : 
					_heartbeat_timer = 1.0;
					var current_time = Time.get_ticks_msec() / 1000.0;
					var remove_keys = [];
					for client_key in _network_clients_list.keys() :
						if (current_time - _network_clients_list[client_key]["last_heartbeat"] > client_timeout_time) :
							remove_keys.append(client_key);
					for key in remove_keys:
						server_remove_client(key);
					_cleanup_received_numbers();
				else : _heartbeat_timer -= delta;
				
				while (_udp_peer.get_available_packet_count() > 0) : 
					var packet : PackedByteArray = _udp_peer.get_packet();
					var _protocol : Protocol = _parse_protocol(packet);
					if (_protocol == null) : continue;
					
					var packet_ip : String = _udp_peer.get_packet_ip();
					var packet_port : int = _udp_peer.get_packet_port();
					var client_key : StringName = &"%s:%d" % [packet_ip, packet_port];
					
					if ( !(client_key in _network_clients_list)) : 
						if (_protocol.type == ProtocolType.CONNECT) : 
							_network_clients_list[client_key] = {
								"last_heartbeat" : Time.get_ticks_msec() / 1000.0,
							};
					else : 
						if (_protocol.type == ProtocolType.DISCONNECT) : 
							_network_clients_list.erase(client_key);
						elif (_protocol.type == ProtocolType.HEARTBEAT) : 
							_network_clients_list[client_key]["last_heartbeat"] = Time.get_ticks_msec() / 1000.0;
						elif (_protocol.type == ProtocolType.DATA) : 
							_handle_data_packet(_protocol, packet_ip, packet_port);
							_send_ack(_protocol, packet_ip, packet_port);
						elif (_protocol.type == ProtocolType.MULTICAST) : 
							send_multicast(_protocol.content, [client_key]);
							recived_data.emit(_protocol.content);
						elif (_protocol.type == ProtocolType.ACK) : 
							var sequence_number = _get_sequence_number(_protocol.content);
							if (_unacknowledged_packets.has(sequence_number)) :
								_unacknowledged_packets.erase(sequence_number);
							# 处理确认包协议

func _handle_data_packet(protocol: Protocol, address: String, port: int) -> void :
	var sequence_number = _get_sequence_number(protocol.content);
	if (! _received_sequence_numbers.has(sequence_number)) :
		_received_sequence_numbers[sequence_number] = true;
		var data = _remove_sequence_number(protocol.content);
		recived_data.emit(data);
	# 处理数据包协议

func _send_ack(protocol: Protocol, address: String, port: int) -> void :
	var sequence_number = _get_sequence_number(protocol.content);
	_prepare_protocol(ProtocolType.ACK, 0, _add_sequence_number(PackedByteArray(), sequence_number));
	send_protocol(_reusable_protocol, address, port);
	# 发送确认包

func socket_disconnect() -> void : ## 将当前Socket移除连接
	if (_connecting) :
		_prepare_protocol(ProtocolType.DISCONNECT, 0, PackedByteArray());
		match (_socket_type) :
			SocketType.CLIENT :  
				send_protocol(_reusable_protocol, _network_server_ip[0], _network_server_ip[1]);
			SocketType.SERVER :  
				for client_key : StringName in _network_clients_list : 
					var client_info : PackedStringArray = client_key.split(":");
					send_protocol(_reusable_protocol, client_info[0], int(client_info[1]));
		_connecting = false;
	_udp_peer.close();


func server_remove_client(client_key : StringName) -> bool : ## 服务器指定将当前Socket移除连接
	if (_socket_type == SocketType.SERVER) : 
		if (_connecting) :  
			if (client_key in _network_clients_list) : 
				_prepare_protocol(ProtocolType.DISCONNECT, 0, PackedByteArray());
				var client_info : PackedStringArray = client_key.split(":");
				send_protocol(_reusable_protocol, client_info[0], int(client_info[1]));
				_network_clients_list.erase(client_key);
				return true;
	return false;

func _build_packet(protocol: Protocol) -> PackedByteArray:
	var packet = PackedByteArray();
	packet.resize(2);
	packet.encode_u8(0, protocol.type); 
	packet.encode_u8(1, protocol.status_code); 
	packet.append_array(protocol.content);
	return packet;

func _parse_protocol(content : PackedByteArray) -> Protocol:
	if (content.size() < 2) :
		return null;
	var protocol = Protocol.new();
	protocol.type = content[0] as ProtocolType;
	protocol.status_code = content[1] as StatusCode;
	if (content.size() > 2) :
		protocol.content = content.slice(2, content.size());
	return protocol;


func _prepare_protocol(type: ProtocolType, status_code: StatusCode, content: PackedByteArray) -> void:
	_reusable_protocol.type = type;
	_reusable_protocol.status_code = status_code;
	_reusable_protocol.content = content;
	# 重用数据包

func _get_sequence_number(data: PackedByteArray) -> int :
	if (data.size() >= 4) :
		return data.slice(0, 4).decode_u32(0);
	return 0;
	# 获取数据包的序号

func _add_sequence_number(data: PackedByteArray, sequence_number: int) -> PackedByteArray :
	var new_data = PackedByteArray();
	new_data.resize(4);
	new_data.encode_s32(0, sequence_number);
	new_data.append_array(data);
	return new_data;
	# 将数据包头部添加序号

func _remove_sequence_number(data: PackedByteArray) -> PackedByteArray :
	if (data.size() >= 4) :
		return data.slice(4, data.size());
	return data;
	# 移除数据包头部的序号

func _cleanup_unacknowledged_packets() -> void:
	var current_time = Time.get_ticks_msec() / 1000.0;
	var remove_keys = [];
	for sequence_number in _unacknowledged_packets.keys() :
		var packet_info = _unacknowledged_packets[sequence_number];
		if (current_time - packet_info["send_time"] > _ack_timeout * 3) :
			remove_keys.append(sequence_number);
	for key in remove_keys:
		_unacknowledged_packets.erase(key);
	while (_unacknowledged_packets.size() > _max_record_size) :
		var oldest_key = _unacknowledged_packets.keys()[0];
		_unacknowledged_packets.erase(oldest_key);

func _cleanup_received_numbers() -> void:
	while (_received_sequence_numbers.size() > _max_record_size) :
		var oldest_key = _received_sequence_numbers.keys()[0];
		_received_sequence_numbers.erase(oldest_key);

class Protocol :
	extends RefCounted;
	var type : ProtocolType = 0; 
	var status_code : StatusCode = 0; 
	var content : PackedByteArray = [];     
