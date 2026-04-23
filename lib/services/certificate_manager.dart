import 'dart:io';
import 'dart:typed_data';
import 'package:basic_utils/basic_utils.dart';
import 'package:pointycastle/export.dart';
import 'package:path_provider/path_provider.dart';

class CertificateManager {
  static const String _caKeyName = 'ca_key.pem';
  static const String _caCertName = 'ca_cert.pem';

  String? _caCertPem;
  AsymmetricKeyPair<RSAPrivateKey, RSAPublicKey>? _caKeyPair;

  Future<void> init() async {
    final directory = await getApplicationDocumentsDirectory();
    final keyFile = File('${directory.path}/$_caKeyName');
    final certFile = File('${directory.path}/$_caCertName');

    if (await keyFile.exists() && await certFile.exists()) {
      _caCertPem = await certFile.readAsString();
      // Load key logic here (omitted for brevity, assume we regenerate if needed)
    } else {
      await _generateCA();
    }
  }

  Future<void> _generateCA() async {
    print("Generating Local CA Certificate...");
    final keyPair = CryptoUtils.generateRSAKeyPair(2048);
    _caKeyPair = AsymmetricKeyPair(keyPair.privateKey as RSAPrivateKey, keyPair.publicKey as RSAPublicKey);

    final csr = X509Utils.generateSelfSignedCertificate(
      _caKeyPair!.privateKey,
      _caCertPem ?? '', // This is just a placeholder, basic_utils has better ways
      3650, // 10 years
      commonName: 'MasterHttpRelayVPN Root CA',
      organization: 'MozPN',
      countryName: 'IR',
    );

    _caCertPem = csr;
    
    final directory = await getApplicationDocumentsDirectory();
    await File('${directory.path}/$_caKeyName').writeAsString(CryptoUtils.encodeRSAPrivateKeyToPem(_caKeyPair!.privateKey));
    await File('${directory.path}/$_caCertName').writeAsString(_caCertPem!);
    print("Local CA generated and saved.");
  }

  String get caCertPath => '${Directory.systemTemp.path}/ca.crt'; // Placeholder for export

  Future<String> getCACertPem() async {
    final directory = await getApplicationDocumentsDirectory();
    return await File('${directory.path}/$_caCertName').readAsString();
  }

  /// Generates a signed certificate for a specific domain (e.g., google.com)
  /// using the local CA. This is used for MITM.
  Future<Map<String, String>> generateDomainCertificate(String domain) async {
    // This is a simplified version. In a real MITM, you'd use the CA to sign a new cert.
    // For this blueprint, we'll use a basic self-signed or CA-signed cert logic.
    // basic_utils provides X509Utils.generateSelfSignedCertificate which we can adapt.
    
    final keyPair = CryptoUtils.generateRSAKeyPair(2048);
    final cert = X509Utils.generateSelfSignedCertificate(
      keyPair.privateKey as RSAPrivateKey,
      '', // Subject
      365,
      commonName: domain,
      organization: 'MasterHttpRelayVPN MITM',
    );

    return {
      'cert': cert,
      'key': CryptoUtils.encodeRSAPrivateKeyToPem(keyPair.privateKey as RSAPrivateKey),
    };
  }
}
