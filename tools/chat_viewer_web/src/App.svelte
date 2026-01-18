<script lang="ts">
  import type { ThreadJson, Message } from './lib/types'
  import MessageView from './components/MessageView.svelte'
  import 'highlight.js/styles/github-dark.css'

  let messages: Message[] = $state([])
  let loading = $state(true)
  let error = $state<string | null>(null)
  let threadUrl = $state<string | null>(null)

  async function loadThread(url: string) {
    loading = true
    error = null
    try {
      const res = await fetch(url)
      if (!res.ok) throw new Error(`Failed to fetch: ${res.status}`)
      const data: ThreadJson = await res.json()

      // Extract messages from request_body
      messages = data.request_body?.messages ?? []

      // Append response_message if present
      if (data.response_message) {
        messages = [...messages, data.response_message]
      }
    } catch (e) {
      error = e instanceof Error ? e.message : 'Unknown error'
    } finally {
      loading = false
    }
  }

  // Load from URL param on mount
  $effect(() => {
    const params = new URLSearchParams(window.location.search)
    const url = params.get('url')
    if (url) {
      threadUrl = url
      loadThread(url)
    } else {
      loading = false
      error = 'No ?url= parameter provided. Pass a URL to a thread.json file.'
    }
  })
</script>

<main class="max-w-4xl mx-auto p-4">
  <header class="mb-6">
    <h1 class="text-2xl font-bold text-gray-100">Chat Viewer</h1>
    {#if threadUrl}
      <p class="text-sm text-gray-500 truncate mt-1">{threadUrl}</p>
    {/if}
  </header>

  {#if loading}
    <div class="text-gray-400">Loading...</div>
  {:else if error}
    <div class="text-red-400 bg-red-900/20 p-4 rounded">{error}</div>
  {:else}
    <div class="space-y-4">
      {#each messages as msg, idx}
        <MessageView message={msg} index={idx + 1} />
      {/each}
    </div>
  {/if}
</main>
