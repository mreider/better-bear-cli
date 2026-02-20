# better-bear-cli

A CLI for [Bear](https://bear.app) notes that talks directly to CloudKit. No SQLite hacking, no x-callback-url.

## Why

Bear's x-callback-url API is awkward for programmatic use and direct SQLite access risks database corruption. As markdown notes become central to LLM workflows, Bear needs a real programmatic interface. [More context here.](https://www.reddit.com/r/bearapp/comments/1r1ff7e/comment/o5oa41z/)

This CLI uses the same CloudKit REST API that [Bear Web](https://web.bear.app) uses. It reads and writes safely through Apple's servers, the same way your devices sync.

## Install

### Download the binary

Grab the latest release from [GitHub Releases](https://github.com/mreider/better-bear-cli/releases/latest).

```
curl -L https://github.com/mreider/better-bear-cli/releases/latest/download/bcli-macos-universal.tar.gz -o bcli.tar.gz
tar xzf bcli.tar.gz
mv bcli ~/.local/bin/bcli
rm bcli.tar.gz
```

The binary is universal (arm64 + x86_64). Requires macOS 13+.

### Build from source

Requires Swift 5.9+.

```
git clone https://github.com/mreider/better-bear-cli.git
cd better-bear-cli
swift build -c release
cp .build/release/bcli ~/.local/bin/bcli
```

## Auth

```
bcli auth
```

Opens your browser for Apple Sign-In via CloudKit JS. The token is saved to `~/.config/bear-cli/auth.json`. You can also pass a token directly with `bcli auth --token '<token>'`.

## Commands

```
bcli ls                              List notes
bcli ls --all --tag work --json      Filter by tag, JSON output
bcli get <id>                        View a note with metadata
bcli get <id> --raw                  Just the markdown
bcli tags                            Tag tree
bcli sync                            Sync notes to local cache
bcli sync --full                     Force full re-sync
bcli search "query"                  Full-text search (title, tags, body)
bcli search "query" --no-sync        Search without syncing first
bcli create "Title" -b "Body"        Create a note
bcli create "Title" -t "t1,t2"       Create with tags
bcli create "Title" --stdin          Pipe content from stdin
bcli edit <id> --append "text"       Append to a note
bcli edit <id> --editor              Open in $EDITOR
bcli edit <id> --stdin               Replace content from stdin
bcli trash <id>                      Move to trash
bcli export ./dir                    Export all notes as markdown
bcli export ./dir --frontmatter      Include YAML metadata
bcli export ./dir --tag work         Export only matching tag
```

## How it works

Bear Web is a CloudKit JS client that talks to `api.apple-cloudkit.com`. There is no Shiny Frog backend. Notes live in your iCloud private database under the container `iCloud.net.shinyfrog.bear` in a custom zone called `Notes`.

This CLI makes the same REST API calls Bear Web makes: `records/query`, `records/lookup`, `records/modify`, and `assets/upload`. Authentication uses the same iCloud web auth token flow.

Three record types: `SFNote` (notes), `SFNoteTag` (tags), `SFNoteBackLink` (wiki links between notes).

## Safe to use with Bear open

The CLI does not touch Bear's local SQLite database. It talks to CloudKit's cloud servers. Running the CLI while Bear is open is no different from having Bear open on two devices at once. CloudKit handles concurrency with optimistic locking via `recordChangeTag`.
