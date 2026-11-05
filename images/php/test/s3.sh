#!/usr/bin/env bash
# Seam S3: verify a PHP image after build.
# Usage: images/php/test/s3.sh <image> <main|xdebug>
set -euo pipefail

image=${1:?missing image}
variant=${2:?missing main|xdebug variant}
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
fail=0

expected=$(LC_ALL=C sort "$here/extensions.txt")
[ "$variant" = xdebug ] && expected=$(printf '%s\nxdebug\n' "$expected" | LC_ALL=C sort)

actual=$(docker run --rm "$image" php -m | sed -n '/PHP Modules/,/^$/p' | grep -v -e '^\[' -e '^$' | LC_ALL=C sort)
if [ "$actual" != "$expected" ]; then
  echo "ERROR: php -m does not match the pinned list ($image)" >&2
  diff <(echo "$expected") <(echo "$actual") >&2 || true
  fail=1
else
  echo "OK: php -m matches ($image)"
fi

has_xdebug=$(docker run --rm "$image" php -r 'echo extension_loaded("xdebug") ? "yes" : "no";')
if [ "$variant" = xdebug ] && [ "$has_xdebug" != yes ]; then
  echo "ERROR: the xdebug variant is missing Xdebug" >&2; fail=1
elif [ "$variant" = main ] && [ "$has_xdebug" != no ]; then
  echo "ERROR: the main image has Xdebug" >&2; fail=1
else
  echo "OK: Xdebug matches variant $variant"
fi

cid=$(docker run -d "$image")
trap 'docker rm -f "$cid" >/dev/null 2>&1 || true' EXIT
ok=0
for _ in $(seq 1 20); do
  if docker exec "$cid" test -S /sock/docker.sock 2>/dev/null; then ok=1; break; fi
  sleep 1
done
if [ "$ok" = 1 ]; then
  echo "OK: php-fpm created /sock/docker.sock"
else
  echo "ERROR: /sock/docker.sock not found" >&2; docker logs "$cid" >&2 || true; fail=1
fi

exit "$fail"
