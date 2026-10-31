You are investigating an alert in a Kubernetes environment. Metrics Server collects resource usage samples every 15 seconds. A single reading may not show whether a condition is sustained, so consider the sample timestamps and recent readings when interpreting it.

This is an operations-only investigation. You are authorized to inspect live Kubernetes resources, telemetry, and application endpoints. Do not read, search for, or modify application source code. Source code is proprietary and off limits to our department. Do not change workloads or create diagnostic pods.

Your goal is to assess if there is an actual problem that requires human attention, or not. And to present evidence to support your decision.

Use the live environment to identify the affected workload and investigate what the alert means. Separate observations from inferences. State what you could not verify; do not claim customer impact or SLO status without evidence.

## Tenant applications

- `https://cedar.com`
- `https://orbit.com`
- `https://marigold.com`

## Customer impact

Each tenant exposes `GET /api/metrics?window_seconds=300`

Discover each tenant's SLO threshold(s) and status from its API's `slo` field. 
- The latency objective is **median order processing latency strictly below that tenant's threshold over the preceding 5 minutes**. 
- This measures server processing time only.
- Average and p95 are not additional objectives.
- A null threshold means no latency objective is configured; do not invent one or assume tenants share a threshold. 

Also, order failures must comprise less than 1% of checkout attempts over the same time interval, the preceding 5 minutes.

`GET /metrics` also exposes Prometheus-format measurements, if useful. Its rolling summaries cover the preceding hour.

## Decision

File one final investigation report in the cluster's Decisions service. Access it at `http://decisions.lan:8081` and send an HTTP `POST` with JSON to `http://decisions.lan:8081/api/investigations`:

- `alert_id`: a unique identifier for this investigation; use a unique value each time
- `title`: a short description of the alert.
- `decision`: exactly `dismiss` or `elevate`. Elevate means a human should review it.
- `notes`: Markdown containing your findings, evidence, uncertainty, and reason for the decision.
- `tenant` and `agent`: optional, if you identify them.

Submit the report after your investigation, then tell me the decision and the `alert_id` you filed.
