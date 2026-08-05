---

description: Pre-flight risk analysis for a task — traces call chains, identifies cross-repo impact, and classifies risk
agent: build

---

Run a tech lead pre-flight analysis on change $ARGUMENTS.

Use the `acts_tech_lead_analysis` tool with change_id "$ARGUMENTS".

If no change ID is provided, first run `acts stack status` to list active changes, then ask which change to analyze.

After receiving the report, interpret the results and provide actionable recommendations:
- Highlight any CRITICAL cross-repo impacts that require deployment coordination
- Identify HIGH-risk symbols that need backward compatibility checks
- Suggest code review priorities for high-complexity functions
- Note any blast radius concerns
