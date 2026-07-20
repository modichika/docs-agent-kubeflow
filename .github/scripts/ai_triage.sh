#!/usr/bin/env bash
set -e
gh extension install github/gh-models --force || true

echo "Using model: $TARGET_MODEL"

read -r -d '' SYSTEM_INSTRUCTIONS << 'EOF' || true
You are an expert Lead Maintainer for the Agentic RAG v2 architecture (`kubeflow/docs-agent`).

Analyze the quality of the incoming issue based on Component Scope, Context, Guidance, and Complexity across layers: Kagent Agent, FastMCP Tools, TEI Embeddings, Milvus Vector DB, KServe Qwen Inference, Ingestion Pipelines, Infrastructure, or Public Edge Guardrails.

Respond strictly following this format structure without other markdown wraps:

- Each section MUST contain exactly 2 to 3 short, bullet fragments. 
- Do NOT write full-length paragraphs or introductory text. Keep it highly concise for quick scanning.
- Do NOT include any time frame or implementation window estimations.

### 📊 Scope & Component Boundaries
- <If the targeted RAG layer and technical task boundaries are clear or ambiguous>
- <If the issue isolates specific component files or manifests correctly>

### 📝 Context & Reproduction
- <Evaluate if steps, error logs, or expected behaviors are provided against repo standards>
- <Check if pipeline states or architecture dependencies are properly documented>

### ⚡ Complexity
- <State difficulty tier: Low, Medium, or High, calibrated against this exact rubric:
  * LOW: Single-file fixes, shallow tweaks, or documentation updates.
  * MEDIUM: Moderate depth affecting internal logic patterns or specific layer wrappers.
  * HIGH: Deep architectural breadth spanning multiple system components simultaneously (e.g., cross-layer changes across MCP, Milvus, and Edge Guardrails).>
- <Break down the breadth (cross-layer impact) and depth of the proposed change>

### 🎯 Overall Issue Quality Verdict
- <State definitively if this is ready for immediate developer pickup>
- <Outline the single most impactful recommendation to improve the issue quality>
EOF

USER_PROMPT="Title: ${TITLE} | Body: ${RAW_BODY}"

if RESULT=$(gh models run "$TARGET_MODEL" --system-prompt "$SYSTEM_INSTRUCTIONS" "$USER_PROMPT" 2>&1); then
    echo "✅ AI model executed successfully."
    ANALYSIS_REPORT="$RESULT"
else
    echo "⚠️ CRITICAL: AI Model execution failed or preview tier limit hit."
    echo "Error details: $RESULT"
            
    read -r -d '' ANALYSIS_REPORT << 'EOF' || true
    ### ⚠️ Automated Triage Skipped
    The issue body text or environment logs exceeded processing size boundaries for this triage pass.
EOF
fi

{
  echo "analysis<<EOF"
  echo "$ANALYSIS_REPORT"
  echo "EOF"
} >> "$GITHUB_OUTPUT"

echo "DEBUG: The raw analysis sent to output was:"
echo "$ANALYSIS_REPORT"