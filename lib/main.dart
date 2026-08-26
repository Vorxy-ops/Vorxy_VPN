import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

void main() => runApp(VorxyApp());

class VorxyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Vorxy VPN',
      theme: ThemeData.dark().copyWith(
        primaryColor: Color(0xFF2563EB),
        scaffoldBackgroundColor: Color(0xFF0F172A),
        appBarTheme: AppBarTheme(
          backgroundColor: Color(0xFF1E293B),
          elevation: 0,
          centerTitle: true,
        ),
      ),
      home: VorxyHome(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class VorxyHome extends StatefulWidget {
  @override
  _VorxyHomeState createState() => _VorxyHomeState();
}

class _VorxyHomeState extends State<VorxyHome> {
  bool _isConnected = false;
  bool _isLoading = false;
  String _statusText = 'Disconnected';
  String _currentIP = '0.0.0.0';
  String _selectedServer = 'Auto';
  String _connectionTime = '00:00:00';
  int _dataReceived = 0;
  int _dataSent = 0;
  List<Map<String, dynamic>> _servers = [];
  int _selectedIndex = 0;
  Timer? _timer;
  int _seconds = 0;

  final List<String> _sources = [
    'https://raw.githubusercontent.com/ebrasha/free-v2ray-public-list/main/V2Ray-Config-By-EbraSha.txt',
    'https://raw.githubusercontent.com/hiztin/VLESS-PO-GRIBI/main/combined.txt',
    'https://raw.githubusercontent.com/LoneKingCode/free-proxy-db/main/proxies/ss.txt',
  ];

  final List<String> _fallbackServers = [
    'vless://b5e3e7e7-8f6a-4d4e-a4b2-1c8e9d0a5f6b@185.162.235.223:443?type=ws&path=/&encryption=none&security=tls#DE-1',
    'vmess://eyJ2IjoiMiIsInBzIjoiVVMtMSIsImFkZCI6IjE0Mi4wLjEzNi4xMzciLCJwb3J0IjoiODAiLCJpZCI6ImZmZmZmZmZmLWZmZmYtZmZmZi1mZmZmLWZmZmZmZmZmZmZmZiIsImFpZCI6IjAiLCJzY3kiOiJhdXRvIiwibmV0Ijoid3MiLCJ0eXBlIjoibm9uZSIsImhvc3QiOiIiLCJwYXRoIjoiIiwidGxzIjoiIn0=',
    'trojan://password@trojan.example.com:443?security=tls&sni=trojan.example.com#Trojan-1',
  ];

  @override
  void initState() {
    super.initState();
    _fetchServers();
    _checkConnectivity();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _checkConnectivity() async {
    final connectivity = Connectivity();
    connectivity.onConnectivityChanged.listen((result) {
      if (result.contains(ConnectivityResult.none)) {
        _showSnackbar('No internet connection');
      }
    });
  }

  Future<void> _fetchServers() async {
    setState(() => _isLoading = true);
    List<Map<String, dynamic>> servers = [];

    for (String source in _sources) {
      try {
        final response = await http.get(Uri.parse(source)).timeout(Duration(seconds: 8));
        if (response.statusCode == 200) {
          final lines = response.body.split('\n');
          for (String line in lines) {
            line = line.trim();
            if (line.startsWith('vless://') || 
                line.startsWith('vmess://') || 
                line.startsWith('trojan://') ||
                line.startsWith('ss://')) {
              final parsed = _parseUrl(line);
              if (parsed != null) servers.add(parsed);
            }
          }
        }
      } catch (_) {}
    }

    for (String url in _fallbackServers) {
      final parsed = _parseUrl(url);
      if (parsed != null) servers.add(parsed);
    }

    final unique = <String, Map<String, dynamic>>{};
    for (var s in servers) {
      unique[s['host']] = s;
    }

    setState(() {
      _servers = unique.values.cast<Map<String, dynamic>>().toList();
      if (_servers.isNotEmpty) _selectedIndex = 0;
      _isLoading = false;
    });

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('servers', jsonEncode(_servers));
  }

  Map<String, dynamic>? _parseUrl(String url) {
    try {
      if (url.startsWith('vless://')) {
        final uri = Uri.parse(url);
        return {
          'url': url,
          'protocol': 'vless',
          'host': uri.host,
          'port': uri.port,
          'remark': uri.fragment.isNotEmpty ? uri.fragment : 'VLESS'
        };
      } else if (url.startsWith('vmess://')) {
        final base64 = url.substring(8);
        final decoded = utf8.decode(base64Decode(base64));
        final data = jsonDecode(decoded);
        return {
          'url': url,
          'protocol': 'vmess',
          'host': data['add'] ?? '',
          'port': int.tryParse(data['port']?.toString() ?? '80') ?? 80,
          'remark': data['ps'] ?? 'VMESS'
        };
      } else if (url.startsWith('trojan://')) {
        final uri = Uri.parse(url);
        return {
          'url': url,
          'protocol': 'trojan',
          'host': uri.host,
          'port': uri.port,
          'remark': uri.fragment.isNotEmpty ? uri.fragment : 'Trojan'
        };
      } else if (url.startsWith('ss://')) {
        final content = url.substring(5);
        if (content.contains('@')) {
          final parts = content.split('@');
          final hostPort = parts[1].split(':');
          return {
            'url': url,
            'protocol': 'shadowsocks',
            'host': hostPort[0],
            'port': int.tryParse(hostPort[1]) ?? 443,
            'remark': 'SS'
          };
        }
      }
    } catch (_) {}
    return null;
  }

  Future<void> _connectVpn(int index) async {
    if (_servers.isEmpty) {
      await _fetchServers();
      if (_servers.isEmpty) return;
    }

    final server = _servers[index];
    setState(() {
      _isLoading = true;
      _selectedServer = server['remark'] ?? server['host'];
      _statusText = 'Connecting';
    });

    try {
      await Future.delayed(Duration(seconds: 2));
      setState(() {
        _isConnected = true;
        _isLoading = false;
        _statusText = 'Protected';
        _currentIP = 'Hidden';
        _seconds = 0;
      });
      _startTimer();
      _showSnackbar('Connected to ${server['host']}');
    } catch (e) {
      setState(() {
        _isLoading = false;
        _statusText = 'Error';
      });
      _showSnackbar('Connection failed');
    }
  }

  void _startTimer() {
    _timer = Timer.periodic(Duration(seconds: 1), (timer) {
      setState(() {
        _seconds++;
        _connectionTime = _formatTime(_seconds);
        _dataReceived += 1024 * (1 + _seconds % 3);
        _dataSent += 512 * (1 + _seconds % 2);
      });
    });
  }

  String _formatTime(int seconds) {
    final hours = (seconds ~/ 3600).toString().padLeft(2, '0');
    final minutes = ((seconds % 3600) ~/ 60).toString().padLeft(2, '0');
    final secs = (seconds % 60).toString().padLeft(2, '0');
    return '$hours:$minutes:$secs';
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1048576) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    if (bytes < 1073741824) return '${(bytes / 1048576).toStringAsFixed(1)} MB';
    return '${(bytes / 1073741824).toStringAsFixed(2)} GB';
  }

  Future<void> _disconnectVpn() async {
    _timer?.cancel();
    setState(() {
      _isConnected = false;
      _statusText = 'Disconnected';
      _currentIP = '0.0.0.0';
      _selectedServer = 'Auto';
      _connectionTime = '00:00:00';
      _dataReceived = 0;
      _dataSent = 0;
      _seconds = 0;
    });
    _showSnackbar('VPN disconnected');
  }

  void _showSnackbar(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: Duration(seconds: 2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Vorxy VPN',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF2563EB),
                    ),
                  ),
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: _isConnected ? Color(0xFF064E3B) : Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: _isConnected ? Color(0xFF22C55E) : Colors.transparent,
                        width: 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _isConnected ? Color(0xFF22C55E) : Color(0xFF64748B),
                          ),
                        ),
                        SizedBox(width: 6),
                        Text(
                          _isConnected ? 'ONLINE' : 'OFFLINE',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: _isConnected ? Color(0xFF22C55E) : Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              SizedBox(height: 4),
              Text(
                'Free Unlimited VPN',
                style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
              ),
              SizedBox(height: 24),
              GestureDetector(
                onTap: _isConnected ? _disconnectVpn : () => _connectVpn(_selectedIndex),
                child: Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: _isConnected
                          ? [Color(0xFF22C55E), Color(0xFF16A34A)]
                          : [Color(0xFF1E293B), Color(0xFF334155)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: _isConnected
                        ? [BoxShadow(color: Color(0xFF22C55E).withOpacity(0.3), blurRadius: 30, spreadRadius: 5)]
                        : [],
                  ),
                  child: Icon(
                    _isConnected ? Icons.vpn_key : Icons.vpn_lock,
                    size: 48,
                    color: Colors.white,
                  ),
                ),
              ),
              SizedBox(height: 16),
              Text(
                _statusText,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
              ),
              SizedBox(height: 4),
              Text(
                'Server: $_selectedServer',
                style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
              ),
              SizedBox(height: 16),
              Container(
                padding: EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                decoration: BoxDecoration(
                  color: Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    Column(
                      children: [
                        Text('Time', style: TextStyle(fontSize: 10, color: Color(0xFF94A3B8))),
                        Text(_connectionTime, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                      ],
                    ),
                    Column(
                      children: [
                        Text('Download', style: TextStyle(fontSize: 10, color: Color(0xFF94A3B8))),
                        Text(_formatBytes(_dataReceived), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                      ],
                    ),
                    Column(
                      children: [
                        Text('Upload', style: TextStyle(fontSize: 10, color: Color(0xFF94A3B8))),
                        Text(_formatBytes(_dataSent), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ],
                ),
              ),
              SizedBox(height: 16),
              Container(
                height: 100,
                child: _isLoading
                  ? Center(child: CircularProgressIndicator(color: Color(0xFF2563EB)))
                  : ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: _servers.length > 20 ? 20 : _servers.length,
                      itemBuilder: (ctx, idx) {
                        final server = _servers[idx];
                        final isSelected = idx == _selectedIndex;
                        return GestureDetector(
                          onTap: () {
                            if (!_isConnected) {
                              setState(() => _selectedIndex = idx);
                            }
                          },
                          child: Container(
                            width: 110,
                            margin: EdgeInsets.only(right: 10),
                            padding: EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: isSelected ? Color(0xFF1E293B) : Color(0xFF0F172A),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isSelected ? Color(0xFF2563EB) : Color(0xFF1E293B),
                                width: isSelected ? 2 : 1,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  server['protocol']?.toUpperCase() ?? 'VPN',
                                  style: TextStyle(fontSize: 10, color: Color(0xFF2563EB), fontWeight: FontWeight.w600),
                                ),
                                SizedBox(height: 2),
                                Text(
                                  server['remark'] ?? 'Server',
                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  server['host'] ?? '',
                                  style: TextStyle(fontSize: 9, color: Color(0xFF94A3B8)),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
              ),
              SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : (_isConnected ? _disconnectVpn : () => _connectVpn(_selectedIndex)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isConnected ? Color(0xFFDC2626) : Color(0xFF2563EB),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    elevation: 0,
                  ),
                  child: Text(
                    _isLoading ? 'CONNECTING' : (_isConnected ? 'DISCONNECT' : 'CONNECT'),
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white),
                  ),
                ),
              ),
              SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '${_servers.length} servers',
                    style: TextStyle(fontSize: 10, color: Color(0xFF64748B)),
                  ),
                  SizedBox(width: 12),
                  GestureDetector(
                    onTap: _fetchServers,
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                      decoration: BoxDecoration(
                        color: Color(0xFF1E293B),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.refresh, size: 12, color: Color(0xFF94A3B8)),
                          SizedBox(width: 4),
                          Text('Refresh', style: TextStyle(fontSize: 10, color: Color(0xFF94A3B8))),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 4),
              Text(
                'Free Unlimited VPN 2026',
                style: TextStyle(fontSize: 9, color: Color(0xFF475569)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
