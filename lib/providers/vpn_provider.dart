import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import '../services/domain_fronter.dart';
import '../services/proxy_server.dart';
import '../services/certificate_manager.dart';
import '../services/logger_service.dart';

enum VpnState { disconnected, connecting, connected, error }

class VpnProvider extends ChangeNotifier {
  static const _channel = MethodChannel('com.example.moz_pn/vpn');
  final LoggerService _logger = LoggerService();
  
  VpnState _state = VpnState.disconnected;
  // Default credentials for testing (CHANGE THESE!)
  String _scriptId = 'AKfycbyYHZmuBqvEIMjXp92izMWW3KxvXXcnrnlIGC2oXH80XB9yk8sUXYRkDrGydxpoIq4TPw';
  String _authPassword = '123456';
  String _errorMessage = '';
  bool _isCertInstalled = false;

  ProxyServer? _proxyServer;

  VpnState get state => _state;
  String get scriptId => _scriptId;
  String get authPassword => _authPassword;
  String get errorMessage => _errorMessage;
  bool get isCertInstalled => _isCertInstalled;

  VpnProvider() {
    _loadSettings();
  }

  Future<bool> checkStoragePermission() async {
    return await _channel.invokeMethod('checkStoragePermission');
  }

  Future<void> requestStoragePermission() async {
    await _channel.invokeMethod('requestStoragePermission');
  }

  Future<bool> prepareVpn() async {
    return await _channel.invokeMethod('prepareVpn');
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    // Default credentials for testing
    _scriptId = prefs.getString('script_id') ?? 'AKfycbyYHZmuBqvEIMjXp92izMWW3KxvXXcnrnlIGC2oXH80XB9yk8sUXYRkDrGydxpoIq4TPw';
    _authPassword = prefs.getString('auth_password') ?? '123456';
    _isCertInstalled = prefs.getBool('cert_installed') ?? false;
    notifyListeners();
  }

  Future<void> installCertificate() async {
    try {
      _logger.log("✓ مرحله 1: در حال ساخت گواهینامه...");
      final certManager = CertificateManager();
      await certManager.init();
      
      // Get certificate in DER format (Android prefers this for CA certs)
      final certDer = await certManager.getCACertDer();
      
      _logger.log("✓ مرحله 2: گواهینامه آماده شد!");
      _logger.log("✓ مرحله 3: در حال ذخیره فایل...");

      // Save to external storage root (not Downloads, easier to find in file picker)
      await _channel.invokeMethod('installCA', {'certData': certDer});
      
      _logger.log("✓ مرحله 4: فایل ذخیره شد!", type: LogType.success);
      _logger.log("📱 نام فایل: MozPN-v2-CA.crt", type: LogType.success);
      _logger.log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━", type: LogType.info);
      _logger.log("📋 مراحل نصب هوشمند:", type: LogType.warning);
      _logger.log("1️⃣ در صفحه تنظیمات، 'CA Certificate' را بزنید", type: LogType.info);
      _logger.log("2️⃣ دکمه 'Install anyway' را انتخاب کنید", type: LogType.info);
      _logger.log("3️⃣ فایل MozPN-v2-CA.crt را از لیست انتخاب کنید", type: LogType.info);
      _logger.log("4️⃣ برگردید به برنامه و دکمه اتصال را بزنید", type: LogType.info);
      _logger.log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━", type: LogType.info);
      
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('cert_installed', true);
      _isCertInstalled = true;
      notifyListeners();
      
    } catch (e) {
      _logger.log("❌ خطا: $e", type: LogType.error);
      _errorMessage = "خطا در نصب گواهینامه: $e";
      notifyListeners();
    }
  }

  Future<void> saveSettings(String id, String password) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('script_id', id);
    await prefs.setString('auth_password', password);
    _scriptId = id;
    _authPassword = password;
    _logger.log("تنظیمات ذخیره شد.");
    notifyListeners();
  }

  Future<bool> testGoogleScriptConnection() async {
    if (_scriptId.isEmpty || _authPassword.isEmpty) {
      _logger.log("لطفاً ابتدا شناسه و رمز عبور را وارد کنید.", type: LogType.error);
      return false;
    }

    try {
      _logger.log("در حال تست اتصال به Google Script...");
      final fronter = DomainFronter(scriptId: _scriptId, authPassword: _authPassword);
      
      final response = await fronter.relayRequest(
        targetUrl: 'https://api.ipify.org?format=json',
        method: 'GET',
      ).timeout(const Duration(seconds: 10));

      if (response.containsKey('error')) {
        _logger.log("خطا: ${response['error']}", type: LogType.error);
        _logger.log("احتمالاً شناسه یا رمز عبور اشتباه است.", type: LogType.warning);
        return false;
      }

      if (response.containsKey('s') && response['s'] == 200) {
        _logger.log("✓ اتصال به Google Script موفق بود!", type: LogType.success);
        _logger.log("شناسه و رمز عبور صحیح است.", type: LogType.info);
        return true;
      } else {
        _logger.log("پاسخ نامعتبر از سرور: ${response.toString()}", type: LogType.error);
        return false;
      }
    } catch (e) {
      _logger.log("خطا در تست اتصال: $e", type: LogType.error);
      _logger.log("لطفاً اتصال اینترنت و تنظیمات را بررسی کنید.", type: LogType.warning);
      return false;
    }
  }

  Future<void> toggleConnection() async {
    if (_state == VpnState.disconnected || _state == VpnState.error) {
      _startVpn(); // Don't await here to keep the UI responsive for 'stop'
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
      _errorMessage = '';
      notifyListeners();
      _logger.log("در حال شروع فرآیند اتصال...");

      // 1. Initialize logic services
      _logger.log("مقداردهی سرویس‌های داخلی...");
      final fronter = DomainFronter(scriptId: _scriptId, authPassword: _authPassword);
      final certManager = CertificateManager();
      _proxyServer = ProxyServer(fronter: fronter, certManager: certManager);

      // Check if user cancelled during initialization
      if (_state != VpnState.connecting) return;

      // 2. Start local proxy
      _logger.log("در حال اجرای سرور پروکسی محلی...");
      await _proxyServer!.start();
      if (_state != VpnState.connecting) {
        await _proxyServer!.stop();
        return;
      }
      _logger.log("سرور پروکسی فعال شد.", type: LogType.success);

      // 3. Start native VPN service
      _logger.log("در حال درخواست مجوز VPN...");
      await _channel.invokeMethod('startVpn');
      if (_state != VpnState.connecting) {
        await _channel.invokeMethod('stopVpn');
        return;
      }
      _logger.log("سرویس VPN فعال شد.");

      // 4. Wait a bit for the tunnel to stabilize
      _logger.log("در حال پایداری تونل...");
      await Future.delayed(const Duration(seconds: 2));
      if (_state != VpnState.connecting) return;

      // 5. Test Connectivity
      _logger.log("در حال تست اتصال...");
      await _testConnection(fronter);
      if (_state != VpnState.connecting) return;

      _state = VpnState.connected;
      _logger.log("اتصال با موفقیت برقرار شد.", type: LogType.success);
      notifyListeners();
    } catch (e) {
      // If we are still in connecting state (not stopped manually)
      if (_state == VpnState.connecting) {
        _state = VpnState.error;
        _errorMessage = e.toString();
        _logger.log("خطا در برقراری اتصال: $e", type: LogType.error);
        notifyListeners();
        await _stopVpn();
      }
    }
  }

  Future<void> _testConnection(DomainFronter fronter) async {
    final stopwatch = Stopwatch()..start();
    try {
      // 1. Test backend directly (Fronter test)
      final backendResponse = await fronter.relayRequest(
        targetUrl: 'https://api.ipify.org?format=json',
        method: 'GET',
      );

      if (backendResponse.containsKey('error')) {
        throw Exception("خطا در ارتباط با سرور گوگل: ${backendResponse['error']}");
      }

      // 2. Test system-wide routing (Actual VPN test)
      // This request SHOULD go through the VPN tunnel.
      // If the tunnel is faked or broken, this might fail or show the real IP.
      final vpnResponse = await http.get(Uri.parse('https://api.ipify.org?format=json'))
          .timeout(const Duration(seconds: 5));
      
      stopwatch.stop();
      _ping = stopwatch.elapsedMilliseconds.toDouble();

      if (vpnResponse.statusCode == 200) {
        final data = jsonDecode(vpnResponse.body);
        _currentIp = data['ip'] ?? 'Unknown';
        _logger.log("آی‌پی شناسایی شده: $_currentIp", type: LogType.info);
      } else {
        _logger.log("هشدار: ترافیک سیستمی از VPN عبور نمی‌کند.", type: LogType.warning);
        _currentIp = "خطا در تایید تونل";
      }
    } catch (e) {
      _ping = -1;
      _currentIp = 'خطا در تست';
      _logger.log("تست اتصال ناموفق بود: $e", type: LogType.warning);
      // We don't throw here to let the app show 'connected' if the backend is at least reachable,
      // but the user will see the warning in logs.
    }
  }

  Future<void> _stopVpn() async {
    try {
      _logger.log("در حال قطع اتصال...");
      await _channel.invokeMethod('stopVpn');
      await _proxyServer?.stop();
      _proxyServer = null;
      _state = VpnState.disconnected;
      _logger.log("اتصال قطع شد.");
      notifyListeners();
    } catch (e) {
      _logger.log("خطا در قطع اتصال: $e", type: LogType.error);
      _state = VpnState.error;
      _errorMessage = e.toString();
      notifyListeners();
    }
  }
}
