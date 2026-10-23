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

export function normalizeStats(response?: ResponseStats | null) {
  if (!response || (!response.timings && !response.usage)) return null
  const t = response.timings
  const u = response.usage
  const m = response.metrics
  const backend = t ? 'llama-server' : response.response_backend === 'sglang' || response.sglext || u?.reasoning_tokens != null ? 'sglang' : 'vllm'
  const cached = t ? t.cache_n : u?.prompt_tokens_details?.cached_tokens
  const prompt = t ? t.prompt_n : u?.prompt_tokens
  const newInput = t ? prompt : cached != null && prompt != null && cached >= 0 && cached <= prompt ? prompt - cached : undefined
  const output = t ? t.predicted_n : u?.completion_tokens
  const spec = response.sglext?.spec_tokens_details
  const sg = spec && !Array.isArray(spec) ? spec : undefined
  const proposed = t ? t.draft_n : sg ? sg.spec_num_proposed_drafts : m?.speculative_decoding?.num_draft_tokens
  const accepted = t ? t.draft_n_accepted : sg ? sg.spec_num_correct_drafts : m?.speculative_decoding?.num_accepted_draft_tokens
  const acceptanceRate = sg ? sg.spec_accept_rate : m?.speculative_decoding?.draft_acceptance_rate
  const inputMs = t ? t.prompt_ms : backend === 'vllm' ? m?.time_to_first_token_ms : undefined
  const outputMs = t ? t.predicted_ms : backend === 'vllm' ? m?.generation_time_ms : undefined
  const inputRate = t ? t.prompt_per_second : newInput != null && newInput > 0 && inputMs != null && inputMs > 0 ? newInput * 1000 / inputMs : undefined
  const outputRate = t ? t.predicted_per_second : output != null && output > 1 && outputMs != null && outputMs > 0 ? (output - 1) * 1000 / outputMs : undefined
  return { backend, cached, prompt, newInput, output, proposed, accepted, acceptanceRate, inputMs, outputMs, inputRate, outputRate,
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
  if (response.metrics?.time_to_first_token_ms != null) lines.push(`TTFT: ${humanizeFloat(response.metrics.time_to_first_token_ms)} ms`)
  if (response.metrics?.queue_time_ms != null && response.metrics.queue_time_ms >= 0.05) lines.push(`queue: ${humanizeFloat(response.metrics.queue_time_ms)} ms`)
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
