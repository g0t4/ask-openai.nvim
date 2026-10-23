import test from 'node:test'
import assert from 'node:assert/strict'
import { timingSummaries } from './timings-summary.ts'

test('matching columns use uncached input, split output, and summed seconds', () => {
  const first = {role:'assistant',usage:{prompt_tokens:1000,completion_tokens:100,
    prompt_tokens_details:{cached_tokens:800},completion_tokens_details:{reasoning_tokens:60}},
    metrics:{time_to_first_token_ms:200,generation_time_ms:990,
      speculative_decoding:{num_draft_tokens:120,num_accepted_draft_tokens:60,mean_acceptance_length:3}}}
  const second = {role:'assistant',usage:{prompt_tokens:1300,completion_tokens:200,
    prompt_tokens_details:{cached_tokens:1100},completion_tokens_details:{reasoning_tokens:40}},
    metrics:{time_to_first_token_ms:100,generation_time_ms:1990}}
  const [summary] = timingSummaries([{role:'user'},first,{role:'assistant',content:'no stats'},second])
  assert.equal(summary.rows[0][1], '200 @ ≈1,000.0 tok/s')
  assert.equal(summary.rows[0][6], '60/120 50.0%')
  assert.equal(summary.rows[1].at(-1), '#3')
  assert.ok(summary.rows[1][0].endsWith('ok'))
  assert.deepEqual(summary.totals, ['', '400', '100', '200', '33.3%', '300', '', '', '0.30 s', '2.98 s', 'total'])
  assert.ok(!summary.headers.includes('overall output'))
  assert.ok(!summary.headers.includes('TTFT'))
})

test('SGLang stays separate with no invented durations and llama has no reasoning split', () => {
  const messages = [{role:'assistant',timings:{cache_n:80,prompt_n:20,predicted_n:10,prompt_ms:100,predicted_ms:200}},
    {role:'assistant',usage:{prompt_tokens:100,completion_tokens:20,reasoning_tokens:7,prompt_tokens_details:{cached_tokens:80}},
      sglext:{spec_tokens_details:{spec_num_correct_drafts:12,spec_num_proposed_drafts:18,spec_accept_rate:2/3,spec_accept_length:8/3}}}]
  const summaries = timingSummaries(messages)
  assert.equal(summaries[0].name, 'llama-server')
  assert.ok(!summaries[0].headers.includes('reasoning tokens'))
  assert.equal(summaries[1].name, 'SGLang')
  assert.equal(summaries[1].rows[0][6], '12/18 66.7%')
  assert.equal(summaries[1].rows[0][8], '—')
  assert.equal(summaries[1].rows[0][9], '—')
  assert.equal(summaries[1].totals[2], '7')
  assert.equal(summaries[1].totals[3], '13')
})
