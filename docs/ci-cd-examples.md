# CI/CD Integration Examples

How to integrate ACTS v2 validation and the full stack lifecycle into your pipeline.

---

## GitHub Actions

Build, test, and exercise the full v2 lifecycle. This mirrors [`.github/workflows/ci.yml`](../.github/workflows/ci.yml):

```yaml
name: ACTS CI

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Setup Zig
        uses: mlugg/setup-zig@v1
        with:
          version: 0.13.0

      - name: Build
        working-directory: ./acts-core
        run: zig build

      - name: Run unit tests
        working-directory: ./acts-core
        run: zig build test

      - name: Run plugin tests
        run: npm test

      - name: Smoke test — full v2 stack lifecycle
        run: |
          set -euo pipefail
          BIN="$(pwd)/acts-core/zig-out/bin/acts"
          git config --global user.email "ci@example.com"
          git config --global user.name "CI"

          mkdir -p /tmp/acts-ci && cd /tmp/acts-ci
          git init -q -b main
          echo "# ci" > README.md
          git add . && git commit -qm init

          mkdir -p .acts
          cat > package.json <<'EOF'
          { "name":"ci","scripts":{"test":"node -e 'process.exit(0)'","lint":"node -e 'process.exit(0)'","build":"node -e 'process.exit(0)'"} }
          EOF
          cat > .acts/acts.json <<'EOF'
          { "quality_gate": { "test":"npm test", "lint":"npm run lint", "typecheck":null, "build":"npm run build" } }
          EOF
          git add -A && git commit -qm "setup"

          "$BIN" stack create ci -t "CI stack"
          git add .acts && git commit -qm "stack manifest"
          "$BIN" change add c1 -t "Feature" --accept "works"
          git add . && git commit -qm "c1"

          # Gate: review must fail before verify
          if "$BIN" review c1 2>/dev/null; then
            echo "ERROR: review should have been blocked before verify"
            exit 1
          fi

          "$BIN" verify c1
          "$BIN" approve c1
          "$BIN" stack land
          "$BIN" validate
```

---

## GitLab CI

```yaml
acts-validation:
  image: alpine:latest
  before_script:
    - apk add --no-cache curl tar zig
    - cd acts-core && zig build release -Dversion=2.0.0 && cd ..
    - cp acts-core/zig-out/bin/acts /usr/local/bin/acts
  script:
    - acts validate
```

---

## Local Pre-commit Hook

```bash
#!/bin/sh
# .git/hooks/pre-commit

if [ -f .acts/stack.json ]; then
  acts validate || exit 1
fi
```

---

## Makefile Target

```makefile
validate:
	acts validate

ci: validate test lint
```

---

## CircleCI

```yaml
version: 2.1

jobs:
  validate:
    docker:
      - image: cimg/base:stable
    steps:
      - checkout
      - run:
          name: Install ACTS
          command: |
            cd acts-core
            curl -L https://ziglang.org/download/0.13.0/zig-linux-x86_64-0.13.0.tar.xz | tar xJ
            export PATH="$PWD/zig-linux-x86_64-0.13.0:$PATH"
            zig build release -Dversion=2.0.0
            sudo cp zig-out/bin/acts /usr/local/bin/acts
      - run:
          name: Validate
          command: acts validate

workflows:
  validate:
    jobs:
      - validate
```
