import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';

class DomainFronter {
  final String googleIp = '216.239.38.120';
  final String sniHost = 'www.google.com';
  final String scriptHost = 'script.google.com';
  final String scriptId;
  final String authPassword;

  DomainFronter({required this.scriptId, required this.authPassword});

  /// Relays a request to the Google Apps Script endpoint using Domain Fronting.
  Future<Map<String, dynamic>> relayRequest({
    required String targetUrl,
    required String method,
    Map<String, String>? headers,
    List<int>? bodyBytes,
  }) async {
    SecureSocket? socket;
    try {
      // 1. Connect to Raw Google IP, but Spoof SNI to www.google.com
      socket = await SecureSocket.connect(
        googleIp,
        443,
        hostName: sniHost, // THIS IS THE SNI SPOOFING MAGIC!
        supportedProtocols: ['http/1.1'],
        onBadCertificate: (_) => true, // Ignore cert mismatch for the spoofed SNI
      );

      // 2. Prepare JSON Payload for Apps Script
      final Map<String, dynamic> payload = {
        "k": authPassword,
        "m": method,
        "u": targetUrl,
        "h": headers ?? {},
        "r": false, // Don't follow redirects automatically
      };

      if (bodyBytes != null && bodyBytes.isNotEmpty) {
        payload["b"] = base64Encode(bodyBytes);
      }

      final String jsonBody = jsonEncode(payload);
      final List<int> jsonBytes = utf8.encode(jsonBody);

      // 3. Build Raw HTTP POST Request
      // We must target the Apps Script URL but use the Host header to distinguish it
      final String requestHeader = 
          "POST /macros/s/$scriptId/exec HTTP/1.1\r\n" +
          "Host: $scriptHost\r\n" +
          "Content-Type: application/json\r\n" +
          "Content-Length: ${jsonBytes.length}\r\n" +
          "Connection: close\r\n\r\n";

      // 4. Send Request
      socket.add(utf8.encode(requestHeader));
      socket.add(jsonBytes);
      await socket.flush();

      // 5. Read Response
      final List<int> responseData = [];
      await socket.listen((data) {
        responseData.addAll(data);
      }).asFuture();

      return _parseRawHttpResponse(responseData);
    } catch (e) {
      return {
        "s": 500,
        "error": e.toString(),
      };
    } finally {
      socket?.destroy();
    }
  }

  Map<String, dynamic> _parseRawHttpResponse(List<int> rawData) {
    final String fullResponse = utf8.decode(rawData, allowMalformed: true);
    
    // Find the body of the HTTP response (after \r\n\r\n)
    final int bodyStartIndex = fullResponse.indexOf('\r\n\r\n');
    if (bodyStartIndex == -1) {
      return {"s": 500, "error": "Invalid HTTP response format"};
    }

    final String body = fullResponse.substring(bodyStartIndex + 4);
    
    try {
      // The body should be the JSON returned by our Apps Script: { "s": status, "h": headers, "b": "base64..." }
      return jsonDecode(body);
    } catch (e) {
      return {
        "s": 500,
        "error": "Failed to parse GAS response JSON: ${e.toString()}",
        "raw_body": body,
      };
    }
  }
}
