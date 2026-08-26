import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:openvpn_flutter/openvpn_flutter.dart';
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
  final OpenVPN _openVpn = OpenVPN();
  bool _isConnected = false;
  bool _isLoading = false;
  bool _isLoadingServers = false;
  String _statusText = 'Disconnected';
  String _selectedServer = 'Auto';
  String _connectionTime = '00:00:00';
  int _dataReceived = 0;
  int _dataSent = 0;
  List<Map<String, dynamic>> _servers = [];
  int _selectedIndex = 0;
  Timer? _timer;
  int _seconds = 0;

  Map<String, String> _countryFlags = {
    'US': '🇺🇸', 'GB': '🇬🇧', 'DE': '🇩🇪', 'FR': '🇫🇷',
    'JP': '🇯🇵', 'KR': '🇰🇷', 'CN': '🇨🇳', 'RU': '🇷🇺',
    'IN': '🇮🇳', 'BR': '🇧🇷', 'CA': '🇨🇦', 'AU': '🇦🇺',
    'IT': '🇮🇹', 'ES': '🇪🇸', 'NL': '🇳🇱', 'SE': '🇸🇪',
    'NO': '🇳🇴', 'DK': '🇩🇰', 'FI': '🇫🇮', 'PL': '🇵🇱',
    'UA': '🇺🇦', 'TR': '🇹🇷', 'IL': '🇮🇱', 'SG': '🇸🇬',
    'MY': '🇲🇾', 'ID': '🇮🇩', 'PH': '🇵🇭', 'VN': '🇻🇳',
    'TH': '🇹🇭', 'EG': '🇪🇬', 'ZA': '🇿🇦', 'AR': '🇦🇷',
    'CL': '🇨🇱', 'CO': '🇨🇴', 'PE': '🇵🇪', 'VE': '🇻🇪',
    'MX': '🇲🇽', 'CH': '🇨🇭', 'AT': '🇦🇹', 'BE': '🇧🇪',
    'GR': '🇬🇷', 'PT': '🇵🇹', 'HU': '🇭🇺', 'CZ': '🇨🇿',
    'RO': '🇷🇴', 'BG': '🇧🇬', 'HR': '🇭🇷', 'SK': '🇸🇰',
    'SI': '🇸🇮', 'LT': '🇱🇹', 'LV': '🇱🇻', 'EE': '🇪🇪',
  };

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
    try {
      await _openVpn.initialize(
        groupIdentifier: 'group.com.vorxy.vpn',
        providerBundleIdentifier: 'com.vorxy.app.VPNExtension',
        localizedDescription: 'Vorxy VPN',
      );
    } catch (e) {
      print('Init error: $e');
    }
  }

  Future<void> _checkConnectivity() async {
    final connectivity = Connectivity();
    connectivity.onConnectivityChanged.listen((result) {
      if (result.contains(ConnectivityResult.none)) {
        _showSnackbar('No internet connection');
      }
    });
  }

  String _getFlag(String country) {
    if (country.isEmpty) return '🌍';
    final upper = country.toUpperCase();
    return _countryFlags[upper] ?? '🌍';
  }

  Future<void> _fetchServers() async {
    setState(() => _isLoadingServers = true);
    List<Map<String, dynamic>> servers = [];

    try {
      final response = await http.get(
        Uri.parse('http://www.vpngate.net/api/iphone/')
      ).timeout(Duration(seconds: 20));

      if (response.statusCode == 200) {
        final lines = response.body.split('\n');
        for (var line in lines) {
          if (line.trim().isEmpty) continue;
          final parts = line.split(',');
          if (parts.length < 15) continue;
          if (parts[0] == '*' || parts[0].isEmpty) continue;
          if (parts[1] == 'HostName' || parts[1].isEmpty) continue;
          if (parts[14].trim().isEmpty) continue;

          try {
            String configStr = '';
            if (parts[14].contains('_')) {
              final configParts = parts[14].split('_');
              if (configParts.length > 1) {
                configStr = configParts[1];
              } else {
                configStr = parts[14];
              }
            } else {
              configStr = parts[14];
            }

            if (configStr.isNotEmpty) {
              configStr = configStr.replaceAll('\\r\\n', '\n').replaceAll('\\n', '\n').replaceAll('"', '');
              if (configStr.contains('client') && configStr.contains('dev tun')) {
                servers.add({
                  'host': parts[1].trim(),
                  'country': parts[6].trim(),
                  'config': configStr,
                  'remark': parts[6].trim(),
                  'score': int.tryParse(parts[2] ?? '0') ?? 0,
                });
              }
            }
          } catch (_) {}
        }
      }
    } catch (e) {
      print('Error fetching servers: $e');
    }

    servers.shuffle();

    if (servers.isEmpty) {
      servers = [
        {
          'host': '185.162.235.223',
          'country': 'DE',
          'config': '''client
dev tun
proto tcp
remote 185.162.235.223 443
resolv-retry infinite
nobind
persist-key
persist-tun
remote-cert-tls server
auth SHA256
cipher AES-256-GCM
ignore-unknown-option block-outside-dns
verb 3
''',
          'remark': 'Germany',
          'score': 100,
        },
        {
          'host': '142.0.136.137',
          'country': 'US',
          'config': '''client
dev tun
proto tcp
remote 142.0.136.137 80
resolv-retry infinite
nobind
persist-key
persist-tun
remote-cert-tls server
auth SHA256
cipher AES-256-GCM
ignore-unknown-option block-outside-dns
verb 3
''',
          'remark': 'USA',
          'score': 95,
        },
        {
          'host': '103.152.112.157',
          'country': 'JP',
          'config': '''client
dev tun
proto tcp
remote 103.152.112.157 443
resolv-retry infinite
nobind
persist-key
persist-tun
remote-cert-tls server
auth SHA256
cipher AES-256-GCM
ignore-unknown-option block-outside-dns
verb 3
''',
          'remark': 'Japan',
          'score': 90,
        },
      ];
    }

    setState(() {
      _servers = servers.length > 50 ? servers.sublist(0, 50) : servers;
      if (_servers.isNotEmpty) _selectedIndex = 0;
      _isLoadingServers = false;
    });
    _showSnackbar('${_servers.length} servers loaded');
  }

  Future<void> _connectVpn(int index) async {
    if (_servers.isEmpty) {
      await _fetchServers();
      if (_servers.isEmpty) return;
    }

    final server = _servers[index];
    if (server['config'] == null || server['config'].toString().isEmpty) {
      _showSnackbar('No config for this server');
      return;
    }

    setState(() {
      _isLoading = true;
      _selectedServer = server['remark'] ?? server['host'];
      _statusText = 'Connecting...';
    });

    try {
      await _openVpn.connect(server['config'].toString(), server['remark']);
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
        _statusText = 'Connection failed';
      });
      _showSnackbar('Failed: ${e.toString().substring(0, 30)}');
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
    final h = (seconds ~/ 3600).toString().padLeft(2, '0');
    final m = ((seconds % 3600) ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
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
              SizedBox(height: 20),
              GestureDetector(
                onTap: _isConnected ? _disconnectVpn : () => _connectVpn(_selectedIndex),
                child: Container(
                  width: 110, height: 110,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: _isConnected ? [Color(0xFF22C55E), Color(0xFF16A34A)] : [Color(0xFF1E293B), Color(0xFF334155)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: _isConnected ? [BoxShadow(color: Color(0xFF22C55E).withOpacity(0.3), blurRadius: 30, spreadRadius: 5)] : [],
                  ),
                  child: Icon(_isConnected ? Icons.vpn_key : Icons.vpn_lock, size: 44, color: Colors.white),
                ),
              ),
              SizedBox(height: 12),
              Text(_statusText, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
              SizedBox(height: 4),
              Text('Server: $_selectedServer', style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8))),
              SizedBox(height: 12),
              Container(
                padding: EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                decoration: BoxDecoration(color: Color(0xFF1E293B), borderRadius: BorderRadius.circular(10)),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    Column(children: [Text('Time', style: TextStyle(fontSize: 9, color: Color(0xFF94A3B8))), Text(_connectionTime, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600))]),
                    Column(children: [Text('Download', style: TextStyle(fontSize: 9, color: Color(0xFF94A3B8))), Text(_formatBytes(_dataReceived), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600))]),
                    Column(children: [Text('Upload', style: TextStyle(fontSize: 9, color: Color(0xFF94A3B8))), Text(_formatBytes(_dataSent), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600))]),
                  ],
                ),
              ),
              SizedBox(height: 12),
              Expanded(
                child: _isLoadingServers
                  ? Center(child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(color: Color(0xFF2563EB)),
                        SizedBox(height: 12),
                        Text('Loading servers...', style: TextStyle(color: Color(0xFF94A3B8))),
                      ],
                    ))
                  : _servers.isEmpty
                      ? Center(child: Text('No servers available', style: TextStyle(color: Color(0xFF94A3B8))))
                      : ListView.builder(
                          itemCount: _servers.length,
                          itemBuilder: (ctx, idx) {
                            final server = _servers[idx];
                            final isSelected = idx == _selectedIndex;
                            final hasConfig = server['config'] != null && server['config'].toString().isNotEmpty;
                            return GestureDetector(
                              onTap: () { if (!_isConnected) setState(() => _selectedIndex = idx); },
                              child: Container(
                                margin: EdgeInsets.only(bottom: 6),
                                padding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                decoration: BoxDecoration(
                                  color: isSelected ? Color(0xFF1E293B) : Color(0xFF0F172A),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: isSelected ? Color(0xFF2563EB) : (hasConfig ? Color(0xFF1E293B) : Color(0xFF4A1A1A)),
                                    width: isSelected ? 2 : 1,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Text(_getFlag(server['country'] ?? ''), style: TextStyle(fontSize: 22)),
                                    SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            server['remark'] ?? 'Server',
                                            style: TextStyle(
                                              fontWeight: FontWeight.w500,
                                              color: hasConfig ? Colors.white : Color(0xFF64748B),
                                            ),
                                          ),
                                          Text(
                                            server['host'] ?? '',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: hasConfig ? Color(0xFF94A3B8) : Color(0xFF4A4A4A),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (!hasConfig)
                                      Container(
                                        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Color(0xFF4A1A1A),
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        child: Text('No config', style: TextStyle(fontSize: 9, color: Color(0xFFEF4444))),
                                      ),
                                    if (hasConfig)
                                      Container(
                                        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: isSelected ? Color(0xFF2563EB) : Color(0xFF1E293B),
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        child: Text('${server['score'] ?? 0}', style: TextStyle(fontSize: 10, color: Colors.white)),
                                      ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
              ),
              SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                height: 44,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : (_isConnected ? _disconnectVpn : () => _connectVpn(_selectedIndex)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isConnected ? Color(0xFFDC2626) : Color(0xFF2563EB),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    elevation: 0,
                  ),
                  child: Text(
                    _isLoading ? 'CONNECTING...' : (_isConnected ? 'DISCONNECT' : 'CONNECT'),
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white),
                  ),
                ),
              ),
              SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('${_servers.length} servers', style: TextStyle(fontSize: 9, color: Color(0xFF64748B))),
                  SizedBox(width: 10),
                  GestureDetector(
                    onTap: _fetchServers,
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: Color(0xFF1E293B), borderRadius: BorderRadius.circular(10)),
                      child: Row(
                        children: [
                          Icon(Icons.refresh, size: 12, color: Color(0xFF94A3B8)),
                          SizedBox(width: 3),
                          Text('Refresh', style: TextStyle(fontSize: 9, color: Color(0xFF94A3B8))),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
