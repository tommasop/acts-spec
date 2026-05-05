# CI/CD Integration Examples

How to integrate ACTS validation in your pipeline.

---

## GitHub Actions

```yaml
name: ACTS Validation

on: [push, pull_request]

jobs:
  validate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - name: Setup Zig
        uses: mlugg/setup-zig@v1
        with:
          version: 0.13.0
      
      - name: Build ACTS
        working-directory: ./acts-core
        run: zig build release
      
      - name: Validate ACTS
        run: ./acts-core/zig-out/bin/acts validate
```

---

## GitLab CI

```yaml
validate-acts:
  image: alpine:latest
  before_script:
    - apk add --no-cache curl tar
    - curl -L https://github.com/tommasop/acts-spec/releases/download/v1.0.0/acts-linux-x86_64.tar.gz | tar xz
    - mv acts-linux-x86_64 /usr/local/bin/acts
  script:
    - acts validate
```

---

## Local Pre-commit Hook

```bash
#!/bin/sh
# .git/hooks/pre-commit

if [ -f .acts/acts.db ]; then
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
            curl -L https://github.com/tommasop/acts-spec/releases/download/v1.0.0/acts-linux-x86_64.tar.gz | tar xz
            sudo mv acts-linux-x86_64 /usr/local/bin/acts
      - run:
          name: Validate
          command: acts validate

workflows:
  validate:
    jobs:
      - validate
```
