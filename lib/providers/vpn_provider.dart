import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/domain_fronter.dart';
import '../services/proxy_server.dart';
import '../services/certificate_manager.dart';

enum VpnState { disconnected, connecting, connected, error }

class VpnProvider extends ChangeNotifier {
  static const _channel = MethodChannel('moz_pn/vpn');
  
  VpnState _state = VpnState.disconnected;
  String _scriptId = '';
  String _authPassword = '';
  String _errorMessage = '';

  ProxyServer? _proxyServer;

  VpnState get state => _state;
  String get scriptId => _scriptId;
  String get authPassword => _authPassword;
  String get errorMessage => _errorMessage;

  VpnProvider() {
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _scriptId = prefs.getString('script_id') ?? '';
    _authPassword = prefs.getString('auth_password') ?? '';
    notifyListeners();
  }

  Future<void> saveSettings(String id, String password) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('script_id', id);
    await prefs.setString('auth_password', password);
    _scriptId = id;
    _authPassword = password;
    notifyListeners();
  }

  Future<void> toggleConnection() async {
    if (_state == VpnState.disconnected) {
      await _startVpn();
    } else {
      await _stopVpn();
    }
  }

  double _ping = 0;
  String _currentIp = '...';

  double get ping => _ping;
  String get currentIp => _currentIp;

  Future<void> _startVpn() async {
    try {
      _state = VpnState.connecting;
      notifyListeners();

      // 1. Initialize logic services
      final fronter = DomainFronter(scriptId: _scriptId, authPassword: _authPassword);
      final certManager = CertificateManager();
      _proxyServer = ProxyServer(fronter: fronter, certManager: certManager);

      // 2. Start local proxy
      await _proxyServer!.start();

      // 3. Start native VPN service
      await _channel.invokeMethod('startVpn');

      // 4. Test Connectivity
      await _testConnection(fronter);

      _state = VpnState.connected;
      notifyListeners();
    } catch (e) {
      _state = VpnState.error;
      _errorMessage = e.toString();
      notifyListeners();
    }
  }

  Future<void> _testConnection(DomainFronter fronter) async {
    final stopwatch = Stopwatch()..start();
    try {
      // Test with api.ipify.org to get current IP and verify relay
      final response = await fronter.relayRequest(
        targetUrl: 'https://api.ipify.org?format=json',
        method: 'GET',
      );

      stopwatch.stop();
      _ping = stopwatch.elapsedMilliseconds.toDouble();

      if (response.containsKey('b')) {
        final body = utf8.decode(base64Decode(response['b']));
        final data = jsonDecode(body);
        _currentIp = data['ip'] ?? 'Unknown';
      }
    } catch (e) {
      _ping = -1;
      _currentIp = 'خطا در دریافت IP';
      throw Exception("تست اتصال با خطا مواجه شد: $e");
    }
  }

  Future<void> _stopVpn() async {
    try {
      await _channel.invokeMethod('stopVpn');
      await _proxyServer?.stop();
      _proxyServer = null;
      _state = VpnState.disconnected;
      notifyListeners();
    } catch (e) {
      _state = VpnState.error;
      _errorMessage = e.toString();
      notifyListeners();
    }
  }
}
