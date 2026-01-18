<script lang="ts">
  import type { Message } from '../lib/types'
  import { getRoleColor, extractContent } from '../lib/types'
  import { getMessageId } from '../lib/hash-nav'
  import ToolCalls from './ToolCalls.svelte'
  import ToolResult from './ToolResult.svelte'
  import LinkButton, { copy } from './LinkButton.svelte'

  interface Props {
    message: Message
    index: number
  }

  let { message, index }: Props = $props()

  const role = $derived(message.role)
  const colorClass = $derived(getRoleColor(role))
  const displayRole = $derived(role === 'tool' ? 'TOOL RESULT' : role.toUpperCase())
  const content = $derived(extractContent(message))
  const reasoning = $derived(message.reasoning_content)
  const toolCalls = $derived(message.tool_calls)
  const msgId = $derived(getMessageId(index))
</script>

<article id={msgId} class="border border-gray-700 rounded-lg overflow-hidden scroll-mt-4 transition-colors duration-500">
  <!-- Header -->
  <header
    class="group px-4 py-2 font-semibold border-b border-gray-700 flex items-center justify-between cursor-pointer"
    class:bg-role-system={role === 'system'}
    class:bg-role-developer={role === 'developer'}
    class:bg-role-user={role === 'user'}
    class:bg-role-assistant={role === 'assistant'}
    class:bg-role-tool={role === 'tool'}
    style="--tw-bg-opacity: 0.2"
    onclick={() => copy(msgId)}
  >
    <span class="text-{colorClass}">{index}: {displayRole}</span>
    <LinkButton id={msgId} />
  </header>

  <!-- Content -->
  <div class="p-4 bg-gray-800/50">
    {#if role === 'tool'}
      <ToolResult {content} msgIndex={index} />
    {:else}
      <!-- Reasoning (for assistant messages with extended thinking) -->
      {#if reasoning}
        <div class="mb-4 pl-4 border-l-2 border-gray-600 text-gray-400 italic whitespace-pre-wrap">
          {reasoning}
        </div>
      {/if}

      <!-- Main content -->
      {#if content}
        <div class="whitespace-pre-wrap text-gray-200">
          {content}
        </div>
      {/if}

      <!-- Tool calls (for assistant) -->
      {#if toolCalls && toolCalls.length > 0}
        <ToolCalls calls={toolCalls} msgIndex={index} />
      {/if}
    {/if}
  </div>
</article>

<style>
  .text-role-system { color: #d946ef; }
  .text-role-developer { color: #06b6d4; }
  .text-role-user { color: #22c55e; }
  .text-role-assistant { color: #eab308; }
  .text-role-tool { color: #ef4444; }

  .bg-role-system { background-color: rgba(217, 70, 239, 0.2); }
  .bg-role-developer { background-color: rgba(6, 182, 212, 0.2); }
  .bg-role-user { background-color: rgba(34, 197, 94, 0.2); }
  .bg-role-assistant { background-color: rgba(234, 179, 8, 0.2); }
  .bg-role-tool { background-color: rgba(239, 68, 68, 0.2); }
</style>
