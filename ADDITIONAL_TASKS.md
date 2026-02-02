

11. MESSAGE COALESCING: If user sends two messages within 2-3 seconds, evaluate if message 2 modifies/appends to message 1. If so, halt message 1 and combine them into a single request before sending to gateway. Prevents double-responses to rapid sequential messages.




15. ACTIVITY/TASK CARD: Create a card component that displays ongoing activities/tasks with:
- Task name and description
- Status indicator (pending, running, complete, failed)
- Progress bar for long-running tasks
- Thinking/loading animation for AI processing
- Expandable details
- Timestamp started/completed
- Use for: agent tasks, file operations, API calls, builds, etc.
This card should be reusable and appear in a feed or overlay when tasks are running.




16. STREAMING RESPONSES: Display responses incrementally as they arrive from gateway, not as one giant block after completion. Show text appearing word-by-word or chunk-by-chunk. Better UX for long responses.

17. TEXT WRAPPING FIX: Inline code blocks and long text currently render outside the message bubble boundaries (dont wrap). Fix all text to properly wrap within the bubble constraint. Check: code blocks, URLs, long words.

18. FILE PREVIEW CARDS: Enhance file attachment previews to show:
- File size (formatted as KB/MB)
- Author/uploader info if available
- Description/caption field
- Type-specific icons and colors
- Thumbnail preview for images/PDFs
This is part of the future rich card system.

19. LIVE PROGRESS CARD: For multi-agent tasks and long-running operations:
- Show real-time progress updates
- Display sub-task hierarchy (agent → sub-agents)
- Progress percentage or steps completed
- Elapsed time and estimated remaining
- Expandable logs/details
- Cancel/pause buttons where applicable
Reference task 15 (ACTIVITY/TASK CARD) for related work.

20. FEED CONSISTENCY (Telegram vs iOS): Audit formatting differences between Telegram bridge and iOS native:
- Compare markdown rendering
- Check timestamp formats
- Align message bubble styling
- Verify media preview consistency
- Ensure rich component parity
