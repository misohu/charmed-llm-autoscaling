# Deploy the serving stack + COS with one Terraform apply

The full LLM serving stack (Envoy gateway, `kserve-controller`, `kserve-llmisvc`,
`lws-controller`, `keda-controller`, an OpenTelemetry collector) together with
**COS Lite** comes from
[canonical/autoscaling-model-serving](https://github.com/canonical/autoscaling-model-serving),
branch `track/0.3`, deployment module `deployments/llm-cos`.

It deploys the serving charms into a **pre-created** model (the `kubeflow` model
that `setup/prepare-machine.sh` created) and stands up COS Lite in its own `cos`
model, wired together with cross-model offers.

```bash
git clone https://github.com/canonical/autoscaling-model-serving.git
cd autoscaling-model-serving && git checkout track/0.3
cd terraform/deployments/llm-cos

# UUID of the pre-created model for the serving stack
MODEL_UUID=$(juju show-model kubeflow --format json \
  | python3 -c 'import sys,json;print(json.load(sys.stdin)["kubeflow"]["model-uuid"])')

terraform init
terraform apply -var model_uuid="$MODEL_UUID"
```

Terraform creates the `cos` model itself. When it finishes, watch both models go
active:

```bash
watch -n10 'echo "== kubeflow =="; juju status -m kubeflow; echo; echo "== cos =="; juju status -m cos'
```
