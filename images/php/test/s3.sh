#!/usr/bin/env bash
# Seam S3: kiểm một image PHP sau khi build.
# Dùng: images/php/test/s3.sh <image> <main|xdebug>
set -euo pipefail

image=${1:?thiếu image}
variant=${2:?thiếu biến thể main|xdebug}
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
fail=0

expected=$(cat "$here/extensions.txt")
[ "$variant" = xdebug ] && expected=$(printf '%s\nxdebug\n' "$expected" | sort)

actual=$(docker run --rm "$image" php -m | sed -n '/PHP Modules/,/^$/p' | grep -v -e '^\[' -e '^$' | sort)
if [ "$actual" != "$expected" ]; then
  echo "LỖI: php -m không khớp danh sách đã chốt ($image)" >&2
  diff <(echo "$expected") <(echo "$actual") >&2 || true
  fail=1
else
  echo "OK: php -m khớp ($image)"
fi

has_xdebug=$(docker run --rm "$image" php -r 'echo extension_loaded("xdebug") ? "yes" : "no";')
if [ "$variant" = xdebug ] && [ "$has_xdebug" != yes ]; then
  echo "LỖI: biến thể xdebug thiếu Xdebug" >&2; fail=1
elif [ "$variant" = main ] && [ "$has_xdebug" != no ]; then
  echo "LỖI: image chính có Xdebug" >&2; fail=1
else
  echo "OK: Xdebug đúng biến thể $variant"
fi

cid=$(docker run -d "$image")
trap 'docker rm -f "$cid" >/dev/null 2>&1 || true' EXIT
ok=0
for _ in $(seq 1 20); do
  if docker exec "$cid" test -S /sock/docker.sock 2>/dev/null; then ok=1; break; fi
  sleep 1
done
if [ "$ok" = 1 ]; then
  echo "OK: php-fpm tạo /sock/docker.sock"
else
  echo "LỖI: không thấy /sock/docker.sock" >&2; docker logs "$cid" >&2 || true; fail=1
fi

exit "$fail"
