import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rdesk/src/services/rdesk_bridge_service.dart';

/// Minimal JPEG payload — only the SOI marker is inspected by the decoder.
final _jpegBytes = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10]);

Uint8List _buildRdf1Packet({
  required int capturedAtMs,
  required int relayReceivedAtMs,
}) {
  final builder = BytesBuilder()
    ..add(const [0x52, 0x44, 0x46, 0x31]) // "RDF1"
    ..add(Uint8List.sublistView(Uint32List.fromList([1280])))
    ..add(Uint8List.sublistView(Uint32List.fromList([720])))
    ..add(Uint8List.sublistView(Uint64List.fromList([capturedAtMs])))
    ..add(Uint8List.sublistView(Uint64List.fromList([relayReceivedAtMs])))
    ..add(_jpegBytes);
  return builder.takeBytes();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final bridge = RdeskBridgeService.instance;

  group('WebSocket frame metrics', () {
    test('a stale frame does not inflate the reported latency', () {
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      // The remote screen has been static for 40s: the last frame the relay
      // holds was captured (and relayed) 40s ago.
      final packet = _buildRdf1Packet(
        capturedAtMs: nowMs - 40000,
        relayReceivedAtMs: nowMs - 40000,
      );

      final frame = bridge.debugDecodeRemoteFramePacket(
        packet,
        receivedAtMs: nowMs,
        fallbackNetworkLatencyMs: 15,
      );

      expect(frame, isNotNull);
      expect(frame!.latencyMs, 15, reason: 'latency must be the measured RTT');
      expect(frame.networkLatencyMs, 15);
      expect(frame.frameAgeMs, greaterThan(1500),
          reason: 'frame age is kept as a staleness diagnostic');
    });

    test('a fresh frame reports the same measured latency', () {
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final packet = _buildRdf1Packet(
        capturedAtMs: nowMs - 30,
        relayReceivedAtMs: nowMs - 10,
      );

      final frame = bridge.debugDecodeRemoteFramePacket(
        packet,
        receivedAtMs: nowMs,
        fallbackNetworkLatencyMs: 15,
      );

      expect(frame!.latencyMs, 15);
      expect(frame.frameAgeMs, lessThan(1500));
    });

    test('falls back to the relay timestamp before the first probe', () {
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final packet = _buildRdf1Packet(
        capturedAtMs: nowMs - 40000,
        relayReceivedAtMs: nowMs - 20,
      );

      final frame = bridge.debugDecodeRemoteFramePacket(
        packet,
        receivedAtMs: nowMs,
      );

      expect(frame!.latencyMs, 20);
    });
  });

  group('HTTP polling frame metrics', () {
    late HttpServer server;
    late int capturedAtMs;
    HttpOverrides? previousOverrides;

    setUp(() async {
      // The test binding stubs every HttpClient with a 400 responder; this
      // group needs real loopback traffic to measure a real round-trip.
      previousOverrides = HttpOverrides.current;
      HttpOverrides.global = null;
      // Fake relay that keeps re-serving one snapshot, exactly like the real
      // relay does while the remote screen is static.
      capturedAtMs = DateTime.now().millisecondsSinceEpoch;
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) {
        request.response.headers
          ..contentType = ContentType('image', 'jpeg')
          ..set('x-rdesk-width', '1280')
          ..set('x-rdesk-height', '720')
          ..set('x-rdesk-captured-at', '$capturedAtMs')
          ..set('x-rdesk-relay-received-at', '$capturedAtMs');
        request.response.add(_jpegBytes);
        request.response.close();
      });
    });

    tearDown(() async {
      await server.close(force: true);
      HttpOverrides.global = previousOverrides;
    });

    test('latency stays flat while the snapshot ages', () async {
      final endpoint = Uri.parse('http://127.0.0.1:${server.port}/frame.jpg');

      final first = await bridge.debugFetchRemotePreviewFrame(
        'test-session',
        endpoint: endpoint,
      );
      expect(first, isNotNull);

      await Future<void>.delayed(const Duration(milliseconds: 1200));

      final second = await bridge.debugFetchRemotePreviewFrame(
        'test-session',
        endpoint: endpoint,
      );
      expect(second, isNotNull);

      // Frame age grows with the snapshot — that is the diagnostic.
      expect(second!.frameAgeMs!, greaterThan(first!.frameAgeMs! + 1000));
      // The reported latency must not follow it.
      expect(second.latencyMs, lessThan(200));
      expect(second.latencyMs, second.networkLatencyMs);
    });

    test('a 40s-old snapshot still reports a loopback-fast latency', () async {
      capturedAtMs = DateTime.now().millisecondsSinceEpoch - 40000;
      final endpoint = Uri.parse('http://127.0.0.1:${server.port}/frame.jpg');

      final frame = await bridge.debugFetchRemotePreviewFrame(
        'test-session',
        endpoint: endpoint,
      );

      expect(frame, isNotNull);
      expect(frame!.latencyMs, lessThan(200));
      expect(frame.frameAgeMs, greaterThan(1500));
    });
  });
}
