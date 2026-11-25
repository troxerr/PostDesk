# PostDesk

A Mac app that does the safe parts of growing @AST_Labs on X for you, and leaves the parts X bans to you.

- **Replies.** Paste posts you found on X (or fetch them with the official X API). Claude skips the ones
  not worth answering, scores the rest as leads, and drafts a short reply for each. Edit it, press
  **Reply on X**, and X's own reply box opens with the text filled in. You press Post.
- **Posts.** Pick your git repositories once. **Draft This Week's Posts** reads the last 7 days of commits
  and writes 5 posts that only claim what the commits show. Each post says whether it's ready or what it
  still needs (a number, a clip, a shorter line). **Post on X** opens the composer prefilled.

PostDesk never posts, likes, follows, or sends DMs, and never drives the X website. Those are what get accounts suspended.

## Set up

1. `./build.sh --open` (needs Xcode or the Command Line Tools, Swift 6.2).
2. Settings (Command-Comma) > Keys: your Anthropic API key. Optional: an X API bearer token for Fetch from X.
3. Settings > Sources: add your repositories (StreamSpike, chat-clip, ...), and adjust keywords and searches.
4. Settings > Writing: pick a tone (friendly, direct, technical, playful), add your own rules, and set how many posts a week.
   Settings > Appearance: light, dark or automatic, and the accent color.

`build.sh` installs to /Applications/PostDesk.app.

## Shortcuts

| Action | Keys |
| --- | --- |
| Paste Posts | Command-Shift-V |
| Fetch Posts from X | Command-Shift-F |
| Draft Replies | Command-R |
| Draft This Week's Posts | Command-Shift-D |
| Open on X | Command-O |
| Redraft or Rewrite | Command-Shift-R |
| Copy Draft | Command-Shift-C |
| Mark as Posted | Command-Return |
| Dismiss | Command-Delete |
| Show Posted and Dismissed | Command-Option-D |
| Replies, Posts | Command-1, Command-2 |

## Cost

One Claude call per on-topic post (about a cent or two on `claude-opus-5-5` at low effort), and one call per week of posts.

## Self-test

`APP_STORE=/tmp/postdesk-self.json /Applications/PostDesk.app/Contents/MacOS/PostDesk --selftest`
drafts replies to four sample posts and writes posts from your repositories with your real key and
settings, prints them as Markdown, and exits 0 when every check passed. Nothing is posted.
