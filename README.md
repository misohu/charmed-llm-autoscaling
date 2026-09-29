# charmed-llm-autoscaling

Companion code for the blog post **"Serve and autoscale open-weight LLMs on your
own GPUs, with Juju, KServe and KEDA"**.

It takes a single GPU VM and brings up a full, self-hosted LLM serving stack:

- **KServe** for serving, behind an **Envoy** gateway
- **KEDA** for metric-driven autoscaling
- the **Canonical Observability Stack (COS)** for metrics, logs and dashboards

…then serves **Mixtral-8x7B-Instruct** across two GPUs and autoscales it on a live
vLLM metric.

Everything is charmed and driven by [Juju](https://juju.is/), so it is
reproducible on your own hardware.

## Prerequisites

- An Ubuntu **24.04 (noble)** VM with one or more NVIDIA GPUs (the post uses
  8× H100 80GB; two free GPUs are enough to follow along).
- Outbound internet access and a [Hugging Face token](https://huggingface.co/settings/tokens).

## Layout

```
.
├── concierge.yaml                     # cluster + Juju bootstrap config (edit the LB CIDR!)
├── setup/prepare-machine.sh           # Helm, Juju, K8s, NVIDIA GPU operator
├── terraform/README.md                # one apply: serving stack + COS
├── manifests/
│   ├── hf-token.secret.example.yaml   # your HF token as a Secret
│   ├── mixtral-llmisvc.yaml           # Mixtral on 2 GPUs (tensor-parallel-size 2)
│   ├── mixtral-llmisvc-safetensors.yaml  # same, but downloads only safetensors (~half)
│   └── scaledobject.yaml              # KEDA: scale on vllm:num_requests_running
└── scripts/generate-load.sh           # drive concurrent traffic
```

## Quick start

```bash
# 1. Prepare the machine (Helm, Juju, Canonical K8s, NVIDIA GPU operator)
#    Edit concierge.yaml first: set the load-balancer CIDR to a free range on
#    your network (needs at least 2 addresses).
./setup/prepare-machine.sh

# 2. Deploy the whole stack + COS with one Terraform apply
#    (see terraform/README.md for the exact commands)

# 3. Serve Mixtral on two GPUs
cp manifests/hf-token.secret.example.yaml /tmp/hf-token.yaml
# edit /tmp/hf-token.yaml and paste your HF token
kubectl apply -f /tmp/hf-token.yaml
kubectl apply -f manifests/mixtral-llmisvc.yaml
kubectl -n default get llminferenceservice mixtral -w   # wait for READY=True

# 4. Call it
GW=$(kubectl -n kubeflow get gateway envoy-ingress-k8s -o jsonpath='{.status.addresses[0].value}')
curl -sS "http://$GW/default/mixtral/v1/completions" \
  -H 'Content-Type: application/json' \
  -d '{"model":"mistralai/Mixtral-8x7B-Instruct-v0.1","prompt":"Hello!","max_tokens":32}'

# 5. Autoscale it with KEDA, then generate load
kubectl apply -f manifests/scaledobject.yaml
./scripts/generate-load.sh

# 6. Watch it scale
kubectl -n default get hpa -w
```

Open Grafana in the `cos` model to see the shipped vLLM dashboard react to the
load. Get the admin password with:

```bash
juju run grafana/0 -m cos get-admin-password
```

## Notes

- **Model download size.** `mixtral-llmisvc.yaml` pulls the full Hugging Face repo
  (~190 GB, weights shipped twice). `mixtral-llmisvc-safetensors.yaml` downloads
  only what vLLM needs (~93 GB). For production, stage the model once in S3 or a
  shared read-only volume so new replicas start fast.
- **GPU budget.** Each replica uses 2 GPUs (tensor parallelism). With
  `maxReplicaCount: 2` that is 4 GPUs; raise it if you have more.
