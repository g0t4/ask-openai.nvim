import { diffWords } from 'diff'

export interface PatchHunk {
  header: string
  changes: HunkChange[]
}

export interface HunkChange {
  type: 'context' | 'removed' | 'added'
  content: string
}

export interface WordDiffSegment {
  type: 'unchanged' | 'removed' | 'added'
  value: string
}

export interface ParsedPatch {
  files: PatchFile[]
}

export interface PatchFile {
  path: string
  action: 'add' | 'update' | 'delete' | 'move'
  newPath?: string  // for move operations
  hunks: PatchHunk[]
}

/**
 * Parse custom patch format used by apply_patch tool:
 * *** Begin Patch
 * *** Update File: path/to/file
 * @@ optional header @@
 * -removed line
 * +added line
 *  context line
 * *** End Patch
 */
export function parsePatch(patch: string): ParsedPatch {
  const lines = patch.split('\n')
  const files: PatchFile[] = []
  let currentFile: PatchFile | null = null
  let currentHunk: PatchHunk | null = null
  let inPatch = false

  for (const line of lines) {
    // Start/end markers
    if (line.trim() === '*** Begin Patch') {
      inPatch = true
      continue
    }
    if (line.trim() === '*** End Patch') {
      inPatch = false
      continue
    }

    if (!inPatch && !currentFile) continue

    // File action markers
    const addMatch = line.match(/^\*\*\* Add File: (.+)/)
    const updateMatch = line.match(/^\*\*\* Update File: (.+)/)
    const deleteMatch = line.match(/^\*\*\* Delete File: (.+)/)
    const moveMatch = line.match(/^\*\*\* Move to: (.+)/)

    if (addMatch || updateMatch || deleteMatch) {
      // Save previous file
      if (currentFile) {
        if (currentHunk) currentFile.hunks.push(currentHunk)
        files.push(currentFile)
      }

      const path = (addMatch || updateMatch || deleteMatch)![1].trim()
      const action = addMatch ? 'add' : updateMatch ? 'update' : 'delete'
      currentFile = { path, action, hunks: [] }
      currentHunk = null
      continue
    }

    if (moveMatch && currentFile) {
      currentFile.action = 'move'
      currentFile.newPath = moveMatch[1].trim()
      continue
    }

    // End of file marker (for truncated content)
    if (line.trim() === '*** End of File') {
      continue
    }

    // Hunk header: @@ ... @@
    if (line.startsWith('@@')) {
      if (currentHunk && currentFile) {
        currentFile.hunks.push(currentHunk)
      }
      currentHunk = {
        header: line,
        changes: [],
      }
      continue
    }

    // Hunk content - must have a file context
    if (currentFile) {
      // Create default hunk if none exists
      if (!currentHunk) {
        currentHunk = { header: '', changes: [] }
      }

      if (line.startsWith('-')) {
        currentHunk.changes.push({ type: 'removed', content: line.slice(1) })
      } else if (line.startsWith('+')) {
        currentHunk.changes.push({ type: 'added', content: line.slice(1) })
      } else if (line.startsWith(' ')) {
        currentHunk.changes.push({ type: 'context', content: line.slice(1) })
      } else if (line === '') {
        // Empty line in context
        currentHunk.changes.push({ type: 'context', content: '' })
      }
    }
  }

  // Don't forget the last file/hunk
  if (currentFile) {
    if (currentHunk) currentFile.hunks.push(currentHunk)
    files.push(currentFile)
  }

  return { files }
}

/**
 * Group consecutive removed/added lines for word-diff comparison
 */
export interface ChangeGroup {
  type: 'context' | 'change'
  context?: string[]
  removed?: string[]
  added?: string[]
  wordDiff?: WordDiffSegment[]
}

export function groupChanges(changes: HunkChange[]): ChangeGroup[] {
  const groups: ChangeGroup[] = []
  let i = 0

  while (i < changes.length) {
    const change = changes[i]

    if (change.type === 'context') {
      // Collect consecutive context lines
      const contextLines: string[] = []
      while (i < changes.length && changes[i].type === 'context') {
        contextLines.push(changes[i].content)
        i++
      }
      groups.push({ type: 'context', context: contextLines })
    } else {
      // Collect consecutive removed, then added
      const removed: string[] = []
      const added: string[] = []

      while (i < changes.length && changes[i].type === 'removed') {
        removed.push(changes[i].content)
        i++
      }
      while (i < changes.length && changes[i].type === 'added') {
        added.push(changes[i].content)
        i++
      }

      // Compute word diff between removed and added
      const oldText = removed.join('\n')
      const newText = added.join('\n')
      const wordDiff = computeWordDiff(oldText, newText)

      groups.push({ type: 'change', removed, added, wordDiff })
    }
  }

  return groups
}

/**
 * Compute word-level diff between two strings
 */
export function computeWordDiff(oldText: string, newText: string): WordDiffSegment[] {
  const diff = diffWords(oldText, newText)
  return diff.map((part) => ({
    type: part.added ? 'added' : part.removed ? 'removed' : 'unchanged',
    value: part.value,
  }))
}

/**
 * Get display path from patch path (remove a/ or b/ prefix)
 */
export function getDisplayPath(path: string): string {
  if (path.startsWith('a/') || path.startsWith('b/')) {
    return path.slice(2)
  }
  return path
}
