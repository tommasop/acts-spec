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
      
      - name: Install dependencies
        run: npm install -g ajv-cli
      
      - name: Validate ACTS
        run: ./scripts/validate.sh --json
```

---

## GitLab CI

```yaml
acts-validation:
  image: node:20
  script:
    - npm install -g ajv-cli
    - ./scripts/validate.sh --json
  only:
    - merge_requests
    - main
```

---

## What Gets Validated

- AGENT.md has required sections
- state.json is valid JSON
- Session files follow naming convention
- All required operations exist
- No DONE tasks with empty files_touched
- No IN_PROGRESS tasks without assignee

---

## Validation Output

```json
{"pass": 42, "fail": 0, "warn": 1}
```

Non-zero `fail` count = merge blocked.

---

## Without GitHuman (CI-only)

If you don't want to install GitHuman in CI:

```yaml
- name: Validate ACTS
  run: ./scripts/validate.sh --json
  env:
    ACTS_NO_GITHUMAN: true
```

This skips GitHuman availability checks.
