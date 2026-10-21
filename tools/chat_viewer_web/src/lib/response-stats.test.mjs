import test from 'node:test'
import assert from 'node:assert/strict'
import { formatResponseStats, totalTokens, vllmGenerations, optionalMetric } from './response-stats.ts'

test('vLLM per-generation stats retain raw semantics and count cached input once', () => {
  const response = {
    role: 'assistant', usage: { prompt_tokens: 100, completion_tokens: 20, total_tokens: 120,
      prompt_tokens_details: { cached_tokens: 80 }, completion_tokens_details: { reasoning_tokens: 10 } },
    metrics: { time_to_first_token_ms: 118.64, generation_time_ms: 52.29, queue_time_ms: 0,
      mean_itl_ms: 52.29, tokens_per_second: 11.7,
      speculative_decoding: { num_draft_tokens: 5, num_accepted_draft_tokens: 1, draft_acceptance_rate: 0.2, mean_acceptance_length: 2 } }
  }
  const original = structuredClone(response)
  const text = formatResponseStats(response).join('\n')
  for (const part of ['in (includes cached): 100', 'out: 20', 'reasoning: 10', 'TTFT: 118.6 ms',
    'queue: 0.0 ms', 'decode: 52.3 ms', 'overall output (includes prefill): 11.7 tok/s', '1/5 (20.0% accepted)']) {
    assert.ok(text.includes(part), text)
  }
  assert.equal(totalTokens(response), 120)
  assert.deepEqual(response, original)
  assert.deepEqual(vllmGenerations([{role:'user'}, response, {...response}]).map(row => row.index), [2, 3])
})

test('missing metrics remain unavailable while usage still renders', () => {
  const response = {usage:{prompt_tokens:6, completion_tokens:2, prompt_tokens_details:null}, metrics:null}
  const text = formatResponseStats(response).join('\n')
  assert.ok(text.includes('out: 2 tokens'))
  assert.ok(!text.includes('tok/s'))
  assert.equal(totalTokens(response), 8)
  assert.equal(optionalMetric(null), '—')
  assert.deepEqual(formatResponseStats(null), [])
})

test('llama-server keeps native prefill/decode rates and additive cache counts', () => {
  const response = {role:'assistant', timings:{cache_n:80, prompt_n:20, predicted_n:10,
    prompt_per_second:500, predicted_per_second:100, draft_n:0, draft_n_accepted:0}}
  const text = formatResponseStats(response).join('\n')
  assert.ok(text.includes('in: 20 tokens @ 500.0 tok/s'))
  assert.ok(text.includes('out: 10 tokens @ 100.0 tok/s'))
  assert.ok(!text.includes('NaN'))
  assert.equal(totalTokens(response), 110)
  assert.deepEqual(vllmGenerations([response]), [])
})
