# TideBot Functional Plugin Guide

A TideBot plugin is a declarative JSON document. It does not load or execute Dart, JavaScript, shell commands, or Android code. Its executable behavior is limited to three runtime-backed capabilities:

- `skills`: prompt rules injected into enabled bots.
- `mcp_servers`: remote HTTP JSON-RPC tools exposed to the model after permission is granted.
- `ui`: a TideBot-rendered form whose actions call declared MCP tools.

## Install and enable

1. Create a JSON file with `format` equal to `tidebot.plugin/v1`.
2. In TideBot, open My > plugin menu > local import plugin.
3. Open the imported plugin from the plugin list.
4. Grant requested permissions. A plugin cannot access an MCP endpoint until `network` is enabled.
5. Leave the plugin enabled. Skills participate in chat; MCP tools are offered to the model on normal tool-enabled chats; UI opens from the plugin detail page.

Updating an installed plugin preserves its enabled state and previously granted permissions.

## Manifest

```json
{
  "format": "tidebot.plugin/v1",
  "id": "example.weather-helper",
  "name": "Weather Helper",
  "description": "Weather lookup and planning helpers.",
  "version": "0.1.0",
  "permissions": ["network"],
  "skills": [
    {
      "name": "Weather response policy",
      "instructions": "When using weather data, state the location and time window. Do not invent a forecast.",
      "bot_ids": []
    }
  ],
  "mcp_servers": [
    {
      "name": "Weather MCP",
      "url": "https://example.com/mcp",
      "headers": {"Authorization": "Bearer replace-me"}
    }
  ],
  "ui": {
    "title": "Weather lookup",
    "description": "Query the configured weather MCP server.",
    "fields": [
      {"id": "location", "label": "Location", "default": "", "multiline": false}
    ],
    "actions": [
      {"label": "Lookup", "mcp_server": 0, "tool": "weather_lookup"}
    ]
  },
  "readme": "Use a server that implements the transport below."
}
```

`id` must match `^[a-z0-9][a-z0-9._-]{2,63}$`. `bot_ids` is optional; omit it or use an empty list to apply a Skill to every bot.

## MCP transport

TideBot currently supports request/response HTTP JSON-RPC 2.0 endpoints. SSE, stdio, OAuth discovery, resources, prompts, and subscriptions are not implemented.

At chat time TideBot requests tools with:

```json
{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}
```

The endpoint must return a JSON-RPC result containing `tools`. Every tool needs `name`, and may supply `description` and `inputSchema`.

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "result": {
    "tools": [
      {
        "name": "weather_lookup",
        "description": "Returns a forecast for a location.",
        "inputSchema": {
          "type": "object",
          "properties": {"location": {"type": "string"}},
          "required": ["location"]
        }
      }
    ]
  }
}
```

When selected by the chat model or a UI action, TideBot calls:

```json
{
  "jsonrpc": "2.0",
  "id": 2,
  "method": "tools/call",
  "params": {
    "name": "weather_lookup",
    "arguments": {"location": "Shanghai"}
  }
}
```

The result is returned to the chat model as tool output, or displayed as formatted JSON in the plugin UI. Tool names must use only letters, digits, `_`, or `-` and be at most 64 characters.

## Security boundary

- Import performs static manifest risk checks before storage and rejects invalid, unsupported, code-execution, file-access, private-network, or malformed MCP declarations.
- Every import and AI-generated plugin is installed disabled. Enabling requires a health check; MCP plugins require the user to grant `network` first and must successfully answer `tools/list`.
- The scanner is a manifest safety gate and transport boundary, not an antivirus engine or an endpoint reputation service.
- MCP headers are stored in the local plugin manifest. Do not publish secrets in a distributable plugin file.
- TideBot verifies every invocation against the current `tools/list` result; a manifest cannot call undeclared server methods.
- Plugins cannot execute arbitrary code, open arbitrary URLs, access Android permissions, read local files, or create background jobs.

For a production public plugin, host a dedicated MCP proxy and use per-user authorization rather than embedding a shared API token in `headers`.
