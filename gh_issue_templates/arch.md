
# Agentic RAG v2 Architecture Deep Dive

**Working repo:** `kubeflow/docs-agent`  
**Authors:** Rohit Kumar, Santhosh Toorpu  
**Related meeting doc:** Kubeflow Agentic RAG Community Call  
**Status:** Draft for community review

---

## 1. Executive Summary
Agentic RAG v2 is the Kubeflow-native documentation and code assistant architecture. The current implementation uses Kagent as the agent control plane, a FastMCP server as the tool layer, TEI for embeddings, Milvus for vector search, KServe for LLM inference, Kubeflow Pipelines for ingestion, Terraform for platform setup, and GitHub Actions for CI/CD and cluster smoke validation.

The goal is to provide grounded answers from Kubeflow documentation, GitHub issues, and code or YAML manifests while dogfooding Kubeflow infrastructure.

**Status update:** The public edge is now hardened with layered gateway guardrails — Istio-terminated TLS, a 60 req/min global rate limit, CORS locked to the published widget origin, and anonymous session-JWT authentication on a staged rollout. The full edge configuration is packaged as the `gateway-guardrails` Helm chart installed by Terraform, replacing the earlier raw manifests and inline Terraform policies. Current project focus is solidifying this architecture (CI/CD hardening, auth rollout completion, image decoupling, ingestion cadence) before adding new capabilities; see sections 3.8 and 7.5.

---

## 2. Current Runtime Architecture
![Current Runtime Architecture Diagram](/assets/current__runtime_arch.png)
 

User Query Path

Public edge path: web widget (kubeflowdemochatbot.netlify.app) → OCI load balancer → Istio ingress gateway (TLS termination, global rate limit, CORS allow-list, session-JWT validation, 30s route timeout) → kagent-ui → Kagent agent (A2A) → MCP tools + KServe Qwen.
![User Query Path with Gateway Guardrails](/assets/User_Query_Path.png)
 

## 3. Component Breakdown

### 3.1 Kagent Agent Layer
* **Purpose:** 
     * Owns the user-facing agent behavior. 
     * Defines which model and MCP tools the agent can use. 
     * Enforces routing instructions through the system message.
* **Current implementation:**
    * `ModelConfig` points to an OpenAI-compatible in-cluster KServe Qwen endpoint.
    * `RemoteMCPServer` points to the MCP server Service URL.
    * Agent wires three MCP tools: `search_kubeflow_docs`, `search_github_issues`, and `search_kubeflow_code`.
* **Key files:** 
    * `docs-agent-mcp/manifests/kagent/setup.yaml`
    * `docs-agent-mcp/terraform/kagent.tf`

### 3.2 MCP Tool Layer
* **Purpose:** 
  * Provides a standard Model Context Protocol interface for retrieval tools. 
  * Keeps retrieval logic separate from the agent orchestration layer. 
  * Supports IDE or local-agent integration in addition to the Kagent UI path.
* **Current implementation:**
    * FastMCP server runs Streamable HTTP on port 8000.
    * Endpoint path is `/mcp`.
    * The server lazily initializes the Milvus client and requires `MILVUS_PASSWORD` from a Kubernetes Secret.
    * Each tool embeds the query through TEI, searches the configured Milvus collection, and returns Markdown with citations and metadata.

| MCP tool | Milvus collection | Use case |
| :--- | :--- | :--- |
| `search_kubeflow_docs` | `docs_rag` | Documentation concepts, setup, APIs, and how-to questions. |
| `search_github_issues` | `issues_rag` | Bugs, errors, stack traces, issue discussions, and community fixes. |
| `search_kubeflow_code` | `code_rag` | Source code, Kubernetes YAML, resource names, and manifest questions. |

* **Key files:** 
    * `docs-agent-mcp/mcp-server/server.py`
    * `docs-agent-mcp/mcp-server/embeddings_client.py`
    * `docs-agent-mcp/manifests/mcp-server/mcp-server.yaml`

### 3.3 Embedding Layer
**Purpose:**
* Converts incoming queries and ingestion chunks into vectors.
* Keeps embedding generation out of the MCP server image.
* Provides one shared embedding service for runtime search and ingestion pipelines.

**Current implementation:**
* CPU-based Hugging Face Text Embeddings Inference service.
* Model: `sentence-transformers/all-mpnet-base-v2`.
* Expected vector dimension: 768.
* Service URL used by MCP and pipelines: `http://embeddings-service-predictor.ml-infra.svc.cluster.local/embed`.

**Key files:**
* `docs-agent-mcp/terraform/embeddings.tf`
* `docs-agent-mcp/terraform/variables.tf`
* `docs-agent-mcp/pipelines/utils.py`

### 3.4 Vector Database Layer

**Purpose:**
* Stores embedded chunks from docs, issues, and code.
* Serves similarity search requests from the MCP tools.

**Current implementation:**
* Milvus Operator is installed through Terraform.
* A lightweight standalone Milvus CR runs in the `ml-infra` namespace.
* Runtime MCP config points to `milvus-milvus.ml-infra.svc.cluster.local:19530`.

**Current collections:**

| Collection | Content | Notes |
| :--- | :--- | :--- |
| `docs_rag` | Kubeflow documentation chunks. | Primary documentation retrieval source. |
| `issues_rag` | GitHub issue and discussion chunks. | Used for troubleshooting and known bug context. |
| `code_rag` | Code and YAML manifest chunks. | May be empty until the code ingestion pipeline is rerun. |

**Key files:**
* `docs-agent-mcp/terraform/milvus.tf`
* `docs-agent-mcp/manifests/mcp-server/mcp-server.yaml`

### 3.5 LLM Inference Layer

**Purpose:**
* Produces final natural-language answers after retrieval.
* Runs inside the Kubeflow/KServe stack instead of depending only on an external LLM provider.

**Current implementation:**
* **Kagent ModelConfig:** Uses provider `OpenAI` because KServe exposes an OpenAI-compatible API.
* **Model name in Kagent config:** `qwen2.5-14B`

**Key files:**
* `docs-agent-mcp/manifests/kagent/setup.yaml`
* `docs-agent-mcp/manifests/vllm/kserve-qwen.yaml`


### 3.6 Ingestion Pipeline Layer

**Purpose:**
* Keeps retrieval data fresh.
* Converts source content into cleaned chunks, embeddings, and Milvus records.
* Uses Kubeflow Pipelines so the reference architecture dogfoods Kubeflow.

**Current implementation:**

| Pipeline | Target collection | Role |
| :--- | :--- | :--- |
| `kubeflow-pipeline.py` | `docs_rag` | Downloads, cleans, chunks, embeds, and stores Kubeflow docs. |
| `issues-pipeline.py` | `issues_rag` | Ingests GitHub issues for troubleshooting context. |
| `code-pipeline.py` | `code_rag` | Ingests code and YAML manifests with resource metadata. |
| `incremental-pipeline.py` | Existing collection records | Handles changed-file updates by deleting old vectors and inserting new chunks. |

**Important current behavior:**
* The newer docs, issues, and code pipelines use failure-aware delete-and-insert logic by `file_unique_id` rather than simply dropping an entire collection.
* The code collection still needs operational runbook coverage so contributors can verify when it is populated.

**Key files:**
* `docs-agent-mcp/pipelines/kubeflow-pipeline.py`
* `docs-agent-mcp/pipelines/issues-pipeline.py`
* `docs-agent-mcp/pipelines/code-pipeline.py`
* `docs-agent-mcp/pipelines/incremental-pipeline.py`
* `docs-agent-mcp/pipelines/utils.py`

### 3.7 Infrastructure and Networking Layer

**Purpose:**
* Provides repeatable setup for namespaces, KServe, Knative, Milvus, TEI, KFP, kagent, and Istio policies.
* Separates platform foundation from workload deployment.

**Current implementation:**

| Area | Terraform file | Notes |
| :--- | :--- | :--- |
| Namespaces | `namespaces.tf` | Creates `ml-infra` and `docs-agent`. |
| KServe and Knative | `knative.tf` | Installs serving dependencies. |
| Milvus | `milvus.tf` | Installs Milvus Operator and standalone Milvus. |
| Embeddings | `embeddings.tf` | Deploys TEI as KServe InferenceService. |
| Kubeflow Pipelines | `kubeflow_pipelines.tf` | Deploys KFP standalone. |
| Kagent | `kagent.tf` | Installs kagent CRDs, controller, and UI. |
| Edge + Istio policies | `gateway_guardrails.tf` | Installs the gateway-guardrails Helm chart (Gateway, TLS, rate limits, session auth, AuthorizationPolicies). Replaces the former `istio_policies.tf` and `kagent_ingress.tf`. |

**Namespace split:**
* `ml-infra`: Milvus, TEI embeddings, and KServe LLM infrastructure.
* `docs-agent`: MCP server and Kagent resources.
* `kubeflow`: Kubeflow Pipelines standalone deployment.

**Key files:**
* `docs-agent-mcp/terraform/`
* `docs-agent-mcp/manifests/`

### 3.8 Public Edge and Gateway Guardrails Layer

**Purpose:**
* Protect the single-GPU LLM from abuse when the chatbot is shared publicly (cost and DoS risk).
* Terminate TLS and route the public domain to the Kagent UI / A2A endpoint.
* Keep public chat anonymous while making usage accountable per session.

**Current implementation:**
* **Ingress:** Istio Gateway with Let’s Encrypt TLS (cert-manager) fronting the public domain; HTTP redirects to HTTPS.
* **Global Rate Limiting:** 60 requests/minute `EnvoyFilter` scoped to the chatbot HTTPS listener only (knative/internal LLM listeners on the shared ingress pod are unaffected); verified live — 429 responses tagged `x-ratelimit-scope: global`.
* **Security & CORS:** CORS locked to the published widget origin (previously wildcard) plus a 30-second route timeout so hung LLM calls cannot pin workers.
* **Anonymous Session Auth:** * A `session-issuer` service mints 30-minute RS256 JWTs (`POST /api/session`, no user accounts).
    * Istio `RequestAuthentication` validates signature and expiry at the gateway, so invalid or expired sessions never reach the LLM. 
    * Enforcement is toggle-gated (`sessionAuth.enforce`) and staged.
* **Rate Limiting Strategy:** Per-IP rate limiting is packaged but disabled (ingress runs `externalTrafficPolicy: Cluster`, so client IPs are SNAT’d to node IPs). Per-session limits keyed on the JWT `sub` claim are the preferred next step.
* **Deployment:** The entire edge ships as the `gateway-guardrails` Helm chart — the single source of truth — installed by Terraform (`gateway_guardrails.tf`); live on the demo cluster as a Helm release after zero-downtime adoption.
* **Rollout state:** Helm-managed with session auth disabled; canary validation and enforcement follow the chat-widget token update (tracked in PR `kubeflow/docs-agent#215`).

**Key files:**
* `docs-agent-mcp/charts/gateway-guardrails/`
* `docs-agent-mcp/session-issuer/`
* `docs-agent-mcp/terraform/gateway_guardrails.tf`


### 4. Deployment Lifecycle

### Diagram: CI/CD and Cluster Validation


**Current Workflows:**

| Workflow | Purpose |
| :--- | :--- |
| `.github/workflows/tests.yml` | PR safety: ruff, format check, compileall, and pytest. |
| `.github/workflows/build-mcp-image.yml` | Standalone multi-arch MCP image publishing to GHCR. |
| `.github/workflows/oke-cicd.yaml` | Compile pipelines, run tests, build/push MCP image, deploy to OKE, and run smoke tests. Also lints, compiles, and unit-tests the session-issuer service. |

**Post-deploy checks:**
* Wait for `embeddings-service` to be `Ready`.
* Wait for Milvus CR status to become `Healthy`.
* Execute `python3 /app/smoke_tools.py` inside the MCP deployment.
* Run non-blocking Qwen chat smoke if a Qwen pod is running.

**Key files:**
* `.github/workflows/tests.yml`
* `.github/workflows/build-mcp-image.yml`
* `.github/workflows/oke-cicd.yaml`
* `docs-agent-mcp/mcp-server/smoke_tools.py`

### 5. Real MCP Smoke Test Details

The smoke script validates the runtime contract, not just process startup.

**Flow:**
1. **Initialize:** `POST` initialize to the MCP endpoint.
2. **Session Handling:** Read the `Mcp-Session-Id` response header.
3. **Handshake:** `POST` `notifications/initialized`.
4. **Registration:** `POST` `tools/list` and assert all three tools are registered.
5. **Tool Validation:** `POST` `tools/call` for:
    * `search_kubeflow_docs`
    * `search_github_issues`
    * `search_kubeflow_code`
    * **Failure criteria:** Fail if a tool returns no text or a `Search failed:` response.
6. **Embedding Verification:** If `EMBEDDINGS_URL` is set, call TEI and verify the returned vector dimension is 768.

**Why this matters:**
* Validates FastMCP session handling.
* Validates tool registration.
* Validates Milvus connectivity.
* Validates TEI connectivity.
* Catches retrieval failures after deployment.

### 6. Technical Detail Page

**Runtime Configuration:**

| Setting | Current value |
| :--- | :--- |
| MCP transport | FastMCP Streamable HTTP |
| MCP endpoint | `/mcp` |
| MCP port | 8000 |
| Docs collection | `docs_rag` |
| Issues collection | `issues_rag` |
| Code collection | `code_rag` |
| Embedding model | `sentence-transformers/all-mpnet-base-v2` |
| Embedding dimension | 768 |
| LLM model name | `qwen2.5-14B` |
| LLM API style | OpenAI-compatible KServe endpoint |
| Global rate limit | 60 requests/min on the chatbot HTTPS listener (`EnvoyFilter` local rate limit) |
| Session token | Anonymous RS256 JWT, 30 min TTL, issued via `POST /api/session` (enforcement staged) |
| Route timeout | 30 seconds |

**Query Execution Flow:**
1. User asks a Kubeflow-related question in Kagent UI.
2. Kagent follows the Agent system message and chooses one or more MCP tools.
3. The MCP server receives a tool call over Streamable HTTP.
4. The MCP server embeds the query through TEI.
5. The MCP server searches the relevant Milvus collection.
6. The MCP server formats retrieved chunks with scores, metadata, and source URLs.
7. Kagent sends retrieved context to the KServe Qwen model.
8. The final answer is returned to the user with citations.

**Ingestion Execution Flow:**
1. KFP pipeline downloads source material from docs, issues, or code repositories.
2. Pipeline cleans content and creates chunks.
3. Pipeline calls TEI to create embeddings.
4. Pipeline writes records into the matching Milvus collection.
5. Runtime MCP tools can retrieve the new records immediately after Milvus load/search succeeds.

### 7. Architecture v2 Discussion Areas

### 7.1 Collection Strategy
Current implementation uses separate collections:
* `docs_rag`
* `issues_rag`
* `code_rag`

**Open design question:**
Should v2 keep separate collections for operational clarity, or move toward a single collection with partitions and hybrid sparse+dense search?

**Trade-off summary:**

| Option | Strength | Risk |
| :--- | :--- | :--- |
| **Separate collections** | Clear ownership, separate schemas, easier per-domain operations. | Federated search and cross-domain ranking are harder. |
| **Single collection with partitions** | Easier unified retrieval and ranking if schema/model are shared. | Harder if domains need different embedding models or schemas. |
| **Hybrid sparse+dense search** | Better exact-match behavior for issue IDs, YAML fields, and identifiers. | Requires schema/index changes and evaluation. |


### 7.2 Thin Context MCP Flow

**Target behavior:**
* IDE agent calls MCP.
* MCP retrieves high-confidence snippets.
* MCP returns a small context package with source URL, chunk text, and score.
* The local IDE agent performs final synthesis using local or user-provided compute.

**Why this matters:**
* Reduces hosted LLM cost.
* Makes source grounding explicit.
* Gives developers exact snippets and validation URLs.


### 7.3 Quality Evaluation

**Recommended evaluation seed:**
* 20 golden questions across docs, issues, and code.
* Expected source URLs for each question.
* Metrics for context precision, citation correctness, latency, and answer usefulness.

**Suggested categories:**

| Category | Example |
| :--- | :--- |
| **Docs** | How do I install or configure a Kubeflow component? |
| **Issues** | Has anyone reported this specific error? |
| **Code** | Where is this Kubernetes resource or setting defined? |
| **Cross-source** | What do docs say, and are there known issues? |

### 7.4 Scale and Cost

**Recommended measurements:**
* Warm response latency p95.
* Cold start latency from zero replicas.
* Burst behavior when concurrent requests increase.
* GPU utilization and cost during traffic and idle windows.

**Potential target gates:**
* **Warm response p95:** under 5 seconds.
* **Cold start p95:** under 45 seconds (if scale-to-zero is enabled).
* **Burst scale-up:** within 60 seconds when request pressure crosses the agreed threshold.

### 7.5 Solidification Workstreams (Current Focus)

Per mentor alignment (July 2026), priority is hardening the implemented architecture before adding new capabilities; the evaluation harness, monitoring dashboards, and an LLM gateway are deferred. Issue triage should map incoming work to one of these workstreams:

* **CI/CD hardening:** Validate the Helm chart and Terraform on every PR, add post-deploy smoke checks, and document and test rollback (`helm rollback`).
* **Auth rollout completion:** Chat-widget token fetch and enforcement for public chat; ingress-level authentication (GitHub OAuth) for admin surfaces such as the Kagent UI and the KFP dashboard.
* **Decoupled container images:** Split the heavy pipeline base image (PyTorch + embedding model) from thin per-change app layers, pin images by digest instead of latest, and add a GHCR retention policy to stop image pile-up.
* **Ingestion cadence:** Scheduled recurring runs (issues daily; docs and code weekly) with manual triggers, incremental updates instead of full re-embeds, and atomic collection swaps during reindex.

# 8. Reference File Index

| Topic | File |
| :--- | :--- |
| MCP server | `docs-agent-mcp/mcp-server/server.py` |
| Embeddings client | `docs-agent-mcp/mcp-server/embeddings_client.py` |
| MCP smoke script | `docs-agent-mcp/mcp-server/smoke_tools.py` |
| MCP Kubernetes manifest | `docs-agent-mcp/manifests/mcp-server/mcp-server.yaml` |
| Kagent Agent/ModelConfig/RemoteMCPServer | `docs-agent-mcp/manifests/kagent/setup.yaml` |
| KServe Qwen manifest | `docs-agent-mcp/manifests/vllm/kserve-qwen.yaml` |
| Terraform platform stack | `docs-agent-mcp/terraform/` |
| Docs ingestion pipeline | `docs-agent-mcp/pipelines/kubeflow-pipeline.py` |
| Issues ingestion pipeline | `docs-agent-mcp/pipelines/issues-pipeline.py` |
| Code ingestion pipeline | `docs-agent-mcp/pipelines/code-pipeline.py` |
| Incremental ingestion pipeline | `docs-agent-mcp/pipelines/incremental-pipeline.py` |
| PR safety workflow | `.github/workflows/tests.yml` |
| OKE CI/CD workflow | `.github/workflows/oke-cicd.yaml` |
| Standalone image build workflow | `.github/workflows/build-mcp-image.yml` |
| Cluster validation guide | `AGENTS.md` |
| Gateway guardrails Helm chart | `docs-agent-mcp/charts/gateway-guardrails/` |
| Session token issuer | `docs-agent-mcp/session-issuer/` |
| Edge Terraform entry point | `docs-agent-mcp/terraform/gateway_guardrails.tf` |
| Session issuer tests | `tests/test_session_issuer.py` |