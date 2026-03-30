---
description: "Ingest initial research data into a workspace. Pulls Linear project data and runs deep web research to build a comprehensive starting dataset. Optimized for deal-war-room and theme-research templates."
---

# Workspace Ingest

You are an ingest agent for an AI workspace system. Your job is to gather comprehensive research materials and populate the workspace with structured, source-cited data. This is the foundation that all subsequent analysis builds on — be thorough.

## Input

The user will provide: `$ARGUMENTS`

This could be:
- A company name (e.g., "Anthropic", "Stripe")
- A topic or theme (e.g., "autonomous logistics", "edge AI inference")
- A URL to a company or resource
- Empty (auto-detect from workspace name and config)

## Step 1: Detect Context

Read `.workspace.yaml` in the current directory to determine:
- `template` — what type of workspace this is
- `name` — the workspace name
- `ingest` — ingest configuration (company/theme/topic, linear_project_id, extra_queries, etc.)

If no arguments were provided, infer the subject from the `ingest` config fields or workspace name.

Build a subject string:
- For `deal-war-room`: use `ingest.company` (or `$ARGUMENTS` or workspace name)
- For `theme-research`: use `ingest.theme` (or `$ARGUMENTS` or workspace name)
- For `research`: use `ingest.topic` (or `$ARGUMENTS` or workspace name)
- For `agent-dev`: use `$ARGUMENTS` or workspace name

Read any additional config:
- `ingest.url` — company website to crawl
- `ingest.crunchbase` — Crunchbase slug
- `ingest.sectors` — sector hints for research
- `ingest.seed_companies` — known companies (for themes)
- `ingest.extra_queries` — additional search queries to run
- `ingest.linear_project_id` — Linear project to fetch

## Step 2: Check Prerequisites

Before proceeding:

1. **Check if data/ already has content** (excluding .gitkeep). If it does, ask the user: "Data directory already has content. Re-ingest (overwrite) or skip?"

2. **Check LINEAR_API_KEY** if `linear_project_id` is set:
   ```bash
   echo "${LINEAR_API_KEY:-NOT_SET}"
   ```
   If not set, warn the user: "LINEAR_API_KEY not set. Add `LINEAR_API_KEY=lin_api_xxx` to `.env` and restart the Flox shell, or skip Linear fetch."

3. Create output directories:
   ```bash
   mkdir -p data/linear data/web
   ```

## Step 3: Linear Data Fetch

If `linear_project_id` is configured and `LINEAR_API_KEY` is available, run the fetch script:

```bash
~/.workspace/plugins/ws-ingest/bin/linear-fetch.sh \
  --project-id "<LINEAR_PROJECT_ID>" \
  --output-dir data/linear
```

The script downloads project metadata, all issues with comments, documents, and project updates into `data/linear/`.

After it completes:
- Read `data/linear/project.md` to understand the project context
- Read `data/linear/issues/index.md` for an overview of all tracked work
- Skim key documents in `data/linear/documents/`
- Log to journal: `ws journal <name> --finding "Linear: X issues, Y documents fetched"`

Use this Linear context to inform your web research — it may contain company details, team notes, open questions, or competitor mentions that guide what to search for.

## Step 4: Web Research — deal-war-room

For deal workspaces, research the company in six structured phases. Write each output file as you complete each phase — do not batch everything at the end.

### Phase A: Company Foundation
**Goal**: Understand what the company does, when it was founded, where it's based, and who leads it.
**Searches**: 3-5 queries using WebSearch + crawl company website if `ingest.url` is set
**Write**: `data/web/company-overview.md` and `data/web/team-leadership.md`

Company overview should include:
- One-paragraph description of what they do
- Founding date, HQ location, employee count
- Business model
- Key products/services

Team leadership should include:
- Founders (backgrounds, prior companies, education)
- C-suite and key executives
- Notable hires or departures
- Board members and advisors

```bash
ws journal <name> --finding "Founded YYYY, HQ City, ~N employees"
```

### Phase B: Financial Intelligence
**Goal**: Map the full funding history and financial signals.
**Searches**: 3-5 queries (include Crunchbase slug if available)
**Write**: `data/web/funding-history.md`

Include:
- All known funding rounds (date, amount, lead investor, other investors)
- Valuation at each round (if available)
- Total funding raised
- Revenue signals (if any public data)
- Any secondary transactions or debt financing

```bash
ws journal <name> --finding "Total raised: $XM, last round Series X at $YM valuation"
```

### Phase C: Product & Technology
**Goal**: Deep understanding of what they've built and how.
**Searches**: 3-5 queries + use Exa (crawling_exa) on the company website and docs
**Write**: `data/web/product-technology.md`

Include:
- Product description and key features
- Technology stack and architecture (if discoverable)
- API/developer ecosystem
- Patents or proprietary tech
- Product roadmap signals (from blog posts, changelogs)
- Notable customers or case studies

Use `crawling_exa` to crawl the company website for product/technology pages.

### Phase D: Market & Competition
**Goal**: Understand the market landscape and competitive positioning.
**Searches**: 5-8 queries + use Exa (web_search_exa) for company discovery
**Write**: `data/web/market-landscape.md` and `data/web/competitors.md`

Market landscape:
- Market category definition
- TAM/SAM/SOM estimates (get 3+ sources, note methodology differences)
- Key market dynamics and trends
- Buyer persona and procurement process

Competitors:
- Direct competitors (similar product, same market)
- Indirect competitors (different approach, same problem)
- For each: one-line description, funding, stage, key differentiator
- Competitive positioning: where does the subject company sit?

Use `web_search_exa` with queries like "[company] competitors" and "[market category] companies" to find comprehensive company lists.

```bash
ws journal <name> --finding "Market: [category], TAM ~$XB (source), N direct competitors identified"
```

### Phase E: Recent Intelligence
**Goal**: What has happened in the last 6-12 months.
**Searches**: 3-5 queries
**Write**: `data/web/recent-news.md`

Include:
- Press releases and announcements
- Media coverage (positive and negative)
- Partnership announcements
- Product launches or major updates
- Executive changes
- Any controversies or concerns

### Phase F: Customer & Traction Signals
**Goal**: Evidence of real-world usage and customer satisfaction.
**Searches**: 3-5 queries + Exa crawling on review sites
**Write**: `data/web/customers-traction.md`

Include:
- Known customers (logos, case studies, testimonials)
- G2/Capterra/TrustRadius reviews (if applicable)
- App store reviews (if applicable)
- Usage metrics (if public — MAU, ARR, growth)
- Hiring patterns (are they hiring aggressively?)
- Job postings analysis (what roles signal about growth/challenges)

Also run any `extra_queries` from the ingest config and incorporate findings into the relevant files.

## Step 5: Web Research — theme-research

For theme workspaces, research the investment theme in five structured phases.

### Phase A: Theme Definition & Market
**Goal**: Define the theme clearly and size the market.
**Searches**: 5-8 queries
**Write**: `data/web/theme-overview.md` and `data/web/market-sizing.md`

Theme overview:
- Clear definition and scope of the theme
- Key technology enablers and why now
- Historical context and evolution
- Adjacent themes and boundaries

Market sizing:
- TAM estimates from 3+ sources with methodology
- Growth rates (historical and projected)
- Key market segments
- Geographic breakdown
- Note conflicts between sources with [CONFLICTING] tag

```bash
ws journal <name> --finding "TAM estimates range from $XB to $YB (sources: A, B, C)"
```

### Phase B: Company Landscape
**Goal**: Map 10-30 companies in the space, categorized.
**Searches**: 8-12 queries + heavy use of Exa (web_search_exa) for discovery
**Write**: `data/web/landscape-companies.md` and `data/web/landscape-matrix.md`

Use `web_search_exa` extensively here — it's better for discovering companies than general web search.

Landscape companies (aim for 15-30):
- Group by segment/approach/category
- For each company: name, one-line description, HQ, founded, funding stage, total raised, notable investors, key differentiator

Landscape matrix (comparison table):
- Markdown table with columns: Company, Category, Stage, Funding, Approach, Key Metric
- Sort by category, then by funding

Also incorporate any `seed_companies` from the ingest config as starting points.

```bash
ws journal <name> --finding "Landscape: N companies identified across M categories"
```

### Phase C: Technical Depth
**Goal**: Understand the technical foundations and maturity.
**Searches**: 5-8 queries (include Google Scholar, arXiv)
**Write**: `data/web/technical-trends.md` and `data/web/academic-papers.md`

Technical trends:
- Key technologies enabling this theme
- Maturity assessment (early R&D vs production-ready)
- Open source vs proprietary dynamics
- Technical moats and barriers to entry
- Infrastructure requirements

Academic papers:
- 5-10 most relevant recent papers (last 2-3 years)
- For each: title, authors, institution, year, one-paragraph summary, relevance
- Key technical breakthroughs
- Active research groups

### Phase D: Investment & Regulatory
**Goal**: Understand the investment landscape and regulatory environment.
**Searches**: 5-8 queries
**Write**: `data/web/investment-activity.md` and `data/web/regulatory-environment.md`

Investment activity:
- Recent deals in the last 12 months
- Most active investors in the space
- Notable exits or IPOs
- Deal size trends
- Geographic distribution of deals

Regulatory environment:
- Current regulations affecting the space
- Pending legislation or policy changes
- Compliance requirements
- Government initiatives or funding programs
- International regulatory differences

### Phase E: Risks & Contrarian Takes
**Goal**: Understand what could go wrong and non-consensus perspectives.
**Searches**: 3-5 queries
**Write**: `data/web/risks-challenges.md`

Include:
- Structural risks (technology, market, regulatory)
- Adoption barriers
- Contrarian perspectives (why this theme might not work)
- Historical analogues (similar themes that failed or took longer)
- Dependency risks (what external factors need to be true)

Also run any `extra_queries` from the ingest config.

## Step 6: Web Research — research

For general research workspaces:

### Phase A: Topic Overview
**Searches**: 3-5 queries
**Write**: `data/web/overview.md`
- Comprehensive summary of the topic
- Key concepts and definitions
- Current state of knowledge
- Major contributors and institutions

### Phase B: Key Sources & Authorities
**Searches**: 3-5 queries
**Write**: `data/web/key-sources.md`
- Authoritative references (books, papers, reports)
- Expert voices and where to find them
- Key institutions and organizations
- Datasets or repositories

### Phase C: Open Questions & Debates
**Searches**: 3-5 queries
**Write**: `data/web/open-questions.md`
- Active debates in the field
- Unresolved questions
- Emerging areas
- Controversies

Also run any `extra_queries` from the ingest config.

## Step 7: Web Research — agent-dev

For agent development workspaces:

### Phase A: Technical References
**Searches**: 2-3 queries + WebFetch on documentation URLs
**Write**: `data/web/reference-docs.md`
- API documentation links and key patterns
- Framework guides
- Example implementations
- Relevant GitHub repos

## Step 8: Write Source Index

Create `data/sources.json` — a master index of every source cited across all files:

```json
{
  "sources": [
    {
      "url": "https://example.com/article",
      "title": "Article Title",
      "accessed": "2026-03-25",
      "used_in": ["company-overview.md", "funding-history.md"],
      "type": "article"
    }
  ],
  "total": 47,
  "generated_at": "2026-03-25T15:00:00Z"
}
```

Types: `article`, `report`, `company_site`, `database`, `academic`, `social`, `government`, `review_site`

## Step 9: Write Ingest Manifest

Create `data/ingest-manifest.json`:

```json
{
  "workspace": "<name>",
  "template": "<template>",
  "subject": "<company/theme/topic>",
  "ingested_at": "<ISO timestamp>",
  "linear": {
    "project_id": "<id or null>",
    "fetched_at": "<timestamp or null>",
    "issues_count": 14,
    "documents_count": 3,
    "status": "complete|skipped|failed"
  },
  "web_research": {
    "categories_completed": ["company-overview", "funding-history", "..."],
    "categories_failed": [],
    "sources_count": 47,
    "status": "complete"
  }
}
```

## Step 10: Create Initial Synthesis

Based on ALL the data gathered (Linear + web research), create an initial synthesis document:

### For deal-war-room: `diligence/initial-screening.md`

Structure:
```markdown
# [Company] — Initial Screening

**Date**: YYYY-MM-DD
**Template**: deal-war-room
**Sources**: N sources consulted

## Executive Summary
2-3 paragraph overview of the company and initial assessment.

## Company Snapshot
| Field | Value |
|---|---|
| Founded | YYYY |
| HQ | City, Country |
| Employees | ~N |
| Total Raised | $XM |
| Last Round | Series X, $YM, YYYY |
| Valuation | $ZM (if known) |

## What They Do
Clear product/service description.

## Market Position
Where they sit in the competitive landscape.

## Key Strengths
- Bullet points

## Key Risks / Open Questions
- Bullet points with [RISK] tags

## Recommended Next Steps
What to investigate further in the deep dive.
```

### For theme-research: `research/YYYY-MM-DD-initial-landscape.md`

Structure:
```markdown
# [Theme] — Initial Landscape

**Date**: YYYY-MM-DD
**Companies Mapped**: N
**Sources**: N sources consulted

## Theme Definition
What this theme is and why it matters now.

## Market Size
Summary of TAM estimates with sources.

## Landscape Overview
High-level categorization of the space.

## Top Companies to Watch
5-10 most interesting companies with 2-3 sentences each.

## Technical Maturity Assessment
Where the technology stands today.

## Investment Thesis Hooks
What makes this theme investable (or not).

## Open Questions
What needs more investigation.
```

### For research: `research/YYYY-MM-DD-initial-overview.md`

Structure: executive summary of the topic, key findings, and open questions.

### For agent-dev: `src/README.md`

Structure: project description, key references, and getting started notes.

## Step 11: Journal Summary

Log the ingest completion:

```bash
ws journal <name> --note "Ingest complete: X web sources, Y Linear items. Files in data/web/ and data/linear/. Initial synthesis in diligence/ (or research/)."
```

## Research Quality Guidelines

These rules apply to ALL research phases:

1. **Source everything**: Every factual claim MUST include a source URL. No unsourced claims.
2. **Tag uncertainty**: Use `[UNVERIFIED]` for claims from a single source only. Use `[CONFLICTING]` when sources disagree — note both versions.
3. **Recency**: Prefer data from the last 12 months. Date all data points.
4. **Multiple sources for key claims**: Market size, revenue, and valuation claims need 3+ sources.
5. **Tool selection**:
   - `web_search_exa` (Exa MCP) — best for discovering companies, finding structured data, and crawling specific sites
   - `crawling_exa` (Exa MCP) — best for extracting content from known URLs
   - `WebSearch` — best for news, press, recent events, general research
   - `WebFetch` — best for known URLs (company sites, SEC filings, specific pages)
6. **Don't fabricate**: If you can't find information, say so explicitly. An honest "[NOT FOUND]" is better than a guess.
7. **File format**: All research files should be markdown with clear headers, source links inline, and a "Sources" section at the bottom of each file.
8. **Progress**: After completing each phase, tell the user what you found and what you're researching next.
