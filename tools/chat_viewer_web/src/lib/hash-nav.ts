/**
 * Hash navigation utilities for deep linking into messages and sub-elements
 *
 * Scheme:
 *   #3         - message 3
 *   #3-tool-1  - message 3, tool call 1
 *   #3-match-2 - message 3, RAG match 2
 *   #3-file-1  - message 3, patch file 1
 */

export function getMessageId(index: number): string {
  return `${index}`
}

export function getToolCallId(msgIndex: number, toolIndex: number): string {
  return `${msgIndex}-tool-${toolIndex}`
}

export function getMatchId(msgIndex: number, matchIndex: number): string {
  return `${msgIndex}-match-${matchIndex}`
}

export function getFileId(msgIndex: number, fileIndex: number): string {
  return `${msgIndex}-file-${fileIndex}`
}

export function scrollToHash(): void {
  const hash = window.location.hash.slice(1) // remove #
  if (!hash) return

  // Small delay to ensure DOM is ready
  requestAnimationFrame(() => {
    const el = document.getElementById(hash)
    if (el) {
      el.scrollIntoView({ behavior: 'smooth', block: 'start' })
      // Add highlight effect
      el.classList.add('hash-highlight')
      setTimeout(() => el.classList.remove('hash-highlight'), 2000)
    }
  })
}

export function copyLink(id: string): void {
  const url = new URL(window.location.href)
  url.hash = id
  navigator.clipboard.writeText(url.toString())
}

export function setupHashListener(): () => void {
  const handler = () => scrollToHash()
  window.addEventListener('hashchange', handler)
  return () => window.removeEventListener('hashchange', handler)
}
