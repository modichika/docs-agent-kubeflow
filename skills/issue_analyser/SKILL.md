# Skill: Kubeflow Docs-Agent Issue Analyzer (Demo Mode)

## Description
Fetch live open issues from the official `kubeflow/docs-agent` repository, perform a deep local Agentic RAG v2 architectural analysis, and output a highly polished, ready-to-copy markdown report directly to your local terminal sidebar. (Safe / Read-Only Mode).

## Prerequisites
- The user must be authenticated via the GitHub CLI (`gh auth login`).
- Internet access is required to pull active issues from the official upstream repository.

## Execution Sequence
1. Execute `gh issue list --repo kubeflow/docs-agent --limit 10 --json number,title,body` to pull the latest 10 open issues from the official Kubeflow organization.
2. Present the summary list of live tickets in the terminal and ask: "Which upstream issue number would you like to analyze for the maintainer demo?"
3. Once selected, download the complete payload using: `gh issue view <NUMBER> --repo kubeflow/docs-agent`
4. Run the issue payload through the core evaluation rubric below, cross-referencing your local codebase architecture context.
5. Identify the appropriate architectural components and status lifecycle labels using the Automated Labeling Engine rules.
6. Print the completed, beautifully formatted markdown analysis card directly to the IDE console stream.
7. End the execution path by outputting a clean code block containing the exact command the maintainer could use to post it:
   ```text
   👉 Copy the report below to show the maintainers, or run this manually to post:
   gh issue comment <NUMBER> --repo kubeflow/docs-agent --body "<REPORT_CONTENT>"
   ```

---

## Evaluation Rubric & Calibration Instructions

You are an expert Lead Maintainer for the Agentic RAG v2 architecture (`kubeflow/docs-agent`). 

Analyze the quality of the incoming issue across these explicit layers: Kagent Agent, FastMCP Tools, TEI Embeddings, Milvus Vector DB, KServe Qwen Inference, Ingestion Pipelines, Infrastructure, or Public Edge Guardrails.

Compare the incoming issue detail density directly against core engineering standards. 

---

## Automated Labeling Engine

Analyze the issue text to isolate the target layer and assign the single most accurate component label and status lifecycle label from these official repo categories:

### ⚙️ Component Categories (Choose One)
- `component/kagent`: Core AI agent orchestration logic, memory handling, or prompting cycles.
- `component/mcp`: FastMCP custom tools, server integrations, or protocol layer messaging.
- `component/vector-db`: Milvus storage collections, schema adjustments, indices, or TEI embeddings matching.
- `component/inference`: KServe Qwen model deployments, token streams, or LLM serving endpoints.
- `component/pipelines`: Data ingestion runs, content scrapers, chunking strategies, or parsing scripts.
- `component/security`: Edge guardrails, input sanitization filtering, PII masks, or jailbreak defenses.
- `component/infra`: Helm charts, K8s manifests, service meshes, or ingress bindings.

### 🚦 Status & Lifecycles (Choose One)
- `lifecycle/needs-information`: If the quality report marks **Ready for Pickup** as **NO**.
- `status/triaged`: If the quality report marks **Ready for Pickup** as **YES**.

---

## Output Formatting Rules

Generate the report string strictly following this format structure. Do not use full-length paragraphs, markdown code wraps, introductory text, or implementation timeframe windows:

### 📊 Scope & Component BoundariesIf the targeted RAG layer and technical task boundaries are clear or ambiguous>
- <If the issue isolates specific component files or manifests correctly>

### 📝 Context & Reproduction
- <Evaluate if steps, error logs, or expected behaviors are provided against repo standards>
- <Check if pipeline states or architecture dependencies are properly documented>

### ⚡ Complexity
- **Difficulty Tier:** <State difficulty tier: LOW, MEDIUM, or HIGH, calibrated against this exact rubric:>
  * *LOW*: Single-file fixes, shallow tweaks, or documentation updates.
  * *MEDIUM*: Moderate depth affecting internal logic patterns or specific layer wrappers.
  * *HIGH*: Deep architectural breadth spanning multiple system components simultaneously (e.g., cross-layer changes across MCP, Milvus, and Edge Guardrails).
- **Architecture Breadth & Depth:** <Break down the breadth (cross-layer impact) and depth of the proposed change>

### 🎯 Overall Issue Quality Verdict
- **Ready for Pickup:** <State definitively YES or NO if this is ready for immediate developer pickup>
- **Key Recommendation:** <Outline the single most impactful recommendation to improve the issue quality>
- **Proposed Labels:** <List the identified component and lifecycle status labels to apply>
