#!/usr/bin/env bash
set -uo pipefail
HOST="${1:-127.0.0.1}"
FAIL=0

echo "[*] Service availability"
if curl -sk --max-time 15 "https://${HOST}/" | grep -qi "html\|penpot"; then
  echo "  PASS: Penpot responded"
else
  echo "  FAIL: no response"; FAIL=1
fi

echo "[*] HTTP to HTTPS redirect"
CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://${HOST}/")
[ "$CODE" = "301" ] && echo "  PASS: redirect works" || echo "  WARN: got ${CODE}"

echo "[*] Security headers"
H=$(curl -skI "https://${HOST}/")
for name in "Strict-Transport-Security" "X-Frame-Options" "X-Content-Type-Options" "Content-Security-Policy"; do
  echo "$H" | grep -qi "$name" && echo "  PASS: ${name}" || { echo "  FAIL: ${name} missing"; FAIL=1; }
done

echo "[*] Exposed ports (expect 22, 80, 443 only)"
nmap -Pn -p 22,80,443,5432,9001 "${HOST}"

exit "$FAIL"
