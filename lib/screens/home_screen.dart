import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/vpn_provider.dart';

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

  void _handleConnect() {
    final provider = Provider.of<VpnProvider>(context, listen: false);
    provider.saveSettings(_scriptIdController.text, _passwordController.text);
    provider.toggleConnection();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'MozPN',
          style: TextStyle(fontFamily: 'Roboto', fontWeight: FontWeight.w600, color: Color(0xFFFFD300)),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 40),
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
            const SizedBox(height: 80),
            Center(
              child: Consumer<VpnProvider>(
                builder: (context, provider, child) {
                  return _buildConnectButton(provider);
                },
              ),
            ),
            const SizedBox(height: 40),
            Consumer<VpnProvider>(
              builder: (context, provider, child) {
                return _buildInstallCAButton(context, provider);
              },
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

  Widget _buildInstallCAButton(BuildContext context, VpnProvider provider) {
    return Column(
      children: [
        OutlinedButton.icon(
          onPressed: () => provider.installCertificate(),
          icon: const Icon(Icons.verified_user_outlined, size: 18),
          label: const Text('نصب گواهینامه امنیتی'),
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFFFFD300),
            side: const BorderSide(color: Color(0xFFFFD300), width: 1),
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        const SizedBox(height: 12),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            'برای دور زدن محدودیت‌های شدید، نصب گواهینامه الزامی است. این گواهینامه فقط برای رمزگشایی ترافیک عبوری از VPN شما استفاده می‌شود.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFF444444), fontSize: 11),
          ),
        ),
      ],
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
      onTap: _handleConnect,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        width: 160,
        height: 160,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: mainColor,
          border: Border.all(
            color: const Color(0xFFFFD300).withOpacity(isConnected ? 0 : 0.3),
            width: 2,
          ),
          boxShadow: isConnected
              ? [
                  BoxShadow(
                    color: const Color(0xFFFFD300).withOpacity(0.15),
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
      default:
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
