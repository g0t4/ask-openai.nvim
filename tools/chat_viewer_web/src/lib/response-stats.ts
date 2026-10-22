import type { Message, ResponseStats } from './types'

export function humanizeInt(value: number): string { return value.toLocaleString() }
export function humanizeFloat(value: number): string {
  return value.toLocaleString(undefined, { minimumFractionDigits: 1, maximumFractionDigits: 1 })
}
export function optionalMetric(value: number | null | undefined, unit = ''): string {
  return value == null ? '—' : `${humanizeFloat(value)}${unit}`
}

export function totalTokens(response?: ResponseStats | null): number | undefined {
  if (response?.timings) {
    const t = response.timings
    return (t.cache_n ?? 0) + (t.prompt_n ?? 0) + (t.predicted_n ?? 0)
  }
  const usage = response?.usage
  if (usage?.total_tokens != null) return usage.total_tokens
  if (usage?.prompt_tokens != null && usage.completion_tokens != null) {
    return usage.prompt_tokens + usage.completion_tokens
  }
}

export function draftAcceptance(response: ResponseStats): string | undefined {
  const t = response.timings
  const s = response.metrics?.speculative_decoding
  const proposed = t ? t.draft_n : s?.num_draft_tokens
  const accepted = t ? t.draft_n_accepted : s?.num_accepted_draft_tokens
  const rate = t ? undefined : s?.draft_acceptance_rate
  const percentage = rate != null ? rate * 100
    : proposed != null && proposed > 0 && accepted != null ? accepted / proposed * 100 : undefined
  const ratio = proposed != null && accepted != null ? `${humanizeInt(accepted)}/${humanizeInt(proposed)}`
    : proposed != null ? `${humanizeInt(proposed)} proposed` : undefined
  if (percentage != null) return `${ratio ? ratio + ' ' : ''}(${humanizeFloat(percentage)}% accepted)`
  return ratio
}

export function formatResponseStats(response?: ResponseStats | null): string[] {
  if (!response) return []
  const lines: string[] = []
  const count = (label: string, value?: number | null) => {
    if (value != null) lines.push(`${label}: ${humanizeInt(value)} tokens`)
  }
  if (response.timings) {
    const t = response.timings
    count('cached', t.cache_n)
    for (const [label, value, rate] of [
      ['in', t.prompt_n, t.prompt_per_second], ['out', t.predicted_n, t.predicted_per_second]
    ] as const) {
      if (value != null) lines.push(`${label}: ${humanizeInt(value)} tokens${rate != null && rate > 0 ? ` @ ${humanizeFloat(rate)} tok/s` : ''}`)
    }
    const acceptance = draftAcceptance(response)
    if (acceptance) lines.push(`  draft: ${acceptance}`)
    if (t.prompt_ms != null) lines.push(`prompt: ${humanizeFloat(t.prompt_ms)} ms`)
    if (t.predicted_ms != null) lines.push(`decode: ${humanizeFloat(t.predicted_ms)} ms`)
  } else {
    const u = response.usage
    const m = response.metrics
    count('cached', u?.prompt_tokens_details?.cached_tokens)
    count('in (includes cached)', u?.prompt_tokens)
    if (m?.time_to_first_token_ms != null) lines.push(`TTFT: ${humanizeFloat(m.time_to_first_token_ms)} ms`)
    if (m?.queue_time_ms != null && m.queue_time_ms >= 0.05) lines.push(`queue: ${humanizeFloat(m.queue_time_ms)} ms`)
    count('out', u?.completion_tokens)
    const reasoning = u?.completion_tokens_details?.reasoning_tokens
    if (reasoning != null && reasoning > 0) count('  reasoning', reasoning)
    const acceptance = draftAcceptance(response)
    if (acceptance) lines.push(`  draft: ${acceptance}`)
    const meanAcceptance = m?.speculative_decoding?.mean_acceptance_length
    if (meanAcceptance != null) lines.push(`    mean acceptance length: ${humanizeFloat(meanAcceptance)} tokens`)
    for (const [label, value, unit] of [
      ['  decode', m?.generation_time_ms, 'ms'], ['  mean ITL', m?.mean_itl_ms, 'ms'],
      ['overall output (includes prefill)', m?.tokens_per_second, 'tok/s']
    ] as const) {
      if (value != null) lines.push(`${label}: ${humanizeFloat(value)} ${unit}`)
    }
  }
  const total = totalTokens(response)
  if (total != null) lines.push(`total: ${humanizeInt(total)} tokens`)
  return lines
}

export function vllmGenerations(messages: Message[]): { index: number; response: Message }[] {
  return messages.flatMap((response, index) => response.role === 'assistant' && response.usage && !response.timings
    ? [{ index: index + 1, response }] : [])
}
