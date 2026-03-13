# T-IA Copilot : GenAI Bridge for Siemens PLCs

**Submission for the GenAI Zürich Hackathon 2026 — Siemens Challenge**

> **Tagline:** Bridging LLMs and Siemens TIA Portal safely. Generates deterministic PLC logic (SCL/ISA-88) from natural language using Sovereign GenAI models.

## About This Repository
This repository contains the **Generative AI bridging components** built specifically during the hackathon.

> **Note:** The core proprietary engine (the deterministic SimaticML XML builder and the TIA Portal Openness API connector) remains private. This open-source repository demonstrates how we successfully connected Sovereign LLMs to our deterministic industrial backend.

---

## Quick Start — Headless Blueprint

### Prerequisites
- **T-IA Connect** installed ([t-ia-connect.com](https://t-ia-connect.com))
- **Siemens TIA Portal** V17, V18, V19 or V20
- A TIA Portal project file (`.ap17` / `.ap18` / `.ap19` / `.ap20`)

### 1. Launch in Headless Mode
```powershell
# No GUI, no WPF window — just a REST API ready to receive commands
TiaPortalApi.App.exe --headless

# Output:
#   T-IA Connect — Headless Mode
#   API: http://localhost:9000/
#   Swagger: http://localhost:9000/swagger
#   Press Ctrl+C to stop.
```

### 2. Open a TIA Portal Project (silently)
```powershell
curl -X POST http://localhost:9000/api/projects/open `
  -H "X-API-Key: your-key" `
  -H "Content-Type: application/json" `
  -d '{ "projectPath": "C:\\Projects\\WaterPlant.ap20" }'
```

### 3. Generate a PLC Block from Natural Language
```powershell
curl -X POST http://localhost:9000/api/blocks/generate `
  -H "X-API-Key: your-key" `
  -H "Content-Type: application/json" `
  -d '{
    "deviceName": "PLC_1",
    "blockType": "FB",
    "blockName": "FB_WaterPump",
    "description": "Water pump with Start/Stop, thermal fault (TON 5s), Manual/Auto mode",
    "language": "SCL"
  }'
```

### 4. Compile — Done
```powershell
curl -X POST http://localhost:9000/api/blocks/compile `
  -H "X-API-Key: your-key" `
  -H "Content-Type: application/json" `
  -d '{ "deviceName": "PLC_1", "blockName": "FB_WaterPump" }'
```

> No TIA Portal window ever opened. The block is compiled and ready.

### Full Automated Script
See [`examples/Run-Headless-Demo.ps1`](examples/Run-Headless-Demo.ps1) for a complete end-to-end script.

---

## Architecture

```
┌─────────────────┐     ┌──────────────────┐     ┌─────────────────┐
│   AI Agent       │     │  T-IA Connect    │     │  TIA Portal     │
│  (Claude, etc.)  │────▶│  REST API        │────▶│  Openness API   │
│                  │ MCP │  + Deterministic │     │  (headless)     │
│  "Create a pump  │ or  │    XML Engine    │     │                 │
│   sequence..."   │ HTTP│                  │     │  ┌───────────┐  │
└─────────────────┘     └──────────────────┘     │  │ FB_Pump   │  │
                                                  │  │ compiled  │  │
                                                  │  └───────────┘  │
                                                  └─────────────────┘
```

---

## Key Hackathon Components

### 1. Sovereign AI Integration (`src/OpenAiProvider.cs`)
- Custom C# provider connecting to European-hosted AI models (OVHcloud AI Endpoints)
- Ensures sensitive PLC logic never leaves the EU
- Tested with `Qwen3-Coder-30B-Instruct` for precise SCL generation

### 2. MCP Bridge E2E Tests (`tests/`)
- Demonstrates headless WPF boot → TIA Portal silent open → MCP `tools/call` execution
- Full lifecycle orchestration without any user interaction

---

## How It Works (The T-IA Copilot Workflow)

| Step | What happens | Who does it |
|------|-------------|-------------|
| 1. **Prompt** | "Generate a pump sequence with a thermal fault" | Engineer or AI Agent |
| 2. **AI Reasoning** | LLM designs the state machine logic (SCL/JSON) | Sovereign LLM (Qwen) |
| 3. **Deterministic Compile** | C# engine builds strict SimaticML XML (no AI hallucination) | T-IA Connect |
| 4. **Deploy** | Block imported + compiled headlessly in TIA Portal | Openness API |

**Result:** Chat prompt → Compiled PLC block in under 30 seconds.

---

## Tech Stack
| Component | Technology |
|-----------|-----------|
| Backend | C# / .NET Framework 4.8 |
| Target | Siemens TIA Portal V17-V20 (Openness API) |
| AI Models | Qwen3-Coder-30B via OVHcloud AI Endpoints |
| Protocol | MCP (Model Context Protocol) by Anthropic |
| API | REST + SignalR (real-time job notifications) |
| Tools | 126 MCP tools for full TIA Portal orchestration |

---

## Links
- **Website:** [t-ia-connect.com](https://t-ia-connect.com)
- **DevPost:** [T-IA Copilot on DevPost](https://devpost.com/software/t-ia-copilot-genai-for-industrial-plcs)
- **Hackathon:** [GenAI Zürich 2026](https://genaizurich2026.devpost.com/)
