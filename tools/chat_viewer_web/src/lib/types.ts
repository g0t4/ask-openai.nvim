export interface TraceJson {
  request_body: RequestBody
  response_message?: Message
  last_sse?: LastSSE
}

// Raw server fields remain separate: vLLM usage includes cached input and its
// overall throughput includes prefill, unlike llama-server's decode rate.
export interface ResponseStats {
  timings?: Timings | null
  usage?: Usage | null
  metrics?: VllmMetrics | null
  response_backend?: string
  sglext?: { spec_tokens_details?: SglangSpeculative | SglangSpeculative[] | null; cached_tokens_details?: unknown } | null
  meta_info?: Record<string, unknown> | null
}

export interface Usage {
  prompt_tokens?: number | null
  completion_tokens?: number | null
  total_tokens?: number | null
  prompt_tokens_details?: { cached_tokens?: number | null } | null
  completion_tokens_details?: { reasoning_tokens?: number | null } | null
  reasoning_tokens?: number | null
}

export interface SglangSpeculative {
  spec_num_proposed_drafts?: number
  spec_num_correct_drafts?: number
  spec_accept_rate?: number
  spec_accept_length?: number
  [key: string]: unknown
}

export interface VllmMetrics {
  time_to_first_token_ms?: number | null
  generation_time_ms?: number | null
  queue_time_ms?: number | null
  mean_itl_ms?: number | null
  tokens_per_second?: number | null
  speculative_decoding?: {
    num_draft_tokens?: number | null
    num_accepted_draft_tokens?: number | null
    draft_acceptance_rate?: number | null
    mean_acceptance_length?: number | null
  } | null
}

export interface LastSSE extends ResponseStats {
  model?: string
  [key: string]: unknown
}

export interface SglangTiming extends SglangSpeculative {
  index?: number
  prompt_tokens?: number
  completion_tokens?: number
  cached_tokens?: number
  reasoning_tokens?: number
  e2e_latency?: number
  first_token_latency?: number
  queue_time?: number
  decode_throughput?: number
}

export interface Timings {
  choices?: SglangTiming[]
  prompt_n?: number
  predicted_n?: number
  cache_n?: number
  draft_n?: number
  draft_n_accepted?: number
  prompt_ms?: number
  predicted_ms?: number
  prompt_per_second?: number
  predicted_per_second?: number
}

export interface RequestBody {
  messages: Message[]
  // Other fields exist but we don't need them for display
  [key: string]: unknown
}

export interface Message extends ResponseStats {
  role: 'system' | 'developer' | 'user' | 'assistant' | 'tool'
  content?: string | ContentObject
  tool_calls?: ToolCall[]
  tool_call_id?: string
  reasoning_content?: string
  duration_ms?: number
  start_time_ms?: number
}

export interface ContentObject {
  text?: string
  [key: string]: unknown
}

export interface ToolCall {
  id: string
  type: 'function'
  function: {
    name: string
    arguments: string // JSON string
  }
}

export interface RagMatch {
  file: string
  text: string
  embed_rank?: number
  rerank_score?: number
}

export interface RagResult {
  matches: RagMatch[]
}

export type Role = Message['role']

export function getRoleColor(role: Role): string {
  switch (role) {
    case 'system':
      return 'role-system'
    case 'developer':
      return 'role-developer'
    case 'user':
      return 'role-user'
    case 'assistant':
      return 'role-assistant'
    case 'tool':
      return 'role-tool'
    default:
      return 'gray-400'
  }
}

export function extractContent(msg: Message): string {
  const content = msg.content
  if (!content) return ''
  if (typeof content === 'string') return content
  if (typeof content === 'object' && 'text' in content) {
    return content.text ?? ''
  }
  return JSON.stringify(content, null, 2)
}

export function formatDurationMs(durationMs: number): string {
  if (durationMs < 1000) {
    return `${durationMs}ms`
  }

  const seconds = durationMs / 1000.0
  if (seconds < 60) {
    const roundedSeconds = Math.round(seconds * 10) / 10
    if (roundedSeconds === Math.floor(roundedSeconds)) {
      return `${Math.floor(roundedSeconds)}s`
    }
    return `${roundedSeconds}s`
  }

  const minutes = Math.floor(seconds / 60)
  const wholeSeconds = Math.floor(seconds % 60)
  return `${minutes}m${wholeSeconds}s`
}

// Shell trace format (different from agent traces)
export interface ShellTraceResponse {
  finish_reason?: string
  model_name?: string
  system_fingerprint?: string
  model_provider?: string
  model?: string
  service?: string
  [key: string]: unknown
}

export interface ShellTraceJson {
  session_id?: number | string
  messages: Message[]
  response?: ShellTraceResponse
  [key: string]: unknown
}
