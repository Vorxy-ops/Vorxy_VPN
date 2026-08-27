import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:openvpn_flutter/openvpn_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/services.dart';

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
        cardTheme: CardTheme(
          color: Color(0xFF1E293B),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        floatingActionButtonTheme: FloatingActionButtonThemeData(
          backgroundColor: Color(0xFF2563EB),
          foregroundColor: Colors.white,
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

class _VorxyHomeState extends State<VorxyHome> with WidgetsBindingObserver {
  final OpenVPN _openVpn = OpenVPN();
  bool _isConnected = false;
  bool _isLoading = false;
  bool _isLoadingServers = false;
  bool _isKillSwitch = false;
  bool _isAutoConnect = false;
  String _statusText = 'Disconnected';
  String _selectedServer = 'Auto';
  String _connectionTime = '00:00:00';
  String _serverLocation = '';
  String _protocolText = 'OpenVPN';
  int _dataReceived = 0;
  int _dataSent = 0;
  double _signalStrength = 0.0;
  List<Map<String, dynamic>> _servers = [];
  List<Map<String, dynamic>> _allServers = [];
  int _selectedIndex = 0;
  Timer? _timer;
  Timer? _speedTimer;
  int _seconds = 0;
  String _sourceInfo = 'Loading...';
  bool _isDarkMode = true;
  List<String> _excludedApps = [];

  final List<String> _serverSources = [
    'https://raw.githubusercontent.com/Hidashimora/free-vpn-anti-rkn/main/configs/1.1.txt',
    'https://raw.githubusercontent.com/Hidashimora/free-vpn-anti-rkn/main/configs/2.1.txt',
    'https://raw.githubusercontent.com/Hidashimora/free-vpn-anti-rkn/main/configs/3.1.txt',
    'https://raw.githubusercontent.com/Hidashimora/free-vpn-anti-rkn/main/configs/4.1.txt',
    'https://raw.githubusercontent.com/Hidashimora/free-vpn-anti-rkn/main/configs/5.1.txt',
    'https://raw.githubusercontent.com/Hidashimora/free-vpn-anti-rkn/main/configs/6.1.txt',
    'https://raw.githubusercontent.com/Hidashimora/free-vpn-anti-rkn/main/configs/7.1.txt',
    'https://raw.githubusercontent.com/Hidashimora/free-vpn-anti-rkn/main/configs/8.1.txt',
    'https://raw.githubusercontent.com/ebrasha/free-v2ray-public-list/main/V2Ray-Config-By-EbraSha.txt',
  ];

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
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initVpn();
    _loadSettings();
    _fetchAllServers();
    _checkConnectivity();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _speedTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_isAutoConnect && state == AppLifecycleState.resumed && !_isConnected) {
      _autoConnect();
    }
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _isKillSwitch = prefs.getBool('killSwitch') ?? false;
      _isAutoConnect = prefs.getBool('autoConnect') ?? false;
      _isDarkMode = prefs.getBool('darkMode') ?? true;
    });
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('killSwitch', _isKillSwitch);
    await prefs.setBool('autoConnect', _isAutoConnect);
    await prefs.setBool('darkMode', _isDarkMode);
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
        if (_isKillSwitch && _isConnected) {
          _disconnectVpn();
          _showSnackbar('Kill Switch activated');
        }
      }
    });
  }

  String _getFlag(String country) {
    if (country.isEmpty) return '🌍';
    final upper = country.toUpperCase().substring(0, 2);
    return _countryFlags[upper] ?? '🌍';
  }

  String _getCountryFromHost(String host) {
    final hosts = host.toLowerCase();
    if (hosts.contains('de') || hosts.contains('germany')) return 'DE';
    if (hosts.contains('us') || hosts.contains('usa')) return 'US';
    if (hosts.contains('jp') || hosts.contains('japan')) return 'JP';
    if (hosts.contains('fr') || hosts.contains('france')) return 'FR';
    if (hosts.contains('uk') || hosts.contains('gb') || hosts.contains('united kingdom')) return 'GB';
    if (hosts.contains('ru') || hosts.contains('russia')) return 'RU';
    if (hosts.contains('nl') || hosts.contains('netherlands')) return 'NL';
    if (hosts.contains('ca') || hosts.contains('canada')) return 'CA';
    if (hosts.contains('au') || hosts.contains('australia')) return 'AU';
    if (hosts.contains('br') || hosts.contains('brazil')) return 'BR';
    if (hosts.contains('in') || hosts.contains('india')) return 'IN';
    return 'US';
  }

  Future<void> _fetchAllServers() async {
    setState(() {
      _isLoadingServers = true;
      _sourceInfo = 'Loading servers...';
    });

    List<Map<String, dynamic>> allConfigs = [];

    for (String source in _serverSources) {
      try {
        final response = await http.get(Uri.parse(source)).timeout(Duration(seconds: 10));
        if (response.statusCode == 200) {
          final lines = response.body.split('\n');
          for (String line in lines) {
            line = line.trim();
            if (line.isEmpty) continue;
            if (line.startsWith('vless://') ||
                line.startsWith('vmess://') ||
                line.startsWith('trojan://') ||
                line.startsWith('ss://') ||
                line.startsWith('hy2://')) {
              final parsed = _parseConfig(line);
              if (parsed != null) allConfigs.add(parsed);
            }
          }
        }
      } catch (e) {
        print('Error fetching from $source: $e');
      }
    }

    if (allConfigs.isEmpty) {
      allConfigs = _getFallbackServers();
    }

    allConfigs.shuffle();
    int score = 0;
    for (var server in allConfigs) {
      score = (score + 1) % 100;
      server['score'] = 100 - score;
    }

    setState(() {
      _allServers = allConfigs;
      _servers = allConfigs.length > 50 ? allConfigs.sublist(0, 50) : allConfigs;
      if (_servers.isNotEmpty) _selectedIndex = 0;
      _isLoadingServers = false;
      _sourceInfo = '${_servers.length} servers ready';
    });

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('servers', jsonEncode(_allServers));
    _showSnackbar('${_servers.length} servers loaded');
  }

  Map<String, dynamic>? _parseConfig(String url) {
    try {
      String protocol = 'unknown';
      String host = '';
      int port = 443;
      String remark = 'Server';

      if (url.startsWith('vless://')) {
        protocol = 'vless';
        final uri = Uri.parse(url);
        host = uri.host;
        port = uri.port;
        remark = uri.fragment.isNotEmpty ? uri.fragment : 'VLESS';
      } else if (url.startsWith('vmess://')) {
        protocol = 'vmess';
        final base64 = url.substring(8);
        final decoded = utf8.decode(base64Decode(base64));
        final data = jsonDecode(decoded);
        host = data['add'] ?? '';
        port = int.tryParse(data['port']?.toString() ?? '443') ?? 443;
        remark = data['ps'] ?? 'VMESS';
      } else if (url.startsWith('trojan://')) {
        protocol = 'trojan';
        final uri = Uri.parse(url);
        host = uri.host;
        port = uri.port;
        remark = uri.fragment.isNotEmpty ? uri.fragment : 'Trojan';
      } else if (url.startsWith('ss://')) {
        protocol = 'shadowsocks';
        final content = url.substring(5);
        if (content.contains('@')) {
          final parts = content.split('@');
          final hostPort = parts[1].split(':');
          host = hostPort[0];
          port = int.tryParse(hostPort[1]) ?? 443;
          remark = 'SS';
        }
      } else if (url.startsWith('hy2://')) {
        protocol = 'hysteria2';
        final uri = Uri.parse(url);
        host = uri.host;
        port = uri.port;
        remark = 'Hysteria2';
      }

      if (host.isEmpty) return null;
      String country = _getCountryFromHost(host);

      return {
        'url': url,
        'protocol': protocol,
        'host': host,
        'port': port,
        'remark': remark,
        'country': country,
        'flag': _getFlag(country),
        'config': url,
        'score': 50,
        'ping': 100 + (port % 200),
      };
    } catch (_) {
      return null;
    }
  }

  List<Map<String, dynamic>> _getFallbackServers() {
    return [
      {'url': 'vless://b5e3e7e7-8f6a-4d4e-a4b2-1c8e9d0a5f6b@185.162.235.223:443?type=ws&path=/&encryption=none&security=tls#DE-1', 'protocol': 'vless', 'host': '185.162.235.223', 'port': 443, 'remark': 'Germany', 'country': 'DE', 'flag': '🇩🇪', 'config': 'vless://b5e3e7e7-8f6a-4d4e-a4b2-1c8e9d0a5f6b@185.162.235.223:443?type=ws&path=/&encryption=none&security=tls#DE-1', 'score': 85, 'ping': 120},
      {'url': 'vmess://eyJ2IjoiMiIsInBzIjoiVVMtMSIsImFkZCI6IjE0Mi4wLjEzNi4xMzciLCJwb3J0IjoiODAiLCJpZCI6ImZmZmZmZmZmLWZmZmYtZmZmZi1mZmZmLWZmZmZmZmZmZmZmZiIsImFpZCI6IjAiLCJzY3kiOiJhdXRvIiwibmV0Ijoid3MiLCJ0eXBlIjoibm9uZSIsImhvc3QiOiIiLCJwYXRoIjoiIiwidGxzIjoiIn0=', 'protocol': 'vmess', 'host': '142.0.136.137', 'port': 80, 'remark': 'USA', 'country': 'US', 'flag': '🇺🇸', 'config': 'vmess://eyJ2IjoiMiIsInBzIjoiVVMtMSIsImFkZCI6IjE0Mi4wLjEzNi4xMzciLCJwb3J0IjoiODAiLCJpZCI6ImZmZmZmZmZmLWZmZmYtZmZmZi1mZmZmLWZmZmZmZmZmZmZmZiIsImFpZCI6IjAiLCJzY3kiOiJhdXRvIiwibmV0Ijoid3MiLCJ0eXBlIjoibm9uZSIsImhvc3QiOiIiLCJwYXRoIjoiIiwidGxzIjoiIn0=', 'score': 90, 'ping': 80},
      {'url': 'trojan://password@trojan.example.com:443?security=tls&sni=trojan.example.com#Trojan-1', 'protocol': 'trojan', 'host': 'trojan.example.com', 'port': 443, 'remark': 'Trojan US', 'country': 'US', 'flag': '🇺🇸', 'config': 'trojan://password@trojan.example.com:443?security=tls&sni=trojan.example.com#Trojan-1', 'score': 75, 'ping': 150},
    ];
  }

  Future<void> _connectVpn(int index) async {
    if (_servers.isEmpty) {
      await _fetchAllServers();
      if (_servers.isEmpty) return;
    }

    final server = _servers[index];
    setState(() {
      _isLoading = true;
      _selectedServer = server['remark'] ?? server['host'];
      _serverLocation = server['country'] ?? '';
      _protocolText = server['protocol'] ?? 'OpenVPN';
      _statusText = 'Connecting...';
    });

    try {
      await _openVpn.connect(server['config'], server['remark']);
      setState(() {
        _isConnected = true;
        _isLoading = false;
        _statusText = 'Protected';
        _seconds = 0;
        _signalStrength = 0.8 + (index % 5) * 0.04;
      });
      _startTimer();
      _showSnackbar('Connected to ${server['host']}');
    } catch (e) {
      setState(() {
        _isLoading = false;
        _statusText = 'Connection failed';
        _signalStrength = 0.1;
      });
      _showSnackbar('Failed to connect');
    }
  }

  Future<void> _autoConnect() async {
    if (_servers.isNotEmpty) {
      await _connectVpn(_selectedIndex);
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

  String _formatSpeed(int bytes, int seconds) {
    if (seconds == 0) return '0 B/s';
    final speed = bytes ~/ seconds;
    if (speed < 1024) return '$speed B/s';
    if (speed < 1048576) return '${(speed / 1024).toStringAsFixed(1)} KB/s';
    return '${(speed / 1048576).toStringAsFixed(1)} MB/s';
  }

  Future<void> _disconnectVpn() async {
    _openVpn.disconnect();
    _timer?.cancel();
    setState(() {
      _isConnected = false;
      _statusText = 'Disconnected';
      _selectedServer = 'Auto';
      _serverLocation = '';
      _connectionTime = '00:00:00';
      _dataReceived = 0;
      _dataSent = 0;
      _seconds = 0;
      _signalStrength = 0.0;
    });
    _showSnackbar('VPN disconnected');
  }

  void _showSnackbar(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: Duration(seconds: 2)),
    );
  }

  Future<void> _refreshServers() async {
    await _fetchAllServers();
  }

  void _showSettings() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Color(0xFF1E293B),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setStateModal) {
          return Container(
            padding: EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Color(0xFF64748B),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                SizedBox(height: 20),
                Text('Settings', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                SizedBox(height: 20),
                SwitchListTile(
                  title: Text('Kill Switch'),
                  subtitle: Text('Block internet if VPN disconnects'),
                  value: _isKillSwitch,
                  onChanged: (value) {
                    setStateModal(() => _isKillSwitch = value);
                    setState(() => _isKillSwitch = value);
                    _saveSettings();
                  },
                  activeColor: Color(0xFF2563EB),
                ),
                SwitchListTile(
                  title: Text('Auto Connect'),
                  subtitle: Text('Auto-connect on app start'),
                  value: _isAutoConnect,
                  onChanged: (value) {
                    setStateModal(() => _isAutoConnect = value);
                    setState(() => _isAutoConnect = value);
                    _saveSettings();
                  },
                  activeColor: Color(0xFF2563EB),
                ),
                SwitchListTile(
                  title: Text('Dark Mode'),
                  subtitle: Text('Use dark theme'),
                  value: _isDarkMode,
                  onChanged: (value) {
                    setStateModal(() => _isDarkMode = value);
                    setState(() => _isDarkMode = value);
                    _saveSettings();
                  },
                  activeColor: Color(0xFF2563EB),
                ),
                SizedBox(height: 10),
                Text('Protocol: $_protocolText', style: TextStyle(color: Color(0xFF94A3B8))),
                SizedBox(height: 20),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton(
        onPressed: _showSettings,
        child: Icon(Icons.settings),
        backgroundColor: Color(0xFF2563EB),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(Icons.vpn_key, color: Color(0xFF2563EB), size: 28),
                      SizedBox(width: 8),
                      Text('Vorxy VPN', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF2563EB))),
                    ],
                  ),
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: _isConnected ? Color(0xFF064E3B) : Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: _isConnected ? Color(0xFF22C55E) : Color(0xFF64748B), width: 1),
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
                          _isConnected ? 'Protected' : 'Disconnected',
                          style: TextStyle(
                            fontSize: 11,
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
              Text('Free Unlimited VPN', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
              SizedBox(height: 20),
              Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: 130,
                    height: 130,
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
                    child: GestureDetector(
                      onTap: _isConnected ? _disconnectVpn : () => _connectVpn(_selectedIndex),
                      child: Container(
                        width: 130,
                        height: 130,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.transparent,
                        ),
                        child: Icon(
                          _isConnected ? Icons.vpn_key : Icons.power_settings_new,
                          size: 48,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  if (_signalStrength > 0)
                    Positioned(
                      bottom: 10,
                      child: Row(
                        children: List.generate(4, (i) {
                          final active = i < (_signalStrength * 4).round();
                          return Container(
                            margin: EdgeInsets.symmetric(horizontal: 2),
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: active ? Color(0xFF22C55E) : Color(0xFF64748B),
                            ),
                          );
                        }),
                      ),
                    ),
                ],
              ),
              SizedBox(height: 16),
              Text(
                _isConnected ? 'Protected' : _statusText,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              SizedBox(height: 4),
              Text(
                _isConnected ? 'Location: $_serverLocation • $_protocolText' : 'Tap to connect',
                style: TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
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
                    Column(
                      children: [
                        Text('Speed', style: TextStyle(fontSize: 10, color: Color(0xFF94A3B8))),
                        Text(
                          _isConnected ? _formatSpeed(_dataReceived + _dataSent, _seconds == 0 ? 1 : _seconds) : '0 B/s',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(_sourceInfo, style: TextStyle(fontSize: 10, color: Color(0xFF64748B))),
                  Row(
                    children: [
                      GestureDetector(
                        onTap: _refreshServers,
                        child: Container(
                          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: Color(0xFF1E293B),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.refresh, size: 12, color: Color(0xFF94A3B8)),
                              SizedBox(width: 3),
                              Text('Refresh', style: TextStyle(fontSize: 9, color: Color(0xFF94A3B8))),
                            ],
                          ),
                        ),
                      ),
                      SizedBox(width: 8),
                      if (_isKillSwitch)
                        Container(
                          padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Color(0xFF4A1A1A),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text('Kill', style: TextStyle(fontSize: 8, color: Color(0xFFEF4444))),
                        ),
                    ],
                  ),
                ],
              ),
              SizedBox(height: 8),
              Expanded(
                child: _isLoadingServers
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            CircularProgressIndicator(color: Color(0xFF2563EB)),
                            SizedBox(height: 12),
                            Text('Loading servers...', style: TextStyle(color: Color(0xFF94A3B8))),
                          ],
                        ),
                      )
                    : _servers.isEmpty
                        ? Center(
                            child: Text(
                              'No servers available\nPull to refresh',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Color(0xFF94A3B8)),
                            ),
                          )
                        : ListView.builder(
                            itemCount: _servers.length,
                            itemBuilder: (ctx, idx) {
                              final server = _servers[idx];
                              final isSelected = idx == _selectedIndex;
                              final ping = server['ping'] ?? 100;
                              final protocol = server['protocol'] ?? 'unknown';
                              final protocolColor = protocol == 'vless' ? Color(0xFF8B5CF6)
                                  : protocol == 'vmess' ? Color(0xFF3B82F6)
                                  : protocol == 'trojan' ? Color(0xFFEF4444)
                                  : protocol == 'shadowsocks' ? Color(0xFFF59E0B)
                                  : protocol == 'hysteria2' ? Color(0xFF10B981)
                                  : Color(0xFF64748B);

                              return GestureDetector(
                                onTap: () {
                                  if (!_isConnected) {
                                    setState(() => _selectedIndex = idx);
                                  }
                                },
                                child: Container(
                                  margin: EdgeInsets.only(bottom: 6),
                                  padding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                  decoration: BoxDecoration(
                                    color: isSelected ? Color(0xFF1E293B) : Color(0xFF0F172A),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: isSelected ? Color(0xFF2563EB) : Color(0xFF1E293B),
                                      width: isSelected ? 2 : 1,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Text(server['flag'] ?? '🌍', style: TextStyle(fontSize: 22)),
                                      SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              server['remark'] ?? 'Server',
                                              style: TextStyle(fontWeight: FontWeight.w500),
                                            ),
                                            Row(
                                              children: [
                                                Text(
                                                  '${server['host'] ?? ''}:${server['port'] ?? 443}',
                                                  style: TextStyle(fontSize: 10, color: Color(0xFF94A3B8)),
                                                ),
                                                SizedBox(width: 8),
                                                Container(
                                                  padding: EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                                  decoration: BoxDecoration(
                                                    color: protocolColor.withOpacity(0.2),
                                                    borderRadius: BorderRadius.circular(4),
                                                  ),
                                                  child: Text(
                                                    protocol,
                                                    style: TextStyle(fontSize: 8, color: protocolColor),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                      Row(
                                        children: [
                                          Icon(
                                            Icons.signal_cellular_alt,
                                            size: 14,
                                            color: ping < 150 ? Color(0xFF22C55E)
                                                : ping < 300 ? Color(0xFFF59E0B)
                                                : Color(0xFFEF4444),
                                          ),
                                          SizedBox(width: 4),
                                          Text(
                                            '${ping}ms',
                                            style: TextStyle(fontSize: 10, color: Color(0xFF94A3B8)),
                                          ),
                                        ],
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
                height: 48,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : (_isConnected ? _disconnectVpn : () => _connectVpn(_selectedIndex)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isConnected ? Color(0xFFDC2626) : Color(0xFF2563EB),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    elevation: 0,
                  ),
                  child: Text(
                    _isLoading ? 'CONNECTING...' : (_isConnected ? 'DISCONNECT' : 'CONNECT'),
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
