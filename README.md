# cost-prediction-action
GitHub Action to predict the cost of K8s spec changes

## Usage

Here is an example Action workflow using Kubecost's Predict Action:
``` yaml
name: Predict K8s spec cost
# This is a manually-triggered workflow. Check out GitHub's documentation for
# "on" to set up this workflow to run on e.g. every PR.
on: [workflow_dispatch]

jobs:
  predict-cost-api:
    runs-on: ubuntu-latest
    steps:
      # Check out the current repo to ./repo
      - uses: actions/checkout@v2
        with:
          path: ./repo
          
      # If using the API support, you need to make sure the Action runner has
      # network access to your instance of Kubecost. This is infra dependent,
      # but this workflow includes an example that assumes the runner has
      # kubectl set up with access to your cluster.
      # 
      # - name: Forward the kubecost service
      #   run: |
      #     kubectl port-forward --namespace kubecost service/kubecost-cost-analyzer 9090 &
      #     sleep 5
      
      # If you use Helm, you should template the chart and then run the Predict
      # Action targeting the result. Here's an example of how to do that.
      # 
      # - name: Install helm
      #   run: |
      #     curl https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3 | bash
      # 
      # - name: Helm template
      #   run: |
      #     helm template RELEASENAME ./repo >> ./templated.yaml

      - name: local action with raw yaml
        id: raw-prediction
        uses: kubecost/cost-prediction-action@v0
        with:
          log_level: "info"
          # Set this to the path containing your YAML specs. It can be a single
          # YAML file or a directory. The Action will recursively search if this
          # is a directory and process all .yaml/.yml files it finds.
          # 
          # If you use Helm, you probably want to run "helm template", output
          # to a path like ./templated.yaml, and set "path: ./templated.yaml".
          path: ./repo
          # Set this to either:
          # - localhost:9090/model if port forwarding OR
          # - The URL of your Kubecost instance if the runner has direct network
          #   access, e.g. "https://kubecost.example.com:9090/model"
          #
          # If unset, the Action will use Kubecost's default pricing to make a
          # prediction and it will be unable to make
          #
          # kubecost_api_path: "http://localhost:9090/model"

      # This example just outputs the result in the Action run. You can also
      # add it as a comment using Actions like:
      # peter-evans/create-or-update-comment
      - name: output raw yaml prediction
        run: |
          echo "${{ steps.raw-prediction.outputs.PREDICTION_TABLE }}"
```

## Limitations

The Action currently only supports predicting `.yml`/`.yaml` specs. If you have
specs in other formats, you will have to put them into YAML before running
prediction logic. E.g. for Helm, use `helm template`.

The Action does not yet support prediction on only changed files. This is tricky
anyway if you use tools like Helm, because how can you know what exactly changed
between templates and values files?

## Development

Source code for the container is mostly closed. Kubecost engineers, visit
`cmd/costpredictionaction` in KCM for more information about development, testing, and releasing.
