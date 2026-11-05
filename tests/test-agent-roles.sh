#!/usr/bin/env bash
# Test S1 cho role và adapter model của bin/agent: ba role nguồn sinh adapter Claude
# Code (.claude/agents/*.md) và Codex (${CODEX_HOME}/agents/magento-*.toml), hạng
# model đọc từ agent/models.env, ghi đè từng ô bằng KIT_MODEL_<HARNESS>_<HẠNG>, quyền
# read-only hay write quyết định danh sách tool của Claude, file không do gói sinh
# được giữ nguyên, adapter cũ bị dọn hoặc được nhắc xoá.
#
# Usage:  bash tests/test-agent-roles.sh
set -Eeuo pipefail
# shellcheck source=tests/lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/lib.sh"

set_profile() {
  sed -i "s|^$1=.*|$1=$2|" "$ROOT/project/profile.env"
}

new_root() {
  sandbox_new
  kit_new shop --domain shop.test > /dev/null
  ROOT="$SANDBOX/shop"
  export CODEX_HOME="$SANDBOX/codex"
  set_profile KIT_GIT_REMOTE origin
  set_profile KIT_GIT_BASE_BRANCH master
  set_profile KIT_GIT_TARGET_BRANCH staging
}

agent() {
  run_in "$ROOT" bin/agent "$@"
}

test_adapters_for_both_harnesses() {
  new_root
  agent install
  assert_status 0 'install sinh adapter thoát 0'
  assert_file "$ROOT/.claude/agents/magento-researcher.md" 'có adapter Claude cho researcher'
  assert_file "$ROOT/.claude/agents/magento-developer.md" 'có adapter Claude cho developer'
  assert_file "$ROOT/.claude/agents/magento-reviewer.md" 'có adapter Claude cho reviewer'
  assert_file "$CODEX_HOME/agents/magento-researcher.toml" 'có adapter Codex cho researcher'
  assert_file "$CODEX_HOME/agents/magento-developer.toml" 'có adapter Codex cho developer'
  assert_file "$CODEX_HOME/agents/magento-reviewer.toml" 'có adapter Codex cho reviewer'
  assert_file_matches "$ROOT/.claude/agents/magento-researcher.md" '^name: magento-researcher$' 'adapter Claude có name'
  assert_file_matches "$ROOT/.claude/agents/magento-researcher.md" '^description: .+' 'adapter Claude có description'
  assert_file_matches "$ROOT/.claude/agents/magento-researcher.md" '^model: haiku$' 'hạng fast thành alias haiku'
  assert_file_matches "$ROOT/.claude/agents/magento-developer.md" '^model: opus$' 'hạng deep thành alias opus'
  assert_file_matches "$ROOT/.claude/agents/magento-reviewer.md" '^model: sonnet$' 'hạng default thành alias sonnet'
  assert_file_matches "$CODEX_HOME/agents/magento-researcher.toml" '^model = "gpt-5.4-mini"$' 'Codex tách model khỏi hạng fast'
  assert_file_matches "$CODEX_HOME/agents/magento-researcher.toml" '^model_reasoning_effort = "low"$' 'Codex tách effort của hạng fast'
  assert_file_matches "$CODEX_HOME/agents/magento-developer.toml" '^model_reasoning_effort = "high"$' 'Codex có effort của hạng deep'
  assert_file_matches "$CODEX_HOME/agents/magento-developer.toml" '^name = "magento-developer"$' 'adapter Codex có name'
}

test_body_copied_verbatim() {
  new_root
  agent install
  assert_file_matches "$ROOT/.claude/agents/magento-researcher.md" 'Bạn điều tra rồi trả lời, không sửa file' 'adapter Claude chép nguyên thân role'
  assert_file_matches "$CODEX_HOME/agents/magento-researcher.toml" 'Bạn điều tra rồi trả lời, không sửa file' 'adapter Codex chép nguyên thân role'
  assert_file_matches "$CODEX_HOME/agents/magento-developer.toml" 'gate \| lệnh \| PASS/FAIL' 'thân role developer giữ bảng bằng chứng gate'
}

test_permission_maps_tools() {
  new_root
  agent install
  assert_file_matches "$ROOT/.claude/agents/magento-researcher.md" '^tools: Read, Grep, Glob, Bash$' 'role chỉ đọc không có tool ghi'
  assert_file_matches "$ROOT/.claude/agents/magento-reviewer.md" '^tools: Read, Grep, Glob, Bash$' 'role reviewer chỉ đọc không có tool ghi'
  assert_file_matches "$ROOT/.claude/agents/magento-developer.md" '^tools: Read, Grep, Glob, Bash, Edit, Write$' 'role write có Edit và Write'
}

test_model_override_per_cell() {
  new_root
  printf 'KIT_MODEL_CLAUDE_FAST=inherit\nKIT_MODEL_CODEX_DEEP=deepseek-v4-pro:max\n' >> "$ROOT/project/profile.env"
  agent install
  assert_status 0 'install với ghi đè model thoát 0'
  assert_file_matches "$ROOT/.claude/agents/magento-researcher.md" '^model: inherit$' 'ghi đè KIT_MODEL_CLAUDE_FAST có hiệu lực'
  assert_file_matches "$CODEX_HOME/agents/magento-developer.toml" '^model = "deepseek-v4-pro"$' 'ghi đè KIT_MODEL_CODEX_DEEP đổi model'
  assert_file_matches "$CODEX_HOME/agents/magento-developer.toml" '^model_reasoning_effort = "max"$' 'ghi đè KIT_MODEL_CODEX_DEEP đổi effort'
  assert_file_matches "$CODEX_HOME/agents/magento-reviewer.toml" '^model = "gpt-5.3-codex"$' 'ô không ghi đè giữ mặc định'
}

test_project_role_gets_codex_prefix() {
  new_root
  mkdir -p "$ROOT/project/agent/roles"
  cat > "$ROOT/project/agent/roles/acme-reviewer.md" <<'EOF'
---
name: acme-reviewer
description: Soát quy ước riêng của dự án.
permission: read-only
model: default
---
Bạn là role riêng của dự án.
EOF
  agent install
  assert_status 0 'install với role dự án thoát 0'
  assert_file "$ROOT/.claude/agents/acme-reviewer.md" 'role dự án có adapter Claude'
  assert_file "$CODEX_HOME/agents/magento-acme-reviewer.toml" 'role dự án có adapter Codex mang tiền tố magento-'
  assert_file_matches "$CODEX_HOME/agents/magento-acme-reviewer.toml" '^name = "magento-acme-reviewer"$' 'adapter Codex dùng tên có tiền tố'
}

test_invalid_role_is_skipped() {
  new_root
  mkdir -p "$ROOT/project/agent/roles"
  cat > "$ROOT/project/agent/roles/thieu-quyen.md" <<'EOF'
---
name: thieu-quyen
description: Role thiếu permission.
model: default
---
Thân role.
EOF
  agent install
  assert_status 0 'install bỏ qua role sai nhưng vẫn thoát 0'
  assert_contains 'read-only hoặc write' 'báo role thiếu permission'
  assert_absent "$ROOT/.claude/agents/thieu-quyen.md" 'không sinh adapter cho role sai'
  assert_absent "$CODEX_HOME/agents/magento-thieu-quyen.toml" 'không sinh adapter Codex cho role sai'
}

test_non_generated_adapter_preserved() {
  new_root
  agent install
  sed -i '/kit:generated/d' "$ROOT/.claude/agents/magento-researcher.md"
  printf 'giữ nguyên bản của người dùng\n' >> "$ROOT/.claude/agents/magento-researcher.md"
  agent install
  assert_status 0 'install lần hai thoát 0'
  assert_contains 'không do bin/agent sinh' 'báo giữ file không do gói sinh'
  assert_file_matches "$ROOT/.claude/agents/magento-researcher.md" 'giữ nguyên bản của người dùng' 'không ghi đè file người dùng'
}

test_stale_generated_adapters_removed() {
  new_root
  agent install
  printf '<!-- kit:generated bởi bin/agent install -->\nrole cũ\n' > "$ROOT/.claude/agents/role-cu.md"
  printf '# kit:generated bởi bin/agent install\nname = "magento-role-cu"\n' > "$CODEX_HOME/agents/magento-role-cu.toml"
  agent install
  assert_status 0 'install dọn adapter cũ thoát 0'
  assert_absent "$ROOT/.claude/agents/role-cu.md" 'xoá adapter Claude không còn nguồn'
  assert_absent "$CODEX_HOME/agents/magento-role-cu.toml" 'xoá adapter Codex không còn nguồn'
}

test_legacy_adapters_warned_not_deleted() {
  new_root
  agent install
  printf -- '---\nname: magento-verifier\n---\ncũ\n' > "$ROOT/.claude/agents/magento-verifier.md"
  printf 'name = "luna-worker"\n' > "$CODEX_HOME/agents/luna-worker.toml"
  agent install
  assert_status 0 'install có adapter cũ vẫn thoát 0'
  assert_contains 'magento-verifier.md' 'nhắc adapter Claude cũ'
  assert_contains 'luna-worker.toml' 'nhắc adapter Codex cũ'
  assert_file "$ROOT/.claude/agents/magento-verifier.md" 'không tự xoá adapter cũ'
  assert_file "$CODEX_HOME/agents/luna-worker.toml" 'không tự xoá adapter Codex cũ'
}

test_install_is_idempotent() {
  new_root
  agent install
  local before_root before_codex
  before_root="$(tree_digest "$ROOT")"
  before_codex="$(tree_digest "$CODEX_HOME")"
  agent install
  assert_status 0 'install lần hai thoát 0'
  assert_not_contains 'Đã ghi' 'lần hai không ghi lại file'
  assert_equals "$before_root" "$(tree_digest "$ROOT")" 'lần hai không đổi file trong Docker root'
  assert_equals "$before_codex" "$(tree_digest "$CODEX_HOME")" 'lần hai không đổi adapter Codex'
}

test_skill_installed_with_roles() {
  new_root
  agent install
  assert_file "$ROOT/.agents/skills/magento-workflow/SKILL.md" 'cài skill magento-workflow vào .agents/skills'
  assert_file "$ROOT/.claude/skills/magento-workflow/SKILL.md" 'cài skill magento-workflow vào .claude/skills'
  assert_file "$ROOT/.agents/skills/magento-workflow/references/gates.md" 'skill có reference ma trận gate'
  assert_file "$ROOT/.agents/skills/magento-workflow/references/git-mr.md" 'skill có reference Git và MR'
  assert_file "$ROOT/.agents/skills/magento-workflow/references/worktree.md" 'skill có reference worktree'
  assert_file_matches "$ROOT/.agents/skills/magento-workflow/SKILL.md" 'không phải trình tự làm việc' 'SKILL nói rõ là tri thức, không phải quy trình'
}

run_tests
finish
