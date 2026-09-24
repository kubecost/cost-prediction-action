# Delta Mode Test Cases

This directory contains test workloads for testing the delta/diff mode and cost threshold features.

## Test Workloads

### base-workload.yaml
Baseline deployment with:
- 2 replicas
- 500m CPU per pod
- 512Mi memory per pod
- Total: 1 CPU, 1Gi memory

### increased-workload.yaml
Increased resources deployment with:
- 5 replicas (2.5x increase)
- 1000m CPU per pod (2x increase)
- 1Gi memory per pod (2x increase)
- Total: 5 CPU, 5Gi memory
- Expected cost increase: ~400-500%

### decreased-workload.yaml
Decreased resources deployment with:
- 1 replica (50% decrease)
- 250m CPU per pod (50% decrease)
- 256Mi memory per pod (50% decrease)
- Total: 250m CPU, 256Mi memory
- Expected cost decrease: ~75%

## Testing Scenarios

### Scenario 1: Cost Increase Detection
Compare `base-workload.yaml` (on main) vs `increased-workload.yaml` (on feature branch)
- Should show significant cost increase
- Should trigger threshold warnings if configured

### Scenario 2: Cost Decrease Detection
Compare `base-workload.yaml` (on main) vs `decreased-workload.yaml` (on feature branch)
- Should show cost decrease
- Should pass all thresholds

### Scenario 3: Threshold Testing

#### Test 3a: Pass thresholds
```yaml
max_cost_increase: "1000.00"
max_cost_percentage: "500"
```
Result: Should pass with increased-workload.yaml

#### Test 3b: Fail absolute threshold
```yaml
max_cost_increase: "10.00"
max_cost_percentage: "500"
```
Result: Should fail with increased-workload.yaml

#### Test 3c: Fail percentage threshold
```yaml
max_cost_increase: "1000.00"
max_cost_percentage: "50"
```
Result: Should fail with increased-workload.yaml

#### Test 3d: Warning only mode
```yaml
max_cost_increase: "10.00"
max_cost_percentage: "50"
fail_on_threshold: "false"
```
Result: Should warn but not fail with increased-workload.yaml

## Manual Testing Steps

1. Commit base-workload.yaml to main branch
2. Create feature branch
3. Replace base-workload.yaml with increased-workload.yaml
4. Run the enhanced action with delta mode enabled
5. Verify cost increase is detected
6. Test various threshold configurations

## Expected Outputs

### With increased-workload.yaml
```
Current Cost: $XXX.XX
Base Cost (main): $YY.YY
Cost Change: +$ZZZ.ZZ (+400-500%)
```

### With decreased-workload.yaml
```
Current Cost: $XX.XX
Base Cost (main): $YY.YY
Cost Change: -$ZZ.ZZ (-75%)