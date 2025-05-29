# Markdown Parser

A simple markdown to pdf translator written in the Zig programming language.

## Mission Statement

I often find myself taking notes in markdown. Sometimes these notes are useful
for non-technical users. I wanted to be able to translate markdown into a format
that is consumable via a standalone file that non-technical people could easily
read and wouldn't find concerning to open. I want this file format to be
viewable over preview mechanisms such as Teams, Slack and OneDrive.

### Strategy

Consume blocks into an array of tokens.

Ex:

```md
> hello world
Nice day
```

- Block Quotes
  - Paragraph
    - Text
- Paragraph
  - Text

`[Block quotes, paragraph, TEXT, paragraph, TEXT]`

or:

```md
# Big Title

Some text with bold
```

- Header1
  - Paragraph
    - TEXT
- EmptyLine
- Paragraph
  - Text

`[Header1, paragraph, TEXT, Emptyline, paragraph, TEXT]`
