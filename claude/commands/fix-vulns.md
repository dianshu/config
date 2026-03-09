---
description: Scan and Fix Vulnerabilities
---

# Multi-Dockerfile Vulnerability Pipeline

> Discover, scan, triage, fix, and report CVEs across all Dockerfiles in a repo. Runs autonomously with parallel agents.

## Phase 1 — Discovery & Setup

1. **Find all Dockerfiles** in the repo:
   ```bash
   find . -name 'Dockerfile*' -not -path '*/.git/*' -not -path '*/node_modules/*' -not -path '*/vendor/*'
   ```
2. **Check exclusions** — skip known build-only or test Dockerfiles (configurable list below).
3. **Group by parent git repository** if working across a monorepo or multi-repo structure.
4. **Auth to ACR** (one-time):
   ```bash
   az acr login --name aihardware
   ```
5. **Create a branch** in each affected repo:
   ```bash
   git checkout -b fix/vulns-$(date +%Y%m%d)
   ```

### Exclusion List (configurable)
Skip these Dockerfiles unless explicitly requested:
- `Test/openwrt/Dockerfile`
- Any path containing `/test/` or `/example/` (case-insensitive)

---

## Phase 2 — Parallel Scan & Fix

Dispatch **parallel agents** (2–3 at a time) per Dockerfile. Each agent runs the full cycle below.

### Per-Dockerfile Agent Template

#### Step 1: Build
```bash
docker build --no-cache --pull -t vuln-scan-$(basename $(dirname $DOCKERFILE)):latest -f $DOCKERFILE $(dirname $DOCKERFILE)
```
If the build fails, log the error and skip this Dockerfile.

#### Step 2: Dual-Scanner Scan
Run **both** scanners and capture JSON output:

**Trivy:**
```bash
trivy image --ignore-unfixed --format json --output trivy-results.json vuln-scan-IMAGE:latest
```

**Grype:**
```bash
grype vuln-scan-IMAGE:latest --only-fixed --output json > grype-results.json
```

If either scanner is not installed, install it or fall back to the available one. Both scanners are preferred for cross-validation.

#### Step 3: Merge & Deduplicate
- Parse both JSON outputs
- Deduplicate CVEs by **CVE ID** — union of findings from both scanners
- For each CVE, record: CVE ID, package name, installed version, fixed version, severity, scanner source

#### Step 4: Triage Each CVE
Classify every CVE as **fixable** or **unfixable**:

| Classification | Criteria |
|---|---|
| **Fixable** | Package appears in our `requirements.txt`, `pyproject.toml`, `package.json`, or Dockerfile `apt-get`/`apk add` lines **AND** a fixed version exists |
| **Unfixable** | Package inherited from base image layer, OR no fix version available, OR fix breaks the build |

#### Step 5: Apply Minimal Fixes
For each fixable CVE, apply the **smallest change** that resolves it:

**Common fix patterns:**

- **pip version bump** (requirements.txt):
  ```
  # Before
  cryptography==41.0.3
  # After
  cryptography==42.0.5
  ```

- **pip version bump** (pyproject.toml):
  ```toml
  # Before
  dependencies = ["cryptography>=41.0.3"]
  # After
  dependencies = ["cryptography>=42.0.5"]
  ```

- **apt-get version pin**:
  ```dockerfile
  # Before
  RUN apt-get install -y libssl3
  # After
  RUN apt-get install -y libssl3=3.0.13-1~deb12u1
  ```

- **apk version pin**:
  ```dockerfile
  # Before
  RUN apk add --no-cache openssl
  # After
  RUN apk add --no-cache openssl=3.1.4-r6
  ```

- **Base image update** (when most CVEs come from an outdated base):
  ```dockerfile
  # Before
  FROM python:3.11-slim-bullseye
  # After
  FROM python:3.11-slim-bookworm
  ```

- **Multi-stage build considerations**: If the Dockerfile uses multi-stage builds, only fix packages in the final stage unless a build-stage vulnerability leaks into the final image.

#### Step 6: Rebuild & Verify
```bash
docker build --no-cache -t vuln-scan-IMAGE:latest -f $DOCKERFILE $(dirname $DOCKERFILE)
trivy image --ignore-unfixed --format json vuln-scan-IMAGE:latest
```
Compare new scan results against original. Confirm fixed CVEs are resolved.

#### Step 7: Revert on Failure
If the rebuild fails after a fix:
1. `git checkout -- <modified-files>` to revert that specific fix
2. Reclassify the CVE as **unfixable** with reason: "fix breaks build"
3. Continue with remaining fixes

---

## Phase 3 — Reporting

Generate `VULNERABILITY_REPORT.md` in each repo root with:

### Report Template

```markdown
# Vulnerability Report — YYYY-MM-DD

## Summary

| Metric | Count |
|--------|-------|
| Dockerfiles scanned | N |
| Total unique CVEs found | N |
| Fixed | N |
| Unfixable (upstream/no-fix) | N |

## Fixed Vulnerabilities

| CVE ID | Package | Old Version | New Version | Severity | Fix Description |
|--------|---------|-------------|-------------|----------|-----------------|
| CVE-XXXX-XXXXX | package-name | 1.0.0 | 1.0.1 | HIGH | Version bump in requirements.txt |

## Unfixable Vulnerabilities

| CVE ID | Package | Severity | Reason | Upstream Link |
|--------|---------|----------|--------|---------------|
| CVE-XXXX-XXXXX | package-name | MEDIUM | Inherited from base image python:3.11-slim | https://github.com/... |

## Scanner Details

- **Trivy version**: X.X.X
- **Grype version**: X.X.X
- **Scan date**: YYYY-MM-DD
```

---

## Phase 4 — PR Creation

1. Stage all changes including `VULNERABILITY_REPORT.md`
2. Use the `/git-push` skill to commit, push, and create a PR per repo
3. PR title: `fix: remediate container vulnerabilities (YYYY-MM-DD)`
4. PR body should include the Summary table from the vulnerability report
5. Print a final summary of all PRs created

---

## Autonomy Rules

- **Only stop** if a fix breaks a build **and** the revert also fails
- Do **not** stop for unfixable CVEs — document them and continue
- Do **not** prompt the user mid-pipeline — complete the full cycle, then present results
- If both scanners fail to install, fall back to whichever one is available
- If neither scanner is available, stop and inform the user

## Usage

```
/fix-vulns
```

No arguments required — the skill discovers Dockerfiles automatically. To scan a specific Dockerfile only, tell the agent which one to target before invoking.
