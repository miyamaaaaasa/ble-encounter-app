# API TLS compatibility

ISRG Root X1 (self-signed), downloaded from https://letsencrypt.org/certs/isrgrootx1.pem via verified HTTPS.
Official source: https://letsencrypt.org/certificates/ and https://letsencrypt.org/docs/certificate-compatibility/.
SHA256 certificate fingerprint: 96:BC:EC:06:26:49:76:F3:74:60:77:9A:CF:28:C5:A7:CF:E8:A3:C0:AA:E1:1A:8F:FC:EE:05:C0:BD:DF:08:C6.

601SO/API24 lacks this root. ApiService adds it only to its own HttpClient trust context alongside system roots. Hostname, validity and certificate-chain checks remain enabled; no badCertificateCallback or global HttpOverrides. No leaf/intermediate pin, so normal certificate renewal works. A CA/expiry change requires rechecking this file and compatibility. Run dart run tool/check_api_tls.dart for positive and negative checks. Runtime asset is public certificate material, never a secret key.
