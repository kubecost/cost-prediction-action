# Enhanced Features: Delta Mode and Cost Thresholds

This document describes the enhanced features added to the Kubecost Cost Prediction Action.

## Overview

The enhanced action adds two major features:
1. **Delta/Diff Mode** - Compare costs between branches to see the impact of changes
2. **Cost Threshold Checks** - Automatically fail workflows when cost increases exceed configured limits

## Delta/Diff Mode

### What is Delta Mode?

Delta mode compares the cost prediction of your current branch against a base branch (typically `main` or `master`). This shows you exactly how much your changes will increase or decrease costs.

### How to Enable

```yaml
- name: Run prediction with delta mode
  uses: ./action-enhanced
  with:
    path: ./manifests
    enable_delta_mode: "true"
    base_ref: "main"  # Branch to compare against
```

### Outputs

When delta mode is enabled, you get additional outputs:

- `BASE_COST` - The cost from the base branch
- `COST_CHANGE` - The absolute cost difference (e.g., "+15.50" or "-5.25")
- `COST_CHANGE_PERCENTAGE` - The percentage change (e.g., "+12.5" or "-8.3")

### Example Output

```
Current Cost: $125.50
Base Cost (main): $110.00
Cost Change: +$15.50 (+14.09%) - INCREASE
```

## Cost Threshold Checks

### What are Cost Thresholds?

Cost thresholds allow you to automatically fail a workflow if cost increases exceed acceptable limits. This prevents accidentally merging expensive changes.

### Configuration Options

```yaml
- name: Run prediction with thresholds
  uses: ./action-enhanced
  with:
    path: ./manifests
    enable_delta_mode: "true"
    base_ref: "main"
    
    # Threshold settings
    max_cost_increase: "50.00"      # Fail if cost increases by more than $50/month
    max_cost_percentage: "20"       # Fail if cost increases by more than 20%
    fail_on_threshold: "true"       # Set to "false" to only warn
```

### Threshold Behavior

- **Both thresholds are checked** - If either threshold is exceeded, the action will fail (if `fail_on_threshold` is true)
- **Absolute threshold** (`max_cost_increase`) - Checks the dollar amount increase
- **Percentage threshold** (`max_cost_percentage`) - Checks the percentage increase
- **Warning mode** - Set `fail_on_threshold: "false"` to only warn without failing

### Example Scenarios

#### Scenario 1: Cost increase within limits
```
Current: $110.00
Base: $100.00
Change: +$10.00 (+10%)

Thresholds:
- max_cost_increase: $50.00 ✓ PASS
- max_cost_percentage: 20% ✓ PASS

Result: Workflow continues
```

#### Scenario 2: Absolute threshold exceeded
```
Current: $160.00
Base: $100.00
Change: +$60.00 (+60%)

Thresholds:
- max_cost_increase: $50.00 ✗ FAIL
- max_cost_percentage: 20% ✗ FAIL

Result: Workflow fails (if fail_on_threshold is true)
```

#### Scenario 3: Percentage threshold exceeded
```
Current: $130.00
Base: $100.00
Change: +$30.00 (+30%)

Thresholds:
- max_cost_increase: $50.00 ✓ PASS
- max_cost_percentage: 20% ✗ FAIL

Result: Workflow fails (if fail_on_threshold is true)
```

## Complete Input Reference

### Required Inputs

| Input | Description | Default |
|-------|-------------|---------|
| `path` | Path to workload file or directory | (required) |

### Optional Inputs

| Input | Description | Default |
|-------|-------------|---------|
| `kubecost_api_path` | URL of Kubecost API | (none) |
| `log_level` | Log level (debug, info, warn, error) | `info` |
| `enable_delta_mode` | Enable cost comparison with base branch | `false` |
| `base_ref` | Base branch for comparison | `main` |
| `max_cost_increase` | Max allowed cost increase in dollars | (none) |
| `max_cost_percentage` | Max allowed cost increase percentage | (none) |
| `fail_on_threshold` | Fail workflow when threshold exceeded | `true` |

## Complete Output Reference

### Standard Outputs

| Output | Description |
|--------|-------------|
| `PREDICTION_TABLE` | ASCII table of cost prediction |
| `PREDICTION_JSON` | JSON formatted prediction data |
| `TOTAL_MONTHLY_COST` | Total monthly cost |
| `THRESHOLD_EXCEEDED` | Whether thresholds were exceeded (true/false) |

### Delta Mode Outputs

| Output | Description |
|--------|-------------|
| `BASE_COST` | Cost from base branch |
| `COST_CHANGE` | Absolute cost difference |
| `COST_CHANGE_PERCENTAGE` | Percentage cost change |

## Usage Examples

### Example 1: Basic Delta Mode

```yaml
name: Cost Check
on: [pull_request]

jobs:
  cost-check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
        with:
          fetch-depth: 0  # Required for delta mode
      
      - name: Check cost impact
        uses: ./action-enhanced
        with:
          path: ./k8s
          enable_delta_mode: "true"
          base_ref: "main"
```

### Example 2: Strict Cost Governance

```yaml
name: Cost Governance
on: [pull_request]

jobs:
  enforce-cost-limits:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
        with:
          fetch-depth: 0
      
      - name: Enforce cost limits
        uses: ./action-enhanced
        with:
          path: ./k8s
          enable_delta_mode: "true"
          base_ref: "main"
          max_cost_increase: "100.00"
          max_cost_percentage: "15"
          fail_on_threshold: "true"
```

### Example 3: Warning Only (No Failure)

```yaml
name: Cost Monitoring
on: [pull_request]

jobs:
  monitor-costs:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
        with:
          fetch-depth: 0
      
      - name: Monitor cost changes
        uses: ./action-enhanced
        with:
          path: ./k8s
          enable_delta_mode: "true"
          base_ref: "main"
          max_cost_increase: "50.00"
          max_cost_percentage: "10"
          fail_on_threshold: "false"  # Only warn
```

### Example 4: PR Comment with Delta

```yaml
name: Cost Prediction
on: [pull_request]

jobs:
  predict:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
        with:
          fetch-depth: 0
      
      - name: Run prediction
        id: prediction
        uses: ./action-enhanced
        with:
          path: ./k8s
          enable_delta_mode: "true"
          base_ref: "main"
      
      - name: Comment on PR
        uses: actions/github-script@v6
        with:
          script: |
            const output = `## Cost Impact Analysis
            
            **Current Cost:** $\`${{ steps.prediction.outputs.TOTAL_MONTHLY_COST }}\`
            **Base Cost:** $\`${{ steps.prediction.outputs.BASE_COST }}\`
            **Change:** \`${{ steps.prediction.outputs.COST_CHANGE }}\` (\`${{ steps.prediction.outputs.COST_CHANGE_PERCENTAGE }}%\`)
            
            <details>
            <summary>Detailed Breakdown</summary>
            
            \`\`\`
            ${{ steps.prediction.outputs.PREDICTION_TABLE }}
            \`\`\`
            </details>`;
            
            github.rest.issues.createComment({
              issue_number: context.issue.number,
              owner: context.repo.owner,
              repo: context.repo.repo,
              body: output
            });
```

## Implementation Notes

### Requirements for Delta Mode

1. **Full Git History** - Use `fetch-depth: 0` in checkout action
2. **Base Branch Access** - The base branch must exist in the repository
3. **Consistent Paths** - The path must exist in both current and base branches

### Cost Parsing

The action parses cost information from the prediction table output. The parsing logic looks for:
- Lines containing "total" (case-insensitive)
- Numeric values in the format `XX.XX`

If your prediction table has a different format, the parsing may need adjustment.

### Threshold Logic

- Thresholds are only checked when `enable_delta_mode` is true
- If no thresholds are configured, no checks are performed
- Both absolute and percentage thresholds are checked independently
- If either threshold is exceeded, `THRESHOLD_EXCEEDED` is set to true

## Troubleshooting

### Delta mode not working

**Problem:** Base branch prediction fails
**Solution:** Ensure `fetch-depth: 0` is set in checkout action

### Thresholds not triggering

**Problem:** Workflow doesn't fail despite exceeding thresholds
**Solution:** Check that `fail_on_threshold` is set to "true" (not true without quotes)

### Cost parsing errors

**Problem:** Costs show as 0.00
**Solution:** Check that the prediction table format matches expected format with "total" line

## Future Enhancements

Potential improvements for future versions:
- Support for multiple base branches
- Cost breakdown by namespace/resource type
- Historical cost tracking
- Integration with cost allocation labels
- Support for custom cost parsing rules
- Support for env-label for environment specific pricing logic
- Dynamic thresholds based on Kubecost Budgets API
- Multi-cluster prediciton support
