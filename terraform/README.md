# Deploy the serving stack + COS with one Terraform apply

The full LLM serving stack (Envoy gateway, `kserve-controller`, `kserve-llmisvc`,
`lws-controller`, `keda-controller`, an OpenTelemetry collector) together with
**COS Lite** comes from
[canonical/autoscaling-model-serving](https://github.com/canonical/autoscaling-model-serving),
branch `track/0.3`, deployment module `deployments/llm-cos`.

It creates a model for the serving charms (named `kserve-llm` by default) and
stands up COS Lite in its own `cos` model, wired together with cross-model
offers.

```bash
git clone https://github.com/canonical/autoscaling-model-serving.git
cd autoscaling-model-serving && git checkout track/0.3
cd terraform/deployments/llm-cos

terraform init
terraform apply
```

Terraform creates both the `kserve-llm` and `cos` models. To deploy into an
existing model instead, pass its UUID with `-var model_uuid="<uuid>"` (and
optionally `-var model_name=<name>` to change the created model's name).

When it finishes, watch both models go active:

```bash
watch -n10 'echo "== kserve-llm =="; juju status -m kserve-llm; echo; echo "== cos =="; juju status -m cos'
```

Terraform creates the models but does not change your Juju CLI context. Point it
at the serving model so later `juju` commands land in the right place:

```bash
juju switch kserve-llm
```
