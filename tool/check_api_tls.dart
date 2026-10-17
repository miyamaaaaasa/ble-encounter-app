import 'dart:io';

// Run from the repository root: dart run tool/check_api_tls.dart.
Future<void> main() async {
  const host = '153-125-148-69.sslip.io';
  Future<int> health(SecurityContext context, String target) async {
    final client = HttpClient(context: context)
      ..connectionTimeout = const Duration(seconds: 12);
    try {
      final request =
          await client.getUrl(Uri.parse('https://$target/v1/health'));
      final response = await request.close();
      await response.drain<void>();
      return response.statusCode;
    } finally {
      client.close(force: true);
    }
  }

  Future<void> rejects(SecurityContext context, String target) async {
    try {
      await health(context, target);
    } on HandshakeException {
      return;
    }
    throw StateError('TLS unexpectedly accepted $target');
  }

  final ca = await File('assets/certificates/isrgrootx1.pem').readAsBytes();
  SecurityContext trusted() =>
      SecurityContext(withTrustedRoots: false)..setTrustedCertificatesBytes(ca);
  await rejects(SecurityContext(withTrustedRoots: false), host);
  if (await health(trusted(), host) != 200) {
    throw StateError('API health failed');
  }
  await rejects(trusted(), '153.125.148.69');
  stdout.writeln(
      'PASS: bundled root verifies API; untrusted chain and wrong hostname rejected.');
}
