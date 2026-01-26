/**
 * Extract Unix timestamp from filename like "1769217593-thread.json"
 * Returns null if no timestamp prefix is found
 */
export function extractTimestamp(filename: string): number | null {
  const match = filename.match(/^(\d{10})-/)
  if (match) {
    return parseInt(match[1], 10)
  }
  return null
}

/**
 * Format timestamp as readable date/time
 */
export function formatDateTime(timestamp: number): string {
  const date = new Date(timestamp * 1000)
  return date.toLocaleString('en-US', {
    month: 'short',
    day: 'numeric',
    hour: 'numeric',
    minute: '2-digit',
    hour12: true
  })
}

/**
 * Calculate relative age like "2h ago", "3d ago", "just now"
 */
export function formatAge(timestamp: number): string {
  const now = Date.now()
  const then = timestamp * 1000
  const diffMs = now - then
  const diffSeconds = Math.floor(diffMs / 1000)
  const diffMinutes = Math.floor(diffSeconds / 60)
  const diffHours = Math.floor(diffMinutes / 60)
  const diffDays = Math.floor(diffHours / 24)
  const diffWeeks = Math.floor(diffDays / 7)
  const diffMonths = Math.floor(diffDays / 30)
  const diffYears = Math.floor(diffDays / 365)

  if (diffSeconds < 60) {
    return 'just now'
  } else if (diffMinutes < 60) {
    return `${diffMinutes}m ago`
  } else if (diffHours < 24) {
    return `${diffHours}h ago`
  } else if (diffDays < 7) {
    return `${diffDays}d ago`
  } else if (diffWeeks < 4) {
    return `${diffWeeks}w ago`
  } else if (diffMonths < 12) {
    return `${diffMonths}mo ago`
  } else {
    return `${diffYears}y ago`
  }
}

/**
 * Get color class based on age (cyan for recent, blue for medium, gray for old)
 */
export function getAgeColor(timestamp: number): string {
  const now = Date.now()
  const diffMs = now - timestamp * 1000
  const diffHours = diffMs / (1000 * 60 * 60)
  const diffDays = diffHours / 24

  if (diffDays < 1) {
    return 'text-cyan-400' // Recent - bright cyan
  } else if (diffDays < 7) {
    return 'text-blue-400' // Medium - blue
  } else {
    return 'text-gray-500' // Older - gray
  }
}

/**
 * Get formatted timestamp info for display
 * Returns null if no timestamp found
 */
export function getTimestampInfo(filename: string): { dateTime: string; age: string; colorClass: string } | null {
  const timestamp = extractTimestamp(filename)
  if (!timestamp) return null

  return {
    dateTime: formatDateTime(timestamp),
    age: formatAge(timestamp),
    colorClass: getAgeColor(timestamp)
  }
}
