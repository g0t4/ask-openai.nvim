import type { Message, ResponseStats, SglangTiming } from './types'

export function humanizeInt(value: number): string { return value.toLocaleString() }
export function humanizeFloat(value: number): string {
  return value.toLocaleString(undefined, { minimumFractionDigits: 1, maximumFractionDigits: 1 })
}
export function optionalMetric(value: number | null | undefined, unit = ''): string {
  return value == null ? '—' : `${humanizeFloat(value)}${unit}`
}

export function totalTokens(response?: ResponseStats | null): number | undefined {
  if (response?.timings && !Array.isArray(response.timings.choices)) {
    const t = response.timings
    return (t.cache_n ?? 0) + (t.prompt_n ?? 0) + (t.predicted_n ?? 0)
  }
  const usage = response?.usage
  if (usage?.total_tokens != null) return usage.total_tokens
  if (usage?.prompt_tokens != null && usage.completion_tokens != null) {
    return usage.prompt_tokens + usage.completion_tokens
  }
  const stats = normalizeStats(response)
  if (stats?.prompt != null && stats.output != null) return stats.prompt + stats.output
}

export function normalizeStats(response?: ResponseStats | null) {
  if (!response || (!response.timings && !response.usage && !response.meta_info)) return null
  const choices = response.timings?.choices
  const patched = Array.isArray(choices)
  const native = response.meta_info as SglangTiming | undefined
  const sgTiming = patched ? (choices.length === 1 ? choices[0] : undefined) : native
  const t = patched ? undefined : response.timings
  const u = response.usage ?? (sgTiming ? {
    prompt_tokens: sgTiming.prompt_tokens, completion_tokens: sgTiming.completion_tokens,
    prompt_tokens_details: { cached_tokens: sgTiming.cached_tokens }, reasoning_tokens: sgTiming.reasoning_tokens
  } : undefined)
  const m = response.metrics
  const backend = t ? 'llama-server' : patched || native || response.response_backend === 'sglang' || response.sglext || u?.reasoning_tokens != null ? 'sglang' : 'vllm'
  const cached = t ? t.cache_n : (u?.prompt_tokens_details?.cached_tokens ?? sgTiming?.cached_tokens)
  const prompt = t ? t.prompt_n : u?.prompt_tokens
  const newInput = t ? prompt : cached != null && prompt != null && cached >= 0 && cached <= prompt ? prompt - cached : undefined
  const output = t ? t.predicted_n : u?.completion_tokens
  const spec = sgTiming ?? response.sglext?.spec_tokens_details
  const sg = spec && !Array.isArray(spec) ? spec : undefined
  const proposed = t ? t.draft_n : sg ? sg.spec_num_proposed_drafts : m?.speculative_decoding?.num_draft_tokens
  const accepted = t ? t.draft_n_accepted : sg ? sg.spec_num_correct_drafts : m?.speculative_decoding?.num_accepted_draft_tokens
  const acceptanceRate = sg ? sg.spec_accept_rate : m?.speculative_decoding?.draft_acceptance_rate
  const ms = (n?: number) => n != null && n >= 0 ? n * 1000 : undefined
  const ttft = backend === 'sglang' ? ms(sgTiming?.first_token_latency) : m?.time_to_first_token_ms
  const queueMs = backend === 'sglang' ? ms(sgTiming?.queue_time) : m?.queue_time_ms
  const elapsed = ms(sgTiming?.e2e_latency)
  const inputMs = t ? t.prompt_ms : ttft
  const outputMs = t ? t.predicted_ms : backend === 'sglang' ? elapsed != null && ttft != null && elapsed >= ttft ? elapsed - ttft : undefined : m?.generation_time_ms
  const inputRate = t ? t.prompt_per_second : newInput != null && newInput > 0 && inputMs != null && inputMs > 0 ? newInput * 1000 / inputMs : undefined
  const outputRate = t ? t.predicted_per_second : sgTiming?.decode_throughput != null && sgTiming.decode_throughput > 0 ? sgTiming.decode_throughput : output != null && output > 1 && outputMs != null && outputMs > 0 ? (output - 1) * 1000 / outputMs : undefined
  return { backend, ttft, queueMs, cached, prompt, newInput, output, proposed, accepted, acceptanceRate, inputMs, outputMs, inputRate, outputRate,
    reasoning: u?.completion_tokens_details?.reasoning_tokens ?? u?.reasoning_tokens,
    meanAccept: sg ? sg.spec_accept_length : m?.speculative_decoding?.mean_acceptance_length,
    totalInput: t && prompt != null ? prompt + (cached ?? 0) : prompt }
}

export function draftAcceptance(response: ResponseStats): string | undefined {
  const stats = normalizeStats(response)
  if (!stats) return undefined
  const { proposed, accepted, acceptanceRate: rate } = stats
  const percentage = rate != null ? rate * 100
    : proposed != null && proposed > 0 && accepted != null ? accepted / proposed * 100 : undefined
  const ratio = proposed != null && accepted != null ? `${humanizeInt(accepted)}/${humanizeInt(proposed)}`
    : proposed != null ? `${humanizeInt(proposed)} proposed` : undefined
  if (percentage != null) return `${ratio ? ratio + ' ' : ''}(${humanizeFloat(percentage)}% accepted)`
  return ratio
}

export function formatResponseStats(response?: ResponseStats | null): string[] {
  const s = normalizeStats(response)
  if (!s || !response) return []
  const lines: string[] = []
  const count = (label: string, value?: number | null) => {
    if (value != null) lines.push(`${label}: ${humanizeInt(value)} tokens`)
  }
  count('cached', s.cached)
  const rate = (value?: number | null) => value != null && value > 0 ? ` @ ${s.backend === 'llama-server' ? '' : '≈'}${humanizeFloat(value)} tok/s` : ''
  const inputLabel = s.newInput == null ? 'in (includes cached)' : 'in'
  const input = s.newInput ?? s.prompt
  if (input != null) lines.push(`${inputLabel}: ${humanizeInt(input)} tokens${rate(s.inputRate)}`)
  if (s.ttft != null) lines.push(`TTFT: ${humanizeFloat(s.ttft)} ms`)
  if (s.queueMs != null && s.queueMs >= 0.05) lines.push(`queue: ${humanizeFloat(s.queueMs)} ms`)
  if (s.output != null) lines.push(`out: ${humanizeInt(s.output)} tokens${rate(s.outputRate)}`)
  if (s.reasoning != null && s.reasoning > 0) count('  reasoning', s.reasoning)
  const acceptance = draftAcceptance(response)
  if (acceptance) lines.push(`  draft: ${acceptance}`)
  if (s.meanAccept != null) lines.push(`    mean acceptance length: ${humanizeFloat(s.meanAccept)} tokens`)
  if (s.inputMs != null && s.backend === 'llama-server') lines.push(`prompt: ${humanizeFloat(s.inputMs)} ms`)
  if (s.outputMs != null) lines.push(`  decode: ${humanizeFloat(s.outputMs)} ms`)
  if (response.metrics?.mean_itl_ms != null) lines.push(`  mean ITL: ${humanizeFloat(response.metrics.mean_itl_ms)} ms`)
  return lines
}

export function vllmGenerations(messages: Message[]): { index: number; response: Message }[] {
  return messages.flatMap((response, index) => response.role === 'assistant' && normalizeStats(response)?.backend === 'vllm'
    ? [{ index: index + 1, response }] : [])
}
