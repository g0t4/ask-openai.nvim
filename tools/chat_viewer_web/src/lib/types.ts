export interface TraceJson {
  request_body: RequestBody
  response_message?: Message
  last_sse?: LastSSE
}

export interface LastSSE {
  model?: string
  timings?: Timings
  [key: string]: unknown
}

export interface Timings {
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

export interface Message {
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
