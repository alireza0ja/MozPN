import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'domain_fronter.dart';
import 'certificate_manager.dart';

class ProxyServer {
  ServerSocket? _httpServer;
  ServerSocket? _socksServer;
  final DomainFronter fronter;
  final CertificateManager certManager;
  final int httpPort;
  final int socksPort;

  ProxyServer({
    required this.fronter,
    required this.certManager,
    this.httpPort = 8085,
    this.socksPort = 1080,
  });

  Future<void> start() async {
    try {
      await certManager.init();
      
      // Start HTTP Proxy Server
      _httpServer = await ServerSocket.bind('127.0.0.1', httpPort);
      print("HTTP Proxy listening on 127.0.0.1:$httpPort");
      _httpServer!.listen(_handleHttpClient);

      // Start SOCKS5 Server (Required for tun2socks)
      _socksServer = await ServerSocket.bind('127.0.0.1', socksPort);
      print("SOCKS5 Server listening on 127.0.0.1:$socksPort");
      _socksServer!.listen(_handleSocksClient);

    } catch (e) {
      print("Failed to start proxy servers: $e");
    }
  }

  Future<void> stop() async {
    await _httpServer?.close();
    await _socksServer?.close();
    _httpServer = null;
    _socksServer = null;
  }

  // --- HTTP PROXY LOGIC ---

  void _handleHttpClient(Socket client) async {
    try {
      final List<int> headerData = await _readHttpHeaders(client);
      if (headerData.isEmpty) {
        client.destroy();
        return;
      }

      String requestStr = utf8.decode(headerData, allowMalformed: true);
      List<String> lines = requestStr.split('\r\n');
      String firstLine = lines[0];
      List<String> parts = firstLine.split(' ');
      if (parts.length < 3) return;

      String method = parts[0];
      String url = parts[1];

      if (method == 'CONNECT') {
        await _handleHttpsConnect(client, url);
      } else {
        await _handleHttpRequest(client, method, url, lines, headerData);
      }
    } catch (e) {
      print("HTTP Proxy Error: $e");
      client.destroy();
    }
  }

  Future<List<int>> _readHttpHeaders(Stream<List<int>> source) async {
    final List<int> buffer = [];
    await for (var chunk in source) {
      buffer.addAll(chunk);
      String s = utf8.decode(buffer, allowMalformed: true);
      if (s.contains('\r\n\r\n')) break;
    }
    return buffer;
  }

  Future<void> _handleHttpsConnect(Socket client, String url) async {
    try {
      // 1. Acknowledge CONNECT
      client.add(utf8.encode("HTTP/1.1 200 Connection Established\r\n\r\n"));
      await client.flush();

      // 2. Upgrade to Secure Server (MITM)
      String domain = url.contains(':') ? url.split(':')[0] : url;
      final certData = await certManager.generateDomainCertificate(domain);

      final context = SecurityContext()
        ..useCertificateChainBytes(utf8.encode(certData['cert']!))
        ..usePrivateKeyBytes(utf8.encode(certData['key']!));

      // USE secureServer for MITM
      final secureClient = await SecureSocket.secureServer(
        client,
        context,
      );

      // 3. Handle encrypted traffic inside TLS
      secureClient.listen((data) async {
        await _processSecureTraffic(secureClient, data, domain);
      }, onError: (e) => secureClient.destroy(), onDone: () => secureClient.destroy());

    } catch (e) {
      print("HTTPS CONNECT Error for $url: $e");
      client.destroy();
    }
  }

  Future<void> _processSecureTraffic(SecureSocket client, List<int> initialData, String domain) async {
    // This needs a more robust HTTP parser to handle multiple requests on same socket (Keep-Alive)
    // For this blueprint, we implement a basic one-shot or simplified stream handler.
    try {
      String requestStr = utf8.decode(initialData, allowMalformed: true);
      if (!requestStr.contains('\r\n\r\n')) return; // Incomplete header

      List<String> lines = requestStr.split('\r\n');
      List<String> firstLineParts = lines[0].split(' ');
      String method = firstLineParts[0];
      String path = firstLineParts[1];
      String targetUrl = "https://$domain$path";

      await _handleHttpRequest(client, method, targetUrl, lines, initialData);
    } catch (e) {
      client.destroy();
    }
  }

  Future<void> _handleHttpRequest(Socket client, String method, String url, List<String> lines, List<int> rawData) async {
    try {
      // 1. Extract Headers
      Map<String, String> headers = {};
      int contentLength = 0;
      for (int i = 1; i < lines.length; i++) {
        if (lines[i].isEmpty) break;
        int colon = lines[i].indexOf(': ');
        if (colon != -1) {
          String key = lines[i].substring(0, colon);
          String value = lines[i].substring(colon + 2);
          headers[key] = value;
          if (key.toLowerCase() == 'content-length') contentLength = int.tryParse(value) ?? 0;
        }
      }

      // 2. Read full Body if Content-Length > 0
      List<int> bodyBytes = [];
      int headerEnd = utf8.decode(rawData, allowMalformed: true).indexOf('\r\n\r\n');
      if (headerEnd != -1) {
        bodyBytes = rawData.sublist(headerEnd + 4);
      }

      while (bodyBytes.length < contentLength) {
        // Read remaining body from socket
        final chunk = await client.first;
        bodyBytes.addAll(chunk);
      }

      // 3. Relay to DomainFronter
      final gasResponse = await fronter.relayRequest(
        targetUrl: url,
        method: method,
        headers: headers,
        bodyBytes: bodyBytes,
      );

      // 4. Send Response Back
      _writeResponse(client, gasResponse);
    } catch (e) {
      client.add(utf8.encode("HTTP/1.1 500 Error\r\n\r\n$e"));
      client.destroy();
    }
  }

  void _writeResponse(Socket client, Map<String, dynamic> gasResponse) {
    if (gasResponse.containsKey('s')) {
      int status = gasResponse['s'];
      Map<String, dynamic> respHeaders = gasResponse['h'] ?? {};
      String? base64Body = gasResponse['b'];

      String header = "HTTP/1.1 $status ${_getStatusText(status)}\r\n";
      respHeaders.forEach((k, v) {
        if (v is List) {
          for (var item in v) header += "$k: $item\r\n";
        } else {
          header += "$k: $v\r\n";
        }
      });
      header += "\r\n";

      client.add(utf8.encode(header));
      if (base64Body != null) client.add(base64Decode(base64Body));
    } else {
      client.add(utf8.encode("HTTP/1.1 502 Bad Gateway\r\n\r\n"));
    }
    client.flush().then((_) => client.destroy());
  }

  // --- SOCKS5 LOGIC (Basic implementation for tun2socks) ---

  void _handleSocksClient(Socket client) async {
    try {
      // 1. Handshake
      final methodData = await client.first;
      if (methodData[0] != 0x05) return; // SOCKS5 only
      client.add(Uint8List.fromList([0x05, 0x00])); // No auth

      // 2. Request
      final requestData = await client.first;
      if (requestData[1] != 0x01) return; // CONNECT only

      // Extract Address
      String host = "";
      int port = 0;
      if (requestData[3] == 0x01) { // IPv4
        host = "${requestData[4]}.${requestData[5]}.${requestData[6]}.${requestData[7]}";
        port = (requestData[8] << 8) | requestData[9];
      } else if (requestData[3] == 0x03) { // Domain Name
        int len = requestData[4];
        host = utf8.decode(requestData.sublist(5, 5 + len));
        port = (requestData[5 + len] << 8) | requestData[5 + len + 1];
      }

      // SOCKS5 expects us to connect to host:port. 
      // But we are a relay. For HTTPS (port 443), we must handle it like CONNECT.
      // For HTTP, we treat it like a normal request.
      
      // Reply success
      client.add(Uint8List.fromList([0x05, 0x00, 0x00, 0x01, 0, 0, 0, 0, 0, 0]));
      
      if (port == 443) {
        // Upgrade to MITM TLS
        await _handleHttpsConnect(client, host);
      } else {
        // Standard HTTP over SOCKS
        client.listen((data) {
          _handleHttpClientData(client, data, host);
        });
      }
    } catch (e) {
      client.destroy();
    }
  }

  void _handleHttpClientData(Socket client, List<int> data, String host) {
    // Similar to HTTP Proxy but without the full URL in the first line
    // We reconstruct it using the 'host' provided during SOCKS handshake
  }

  String _getStatusText(int status) => {200: "OK", 502: "Bad Gateway"}[status] ?? "Status $status";
}
