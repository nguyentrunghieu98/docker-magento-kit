#!/usr/bin/env bash
# S1 test for the commands that read values from the profile file: bin/setup,
# bin/setup-domain, bin/setup-ssl, bin/deploy, `install.sh new --setup`, the Makefile
# with project/bin and the OPcache file. Child commands (bin/magento, bin/start, ...)
# are replaced by logging stubs.
#
# Usage:  bash tests/test-profile-commands.sh
set -Eeuo pipefail
# shellcheck source=tests/lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/lib.sh"

# Fake docker: log commands, report memory so the RAM checks in setup and start pass.
install_docker() {
  cat > "$SANDBOX/.fakebin/docker" <<'STUB'
#!/usr/bin/env bash
if [[ "${1:-}" == compose && "${2:-}" == version ]]; then exit 0; fi
printf 'docker %s\n' "$*" >> "${KIT_LOG_DIR:?}/docker.log"
if [[ "${1:-}" == info ]]; then
  if [[ "${2:-}" == -f ]]; then echo 16000000000; else echo 'Total Memory: 16GiB'; fi
fi
exit 0
STUB
  chmod 755 "$SANDBOX/.fakebin/docker"
  # Fake sudo: never writes the real /etc/hosts.
  cat > "$SANDBOX/.fakebin/sudo" <<'STUB'
#!/usr/bin/env bash
printf 'sudo %s\n' "$*" >> "${KIT_LOG_DIR:?}/sudo.log"
cat > /dev/null
STUB
  chmod 755 "$SANDBOX/.fakebin/sudo"
}

# Stub that writes `<name> <args>` to calls.log for each given bin/ command.
stub_bins() {
  local name
  for name in "$@"; do
  # String for a subshell or a fixture, left with its literal $ character.
  # shellcheck disable=SC2016
    printf '#!/usr/bin/env bash\nprintf "%s %%s\\n" "$*" >> "${KIT_LOG_DIR:?}/calls.log"\n' "$name" > "$ROOT/bin/$name"
    chmod 755 "$ROOT/bin/$name"
  done
}

calls() { cat "$KIT_LOG_DIR/calls.log" 2>/dev/null || true; }

# Installed Docker root, KIT_DOMAIN and KIT_STATIC_LOCALES from the arguments (may be empty).
new_root() {
  local domain="${1-shop.test}" locales="${2-}"
  sandbox_new
  install_docker
  kit_new shop >/dev/null
  ROOT="$SANDBOX/shop"
  sed -i "s|^KIT_DOMAIN=.*|KIT_DOMAIN=$domain|" "$ROOT/project/profile.env"
  if [[ -n "$locales" ]]; then
    printf 'KIT_STATIC_LOCALES=%s\n' "$locales" >> "$ROOT/project/profile.env"
  fi
}

test_setup_uses_profile_domain() {
  new_root shop.test
  stub_bins stop start setup-install copyfromcontainer setup-domain fixowns fixperms clinotty
  run_in "$ROOT" bin/setup
  assert_status 0 'bin/setup exits 0 without an argument'
  assert_contains 'setup-install shop.test' 'setup-install gets KIT_DOMAIN' "$(calls)"
  assert_contains 'setup-domain shop.test' 'setup-domain gets KIT_DOMAIN' "$(calls)"
}

test_setup_argument_wins() {
  new_root shop.test
  stub_bins stop start setup-install copyfromcontainer setup-domain fixowns fixperms clinotty
  run_in "$ROOT" bin/setup other.test
  assert_status 0 'bin/setup accepts an explicit domain'
  assert_contains 'setup-install other.test' 'argument beats KIT_DOMAIN' "$(calls)"
  assert_not_contains 'shop.test' 'KIT_DOMAIN is not used when an argument is given' "$(calls)"
}

test_setup_stops_without_domain() {
  new_root ''
  stub_bins stop start setup-install
  run_in "$ROOT" bin/setup
  assert_status 1 'bin/setup stops when KIT_DOMAIN is empty'
  assert_contains 'KIT_DOMAIN' 'message names the missing key'
  assert_equals '' "$(calls)" 'nothing ran before the check'
}

test_setup_domain_uses_profile_domain() {
  new_root shop.test
  stub_bins clinotty setup-ssl
  run_in "$ROOT" bin/setup-domain
  assert_status 0 'bin/setup-domain exits 0 without an argument'
  assert_contains 'https://shop.test/' 'base_url is set from KIT_DOMAIN' "$(calls)"
  assert_contains 'setup-ssl shop.test' 'setup-ssl gets KIT_DOMAIN' "$(calls)"
}

test_setup_domain_stops_without_domain() {
  new_root ''
  stub_bins clinotty setup-ssl
  run_in "$ROOT" bin/setup-domain
  assert_status 1 'bin/setup-domain stops when KIT_DOMAIN is empty'
  assert_contains 'KIT_DOMAIN' 'message names the missing key'
  assert_equals '' "$(calls)" 'nothing ran before the check'
}

test_setup_ssl_uses_profile_domain() {
  new_root shop.test
  stub_bins setup-ssl-ca restart
  run_in "$ROOT" bin/setup-ssl
  assert_status 0 'bin/setup-ssl exits 0 without an argument'
  assert_docker_called 'mkcert -key-file nginx.key -cert-file nginx.crt shop.test' 'certificate is made for KIT_DOMAIN'
}

test_setup_ssl_arguments_win() {
  new_root shop.test
  stub_bins setup-ssl-ca restart
  run_in "$ROOT" bin/setup-ssl a.test b.test:443
  assert_status 0 'bin/setup-ssl accepts domains'
  assert_docker_called 'mkcert -key-file nginx.key -cert-file nginx.crt a.test b.test' 'port is stripped and arguments win'
  assert_file_does_not_match "$KIT_LOG_DIR/docker.log" 'shop\.test' 'KIT_DOMAIN not used when arguments exist'
}

test_setup_ssl_stops_without_domain() {
  new_root ''
  stub_bins setup-ssl-ca restart
  run_in "$ROOT" bin/setup-ssl
  assert_status 1 'bin/setup-ssl stops when KIT_DOMAIN is empty'
  assert_contains 'KIT_DOMAIN' 'message names the missing key'
  assert_docker_not_called 'docker was not called'
}

# Fake nproc so the job count does not depend on the test machine.
fake_nproc() {
  printf '#!/usr/bin/env bash\necho %s\n' "$1" > "$SANDBOX/.fakebin/nproc"
  chmod 755 "$SANDBOX/.fakebin/nproc"
}

test_deploy_default_locales_and_jobs() {
  new_root shop.test 'en_US vi_VN'
  stub_bins composer magento cli
  fake_nproc 6
  run_in "$ROOT" bin/deploy
  assert_status 0 'bin/deploy exits 0 without an argument'
  assert_contains 'magento setup:static-content:deploy en_US vi_VN -j6 -f' 'locales from KIT_STATIC_LOCALES, jobs from nproc' "$(calls)"
}

test_deploy_default_locale_without_key() {
  new_root shop.test
  stub_bins composer magento cli
  fake_nproc 2
  run_in "$ROOT" bin/deploy
  assert_status 0 'bin/deploy works with no KIT_STATIC_LOCALES'
  assert_contains 'magento setup:static-content:deploy en_US -j2 -f' 'falls back to the package default en_US' "$(calls)"
}

test_deploy_arguments_win() {
  new_root shop.test 'en_US vi_VN'
  stub_bins composer magento cli
  fake_nproc 4
  run_in "$ROOT" bin/deploy fr_FR
  assert_status 0 'bin/deploy accepts locales'
  assert_contains 'magento setup:static-content:deploy fr_FR -j4 -f' 'arguments replace KIT_STATIC_LOCALES' "$(calls)"
  assert_not_contains 'vi_VN' 'profile locales not used when arguments exist' "$(calls)"
}

test_deploy_fast_not_shipped() {
  assert_absent "$KIT_REPO_ROOT/dist/files/bin/deploy-fast" 'bin/deploy-fast is not in the package'
  assert_file_does_not_match "$KIT_REPO_ROOT/dist/manifest" 'deploy-fast' 'manifest does not list deploy-fast'
}

test_opcache_file_is_mounted() {
  assert_file "$KIT_REPO_ROOT/dist/files/conf/php/opcache.ini" 'OPcache file ships with the package'
  assert_file_matches "$KIT_REPO_ROOT/dist/manifest" ' conf/php/opcache\.ini$' 'OPcache file is in the manifest'
  assert_file_matches "$KIT_REPO_ROOT/dist/files/compose.dev.yaml" 'conf/php/opcache\.ini:/usr/local/etc/php/conf\.d/zz-opcache\.ini' 'compose.dev.yaml mounts it'
  new_root
  assert_file "$ROOT/conf/php/opcache.ini" 'installer writes the OPcache file'
  if docker compose version >/dev/null 2>&1; then
    PATH="$ORIG_PATH" run_in "$ROOT" bin/docker-compose config
    assert_status 0 'compose config is valid'
    assert_contains 'zz-opcache.ini' 'phpfpm gets the OPcache mount' "$OUTPUT"
  fi
}

test_make_runs_project_command() {
  new_root
  mkdir -p "$ROOT/project/bin"
  printf '#!/usr/bin/env bash\necho "project-hello $*"\n' > "$ROOT/project/bin/hello"
  chmod 755 "$ROOT/project/bin/hello"
  run_in "$ROOT" make hello one two
  assert_status 0 'make runs a project command'
  assert_contains 'project-hello one two' 'arguments are passed to the project command'
  run_in "$ROOT" make unknown-target
  assert_status 0 'make is still a no-op for an unknown target'
  assert_equals '' "$OUTPUT" 'unknown target prints nothing'
}

test_make_project_command_in_help() {
  new_root
  mkdir -p "$ROOT/project/bin"
  printf '#!/usr/bin/env bash\ntrue\n' > "$ROOT/project/bin/hello"
  chmod 755 "$ROOT/project/bin/hello"
  run_in "$ROOT" make help
  assert_status 0 'make help works with project commands'
  assert_contains 'bin/hello' 'help lists the project command'
}

test_make_rejects_clashing_name() {
  new_root
  mkdir -p "$ROOT/project/bin"
  printf '#!/usr/bin/env bash\necho hijacked\n' > "$ROOT/project/bin/deploy"
  chmod 755 "$ROOT/project/bin/deploy"
  run_in "$ROOT" make deploy
  assert_status_nonzero 'make refuses a project command named like a package command'
  assert_contains 'clashes with a package command' 'message says the name clashes'
  assert_contains 'deploy' 'message names the command'
  assert_not_contains 'hijacked' 'the project command did not run'
}

test_make_keeps_wt_target() {
  assert_file_matches "$KIT_REPO_ROOT/dist/files/Makefile" '^wt:' 'Makefile has the wt target'
}

# Fake docker complete enough for bin/download and bin/setup to really run in the sandbox.
test_installer_setup_runs_download_then_setup() {
  sandbox_new
  install_docker
  run_installer new "$SANDBOX/shop" --source "$KIT_REPO_ROOT" --domain shop.test --setup --magento 2.4.7
  assert_status 0 'install.sh new --setup exits 0'
  local log="$KIT_LOG_DIR/docker.log" dl st
  dl="$(grep -n 'create-project' "$log" | head -1 | cut -d: -f1)"
  st="$(grep -n 'setup:install' "$log" | head -1 | cut -d: -f1)"
  assert_file_matches "$log" 'create-project .*project-community-edition=2\.4\.7' 'bin/download got the Magento version'
  assert_file_matches "$log" 'base-url=https://shop\.test/' 'bin/setup used the domain from the profile'
  if [[ -n "$dl" && -n "$st" && "$dl" -lt "$st" ]]; then
    pass_ 'download ran before setup'
  else
    fail_ 'download ran before setup' "download line [$dl], setup line [$st]"
  fi
}

test_installer_without_setup_runs_nothing() {
  sandbox_new
  install_docker
  run_installer new "$SANDBOX/shop" --source "$KIT_REPO_ROOT" --domain shop.test --magento 2.4.7
  assert_status 0 'install.sh new exits 0 without --setup'
  assert_docker_not_called 'no docker command ran without --setup'
}

test_installer_setup_needs_magento_and_domain() {
  sandbox_new
  install_docker
  run_installer new "$SANDBOX/a" --source "$KIT_REPO_ROOT" --domain shop.test --setup
  assert_status_nonzero '--setup without --magento fails'
  assert_contains '--magento' 'message names --magento'
  assert_absent "$SANDBOX/a" 'nothing installed on that failure'
  run_installer new "$SANDBOX/b" --source "$KIT_REPO_ROOT" --setup --magento 2.4.7
  assert_status_nonzero '--setup without --domain fails'
  assert_contains '--domain' 'message names --domain'
  assert_docker_not_called 'docker was not called'
}

run_tests
finish
