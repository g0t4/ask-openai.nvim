import { test } from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { normalizeStats, formatResponseStats, totalTokens } from '../src/lib/response-stats.ts'
import { timingSummaries } from '../src/lib/timings-summary.ts'

const fixture = () => JSON.parse(readFileSync(new URL('../../chat_viewer/fixtures/sglang-sse-timings.json', import.meta.url), 'utf8'))

test('SGLang final SSE timings normalize seconds and preserve cache/count semantics', () => {
  const event = fixture()
  const s = normalizeStats(event)!
  assert.equal(s.backend, 'sglang')
  assert.equal(s.newInput, 200)
  assert.equal(s.inputMs, 400)
  assert.equal(s.queueMs, 10)
  assert.equal(s.outputMs, 500)
  assert.equal(s.inputRate, 500)
  assert.equal(s.outputRate, 200)
  assert.equal(s.accepted, 80)
  assert.equal(s.reasoning, 20)
  assert.equal(totalTokens(event), 1101)
  assert.ok(formatResponseStats(event).some(line => line.includes('TTFT: 400.0 ms')))
  assert.ok(formatResponseStats(event).some(line => line.includes('200.0 tok/s')))
  const summary = timingSummaries([{ role: 'assistant', ...event }])[0]
  assert.equal(summary.name, 'SGLang')
  assert.ok(summary.rows[0].some(cell => cell.includes('200.0 tok/s')))
  delete event.usage
  assert.equal(normalizeStats(event)!.output, 101)
  assert.equal(totalTokens(event), 1101)
})

test('multiple-choice usage does not inherit one choice timing or speculation', () => {
  const event = fixture()
  event.timings.choices.push({ ...event.timings.choices[0], index: 1 })
  event.usage.completion_tokens = 202
  const s = normalizeStats(event)!
  assert.equal(s.backend, 'sglang')
  assert.equal(s.output, 202)
  assert.equal(s.inputMs, undefined)
  assert.equal(s.outputRate, undefined)
  assert.equal(s.accepted, undefined)
})

test('llama-server and vLLM keep their existing semantics', () => {
  assert.equal(normalizeStats({timings: {prompt_n: 10, cache_n: 20, predicted_n: 5}})!.totalInput, 30)
  assert.equal(totalTokens({timings: {prompt_n: 10, cache_n: 20, predicted_n: 5}}), 35)
  assert.equal(normalizeStats({usage: {prompt_tokens: 20, completion_tokens: 11}, metrics: {generation_time_ms: 100}})!.outputRate, 100)
})
