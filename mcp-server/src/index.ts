#!/usr/bin/env node

import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
} from "@modelcontextprotocol/sdk/types.js";
import {
  execBcliWithReauth,
  execBcliWithStdinAndReauth,
  BcliError,
} from "./bcli.js";
import { tools } from "./tools.js";

const server = new Server(
  {
    name: "better-bear-mcp",
    version: "0.1.0",
  },
  {
    capabilities: {
      tools: {},
    },
  },
);

server.setRequestHandler(ListToolsRequestSchema, async () => ({
  tools: Object.values(tools).map((t) => t.tool),
}));

server.setRequestHandler(CallToolRequestSchema, async (request) => {
  const { name, arguments: input } = request.params;
  const handler = tools[name];

  if (!handler) {
    return {
      content: [{ type: "text", text: `Unknown tool: ${name}` }],
      isError: true,
    };
  }

  const params = (input ?? {}) as Record<string, unknown>;

  // Validate bear_edit_note: exactly one of append_text or body
  if (name === "bear_edit_note") {
    const hasAppend = params.append_text !== undefined;
    const hasBody = params.body !== undefined;
    if (!hasAppend && !hasBody) {
      return {
        content: [
          {
            type: "text",
            text: "Either 'append_text' or 'body' must be provided.",
          },
        ],
        isError: true,
      };
    }
    if (hasAppend && hasBody) {
      return {
        content: [
          {
            type: "text",
            text: "Provide either 'append_text' or 'body', not both.",
          },
        ],
        isError: true,
      };
    }
  }

  try {
    const args = handler.buildArgs(params);
    let result: { stdout: string; stderr: string };

    // Check if this tool needs stdin piping
    const stdinData = handler.usesStdin?.(params) ?? null;
    if (stdinData !== null) {
      result = await execBcliWithStdinAndReauth(args, stdinData);
    } else {
      result = await execBcliWithReauth(args);
    }

    // Parse JSON output from bcli
    const stdout = result.stdout.trim();
    if (!stdout) {
      return {
        content: [{ type: "text", text: "Command completed successfully." }],
      };
    }

    // Validate it's JSON and pretty-print
    try {
      const parsed = JSON.parse(stdout);
      return {
        content: [
          { type: "text", text: JSON.stringify(parsed, null, 2) },
        ],
      };
    } catch {
      // If bcli returned non-JSON, pass it through
      return {
        content: [{ type: "text", text: stdout }],
      };
    }
  } catch (error) {
    const message =
      error instanceof BcliError ? error.message : String(error);
    return {
      content: [{ type: "text", text: message }],
      isError: true,
    };
  }
});

async function main() {
  const transport = new StdioServerTransport();
  await server.connect(transport);
}

main().catch((error) => {
  console.error("Fatal error:", error);
  process.exit(1);
});
