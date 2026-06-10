# Documentation Style

Documentation must be short, current, and actionable.

## Rules

- Prefer one precise sentence over an explanation block.
- Document decisions and tradeoffs in the vault, not in repo docs.
- Keep repo docs focused on what exists, how to use it, and defaults.
- Do not repeat information already listed in a reference table.
- Use examples only when they prevent ambiguity.
- Avoid vague labels like "important", "advanced", "optional feature", or "how it works" unless the section proves it.
- Remove stale context instead of adding caveats around it.

## Module Comments

- File headers are optional for small modules.
- Use comments for non-obvious intent, invariants, or external constraints.
- Do not comment straightforward assignments.
- Shell scripts need comments only around control flow that is not obvious.

## Markdown Shape

- Start with the purpose.
- Put commands in fenced blocks.
- Keep tables as the source of truth for options and defaults.
- Link to related docs instead of duplicating content.
- Use ASCII unless the file already uses Unicode deliberately.
