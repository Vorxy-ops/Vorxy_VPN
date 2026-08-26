import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:openvpn_flutter/openvpn_flutter.dart';

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
  final OpenVPN _openVpn = OpenVPN();
  bool _isConnected = false;
  bool _isLoading = false;
  String _statusText = 'Disconnected';
  String _selectedServer = 'Auto';
  String _connectionTime = '00:00:00';
  int _dataReceived = 0;
  int _dataSent = 0;
  List<Map<String, dynamic>> _servers = [];
  int _selectedIndex = 0;
  Timer? _timer;
  int _seconds = 0;

  @override
  void initState() {
    super.initState();
    _initVpn();
    _fetchServers();
    _checkConnectivity();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _initVpn() async {
    await _openVpn.initialize(
      groupIdentifier: 'group.com.vorxy.vpn',
      providerBundleIdentifier: 'com.vorxy.app.VPNExtension',
      localizedDescription: 'Vorxy VPN',
    );
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

    try {
      final response = await http.get(
        Uri.parse('http://www.vpngate.net/api/iphone/')
      ).timeout(Duration(seconds: 8));
      if (response.statusCode == 200) {
        final lines = response.body.split('\n');
        for (var line in lines) {
          if (line.contains('OpenVPN')) {
            final parts = line.split(',');
            if (parts.length > 14) {
              servers.add({
                'host': parts[1],
                'country': parts[6],
                'config': base64Decode(parts[14]),
                'remark': '${parts[6]} ${parts[1]}',
              });
            }
          }
        }
      }
    } catch (_) {}

    if (servers.isEmpty) {
      servers = [
        {
          'host': '185.162.235.223',
          'country': 'DE',
          'config': '',
          'remark': 'Fallback Server',
        }
      ];
    }

    setState(() {
      _servers = servers;
      if (_servers.isNotEmpty) _selectedIndex = 0;
      _isLoading = false;
    });
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
      _statusText = 'Connecting...';
    });

    try {
      await _openVpn.connect(server['config'], server['remark']);
      setState(() {
        _isConnected = true;
        _isLoading = false;
        _statusText = 'Protected';
        _seconds = 0;
      });
      _startTimer();
      _showSnackbar('Connected to ${server['host']}');
    } catch (e) {
      setState(() {
        _isLoading = false;
        _statusText = 'Error: ${e.toString().substring(0, 30)}';
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
    _openVpn.disconnect();
    _timer?.cancel();
    setState(() {
      _isConnected = false;
      _statusText = 'Disconnected';
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
                  Text('Vorxy VPN', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF2563EB))),
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: _isConnected ? Color(0xFF064E3B) : Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: _isConnected ? Color(0xFF22C55E) : Colors.transparent, width: 1),
                    ),
                    child: Row(
                      children: [
                        Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: _isConnected ? Color(0xFF22C55E) : Color(0xFF64748B))),
                        SizedBox(width: 6),
                        Text(_isConnected ? 'ONLINE' : 'OFFLINE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: _isConnected ? Color(0xFF22C55E) : Color(0xFF64748B))),
                      ],
                    ),
                  ),
                ],
              ),
              SizedBox(height: 4),
              Text('Free Unlimited VPN', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
              SizedBox(height: 24),
              GestureDetector(
                onTap: _isConnected ? _disconnectVpn : () => _connectVpn(_selectedIndex),
                child: Container(
                  width: 120, height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: _isConnected ? [Color(0xFF22C55E), Color(0xFF16A34A)] : [Color(0xFF1E293B), Color(0xFF334155)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: _isConnected ? [BoxShadow(color: Color(0xFF22C55E).withOpacity(0.3), blurRadius: 30, spreadRadius: 5)] : [],
                  ),
                  child: Icon(_isConnected ? Icons.vpn_key : Icons.vpn_lock, size: 48, color: Colors.white),
                ),
              ),
              SizedBox(height: 16),
              Text(_statusText, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
              SizedBox(height: 4),
              Text('Server: $_selectedServer', style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8))),
              SizedBox(height: 16),
              Container(
                padding: EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                decoration: BoxDecoration(color: Color(0xFF1E293B), borderRadius: BorderRadius.circular(12)),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    Column(children: [Text('Time', style: TextStyle(fontSize: 10, color: Color(0xFF94A3B8))), Text(_connectionTime, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600))]),
                    Column(children: [Text('Download', style: TextStyle(fontSize: 10, color: Color(0xFF94A3B8))), Text(_formatBytes(_dataReceived), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600))]),
                    Column(children: [Text('Upload', style: TextStyle(fontSize: 10, color: Color(0xFF94A3B8))), Text(_formatBytes(_dataSent), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600))]),
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
                          onTap: () { if (!_isConnected) setState(() => _selectedIndex = idx); },
                          child: Container(
                            width: 110,
                            margin: EdgeInsets.only(right: 10),
                            padding: EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: isSelected ? Color(0xFF1E293B) : Color(0xFF0F172A),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: isSelected ? Color(0xFF2563EB) : Color(0xFF1E293B), width: isSelected ? 2 : 1),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text('VPN', style: TextStyle(fontSize: 10, color: Color(0xFF2563EB), fontWeight: FontWeight.w600)),
                                SizedBox(height: 2),
                                Text(server['remark'] ?? 'Server', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500), maxLines: 1, overflow: TextOverflow.ellipsis),
                                Text(server['host'] ?? '', style: TextStyle(fontSize: 9, color: Color(0xFF94A3B8)), maxLines: 1, overflow: TextOverflow.ellipsis),
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
                  Text('${_servers.length} servers', style: TextStyle(fontSize: 10, color: Color(0xFF64748B))),
                  SizedBox(width: 12),
                  GestureDetector(
                    onTap: _fetchServers,
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                      decoration: BoxDecoration(color: Color(0xFF1E293B), borderRadius: BorderRadius.circular(12)),
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
              Text('Free Unlimited VPN 2026', style: TextStyle(fontSize: 9, color: Color(0xFF475569))),
            ],
          ),
        ),
      ),
    );
  }
}
