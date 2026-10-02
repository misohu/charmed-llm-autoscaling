#!/usr/bin/env bash
# Drive concurrent inference load at the Mixtral model through the Envoy gateway,
# so vllm:num_requests_running climbs and KEDA scales the workload out.
#
# Env:
#   LLM_MODEL    Juju model running the serving stack (default: kserve-llm)
#   CONCURRENCY  number of parallel in-flight requests (default: 48)
#   MAX_TOKENS   generation length per request (default: 512)
#
# Ctrl-C to stop.
set -euo pipefail
: "${LLM_MODEL:=kserve-llm}"
: "${CONCURRENCY:=48}"
: "${MAX_TOKENS:=512}"

GW=$(kubectl -n "$LLM_MODEL" get gateway envoy-ingress-k8s \
      -o jsonpath='{.status.addresses[0].value}')
URL="http://$GW/default/mixtral/v1/completions"

echo "Hammering $URL with $CONCURRENCY concurrent requests (Ctrl-C to stop)"
seq 1 1000000 | xargs -P "$CONCURRENCY" -I{} curl -s -o /dev/null --max-time 180 "$URL" \
  -H 'Content-Type: application/json' \
  -d "{\"model\":\"mistralai/Mixtral-8x7B-Instruct-v0.1\",\"prompt\":\"Write a long, detailed essay on the history of computing, from the abacus to modern GPUs.\",\"max_tokens\":${MAX_TOKENS},\"temperature\":0.9}"
