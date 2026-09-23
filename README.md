# Kubernetes Cost Prediction Action

Predict the cost of Kubernetes manifests (specs) in CI! Make cost decisions before
merging changes.

This is a [GitHub Action](https://docs.github.com/en/actions/quickstart), powered by [Kubecost](https://docs.kubecost.com/install-and-configure/install), to make cost predictions for K8s workloads before they are applied to your cluster. It _does not_ require you to have Kubecost installed, but will produce highly-accurate, environment-specific predictions if you do.

In action:

![](./media/actioncomment.png)

---

## Actions in this Repository

| Action | Description |
|--------|-------------|
| [`kubecost/cost-prediction-action`](https://github.com/kubecost/cost-prediction-action) | **Base action** — predicts cost of K8s manifests and outputs a formatted table |
| [`./action-enhanced`](./action-enhanced/action.yaml) | **Enhanced action** — adds delta/diff mode, cost threshold enforcement, and budget checks on top of the base action |

---

## Base Action Usage

Add this Action as a step in one of your Actions workflows and point it at a single
YAML file or a directory containing at least one YAML file. Non-YAML files will be
ignored. The YAML files will be interpreted as Kubernetes manifests and a cost
prediction will be run on supported [Kubernetes object types](https://kubernetes.io/docs/concepts/overview/working-with-objects/kubernetes-objects/).

> If you aren't familiar with GitHub Actions, check out GitHub's [quickstart](https://docs.github.com/en/actions/quickstart) documentation.

### Simple

```yaml
- name: Run prediction
  id: prediction
  uses: kubecost/cost-prediction-action@v0.1.1
  with:
    path: ./repo

- name: Find existing PR comment
  uses: kubecost/github-actions/find-comment@main
  id: find-comment
  with:
    token: ${{ secrets.GITHUB_TOKEN }}
    issue-number: ${{ github.event.pull_request.number }}
    comment-author: 'github-actions[bot]'
    body-includes: '<!-- kubecost-prediction-results -->'
- name: Create or update PR comment with prediction results
  uses: kubecost/github-actions/create-or-update-comment@main
  with:
    token: ${{ secrets.GITHUB_TOKEN }}
    issue-number: ${{ github.event.pull_request.number }}
    comment-id: ${{ steps.find-comment.outputs.comment-id }}
    edit-mode: replace
    body: |
      <!-- kubecost-prediction-results -->

      ## Kubecost's total cost prediction for K8s YAML Manifests in this PR

      \```
      ${{ steps.prediction.outputs.PREDICTION_TABLE }}
      \```
```

### Advanced (full workflow)

```yaml
name: Predict K8s spec cost
on: [pull_request]

jobs:
  predict-cost:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          path: ./repo

      # Uncomment for GKE / port-forwarded Kubecost access:
      # - name: Forward the kubecost service
      #   run: |
      #     kubectl port-forward --namespace kubecost service/kubecost-cost-analyzer 9090 &
      #     sleep 5

      # For Helm-based repos, template first:
      # - name: Helm template
      #   run: helm template RELEASENAME ./repo >> ./templated.yaml

      - name: Run prediction
        id: prediction
        uses: kubecost/cost-prediction-action@v0.1.1
        with:
          log_level: "info"
          path: ./repo
          # kubecost_api_path: "http://localhost:9090/model"

      - name: Find existing PR comment
        uses: kubecost/github-actions/find-comment@main
        id: find-comment
        with:
          token: ${{ secrets.GITHUB_TOKEN }}
          issue-number: ${{ github.event.pull_request.number }}
          comment-author: 'github-actions[bot]'
          body-includes: '<!-- kubecost-prediction-results -->'
      - name: Create or update PR comment with prediction results
        uses: kubecost/github-actions/create-or-update-comment@main
        with:
          token: ${{ secrets.GITHUB_TOKEN }}
          issue-number: ${{ github.event.pull_request.number }}
          comment-id: ${{ steps.find-comment.outputs.comment-id }}
          edit-mode: replace
          body: |
            <!-- kubecost-prediction-results -->

            ## Kubecost's total cost prediction for K8s YAML Manifests in this PR

            \```
            ${{ steps.prediction.outputs.PREDICTION_TABLE }}
            \```
```

### Base Action Inputs/Outputs

#### Inputs

| Name | Description | Required | Default |
|------|-------------|----------|---------|
| `path` | Path to a file or directory of K8s YAML manifests | Yes | |
| `kubecost_api_path` | URL of your Kubecost API (e.g. `https://kubecost.example.com:9090/model`). If omitted, default pricing is used. | No | |
| `log_level` | Log verbosity: `debug`, `info`, `warn`, `error` | No | `info` |

#### Outputs

| Name | Description |
|------|-------------|
| `PREDICTION_TABLE` | ASCII-formatted cost prediction table |

---

## Enhanced Action Usage

The enhanced action (`./action-enhanced`) wraps the base action and adds:

1. **Delta/Diff Mode** — compares cost between your PR branch and a base branch
2. **Cost Threshold Enforcement** — fails the workflow if cost increases exceed configured limits
3. **Budget Checks** — validates predicted cost against a Kubecost budget

### Example: Full Governance Workflow

```yaml
name: Cost Governance
on: [pull_request]

jobs:
  cost-check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0  # Required for delta mode

      - name: Check cost impact
        id: cost
        uses: kubecost/cost-prediction-action/action-enhanced@main
        with:
          path: ./k8s
          kubecost_api_path: ${{ secrets.KUBECOST_API_PATH }}
          enable_delta_mode: "true"
          base_ref: "main"
          max_cost_increase: "100.00"
          max_cost_percentage: "15"
          fail_on_threshold: "true"
          budget_check_enabled: "true"
          budget_id: "team-alpha-budget"
          fail_on_budget_exceeded: "true"

      - name: Comment on PR
        uses: actions/github-script@v7
        with:
          script: |
            github.rest.issues.createComment({
              issue_number: context.issue.number,
              owner: context.repo.owner,
              repo: context.repo.repo,
              body: `## 💰 Cost Impact Analysis
              | | |
              |---|---|
              | **Current Cost** | \`$${{ steps.cost.outputs.TOTAL_MONTHLY_COST }}/mo\` |
              | **Base Cost** | \`$${{ steps.cost.outputs.BASE_COST }}/mo\` |
              | **Change** | \`${{ steps.cost.outputs.COST_CHANGE }}\` (\`${{ steps.cost.outputs.COST_CHANGE_PERCENTAGE }}%\`) |
              | **Budget Status** | \`${{ steps.cost.outputs.BUDGET_STATUS }}\` |
              | **Budget Remaining** | \`$${{ steps.cost.outputs.BUDGET_REMAINING }}\` |`
            });
```

### Enhanced Action Inputs

#### Base Inputs (inherited)

| Input | Description | Default |
|-------|-------------|---------|
| `path` | Path to workload file or directory | (required) |
| `kubecost_api_path` | URL of Kubecost API | |
| `log_level` | Log level | `info` |

#### Delta Mode

| Input | Description | Default |
|-------|-------------|---------|
| `enable_delta_mode` | Compare costs between current and base branch | `false` |
| `base_ref` | Base branch to compare against | `main` |

#### Cost Thresholds

| Input | Description | Default |
|-------|-------------|---------|
| `max_cost_increase` | Max allowed cost increase in dollars | (none) |
| `max_cost_percentage` | Max allowed cost increase percentage | (none) |
| `fail_on_threshold` | Fail workflow when threshold exceeded | `true` |

#### Budget Checks

| Input | Description | Default |
|-------|-------------|---------|
| `budget_check_enabled` | Enable budget validation | `false` |
| `budget_id` | Kubecost budget ID to check against | (none) |
| `fail_on_budget_exceeded` | Fail workflow when budget would be exceeded | `true` |

### Enhanced Action Outputs

| Output | Description |
|--------|-------------|
| `PREDICTION_TABLE` | ASCII cost prediction table |
| `PREDICTION_JSON` | JSON-formatted prediction data |
| `TOTAL_MONTHLY_COST` | Total monthly cost |
| `BASE_COST` | Base branch cost *(delta mode only)* |
| `COST_CHANGE` | Absolute cost difference *(delta mode only)* |
| `COST_CHANGE_PERCENTAGE` | Percentage cost change *(delta mode only)* |
| `THRESHOLD_EXCEEDED` | Whether thresholds were exceeded (`true`/`false`) |
| `BUDGET_STATUS` | `WITHIN_BUDGET`, `EXCEEDS_BUDGET`, or `NOT_CHECKED` |
| `BUDGET_TOTAL` | Budget spend limit in dollars |
| `BUDGET_CURRENT_SPEND` | Current spend against the budget |
| `BUDGET_REMAINING` | Remaining budget before this deployment |
| `BUDGET_UTILIZATION_PERCENTAGE` | Current utilization % before this deployment |

---

## Limitations

- Only `.yml`/`.yaml` manifest files are supported. For Helm, run `helm template` first.
- A limited set of Kubernetes object types are supported. More are planned.
- Manifests without container resource requests will not produce predictions.
- Delta mode requires `fetch-depth: 0` in the checkout step so that the base branch is accessible.

---

## Development

Source code for the prediction container is in the upstream Kubecost repo. Kubecost engineers: see `cmd/costpredictionaction` in KCM for development, testing, and releasing details.
