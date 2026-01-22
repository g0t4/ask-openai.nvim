<!-- Gippity took dibs -->
<script lang="ts">
  import type { ThreadJson, Message } from './lib/types'
  import { scrollToHash, setupHashListener } from './lib/hash-nav'
  import MessageView from './components/MessageView.svelte'
  import FileBrowser from './components/FileBrowser.svelte'
  import GitHubBrowser from './components/GitHubBrowser.svelte'
  import LocalBrowser from './components/LocalBrowser.svelte'
  import 'highlight.js/styles/github-dark.css'

  let messages: Message[] = $state([])
  let loading = $state(true)
  let error = $state<string | null>(null)
  let threadUrl = $state<string | null>(null)
  let isDirectory = $state(false)
  let githubPath = $state<string | null>(null) // e.g., "g0t4/dataset-gfy/master/path/to/file"
  let localPath = $state<string | null>(null) // e.g., "semantic_grep_auto_context/fims"

  // Decoded URL for display
  const displayUrl = $derived(
    localPath
      ? `local → ${localPath || '(root)'}`
      : githubPath
        ? `github.com/${githubPath.split('/').slice(0, 2).join('/')} → ${githubPath.split('/').slice(3).join('/')}`
        : threadUrl
          ? decodeURIComponent(threadUrl)
          : null
  )

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

    // New github= parameter (e.g., ?github=g0t4/dataset-gfy/master/path/to/file)
    const githubParam = params.get('github')

    // Dev-only local= parameter (e.g., ?local=semantic_grep_auto_context/fims)
    const localParam = params.get('local')

    // Legacy url= parameter (backward compat, files only)
    const urlParam = params.get('url')

    if (githubParam) {
      // Parse github=owner/repo/branch/path
      githubPath = githubParam
      localPath = null
      const parts = githubParam.split('/')
      if (parts.length < 3) {
        error = 'Invalid github parameter format. Expected: owner/repo/branch/path'
        loading = false
        return
      }

      const owner = parts[0]
      const repo = parts[1]
      const branch = parts[2]
      const path = parts.slice(3).join('/')

      // Use path heuristics to detect directory
      isDirectory = isDirectoryUrl(path)

      if (isDirectory) {
        // Directory - will use GitHubBrowser
        loading = false
      } else {
        // File - fetch from jsDelivr CDN
        const cdnUrl = `https://cdn.jsdelivr.net/gh/${owner}/${repo}@${branch}/${path}`
        threadUrl = cdnUrl
        loadThread(cdnUrl)
      }
    } else if (localParam && import.meta.env.MODE === 'development') {
      // Dev-only local= parameter
      localPath = localParam
      githubPath = null

      // Use path heuristics to detect directory
      isDirectory = isDirectoryUrl(localParam)

      if (isDirectory) {
        // Directory - will use LocalBrowser
        loading = false
      } else {
        // File - fetch via API endpoint
        threadUrl = `/api/local/file?path=${encodeURIComponent(localParam)}`
        loadThread(threadUrl)
      }
    } else if (urlParam) {
      // Legacy url= parameter (files only, no directory browsing)
      threadUrl = urlParam
      githubPath = null
      localPath = null
      isDirectory = false
      loadThread(urlParam)
    } else {
      loading = false
      error =
        import.meta.env.MODE === 'development'
          ? 'Provide a ?github=, ?url=, or ?local= parameter.'
          : 'Provide a ?github= or ?url= parameter.'
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
  {:else if isDirectory && localPath}
    <LocalBrowser localPath={localPath} />
  {:else if isDirectory && githubPath}
    <GitHubBrowser githubPath={githubPath} />
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
