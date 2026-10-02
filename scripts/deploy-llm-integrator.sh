#!/usr/bin/env bash
# Deploy a model with the llm-integrator charm instead of writing an
# LLMInferenceService by hand. This uses the S3 path (relate to s3-integrator);
# for Hugging Face, drop s3-integrator and set MODEL_URI=hf://... plus a
# hf-token-secret (see the notes at the bottom).
#
# llm-integrator renders the LLMInferenceService for you and, by default, deploys
# it in disaggregated prefill/decode mode (enable-prefill-decode=true).
#
# Env (S3 credentials for your bucket):
#   AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_DEFAULT_REGION (default eu-central-1)
#   BUCKET      (default: my-model-bucket)
#   MODEL_URI   (default: s3://$BUCKET/pythia-70m)
#   MODEL_NAME  (default: EleutherAI/pythia-70m)
#   LLM_MODEL   Juju model running the serving stack (default: kserve-llm)
set -euo pipefail

: "${AWS_ACCESS_KEY_ID:?set AWS_ACCESS_KEY_ID}"
: "${AWS_SECRET_ACCESS_KEY:?set AWS_SECRET_ACCESS_KEY}"
: "${AWS_DEFAULT_REGION:=eu-central-1}"
: "${BUCKET:=my-model-bucket}"
: "${MODEL_URI:=s3://$BUCKET/pythia-70m}"
: "${MODEL_NAME:=EleutherAI/pythia-70m}"
: "${LLM_MODEL:=kserve-llm}"

VLLM_CPU_IMAGE=docker.io/charmedkubeflow/vllm-cpu:0.19.0-5f4a278-20260825092922
STORAGE_INIT_IMAGE=docker.io/charmedkubeflow/storage-initializer:0.17.0-07d37fb

echo "== 0) target the serving model ($LLM_MODEL) =="
juju switch "$LLM_MODEL"

echo "== 1) s3-integrator with the bucket coordinates =="
juju deploy s3-integrator --channel 2/edge \
  --config endpoint="https://s3.${AWS_DEFAULT_REGION}.amazonaws.com" \
  --config region="${AWS_DEFAULT_REGION}" \
  --config bucket="${BUCKET}"

echo "== 2) pass the S3 credentials via a Juju secret =="
SECRET_URI=$(juju add-secret s3-creds \
  access-key="$AWS_ACCESS_KEY_ID" secret-key="$AWS_SECRET_ACCESS_KEY")
juju grant-secret s3-creds s3-integrator
juju config s3-integrator credentials="$SECRET_URI"

echo "== 3) deploy llm-integrator pointed at the model =="
juju deploy llm-integrator --channel latest/edge --trust \
  --config model-uri="$MODEL_URI" \
  --config model-name="$MODEL_NAME" \
  --config runtime-image="$VLLM_CPU_IMAGE" \
  --config storage-initializer-image="$STORAGE_INIT_IMAGE"

echo "== 4) relate to kserve-llmisvc and to s3-integrator =="
juju integrate llm-integrator:kserve-llmisvc kserve-llmisvc:kserve-llmisvc
juju integrate llm-integrator:s3-credentials s3-integrator:s3-credentials

echo
echo "Watch it settle, then check the pods (prefill / decode / router-scheduler):"
echo "  juju status s3-integrator llm-integrator kserve-llmisvc --relations"
echo "  kubectl -n kserve-llm get pods -l app.kubernetes.io/name=llm-integrator -L llm-d.ai/role"
echo
echo "Hugging Face instead of S3:"
echo "  juju add-secret hf-token token=\$HF_TOKEN   # then grant it to llm-integrator"
echo "  juju deploy llm-integrator --channel latest/edge --trust \\"
echo "    --config model-uri=hf://<org>/<model> --config model-name=<org>/<model> \\"
echo "    --config hf-token-secret=<secret-uri> --config runtime-image=... --config storage-initializer-image=..."
echo "  juju integrate llm-integrator:kserve-llmisvc kserve-llmisvc:kserve-llmisvc"
