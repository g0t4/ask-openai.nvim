import type { Message } from './types'
import { normalizeStats, humanizeInt, humanizeFloat } from './response-stats.ts'

const count = (n?: number | null) => n == null ? '—' : humanizeInt(n)
const seconds = (n?: number | null) => n == null ? '—' : `${(n / 1000).toFixed(2)} s`
const sumKnown = (values: (number | null | undefined)[]) => values.every(n => n != null) ? values.reduce<number>((sum, n) => sum + n!, 0) : undefined

export function timingSummaries(messages: Message[]) {
  const groups = new Map<string, { ordinal: number; stats: NonNullable<ReturnType<typeof normalizeStats>> }[]>()
  let ordinal = 0
  for (const message of messages) {
    if (message.role !== 'assistant') continue
    ordinal++
    const stats = normalizeStats(message)
    if (!stats) continue
    if (!groups.has(stats.backend)) groups.set(stats.backend, [])
    groups.get(stats.backend)!.push({ ordinal, stats })
  }
  return [...groups].map(([backend, entries]) => {
    const split = backend !== 'llama-server'
    const headers = ['cached tokens', 'in tokens', ...(split ? ['reasoning tokens', 'final tokens', 'thinking %'] : []),
      split ? 'total out tokens' : 'out tokens', 'draft', 'mean accept len', 'in duration', 'out duration', '#']
    const tokenRate = (n?: number | null, rate?: number | null) => count(n) + (n != null && rate != null && rate > 0 ? ` @ ${backend === 'llama-server' ? '' : '≈'}${humanizeFloat(rate)} tok/s` : '')
    const reasoning = entries.map(({stats:s}) => s.reasoning != null && s.output != null && s.reasoning >= 0 && s.reasoning <= s.output ? s.reasoning : undefined)
    const finals = entries.map(({stats:s}, i) => reasoning[i] != null && s.output != null ? s.output - reasoning[i]! : undefined)
    const percentage = (reasoning?: number | null, output?: number | null) => reasoning != null && output != null && output > 0 ? `${humanizeFloat(reasoning / output * 100)}%` : '—'
    const rows = entries.map(({ordinal,stats:s}, i) => {
      let cached = count(s.cached)
      if (s.cached != null && s.totalInput != null && s.totalInput > 0) cached += `\n${humanizeFloat(s.cached / s.totalInput * 100)}% hit`
      const previous = i > 0 ? entries[i - 1].stats : null
      if (previous?.cached != null && previous.totalInput != null && previous.output != null && s.cached != null) {
        const delta = s.cached - previous.totalInput - previous.output
        cached += Math.abs(delta) <= 1 ? '\nok' : `\nMISS ${delta >= 0 ? '+' : ''}${humanizeInt(delta)}`
      }
      const acceptance = s.acceptanceRate != null ? s.acceptanceRate * 100 : s.accepted != null && s.proposed ? s.accepted / s.proposed * 100 : undefined
      const draft = s.proposed != null ? `${count(s.accepted)}/${count(s.proposed)}${acceptance != null ? ` ${humanizeFloat(acceptance)}%` : ''}` : '—'
      return [cached, tokenRate(s.newInput, s.inputRate), ...(split ? [count(reasoning[i]), count(finals[i]), percentage(reasoning[i], s.output)] : []),
        tokenRate(s.output, s.outputRate), draft, s.meanAccept == null ? '—' : s.meanAccept.toFixed(2), seconds(s.inputMs), seconds(s.outputMs), `#${ordinal}`]
    })
    const output = sumKnown(entries.map(({stats:s}) => s.output))
    const totalReasoning = sumKnown(reasoning)
    const totals = ['', count(sumKnown(entries.map(({stats:s}) => s.newInput))),
      ...(split ? [count(totalReasoning), count(sumKnown(finals)), percentage(totalReasoning, output)] : []), count(output), '', '',
      seconds(sumKnown(entries.map(({stats:s}) => s.inputMs))), seconds(sumKnown(entries.map(({stats:s}) => s.outputMs))), 'total']
    return { backend, name: backend === 'vllm' ? 'vLLM' : backend === 'sglang' ? 'SGLang' : backend, headers, rows, totals }
  })
}
