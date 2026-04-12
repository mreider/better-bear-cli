import type { Tool } from "@modelcontextprotocol/sdk/types.js";

export interface ToolHandler {
  tool: Tool;
  buildArgs: (input: Record<string, unknown>) => string[];
  usesStdin?: (input: Record<string, unknown>) => string | null;
}

export const tools: Record<string, ToolHandler> = {
  bear_list_notes: {
    tool: {
      name: "bear_list_notes",
      description:
        "List Bear notes with optional tag filtering. Returns an array of notes with IDs, titles, tags, pin status, and modification dates. Notes with 'locked: true' are private/encrypted in Bear and their body content is not searchable — if a search returns no results, check whether the relevant note is locked. Use bear_get_note to read the full content of a specific note.",
      inputSchema: {
        type: "object" as const,
        properties: {
          tag: {
            type: "string",
            description: "Filter notes by tag (partial match)",
          },
          include_archived: {
            type: "boolean",
            description: "Include archived notes in results",
          },
          include_trashed: {
            type: "boolean",
            description: "Include trashed notes in results",
          },
          limit: {
            type: "number",
            description:
              "Maximum number of notes to return (default 30)",
          },
        },
      },
    },
    buildArgs: (input) => {
      const args = ["ls", "--json"];
      if (input.tag) args.push("--tag", String(input.tag));
      if (input.include_archived) args.push("--archived");
      if (input.include_trashed) args.push("--trashed");
      if (input.limit) args.push("--limit", String(input.limit));
      return args;
    },
  },

  bear_get_note: {
    tool: {
      name: "bear_get_note",
      description:
        "Get a single Bear note's full content and metadata by ID. Returns the note title, tags, full markdown text, and dates. If the note is locked/private, 'locked: true' will be included in the response. Use the 'raw' option to get just the markdown without metadata.",
      inputSchema: {
        type: "object" as const,
        properties: {
          id: {
            type: "string",
            description: "Note ID (uniqueIdentifier)",
          },
          raw: {
            type: "boolean",
            description: "Return only the raw markdown content",
          },
        },
        required: ["id"],
      },
    },
    buildArgs: (input) => {
      const args = ["get", String(input.id), "--json"];
      if (input.raw) args.push("--raw");
      return args;
    },
  },

  bear_search: {
    tool: {
      name: "bear_search",
      description:
        "Full-text search across Bear note titles, tags, and body content. Returns matching notes ranked by relevance (title matches first, then tag, then body). Body matches include a text snippet with surrounding context. Locked/private notes will match by title but may not match body searches — results include 'locked: true' for these notes. If you can't find content you expect, try listing notes to check if the relevant note is locked.",
      inputSchema: {
        type: "object" as const,
        properties: {
          query: {
            type: "string",
            description: "Search query text",
          },
          limit: {
            type: "number",
            description: "Maximum number of results (default 20)",
          },
          since: {
            type: "string",
            description:
              "Only notes modified after this date (YYYY-MM-DD, or: today, yesterday, last-week, last-month)",
          },
          before: {
            type: "string",
            description:
              "Only notes modified before this date (YYYY-MM-DD)",
          },
        },
        required: ["query"],
      },
    },
    buildArgs: (input) => {
      const args = ["search", String(input.query), "--json"];
      if (input.limit) args.push("--limit", String(input.limit));
      if (input.since) args.push("--since", String(input.since));
      if (input.before) args.push("--before", String(input.before));
      return args;
    },
  },

  bear_get_tags: {
    tool: {
      name: "bear_get_tags",
      description:
        "Get the full tag hierarchy from Bear. Returns all tags with their note counts and pin status. Useful for understanding how notes are organized.",
      inputSchema: {
        type: "object" as const,
        properties: {},
      },
    },
    buildArgs: () => ["tags", "--json"],
  },

  bear_create_note: {
    tool: {
      name: "bear_create_note",
      description:
        "Create a new Bear note with a title, optional body text, tags, and YAML front matter. Front matter is stored as a collapsed metadata block at the top of the note. Returns the new note's ID.",
      inputSchema: {
        type: "object" as const,
        properties: {
          title: {
            type: "string",
            description: "Note title",
          },
          body: {
            type: "string",
            description: "Note body text (markdown)",
          },
          tags: {
            type: "array",
            items: { type: "string" },
            description: "Tags to assign to the note",
          },
          frontmatter: {
            type: "object",
            description:
              "YAML front matter fields as key-value pairs (e.g. {status: 'draft', project: 'alpha'})",
            additionalProperties: { type: "string" },
          },
        },
        required: ["title"],
      },
    },
    buildArgs: (input) => {
      const args = ["create", String(input.title), "--json"];
      if (input.body) args.push("--body", String(input.body));
      if (Array.isArray(input.tags) && input.tags.length > 0) {
        args.push("--tags", input.tags.join(","));
      }
      if (input.frontmatter && typeof input.frontmatter === "object") {
        const fm = input.frontmatter as Record<string, string>;
        args.push(
          "--fm",
          ...Object.entries(fm).map(([k, v]) => `${k}=${v}`),
        );
      }
      return args;
    },
  },

  bear_edit_note: {
    tool: {
      name: "bear_edit_note",
      description:
        "Edit an existing Bear note. Provide 'append_text' to add text, 'body' to replace content, or 'set_frontmatter'/'remove_frontmatter' to edit YAML front matter fields. Front matter edits can be combined with each other but not with body/append.",
      inputSchema: {
        type: "object" as const,
        properties: {
          id: {
            type: "string",
            description: "Note ID (uniqueIdentifier)",
          },
          append_text: {
            type: "string",
            description: "Text to append to the end of the note",
          },
          body: {
            type: "string",
            description:
              "New content to replace the entire note body",
          },
          after: {
            type: "string",
            description:
              "Insert appended text after the line containing this text (use with append_text)",
          },
          replace_section: {
            type: "string",
            description:
              "Replace content under this heading (replaces until next heading of same or higher level)",
          },
          section_content: {
            type: "string",
            description:
              "New content for the section (use with replace_section)",
          },
          set_frontmatter: {
            type: "object",
            description:
              "Front matter fields to set or update (key-value pairs)",
            additionalProperties: { type: "string" },
          },
          remove_frontmatter: {
            type: "array",
            items: { type: "string" },
            description: "Front matter field keys to remove",
          },
        },
        required: ["id"],
      },
    },
    buildArgs: (input) => {
      // Front matter editing mode
      const hasFm =
        (input.set_frontmatter &&
          Object.keys(input.set_frontmatter as object).length > 0) ||
        (Array.isArray(input.remove_frontmatter) &&
          input.remove_frontmatter.length > 0);

      if (hasFm && !input.append_text && !input.body) {
        const args = ["edit", String(input.id), "--json"];
        if (input.set_frontmatter && typeof input.set_frontmatter === "object") {
          const fm = input.set_frontmatter as Record<string, string>;
          args.push(
            "--set-fm",
            ...Object.entries(fm).map(([k, v]) => `${k}=${v}`),
          );
        }
        if (Array.isArray(input.remove_frontmatter)) {
          args.push(
            "--remove-fm",
            ...input.remove_frontmatter.map(String),
          );
        }
        return args;
      }

      // Section replacement mode
      if (input.replace_section) {
        const args = ["edit", String(input.id), "--replace-section", String(input.replace_section), "--json"];
        if (input.section_content) args.push("--section-content", String(input.section_content));
        return args;
      }

      if (input.append_text) {
        const args = [
          "edit",
          String(input.id),
          "--append",
          String(input.append_text),
          "--json",
        ];
        if (input.after) args.push("--after", String(input.after));
        return args;
      }
      // --stdin case handled separately via usesStdin
      return ["edit", String(input.id), "--stdin", "--json"];
    },
    usesStdin: (input) => {
      if (input.body && !input.append_text) {
        return String(input.body);
      }
      return null;
    },
  },

  bear_trash_note: {
    tool: {
      name: "bear_trash_note",
      description:
        "Move a Bear note to the trash. This is a soft delete — the note can be recovered from Bear's trash. The note is identified by its ID.",
      inputSchema: {
        type: "object" as const,
        properties: {
          id: {
            type: "string",
            description: "Note ID (uniqueIdentifier)",
          },
        },
        required: ["id"],
      },
    },
    buildArgs: (input) => ["trash", String(input.id), "--json"],
  },

  bear_sync: {
    tool: {
      name: "bear_sync",
      description:
        "Trigger a sync of Bear notes from iCloud. Normally an incremental sync fetching only changes. Use 'full' to force a complete re-sync. Most read operations auto-sync when the cache is stale, so manual sync is rarely needed.",
      inputSchema: {
        type: "object" as const,
        properties: {
          full: {
            type: "boolean",
            description: "Force a full re-sync instead of incremental",
          },
        },
      },
    },
    buildArgs: (input) => {
      const args = ["sync", "--json"];
      if (input.full) args.push("--full");
      return args;
    },
  },

  bear_list_todos: {
    tool: {
      name: "bear_list_todos",
      description:
        "List Bear notes that have incomplete TODO items (markdown checkboxes like '- [ ]'). Returns each note's title, tags, and counts of complete/incomplete items.",
      inputSchema: {
        type: "object" as const,
        properties: {
          limit: {
            type: "number",
            description: "Maximum number of notes to return (default 30)",
          },
        },
      },
    },
    buildArgs: (input) => {
      const args = ["todo", "--json"];
      if (input.limit) args.push("--limit", String(input.limit));
      return args;
    },
  },

  bear_get_todos: {
    tool: {
      name: "bear_get_todos",
      description:
        "Get all TODO items from a specific Bear note. Returns each item's text, completion status, and index number (use the index with bear_toggle_todo to toggle items).",
      inputSchema: {
        type: "object" as const,
        properties: {
          id: {
            type: "string",
            description: "Note ID (uniqueIdentifier)",
          },
        },
        required: ["id"],
      },
    },
    buildArgs: (input) => ["todo", String(input.id), "--json"],
  },

  bear_toggle_todo: {
    tool: {
      name: "bear_toggle_todo",
      description:
        "Toggle a specific TODO item in a Bear note between complete and incomplete. The item_index is 1-based — use bear_get_todos first to see the list with index numbers.",
      inputSchema: {
        type: "object" as const,
        properties: {
          id: {
            type: "string",
            description: "Note ID (uniqueIdentifier)",
          },
          item_index: {
            type: "number",
            description: "1-based index of the TODO item to toggle",
          },
        },
        required: ["id", "item_index"],
      },
    },
    buildArgs: (input) => [
      "todo",
      String(input.id),
      "--toggle",
      String(input.item_index),
      "--json",
    ],
  },

  bear_attach_file: {
    tool: {
      name: "bear_attach_file",
      description:
        "Attach a file or image to an existing Bear note. The file is uploaded to iCloud and embedded in the note's markdown. Supports common image formats (jpg, png, gif, webp, heic) and other file types (pdf, zip, etc.). By default the attachment is appended to the end. Use 'after' or 'before' to place it relative to text in the note, or 'prepend' to put it right after the title.",
      inputSchema: {
        type: "object" as const,
        properties: {
          id: {
            type: "string",
            description: "Note ID (uniqueIdentifier)",
          },
          file_path: {
            type: "string",
            description:
              "Absolute path to the file to attach",
          },
          after: {
            type: "string",
            description:
              "Insert after the line containing this text",
          },
          before: {
            type: "string",
            description:
              "Insert before the line containing this text",
          },
          prepend: {
            type: "boolean",
            description:
              "Insert after the title line instead of at the end",
          },
        },
        required: ["id", "file_path"],
      },
    },
    buildArgs: (input) => {
      const args = [
        "attach",
        String(input.id),
        String(input.file_path),
        "--json",
      ];
      if (input.after) args.push("--after", String(input.after));
      if (input.before) args.push("--before", String(input.before));
      if (input.prepend) args.push("--prepend");
      return args;
    },
  },

  bear_archive_note: {
    tool: {
      name: "bear_archive_note",
      description:
        "Archive a Bear note. Archived notes are hidden from the main list but not deleted. Use 'undo' to unarchive.",
      inputSchema: {
        type: "object" as const,
        properties: {
          id: {
            type: "string",
            description: "Note ID (uniqueIdentifier)",
          },
          undo: {
            type: "boolean",
            description: "Unarchive the note instead of archiving",
          },
        },
        required: ["id"],
      },
    },
    buildArgs: (input) => {
      const args = ["archive", String(input.id), "--json"];
      if (input.undo) args.push("--undo");
      return args;
    },
  },

  bear_add_tag: {
    tool: {
      name: "bear_add_tag",
      description:
        "Add a tag to an existing Bear note. The tag is inserted into the note's markdown.",
      inputSchema: {
        type: "object" as const,
        properties: {
          id: {
            type: "string",
            description: "Note ID (uniqueIdentifier)",
          },
          tag: {
            type: "string",
            description: "Tag to add (without #)",
          },
        },
        required: ["id", "tag"],
      },
    },
    buildArgs: (input) => [
      "tag",
      "add",
      String(input.id),
      String(input.tag),
      "--json",
    ],
  },

  bear_remove_tag: {
    tool: {
      name: "bear_remove_tag",
      description:
        "Remove a tag from a specific Bear note.",
      inputSchema: {
        type: "object" as const,
        properties: {
          id: {
            type: "string",
            description: "Note ID (uniqueIdentifier)",
          },
          tag: {
            type: "string",
            description: "Tag to remove (without #)",
          },
        },
        required: ["id", "tag"],
      },
    },
    buildArgs: (input) => [
      "tag",
      "remove",
      String(input.id),
      String(input.tag),
      "--json",
    ],
  },

  bear_rename_tag: {
    tool: {
      name: "bear_rename_tag",
      description:
        "Rename a tag across all Bear notes. Every note containing the old tag will be updated.",
      inputSchema: {
        type: "object" as const,
        properties: {
          old_name: {
            type: "string",
            description: "Current tag name (without #)",
          },
          new_name: {
            type: "string",
            description: "New tag name (without #)",
          },
        },
        required: ["old_name", "new_name"],
      },
    },
    buildArgs: (input) => [
      "tag",
      "rename",
      String(input.old_name),
      String(input.new_name),
      "--json",
    ],
  },

  bear_delete_tag: {
    tool: {
      name: "bear_delete_tag",
      description:
        "Delete a tag from all Bear notes. The tag text is removed but notes are preserved.",
      inputSchema: {
        type: "object" as const,
        properties: {
          tag: {
            type: "string",
            description: "Tag to delete (without #)",
          },
        },
        required: ["tag"],
      },
    },
    buildArgs: (input) => [
      "tag",
      "delete",
      String(input.tag),
      "--json",
    ],
  },

  bear_find_untagged: {
    tool: {
      name: "bear_find_untagged",
      description:
        "List Bear notes that have no tags assigned.",
      inputSchema: {
        type: "object" as const,
        properties: {
          limit: {
            type: "number",
            description: "Maximum number of notes to return (default 30)",
          },
        },
      },
    },
    buildArgs: (input) => {
      const args = ["ls", "--untagged", "--json"];
      if (input.limit) args.push("--limit", String(input.limit));
      return args;
    },
  },

  bear_health_check: {
    tool: {
      name: "bear_health_check",
      description:
        "Run a health check on the Bear notes library. Reports duplicate titles, empty notes, notes stuck in trash, sync conflicts, orphaned tags, untagged notes, and oversized notes. Use this to identify cleanup opportunities or diagnose sync issues.",
      inputSchema: {
        type: "object" as const,
        properties: {},
      },
    },
    buildArgs: () => ["health", "--json"],
  },
};
