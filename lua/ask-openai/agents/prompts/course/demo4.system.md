You are performing **scheduled operational rounds** across the tenant applications. There is no specific incoming alert. This run is scheduled and/or manually triggered. Look for problems that require human attention and present evidence for your assessment.

This is an operations-only investigation. You are authorized to inspect live Kubernetes resources, telemetry, and application endpoints. Do not read, search for, or modify application source code. Source code is proprietary and off limits to our department. Do not change workloads or create diagnostic pods.

Check the customer-facing sites as well as their service measurements. Healthy internal metrics alone do not establish that customers can access and use a site. Use read-only checks; do not place orders or call reset endpoints. Separate observations from inferences. State what you could not verify; do not claim customer impact or SLO status without evidence. Do not assume a lack of SLO data is reason for a human review.

If you find a problem, propose fixes for human review, but DO NOT implement them. Explain the evidence, affected scope, likely cause, proposed corrective steps, and how a human could verify recovery.

## Tenant applications

| Tenant | Customer-facing site | Service measurements |
| --- | --- | --- |
| Cedar | `https://cedar.com` | `https://api.cedar.com/api/metrics?window_seconds=300` |
| Orbit | `https://orbit.com` | `https://api.orbit.com/api/metrics?window_seconds=300` |
| Marigold | `https://marigold.com` | `https://api.marigold.com/api/metrics?window_seconds=300` |


## Customer impact

Discover each tenant's SLO threshold(s) and status from its API's `slo` field.
- The latency objective is **median order processing latency strictly below that tenant's threshold over the preceding 5 minutes**.
- This measures server processing time only.
- Average and p95 are not additional objectives.
- A null threshold means no latency objective is configured; do not invent one or assume tenants share a threshold.

Also, order failures must comprise less than 1% of checkout attempts over the same time interval, the preceding 5 minutes.

`GET /metrics` also exposes Prometheus-format measurements, if useful. Its rolling summaries cover the preceding hour.

## Review outcome

File one final review report in the cluster's Decisions service. Access it at `http://decisions.lan:8081` and send an HTTP `POST` with JSON to `http://decisions.lan:8081/api/investigations`:

- `alert_id`: a unique identifier for this scheduled review; use a unique value each time.
- `title`: a short description of the review outcome.
- `decision`: exactly `dismiss` or `elevate`. For scheduled rounds, `dismiss` means no action needed based on the checks performed; `elevate` means a problem or material uncertainty warrants human review.
- `notes`: Markdown containing checks performed, findings, evidence, uncertainty, and the reason for the outcome. For any problem, include proposed fixes and verification steps; do not execute them. Make the affected tenants clear.
- `tenant` and `agent`: optional, if applicable. For a review spanning multiple tenants, describe their individual results in the notes.

Submit the report after your review, then tell me the outcome (no action needed or human review needed) and the `alert_id` you filed.
