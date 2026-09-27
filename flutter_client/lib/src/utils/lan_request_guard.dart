import 'dart:io';

import 'package:flutter/foundation.dart';

/// Runs one LAN host request so that malformed input still gets a response.
///
/// `Stream.forEach` does not await async handlers: an exception from
/// `jsonDecode` or a payload cast would otherwise leave the viewer's
/// connection open until it times out and surface as an uncaught error.
Future<void> guardLanRequest(
    HttpRequest request, Future<void> Function() handle) async {
  try {
    await handle();
  } catch (e) {
    debugPrint('[RDesk] LAN request ${request.method} ${request.uri.path} '
        'rejected: ${e.runtimeType}');
    final response = request.response;
    try {
      response.statusCode = e is FormatException || e is TypeError
          ? HttpStatus.badRequest
          : HttpStatus.internalServerError;
    } on StateError {
      // Headers were already sent; closing is all that is left to do.
    }
    try {
      await response.close();
    } catch (_) {
      // The viewer may already have disconnected.
    }
  }
}
