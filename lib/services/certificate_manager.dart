import 'dart:io';
import 'dart:math';
import 'dart:convert';
import 'package:basic_utils/basic_utils.dart';
import 'package:path_provider/path_provider.dart';

class CertificateManager {
  static const String _caKeyName = 'ca_key_v2.pem';
  static const String _caCertName = 'ca_cert_v2.pem';

  String? _caCertPem;
  RSAPrivateKey? _caPrivateKey;

  Future<void> init() async {
    final directory = await getApplicationDocumentsDirectory();
    final keyFile = File('${directory.path}/$_caKeyName');
    final certFile = File('${directory.path}/$_caCertName');

    if (await keyFile.exists() && await certFile.exists()) {
      final keyPem = await keyFile.readAsString();
      _caPrivateKey = CryptoUtils.rsaPrivateKeyFromPem(keyPem);
      _caCertPem = await certFile.readAsString();
    } else {
      await _generateCA();
    }
  }

  Future<void> _generateCA() async {
    final keyPair = CryptoUtils.generateRSAKeyPair(keySize: 2048);
    _caPrivateKey = keyPair.privateKey as RSAPrivateKey;

    final Map<String, String> attributes = {
      'CN': 'MozPN Root CA',
      'O': 'MozPN',
      'C': 'IR',
    };

    final csr = X509Utils.generateRsaCsrPem(attributes, _caPrivateKey!, keyPair.publicKey as RSAPublicKey);

    // Generate self-signed Root CA with CA:TRUE extension
    _caCertPem = X509Utils.generateSelfSignedCertificate(
      _caPrivateKey!,
      csr,
      3650, // 10 years
      serialNumber: '1',
      cA: true, // Correct parameter name
    );
    
    final directory = await getApplicationDocumentsDirectory();
    await File('${directory.path}/$_caKeyName').writeAsString(CryptoUtils.encodeRSAPrivateKeyToPem(_caPrivateKey!));
    await File('${directory.path}/$_caCertName').writeAsString(_caCertPem!);
  }

  /// Generates a certificate for a specific domain, SIGNED by the Local Root CA.
  Future<Map<String, String>> generateDomainCertificate(String domain) async {
    if (_caPrivateKey == null || _caCertPem == null) {
      throw Exception("CA not initialized");
    }

    // 1. Generate key pair for the leaf certificate
    final leafKeyPair = CryptoUtils.generateRSAKeyPair(keySize: 2048);
    final leafPrivateKey = leafKeyPair.privateKey as RSAPrivateKey;

    // 2. Generate CSR for the domain
    final Map<String, String> attributes = {
      'CN': domain,
      'O': 'MozPN MITM',
      'C': 'IR',
    };
    final csr = X509Utils.generateRsaCsrPem(attributes, leafPrivateKey, leafKeyPair.publicKey as RSAPublicKey);

    // 3. Generate the certificate and SIGN it with the CA's private key
    final leafCertPem = X509Utils.generateSelfSignedCertificate(
      _caPrivateKey!, // Sign with CA private key
      csr,
      365,
      serialNumber: Random().nextInt(1000000).toString(),
      issuer: X509Utils.csrFromPem(X509Utils.generateRsaCsrPem({
        'CN': 'MozPN Root CA',
        'O': 'MozPN',
        'C': 'IR',
      }, _caPrivateKey!, CryptoUtils.rsaPublicKeyFromPem(_caCertPem!))).certificationRequestInfo?.subject,
    );

    return {
      'cert': leafCertPem,
      'key': CryptoUtils.encodeRSAPrivateKeyToPem(leafPrivateKey),
    };
  }

  Future<String> getCACertPem() async {
    if (_caCertPem == null) await init();
    return _caCertPem!;
  }

  /// Export CA certificate in DER format for Android installation
  Future<List<int>> getCACertDer() async {
    if (_caCertPem == null) await init();
    
    // Convert PEM to DER format (binary)
    // Remove PEM headers and decode base64
    final lines = _caCertPem!
        .replaceAll('-----BEGIN CERTIFICATE-----', '')
        .replaceAll('-----END CERTIFICATE-----', '')
        .replaceAll('\n', '')
        .replaceAll('\r', '')
        .trim();
    
    return base64Decode(lines);
  }

  /// Get CA private key PEM
  Future<String> getCAKeyPem() async {
    if (_caPrivateKey == null) await init();
    return CryptoUtils.encodeRSAPrivateKeyToPem(_caPrivateKey!);
  }
}
