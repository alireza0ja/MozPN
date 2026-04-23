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
      // 1. Connect with SNI Spoofing
      socket = await SecureSocket.connect(
        googleIp,
        443,
        hostName: sniHost,
        supportedProtocols: ['http/1.1'],
        onBadCertificate: (_) => true,
      );

      // 2. Prepare GAS Payload
      final Map<String, dynamic> payload = {
        "k": authPassword,
        "m": method,
        "u": targetUrl,
        "h": headers ?? {},
        "r": false,
      };

      if (bodyBytes != null && bodyBytes.isNotEmpty) {
        payload["b"] = base64Encode(bodyBytes);
      }

      final String jsonBody = jsonEncode(payload);
      final List<int> jsonBytes = utf8.encode(jsonBody);

      // 3. Build Raw HTTP Request
      final String requestHeader = 
          "POST /macros/s/$scriptId/exec HTTP/1.1\r\n" +
          "Host: $scriptHost\r\n" +
          "Content-Type: application/json\r\n" +
          "Content-Length: ${jsonBytes.length}\r\n" +
          "Connection: close\r\n\r\n";

      socket.add(utf8.encode(requestHeader));
      socket.add(jsonBytes);
      await socket.flush();

      // 4. Read Response with Chunked handling
      return await _readAndParseResponse(socket);
    } catch (e) {
      return {"s": 500, "error": e.toString()};
    } finally {
      socket?.destroy();
    }
  }

  Future<Map<String, dynamic>> _readAndParseResponse(Stream<List<int>> stream) async {
    final List<int> responseBuffer = [];
    await for (var chunk in stream) {
      responseBuffer.addAll(chunk);
    }

    final String fullResponse = utf8.decode(responseBuffer, allowMalformed: true);
    final int headerEnd = fullResponse.indexOf('\r\n\r\n');
    if (headerEnd == -1) return {"s": 500, "error": "Invalid HTTP response"};

    final String headerPart = fullResponse.substring(0, headerEnd);
    final String bodyPart = fullResponse.substring(headerEnd + 4);

    // Handle Chunked Transfer-Encoding
    String finalBody = bodyPart;
    if (headerPart.toLowerCase().contains("transfer-encoding: chunked")) {
      finalBody = _decodeChunked(bodyPart);
    }

    try {
      return jsonDecode(finalBody);
    } catch (e) {
      return {
        "s": 500,
        "error": "Failed to parse JSON: $e",
        "raw_body": finalBody,
      };
    }
  }

  String _decodeChunked(String body) {
    StringBuffer decoded = StringBuffer();
    int pos = 0;
    while (pos < body.length) {
      int lineEnd = body.indexOf('\r\n', pos);
      if (lineEnd == -1) break;
      
      String hexSize = body.substring(pos, lineEnd).trim();
      int size = int.parse(hexSize, radix: 16);
      if (size == 0) break;

      pos = lineEnd + 2;
      decoded.write(body.substring(pos, pos + size));
      pos += size + 2; // +2 for \r\n
    }
    return decoded.toString();
  }
}
