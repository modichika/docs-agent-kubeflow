set -e
gh extension install github/gh-models --force || true

ARCH_FILE=$1
echo "Using model: $TARGET_MODEL"

if [ -f "$ARCH_FILE" ]; then
  ARCH_CONTENT=$(cat "$ARCH_FILE")
else
  ARCH_CONTENT="Architecture documentation not found at $ARCH_FILE."
fi

read -r -d '' SYSTEM_INSTRUCTIONS << "EOF" || true
You are an expert open-source maintainer for Kubeflow docs-agent.

Analyze the quality of the incoming issue based on Scope, Context, Guidance, and Complexity.

The following is the official system architecture. You MUST use this to evaluate the incoming issue for architectural alignment, component impact, and technical feasibility.

[BEGIN ARCHITECTURE]
${ARCH_CONTENT}
[END ARCHITECTURE]             

Compare the incoming issue detail density directly against the relevant blueprint standard above.
Respond strictly following this format structure without other markdown wraps:

- Each section MUST contain exactly 2 to 3 short, bullet fragments. 
- Do NOT write full-length paragraphs or introductory text. Keep it highly concise for quick scanning.
- Do NOT include any time frame or implementation window estimations.

### Architectural Alignment: Does this request violate the patterns in arch.md?

### 📊 Scope
- <If the technical task boundaries are clear or ambiguous>
- <If the issue isolates specific components, files, or packages correctly>

### 📝 Context & Guidance
<Evaluate if steps, expected behavior, or links are provided against repo standards>

### ⚡ Complexity
- <State difficulty tier: Low, Medium, or High, calibrated against this exact rubric:
  * LOW: Task is isolated to single-file fixes, shallow tweaks, or documentation updates.
  * MEDIUM: Task has moderate architectural depth, affecting internal logic patterns or specific layer wrappers.
  * HIGH: Task has deep architectural depth or high breadth, spanning multiple system components simultaneously (e.g., changes across the SDK, backend, frontend, or infrastructure).>
- <Break down the breadth (cross-layer impact) and depth (internal system complexity) of the proposed change>


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

echo "analysis<<EOF" >> $GITHUB_OUTPUT
echo "$ANALYSIS_REPORT" >> $GITHUB_OUTPUT
echo "EOF" >> $GITHUB_OUTPUT

          
echo "DEBUG: The raw analysis sent to output was:"
echo "$ANALYSIS_REPORT"

echo "--- DEBUG: ARCH_CONTENT being sent to AI ---"
echo "$ARCH_CONTENT"
echo "----------------------------------------------"
