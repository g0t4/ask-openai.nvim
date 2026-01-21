<script lang="ts">
  interface GitHubItem {
    name: string
    path: string
    type: 'file' | 'dir'
  }

  interface Props {
    githubPath: string // e.g., "g0t4/dataset-gfy/master/semantic_grep_auto_context/fims"
  }

  let { githubPath }: Props = $props()

  let items: GitHubItem[] = $state([])
  let loading = $state(true)
  let error = $state<string | null>(null)

  // Parse github path into components
  const parsed = $derived.by(() => {
    const parts = githubPath.split('/')
    if (parts.length < 3) return null

    return {
      owner: parts[0],
      repo: parts[1],
      branch: parts[2],
      path: parts.slice(3).join('/'),
      fullPath: githubPath,
    }
  })

  // Build github.com URL for scraping
  const githubUrl = $derived(
    parsed
      ? `https://github.com/${parsed.owner}/${parsed.repo}/tree/${parsed.branch}/${parsed.path}`
      : null
  )

  // Build app URL for navigation
  function buildAppUrl(itemPath: string, isDir: boolean): string {
    if (!parsed) return ''
    const newGithubPath = `${parsed.owner}/${parsed.repo}/${parsed.branch}/${itemPath}`
    return `${window.location.pathname}?github=${encodeURIComponent(newGithubPath)}${window.location.hash}`
  }

  // Get parent directory path
  const parentPath = $derived.by(() => {
    if (!parsed || !parsed.path) return null
    const parts = parsed.path.split('/').filter(Boolean)
    if (parts.length === 0) return null
    parts.pop()
    const parentDir = parts.join('/')
    return `${parsed.owner}/${parsed.repo}/${parsed.branch}/${parentDir}`
  })

  async function loadDirectory() {
    loading = true
    error = null
    items = []

    if (!githubUrl || !parsed) {
      error = 'Invalid GitHub path'
      loading = false
      return
    }

    try {
      // Try fetching HTML directly from GitHub
      // GitHub pages might allow CORS, but if not we'll get an error
      const response = await fetch(githubUrl)

      if (!response.ok) {
        throw new Error(`Failed to fetch directory: ${response.status}`)
      }

      const html = await response.text()

      // Parse HTML to extract file/folder listings
      // GitHub uses a specific structure in their tree view
      const parser = new DOMParser()
      const doc = parser.parseFromString(html, 'text/html')

      // Find all rows in the file table
      // GitHub uses role="rowgroup" for the file listing
      const rows = doc.querySelectorAll('div[role="rowgroup"] div[role="row"]')

      const extractedItems: GitHubItem[] = []

      rows.forEach((row) => {
        // Each row has a link with aria-label that contains the file/folder name
        const link = row.querySelector('a[aria-label]')
        if (!link) return

        const ariaLabel = link.getAttribute('aria-label') || ''
        const href = link.getAttribute('href') || ''

        // Extract name from aria-label (format: "filename" or "foldername, (Directory)")
        let name = ariaLabel.replace(/, \(Directory\)$/, '').trim()
        const isDir = ariaLabel.includes('(Directory)')

        // Build full path
        const fullItemPath = parsed.path ? `${parsed.path}/${name}` : name

        if (name) {
          extractedItems.push({
            name,
            path: fullItemPath,
            type: isDir ? 'dir' : 'file',
          })
        }
      })

      // Sort: directories first, then alphabetically
      items = extractedItems.sort((a, b) => {
        if (a.type !== b.type) return a.type === 'dir' ? -1 : 1
        return a.name.localeCompare(b.name)
      })

      if (items.length === 0) {
        error = 'No files or folders found (or unable to parse GitHub page structure)'
      }
    } catch (e) {
      error = e instanceof Error ? e.message : 'Unknown error'
    } finally {
      loading = false
    }
  }

  // Load directory when githubPath changes
  $effect(() => {
    loadDirectory()
  })
</script>

<div class="space-y-4">
  <div class="flex items-center gap-2 text-sm text-gray-400">
    <span>📁</span>
    <span class="font-mono">{parsed?.path || '(root)'}</span>
  </div>

  {#if loading}
    <div class="text-gray-400">Loading directory...</div>
  {:else if error}
    <div class="text-red-400 bg-red-900/20 p-4 rounded">{error}</div>
  {:else}
    <div class="space-y-1">
      {#if parentPath}
        <a
          href={buildAppUrl(parentPath.split('/').slice(3).join('/'), true)}
          class="block p-3 rounded hover:bg-gray-800 transition-colors"
        >
          <div class="flex items-center gap-3">
            <span class="text-xl">📁</span>
            <span class="text-gray-300 font-mono">..</span>
          </div>
        </a>
      {/if}

      {#each items as item}
        <a
          href={buildAppUrl(item.path, item.type === 'dir')}
          class="block p-3 rounded hover:bg-gray-800 transition-colors"
        >
          <div class="flex items-center gap-3">
            {#if item.type === 'dir'}
              <span class="text-xl">📁</span>
              <span class="text-gray-300 font-mono">{item.name}/</span>
            {:else}
              <span class="text-xl">
                {#if item.name.endsWith('.json')}
                  📄
                {:else if item.name.endsWith('.py')}
                  🐍
                {:else if item.name.endsWith('.js') || item.name.endsWith('.ts')}
                  📜
                {:else if item.name.endsWith('.md')}
                  📝
                {:else}
                  📄
                {/if}
              </span>
              <span class="text-gray-300 font-mono">{item.name}</span>
              {#if item.name.endsWith('.json')}
                <span class="text-xs text-cyan-400">(thread)</span>
              {/if}
            {/if}
          </div>
        </a>
      {/each}
    </div>
  {/if}
</div>
