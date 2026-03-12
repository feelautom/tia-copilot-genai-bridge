# T-IA Copilot : GenAI Bridge for Siemens PLCs

**Submission for the GenAI Zürich Hackathon 2026 - Siemens Challenge**

## About This Repository
This repository contains the newly developed **Generative AI bridging components** built specifically during the hackathon. 

> **Note:** The core proprietary engine (the deterministic SimaticML XML builder and the TIA Portal Openness API connector) remains private. This open-source repository demonstrates how we successfully connected Sovereign LLMs (via an OpenAI-compatible proxy) to our deterministic industrial backend.

## Key Hackathon Features

1. **Sovereign AI Integration (`OpenAiProvider.cs`)**
   - We built a custom C# provider to securely connect our industrial backend to European-hosted AI models (OVHcloud AI Endpoints / Kepler).
   - This ensures that sensitive PLC logic (P&ID specs, ISA-88 sequences) never leaves the European Union and complies with strict industrial data privacy standards.
   - Tested successfully with `Qwen3-Coder-30B-Instruct` for precise SCL syntax generation.

2. **Model Context Protocol (MCP) Bridge Orchestration**
   - We developed robust E2E test scripts (see `tests/`) demonstrating how our Headless WPF application boots TIA Portal silently, authenticates the MCP connection via API keys, and executes `tools/call` seamlessly.

## How it works (The T-IA Copilot Workflow)
1. **Prompt:** "Generate a pump sequence with a thermal fault."
2. **AI Reasoning:** The Sovereign LLM generates the pure SCL logic.
3. **Validation:** Our private C# engine parses the logic and mathematically constructs strict SimaticML XML.
4. **Execution:** The code is deployed headlessly into Siemens TIA Portal V19/V20.

## Tech Stack
*   **Language:** C# / .NET 4.8
*   **Target:** Siemens TIA Portal Openness API
*   **AI Models:** Qwen-Coder, DeepSeek-R1
*   **Protocol:** Model Context Protocol (MCP) by Anthropic
