export interface ThreadJson {
  request_body: RequestBody
  response_message?: Message
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
