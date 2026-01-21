<!-- Gippity took dibs -->
<script lang="ts">
  import type { ThreadJson, Message } from './lib/types'
  import { scrollToHash, setupHashListener } from './lib/hash-nav'
  import MessageView from './components/MessageView.svelte'
  import FileBrowser from './components/FileBrowser.svelte'
  import 'highlight.js/styles/github-dark.css'

  let messages: Message[] = $state([])
  let loading = $state(true)
  let error = $state<string | null>(null)
  let threadUrl = $state<string | null>(null)
  let isDirectory = $state(false)

  // Decoded URL for display
  const displayUrl = $derived(threadUrl ? decodeURIComponent(threadUrl) : null)

  // Derive title from thread URL
  const pageTitle = $derived.by(() => {
    if (!threadUrl) return 'Chat Viewer'
    if (isDirectory) return 'File Browser'
    const url = threadUrl.toLowerCase()
    if (url.includes('rewrite')) return ':AskRewrite'
    if (url.includes('tools')) return ':AskQuestion /tools'
    if (url.includes('question')) return ':AskQuestion'
    if (url.includes('fim')) return ':AskPredict'
    return 'Chat Viewer'
  })

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

  // Detect if URL is a directory based on path heuristics
  function isDirectoryUrl(url: string): boolean {
    // Ends with / = directory
    if (url.endsWith('/')) return true

    // Extract path from URL
    try {
      const urlObj = new URL(url)
      const path = urlObj.pathname
      const lastSegment = path.split('/').filter(Boolean).pop() || ''

      // No extension = directory (e.g., "2026-01-19_002")
      // Has .json extension = file
      if (!lastSegment.includes('.')) return true
      if (lastSegment.endsWith('.json')) return false

      // Other extensions default to file
      return false
    } catch {
      // If URL parsing fails, fallback to slash check
      return url.endsWith('/')
    }
  }

  // Load from URL param on mount
  $effect(() => {
    const params = new URLSearchParams(window.location.search)
    // Accept either a full URL via ?url= or a local filesystem path via ?path= (dev only)
    const urlParam = params.get('url')
    const pathParam = params.get('path')
    let source: string | null = null
    if (urlParam) {
      source = urlParam
    } else if (pathParam && import.meta.env.MODE === 'development') {
      // Vite dev server can serve files from the project root when strict mode is disabled.
      // Use a relative path directly; fetch will resolve it against the current origin.
      source = pathParam
    }

    if (source) {
      threadUrl = source
      // Use path heuristics to detect directory
      isDirectory = isDirectoryUrl(source)

      if (isDirectory) {
        // For directories, just set loading to false - FileBrowser handles its own loading
        loading = false
      } else {
        // For files, load the thread
        loadThread(source)
      }
    } else {
      loading = false
      // Show a concise message in production (no mention of ?path=)
      error =
        import.meta.env.MODE === 'development'
          ? 'Provide a ?url= or ?path= parameter pointing to a thread.json file or directory.'
          : 'Provide a ?url= parameter pointing to a thread.json file or directory.'
    }
  })

  // Scroll to hash after content loads
  $effect(() => {
    if (!loading && messages.length > 0) {
      // Delay to ensure DOM is rendered
      setTimeout(scrollToHash, 100)
    }
  })

  // Listen for hash changes
  $effect(() => {
    return setupHashListener()
  })

  // Update document title when pageTitle changes
  $effect(() => {
    document.title = pageTitle
  })
</script>

<main class="max-w-7xl mx-auto p-4">
  <header class="mb-6">
    <h1 class="text-2xl font-bold text-gray-100">{pageTitle}</h1>
    {#if displayUrl}
      <p class="text-sm text-gray-500 truncate mt-1">{displayUrl}</p>
    {/if}
  </header>

  {#if loading}
    <div class="text-gray-400">Loading...</div>
  {:else if error}
    <div class="text-red-400 bg-red-900/20 p-4 rounded">{error}</div>
  {:else if isDirectory && threadUrl}
    <FileBrowser url={threadUrl} />
  {:else}
    <div class="space-y-4">
      {#each messages as msg, idx}
        <MessageView message={msg} index={idx + 1} />
      {/each}
    </div>
  {/if}
</main>
