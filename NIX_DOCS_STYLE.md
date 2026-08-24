# Documentation Style

Documentation should be current, readable, and useful to the person trying to
understand or use the configuration.

## Voice and Scope

- Start each document with its purpose and intended audience.
- The root README may use a personal voice and explain the project's motivation.
- Reference and operational documents should stay direct and task-focused, with a friendly tone where appropriate.
- Keep user-relevant trade-offs, limitations, installation constraints, and operational rationale in the repository.
- Keep private diary-style history and abandoned alternatives elsewhere.
- Prefer a concise explanation over unexplained shorthand, but remove stale context instead of adding caveats around it.

## Structure

- Use one clear H1 title followed by logical H2/H3 sections.
- Put the most common path first, then alternatives, exceptions, and recovery procedures.
- Keep one authoritative location for each option, default, or complete list.
- Explanatory prose may repeat a concept when it adds rationale, limitations, procedure, or an example; do not repeat the same reference data without adding value.
- Use tables for compact option/default overviews and prose for behavior, trade-offs, and decisions.
- Link to an authoritative related document instead of copying a complete procedure.

## Examples and Commands

- Use fenced blocks for commands and configuration.
- Make configuration examples complete enough to copy without guessing their parent namespace.
- Prefer nested Nix attributes for related settings:

```nix
features = {
  desktop = {
    wm = "kde";
  };
};
```

- Use synthetic hostnames, usernames, paths, and timestamps in general documentation.
- Mark commands that are destructive, privileged, irreversible, or create plaintext secrets.
- Keep examples aligned with the current module schemas and defaults.

## Technical Detail

- Explain user-visible behavior and non-obvious implementation constraints.
- Distinguish system configuration, Home-Manager configuration, session-specific behavior, and operational policy.
- Document security limitations honestly; do not describe a mitigation as eliminating a threat it only reduces.
- For stateful systems such as Impermanence, Btrfs snapshots, SOPS, and network mounts, explain what survives, what is restored, and what can be lost.

## Markdown

- Use ASCII for commands, paths, identifiers, option names, and machine-readable examples.
- Unicode is acceptable in prose, diagrams, UI labels, and deliberately personal README content.
- Use consistent punctuation and terminology across documents.
- Avoid vague headings such as “Important” or “How it works” unless the section makes the scope explicit.

## Validation

This guide is partly normative and partly editorial. CI currently checks Nix
formatting, Markdown formatting with Prettier, Markdown structure with
markdownlint, statix, deadnix, shellcheck where configured, selected Nix syntax
conventions, and the presence of purpose comments on evaluated modules. It does
not judge documentation quality, architecture, or whether a description is
accurate. Those remain review responsibilities.
