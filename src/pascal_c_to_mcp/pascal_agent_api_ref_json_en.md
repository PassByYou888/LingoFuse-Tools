> *English translation of [pascal_agent_api_ref_json.md](pascal_agent_api_ref_json.md).*

Below is a **complete and self-contained** JSON example that covers both the **full tool-list structure returned by `agent_main`** and the **single-tool structure used by `register_agent` when registering**. Both are combined in one complete example, followed by a field-by-field explanation.

---

### Complete JSON example (containing the full definition of two tools)

```json
{
  "tools": [
    {
      "name": "add",
      "description": "Computes the sum of two integers and returns the result of a + b",
      "target_app": "my_calculator",
      "target_api": "add",
      "parameters": {
        "type": "object",
        "properties": {
          "a": {
            "type": "integer",
            "description": "The first addend; must be an integer"
          },
          "b": {
            "type": "integer",
            "description": "The second addend; must be an integer"
          }
        },
        "required": [
          "a",
          "b"
        ]
      }
    },
    {
      "name": "echo",
      "description": "Echoes the input message, with optional uppercase conversion",
      "target_app": "my_echo_service",
      "target_api": "echo",
      "parameters": {
        "type": "object",
        "properties": {
          "message": {
            "type": "string",
            "description": "The message content to echo"
          },
          "uppercase": {
            "type": "boolean",
            "description": "Whether to convert the message to uppercase before returning it",
            "default": false
          }
        },
        "required": [
          "message"
        ]
      }
    }
  ]
}
```

---

### Field-by-field explanation

| Path | Type | Required | Description |
|------|------|----------|-------------|
| **`tools`** | `array` | ✅ Required | Top-level field: an array containing all registered tools. Each array element is a tool definition object. |
| **`tools[]`** | `object` | ✅ Required | A single tool definition object. |
| `tools[].name` | `string` | ✅ Required | **Tool name**. The MCP client calls the tool by this name (e.g. the `name` in `tools/call`). It must be unique within the whole tool list. |
| `tools[].description` | `string` | ✅ Required | **Tool description**. The AI model decides whether to call the tool based on this description, so it should clearly state the function and the usage scenario. |
| `tools[].target_app` | `string` | ✅ Required | **LingoFuse target application name**. Used for `LF_Call` routing; it must exactly match the first parameter (`APP_NAME`) of `LF.TAppHandle.Create` in the backend Pascal service. |
| `tools[].target_api` | `string` | ✅ Required | **LingoFuse target API name**. Used for `LF_Call` routing; it must exactly match the API name passed to `App.RegisterCall` in the backend Pascal service. |
| `tools[].parameters` | `object` | ✅ Required | **Parameter definition (a subset of JSON Schema)**. Describes which parameters the tool accepts and their types. |
| `parameters.type` | `string` | ✅ Required | Must be fixed to **`"object"`**, meaning the parameters are a JSON object. |
| `parameters.properties` | `object` | ✅ Required | **Parameter property definitions**. Keys are parameter names, values are the Schema definition of that parameter. |
| `properties.<key>.type` | `string` | ✅ Required | The parameter's data type. Supported: `string`, `integer`, `number`, `boolean`, `array`, `object`. |
| `properties.<key>.description` | `string` | ❌ Strongly recommended | Explanation text for the parameter, helping the AI understand its meaning and usage. |
| `properties.<key>.default` | any | ❌ Optional | Default value of the parameter. Used when the parameter is not passed at call time. |
| `parameters.required` | `array` | ❌ Optional | **List of required parameters**. Array elements are keys from `properties`. Parameters not listed here are all optional. |

---

### Additional notes

- **When registering via `register_agent`**: the request body should be a **single tool object** (that is, without the outer `"tools": [...]` wrapper), e.g. `{"name":"add","description":"...",...}`.
- **When returning from `agent_main`**: the full `{"tools": [...]}` structure must be used, because the MCP server expects an array list.
- **Consistency of `target_app` and `target_api`**: the beacon service (`pascal_agent_service`) calls `LF_CheckApiEx` inside `agent_main` to verify that the APIs corresponding to these two fields are actually available, so they must match the started backend service exactly.
