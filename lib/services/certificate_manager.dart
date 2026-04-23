import 'dart:io';
import 'dart:math';
import 'package:basic_utils/basic_utils.dart';
import 'package:pointycastle/export.dart';
import 'package:path_provider/path_provider.dart';

class CertificateManager {
  static const String _caKeyName = 'ca_key.pem';
  static const String _caCertName = 'ca_cert.pem';

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
      print("Local CA loaded from storage.");
    } else {
      await _generateCA();
    }
  }

  Future<void> _generateCA() async {
    print("Generating Local Root CA Certificate...");
    final keyPair = CryptoUtils.generateRSAKeyPair(2048);
    _caPrivateKey = keyPair.privateKey as RSAPrivateKey;

    // Generate self-signed Root CA
    _caCertPem = X509Utils.generateSelfSignedCertificate(
      _caPrivateKey!,
      'CN=MozPN Root CA, O=MozPN, C=IR',
      3650, // 10 years
      commonName: 'MozPN Root CA',
      organization: 'MozPN',
      countryName: 'IR',
    );
    
    final directory = await getApplicationDocumentsDirectory();
    await File('${directory.path}/$_caKeyName').writeAsString(CryptoUtils.encodeRSAPrivateKeyToPem(_caPrivateKey!));
    await File('${directory.path}/$_caCertName').writeAsString(_caCertPem!);
    print("Local Root CA generated and saved.");
  }

  /// Generates a certificate for a specific domain, SIGNED by the Local Root CA.
  Future<Map<String, String>> generateDomainCertificate(String domain) async {
    if (_caPrivateKey == null || _caCertPem == null) {
      throw Exception("CA not initialized");
    }

    // 1. Generate key pair for the leaf certificate
    final leafKeyPair = CryptoUtils.generateRSAKeyPair(2048);
    final leafPrivateKey = leafKeyPair.privateKey as RSAPrivateKey;

    // 2. Define Certificate attributes
    final subject = 'CN=$domain, O=MozPN MITM, C=IR';
    final issuer = X509Utils.getSubjectFromPem(_caCertPem!);
    
    // 3. Generate the certificate and SIGN it with the CA's private key
    // Note: basic_utils.X509Utils.generateCertificate is ideal for this.
    final serialNumber = BigInt.from(Random().nextInt(1000000000));
    
    final leafCertPem = X509Utils.generateCertificate(
      leafPrivateKey, // The public key of the leaf will be extracted from this
      issuer, // Issuer from our Root CA
      subject, // Subject is the target domain
      leafKeyPair.publicKey as RSAPublicKey,
      serialNumber.toString(),
      DateTime.now(),
      DateTime.now().add(const Duration(days: 365)),
      signingKey: _caPrivateKey!, // THE MAGIC: Signed by our Root CA's private key
      isCA: false,
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
}
