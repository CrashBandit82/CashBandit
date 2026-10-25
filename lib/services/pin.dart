import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// PIN hashing: PBKDF2-HMAC-SHA256 with a random salt. Only the result is
/// stored (flutter_secure_storage), never the PIN.
const pinIterations = 60000;

bool isValidPin(String pin) => RegExp(r'^\d{4,6}$').hasMatch(pin);

Uint8List _pbkdf2(List<int> password, List<int> salt, int iterations) {
  final hmac = Hmac(sha256, password);
  // single block (32 bytes): U1 = HMAC(salt || INT(1))
  var u = hmac.convert([...salt, 0, 0, 0, 1]).bytes;
  final out = Uint8List.fromList(u);
  for (var i = 1; i < iterations; i++) {
    u = hmac.convert(u).bytes;
    for (var j = 0; j < out.length; j++) {
      out[j] ^= u[j];
    }
  }
  return out;
}

/// Format: `pbkdf2$<iterations>$<salt b64>$<hash b64>`
String hashPin(String pin, {List<int>? salt}) {
  final s = salt ?? List<int>.generate(16, (_) => Random.secure().nextInt(256));
  final h = _pbkdf2(utf8.encode(pin), s, pinIterations);
  return 'pbkdf2\$$pinIterations\$${base64.encode(s)}\$${base64.encode(h)}';
}

bool verifyPin(String pin, String stored) {
  final p = stored.split(r'$');
  if (p.length != 4 || p[0] != 'pbkdf2') return false;
  final iterations = int.tryParse(p[1]);
  if (iterations == null) return false;
  final expected = base64.decode(p[3]);
  final actual = _pbkdf2(utf8.encode(pin), base64.decode(p[2]), iterations);
  // constant-time compare
  var diff = expected.length ^ actual.length;
  for (var i = 0; i < min(expected.length, actual.length); i++) {
    diff |= expected[i] ^ actual[i];
  }
  return diff == 0;
}
