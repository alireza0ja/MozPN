import 'dart:io';
import 'dart:convert';
import 'domain_fronter.dart';
import 'certificate_manager.dart';

class ProxyServer {
  ServerSocket? _server;
  final DomainFronter fronter;
  final CertificateManager certManager;
  final int port;

  ProxyServer({
    required this.fronter, 
    required this.certManager,
    this.port = 8085,
  });

  Future<void> start() async {
    try {
      await certManager.init();
      _server = await ServerSocket.bind('127.0.0.1', port);
      print("Local Proxy listening on 127.0.0.1:$port");

      _server!.listen((Socket clientSocket) {
        _handleClient(clientSocket);
      });
    } catch (e) {
      print("Failed to start proxy server: $e");
    }
  }

  Future<void> stop() async {
    await _server?.close();
    _server = null;
  }

  void _handleClient(Socket client) async {
    try {
      // 1. Read the initial request
      final List<int> requestData = [];
      
      // Basic buffer reading logic
      await for (var data in client) {
        requestData.addAll(data);
        String currentRequest = utf8.decode(requestData, allowMalformed: true);
        if (currentRequest.contains('\r\n\r\n')) {
          break;
        }
      }

      if (requestData.isEmpty) {
        client.destroy();
        return;
      }

      String requestStr = utf8.decode(requestData, allowMalformed: true);
      List<String> lines = requestStr.split('\r\n');
      if (lines.isEmpty) return;

      String firstLine = lines[0];
      List<String> parts = firstLine.split(' ');
      if (parts.length < 3) return;

      String method = parts[0];
      String url = parts[1];

      if (method == 'CONNECT') {
        _handleHttpsConnect(client, url);
      } else {
        _handleHttpRequest(client, method, url, lines, requestData);
      }
    } catch (e) {
      print("Error handling client: $e");
      client.destroy();
    }
  }

  void _handleHttpsConnect(Socket client, String url) async {
    try {
      // 1. Respond to client that connection is established
      client.add(utf8.encode("HTTP/1.1 200 Connection Established\r\n\r\n"));
      await client.flush();

      // 2. Generate dynamic cert for the domain
      String domain = url.contains(':') ? url.split(':')[0] : url;
      final certData = await certManager.generateDomainCertificate(domain);

      // 3. Upgrade to SecureSocket (MITM)
      // This requires the private key and cert generated in step 2.
      // Note: Dart's SecureSocket.secure requires a SecurityContext.
      final context = SecurityContext()
        ..useCertificateChainBytes(utf8.encode(certData['cert']!))
        ..usePrivateKeyBytes(utf8.encode(certData['key']!));

      final secureClient = await SecureSocket.secure(
        client,
        context: context,
        onBadCertificate: (_) => true,
      );

      // 4. Handle encrypted requests inside the tunnel
      secureClient.listen((data) {
        // Here we would parse the decrypted HTTP request and relay via DomainFronter
        // For brevity, we'll follow a similar flow to _handleHttpRequest
        _handleSecureClient(secureClient, data, domain);
      }, onError: (e) => secureClient.destroy(), onDone: () => secureClient.destroy());
    } catch (e) {
      print("MITM Error for $url: $e");
      client.destroy();
    }
  }

  void _handleSecureClient(SecureSocket client, List<int> data, String domain) async {
    // Implementation of parsing decrypted HTTPS data and relaying...
    // Similar to _handleHttpRequest but on a secure socket
  }

  void _handleHttpRequest(Socket client, String method, String url, List<String> lines, List<int> rawRequest) async {
    try {
      // Extract headers
      Map<String, String> headers = {};
      for (int i = 1; i < lines.length; i++) {
        if (lines[i].isEmpty) break;
        int colonIndex = lines[i].indexOf(': ');
        if (colonIndex != -1) {
          headers[lines[i].substring(0, colonIndex)] = lines[i].substring(colonIndex + 2);
        }
      }

      // Extract body if any (for POST/PUT)
      List<int>? bodyBytes;
      int headerEndIndex = utf8.decode(rawRequest, allowMalformed: true).indexOf('\r\n\r\n');
      if (headerEndIndex != -1 && headerEndIndex + 4 < rawRequest.length) {
        bodyBytes = rawRequest.sublist(headerEndIndex + 4);
      }

      // Relay via DomainFronter
      final gasResponse = await fronter.relayRequest(
        targetUrl: url,
        method: method,
        headers: headers,
        bodyBytes: bodyBytes,
      );

      // Build and send response back to client
      if (gasResponse.containsKey('s')) {
        int status = gasResponse['s'];
        Map<String, dynamic> respHeaders = gasResponse['h'] ?? {};
        String? base64Body = gasResponse['b'];
        
        String responseHeader = "HTTP/1.1 $status ${_getStatusText(status)}\r\n";
        respHeaders.forEach((key, value) {
          if (value is List) {
            for (var v in value) {
              responseHeader += "$key: $v\r\n";
            }
          } else {
            responseHeader += "$key: $value\r\n";
          }
        });
        responseHeader += "\r\n";

        client.add(utf8.encode(responseHeader));
        if (base64Body != null) {
          client.add(base64Decode(base64Body));
        }
      } else {
        String errorMsg = gasResponse['error'] ?? "Unknown Error";
        client.add(utf8.encode("HTTP/1.1 502 Bad Gateway\r\n\r\nError: $errorMsg"));
      }
    } catch (e) {
      client.add(utf8.encode("HTTP/1.1 500 Internal Server Error\r\n\r\nError: $e"));
    } finally {
      await client.flush();
      client.destroy();
    }
  }

  void _handleHttpsConnect(Socket client, String url) async {
    // For now, we respond with "Connection Established"
    // In Task 4, we will upgrade this to MITM using a local CA
    client.add(utf8.encode("HTTP/1.1 200 Connection Established\r\n\r\n"));
    
    // TEMPORARY: Since we don't have MITM yet, we can't see the traffic inside the tunnel.
    // Real implementation of Task 4 goes here.
    print("HTTPS CONNECT to $url - MITM implementation pending in Task 4");
    
    // For now, we'll just close the connection or wait for the next phase.
    // In a real MITM, we would wrap 'client' with a SecureSocket using a dynamic cert.
  }

  String _getStatusText(int status) {
    switch (status) {
      case 200: return "OK";
      case 201: return "Created";
      case 301: return "Moved Permanently";
      case 302: return "Found";
      case 400: return "Bad Request";
      case 401: return "Unauthorized";
      case 403: return "Forbidden";
      case 404: return "Not Found";
      case 500: return "Internal Server Error";
      case 502: return "Bad Gateway";
      default: return "Unknown";
    }
  }
}
