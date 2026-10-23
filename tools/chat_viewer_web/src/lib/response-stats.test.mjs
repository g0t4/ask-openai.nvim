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
  for (const part of ['in: 20', 'out: 20', 'reasoning: 10', 'TTFT: 118.6 ms',
    'decode: 52.3 ms', '1/5 (20.0% accepted)']) {
    assert.ok(text.includes(part), text)
  }
  assert.ok(!text.includes('queue:'))
  assert.ok(text.includes('\n  reasoning: 10'))
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

test('output details nest under output and zero queue/reasoning are hidden', () => {
  for (const queue of [null, 0, 0.02, 1.25]) {
    for (const reasoning of [null, 0, 7]) {
      const response = {usage: {completion_tokens: 20, completion_tokens_details: {reasoning_tokens: reasoning}},
        metrics: {queue_time_ms: queue, generation_time_ms: 50, mean_itl_ms: 2.5,
          speculative_decoding: {num_draft_tokens: 10, num_accepted_draft_tokens: 5, mean_acceptance_length: 2}}}
      const original = structuredClone(response)
      const lines = formatResponseStats(response)
      assert.equal(lines.some(line => line.startsWith('queue:')), queue != null && queue >= 0.05)
      assert.equal(lines.some(line => line.includes('reasoning:')), reasoning === 7)
      if (reasoning) assert.ok(lines.includes('  reasoning: 7 tokens'))
      const draftIndex = lines.findIndex(line => line.startsWith('  draft:'))
      assert.ok(draftIndex > lines.indexOf('out: 20 tokens'))
      assert.equal(lines[draftIndex + 1], '    mean acceptance length: 2.0 tokens')
      assert.ok(lines.includes('  decode: 50.0 ms'))
      assert.ok(lines.includes('  mean ITL: 2.5 ms'))
      assert.deepEqual(response, original)
    }
  }
})

test('SGLang fields render through the shared stats adapter without fabricated timings', () => {
  const response = {usage:{prompt_tokens:100,completion_tokens:20,reasoning_tokens:7,prompt_tokens_details:{cached_tokens:80}},
    sglext:{spec_tokens_details:{spec_num_correct_drafts:12,spec_num_proposed_drafts:18,spec_accept_rate:2/3,spec_accept_length:8/3}}}
  const original = structuredClone(response)
  const text = formatResponseStats(response).join('\n')
  for (const value of ['in: 20', 'out: 20', 'reasoning: 7', '12/18 (66.7% accepted)', 'mean acceptance length: 2.7']) {
    assert.ok(text.includes(value), text)
  }
  assert.ok(!text.includes('TTFT'))
  assert.ok(!text.includes('tok/s'))
  assert.deepEqual(vllmGenerations([{role:'assistant',...response}]), [])
  assert.deepEqual(response, original)
})
