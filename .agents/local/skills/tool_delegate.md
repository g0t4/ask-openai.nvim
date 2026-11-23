## Use `delegate` to spawn a subagent.

Delegate lets you offload a task to a specialized subagent. The subagent will work independently and return a summarized result.

### How it works

1. Provide a clear **description** of the task
2. Optionally specify an **agent_type** to select a specialized profile
3. Optionally set **recursion_limit** to cap nested delegation

### Example

```json
{
  "description": "Review src/ and summarize all security concerns",
  "agent_type": "code-auditor",
  "recursion_limit": 3
}
```

### Reminders

- The subagent runs asynchronously — you'll receive its summary as output
- Keep descriptions focused and specific for best results
- Use `agent_type` to match the right specialist to the task
