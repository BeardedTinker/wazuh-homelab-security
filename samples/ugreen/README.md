# UGREEN UGOS Pro samples

These scenarios preserve message structures observed on UGOS Pro while replacing
usernames, IP addresses, hostnames, process IDs, sectors, and device identifiers.

| Scenario | Expected result |
|---|---|
| `web-login-success` | web login success rule `100600` |
| `web-bruteforce` | fifth same-source failure triggers `100610` |
| `web-success-after-failure` | same-source success after failure triggers `100611` |
| `storage-repeated-io` | third same-device I/O error triggers `100631` |

UGOS web failure records do not provide a reliable username, so the two web
correlations intentionally use only `srcip`. The storage scenario uses a
sanitized Linux block-device name and sector values.
