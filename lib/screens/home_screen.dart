import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/vpn_provider.dart';
import '../widgets/log_viewer.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  final TextEditingController _scriptIdController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  late AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = Provider.of<VpnProvider>(context, listen: false);
      _scriptIdController.text = provider.scriptId;
      _passwordController.text = provider.authPassword;
    });
  }

  @override
  void dispose() {
    _scriptIdController.dispose();
    _passwordController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  void _handleConnect() async {
    final provider = Provider.of<VpnProvider>(context, listen: false);
    
    // If already connected, just disconnect
    if (provider.state == VpnState.connected) {
      provider.toggleConnection();
      return;
    }

    // 1. Check Credentials
    if (_scriptIdController.text.isEmpty || _passwordController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لطفاً ابتدا تنظیمات را وارد کنید'))
      );
      return;
    }
    provider.saveSettings(_scriptIdController.text, _passwordController.text);

    // 2. Check VPN Permission
    bool hasVpn = await provider.prepareVpn();
    if (!hasVpn) {
      _showWizardInfo('گام ۱: تایید سرویس VPN', 'لطفاً برای شروع، دکمه OK را برای تایید اتصال VPN بزنید.');
      return;
    }

    // 3. Check Storage Permission
    bool hasStorage = await provider.checkStoragePermission();
    if (!hasStorage) {
      _showWizardInfo('گام ۲: دسترسی به حافظه', 'برنامه نیاز به اجازه "All Files Access" دارد تا گواهینامه را برای شما ذخیره کند.', onConfirm: () async {
        await provider.requestStoragePermission();
      });
      return;
    }

    // 4. Check Certificate Installation Status
    if (!provider.isCertInstalled) {
      _startSetupWizard();
      return;
    }

    // 5. Final Step: Connect
    provider.toggleConnection();
  }

  void _startSetupWizard() {
    _handleInstallCertificate();
  }

  void _showWizardInfo(String title, String message, {VoidCallback? onConfirm}) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: Text(title, style: const TextStyle(color: Color(0xFFFFD300))),
        content: Text(message, style: const TextStyle(color: Colors.white70)),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              if (onConfirm != null) onConfirm();
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFFD300), foregroundColor: Colors.black),
            child: const Text('فهمیدم'),
          ),
        ],
      ),
    );
  }

  void _showLogs() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        minChildSize: 0.4,
        builder: (_, controller) => const LogViewer(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'MozPN',
          style: TextStyle(fontFamily: 'Roboto', fontWeight: FontWeight.w600, color: Color(0xFFFFD300)),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.receipt_long_rounded, color: Color(0xFFFFD300)),
            onPressed: _showLogs,
            tooltip: 'گزارش‌ها',
          ),
        ],
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 20),
            _buildInputField(
              controller: _scriptIdController,
              label: 'شناسه استقرار گوگل',
              hint: 'Deployment ID',
              icon: Icons.api_rounded,
            ),
            const SizedBox(height: 24),
            _buildInputField(
              controller: _passwordController,
              label: 'رمز عبور',
              hint: 'Auth Password',
              icon: Icons.lock_outline_rounded,
              isPassword: true,
            ),
            const SizedBox(height: 60),
            Center(
              child: Consumer<VpnProvider>(
                builder: (context, provider, child) {
                  return Column(
                    children: [
                      OutlinedButton.icon(
                        onPressed: () async {
                          provider.saveSettings(_scriptIdController.text, _passwordController.text);
                          await provider.testGoogleScriptConnection();
                          _showLogs();
                        },
                        icon: const Icon(Icons.wifi_tethering_rounded, size: 18),
                        label: const Text('تست اتصال به Google Script'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF00BCD4),
                          side: const BorderSide(color: Color(0xFF00BCD4), width: 1),
                          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                      const SizedBox(height: 20),
                      _buildConnectButton(provider),
                    ],
                  );
                },
              ),
            ),
            const SizedBox(height: 40),
            Consumer<VpnProvider>(
              builder: (context, provider, child) {
                return _buildStatusText(provider);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _handleInstallCertificate() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.verified_user, color: Color(0xFFFFD300), size: 28),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'نصب گواهینامه (مرحله به مرحله)',
                textAlign: TextAlign.right,
                style: TextStyle(color: Color(0xFFFFD300), fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF2A2A2A),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  '⚠️ بسیار مهم: در مرحله آخر فایل MozPN-v2-CA.crt را انتخاب کنید',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFFFFD300), fontSize: 13, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 16),
              _buildStep('1', 'دکمه شروع نصب را بزنید'),
              _buildStep('2', 'در صفحه تنظیمات، گزینه "CA Certificate" را بزنید'),
              _buildStep('3', 'دکمه "Install Anyway" را بزنید'),
              _buildStep('4', 'فایل MozPN-v2-CA.crt را از لیست انتخاب کنید'),
              _buildStep('5', 'به برنامه برگردید و دکمه اتصال را بزنید'),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF2A2A2A),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF00BCD4), width: 1),
                ),
                child: const Text(
                  '💡 نکته: اگر فایل را نمی‌بینید، به تنظیمات بروید و اجازه "All Files Access" را به برنامه بدهید.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70, fontSize: 11, height: 1.4),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('انصراف', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(context);
              Provider.of<VpnProvider>(context, listen: false).installCertificate();
              _showLogs();
            },
            icon: const Icon(Icons.arrow_forward, size: 18),
            label: const Text('شروع نصب'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFFD300),
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStep(String number, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: const Color(0xFFFFD300),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                number,
                style: const TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                text,
                textAlign: TextAlign.right,
                style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.4),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInstallCAButton(BuildContext context, VpnProvider provider) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFFFFD300).withOpacity(0.1),
            const Color(0xFFFFD300).withOpacity(0.05),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFFD300).withValues(alpha: 0.3), width: 1),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFD300),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.security, color: Colors.black, size: 24),
              ),
              const SizedBox(width: 12),
              const Text(
                'مرحله اول: نصب گواهینامه',
                style: TextStyle(
                  color: Color(0xFFFFD300),
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text(
            'برای استفاده از VPN، ابتدا باید گواهینامه امنیتی را نصب کنید.\nاین کار فقط یک بار لازم است.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.5),
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: _handleConnect,
            icon: const Icon(Icons.auto_fix_high_rounded, size: 20),
            label: const Text('آماده‌سازی خودکار برنامه', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFFD300),
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 32),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 4,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.info_outline, color: Color(0xFF888888), size: 14),
              const SizedBox(width: 6),
              const Text(
                'فقط 5 مرحله ساده',
                style: TextStyle(color: Color(0xFF888888), fontSize: 11),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInputField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    bool isPassword = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4.0),
          child: Text(
            label,
            style: const TextStyle(color: Color(0xFFFFD300), fontSize: 13, fontWeight: FontWeight.w500),
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: controller,
          obscureText: isPassword,
          style: const TextStyle(color: Colors.white, fontSize: 15),
          decoration: InputDecoration(
            hintText: hint,
            prefixIcon: Icon(icon, color: const Color(0xFF666666), size: 20),
            contentPadding: const EdgeInsets.symmetric(vertical: 18, horizontal: 20),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFF333333)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFF333333)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFFFD300), width: 1),
            ),
            filled: true,
            fillColor: const Color(0xFF121212),
          ),
        ),
      ],
    );
  }

  Widget _buildConnectButton(VpnProvider provider) {
    bool isConnected = provider.state == VpnState.connected;
    bool isConnecting = provider.state == VpnState.connecting;
    
    Color mainColor = isConnected ? const Color(0xFFFFD300) : const Color(0xFF1A1A1A);
    Color contentColor = isConnected ? Colors.black : const Color(0xFFFFD300);

    return GestureDetector(
      onTap: isConnecting ? null : _handleConnect,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        width: 160,
        height: 160,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: mainColor,
          border: Border.all(
            color: const Color(0xFFFFD300).withValues(alpha: isConnected ? 0 : 0.3),
            width: 2,
          ),
          boxShadow: isConnected
              ? [
                  BoxShadow(
                    color: const Color(0xFFFFD300).withValues(alpha: 0.3),
                    blurRadius: 40,
                    spreadRadius: 4,
                  )
                ]
              : [],
        ),
        child: Center(
          child: isConnecting
              ? SizedBox(
                  width: 40,
                  height: 40,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    valueColor: AlwaysStoppedAnimation<Color>(contentColor),
                  ),
                )
              : Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      isConnected ? Icons.power_settings_new_rounded : Icons.power_settings_new_rounded,
                      size: 48,
                      color: contentColor,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      isConnected ? 'قطع اتصال' : 'اتصال',
                      style: TextStyle(
                        color: contentColor,
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildStatusText(VpnProvider provider) {
    String status;
    Color color;

    switch (provider.state) {
      case VpnState.connected:
        status = 'اتصال برقرار شد';
        color = const Color(0xFFFFD300);
        break;
      case VpnState.connecting:
        status = 'در حال تلاش...';
        color = const Color(0xFF666666);
        break;
      case VpnState.error:
        status = 'خطا در برقراری ارتباط';
        color = Colors.redAccent;
        break;
      case VpnState.disconnected:
        status = 'آماده اتصال';
        color = const Color(0xFF666666);
        break;
    }

    return Column(
      children: [
        Text(
          status,
          textAlign: TextAlign.center,
          style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.w500),
        ),
        if (provider.state == VpnState.connected) ...[
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildStatItem('پینگ', '${provider.ping.toInt()} ms', Icons.speed_rounded),
              const SizedBox(width: 32),
              _buildStatItem('آی‌پی شما', provider.currentIp, Icons.public_rounded),
            ],
          ),
        ],
        if (provider.state == VpnState.error && provider.errorMessage.isNotEmpty) ...[
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              provider.errorMessage,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.redAccent, fontSize: 12),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildStatItem(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: const Color(0xFF444444), size: 18),
        const SizedBox(height: 6),
        Text(
          label,
          style: const TextStyle(color: Color(0xFF666666), fontSize: 11),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }
}
