# Korero Agent Communication Protocol

This directory contains protocol definitions for Korero's multi-agent ideation system.

## Protocol v1

File: `agent-protocol-v1.json`

Defines JSON schema for inter-agent messages during ideation loops:
- **PROPOSAL** — Agent's idea submission with title, category, type, and description
- **CHALLENGE** — Evaluator's critique of a proposal
- **DEFENSE** — Original agent's response to challenges
- **EVALUATION** — Structured scores from evaluator agents
- **SELECTION** — Idea Orchestrator's final ranking and winner selection

## Message Flow

Each ideation loop follows this message sequence:

```
Phase 1: Idea Generation
  Domain Agent 1 → PROPOSAL
  Domain Agent 2 → PROPOSAL
  Domain Agent N → PROPOSAL

Phase 2: Structured Debate
  Round 1 (Evaluation):
    Devil's Advocate    → CHALLENGE (per proposal)
    Feasibility Analyst → EVALUATION (per proposal)

  Round 2 (Rebuttal):
    Proposal authors    → DEFENSE (responding to challenges)

  Round 3 (Final Selection):
    Idea Orchestrator   → SELECTION (with rankings)
```

## Usage

Protocol v1 is a definitional schema. It does not change runtime behavior but
establishes the standard format for future features:
- Structured debate logging
- Debate replay commands (`korero debates --loop N`)
- Agent performance tracking
- Programmatic debate analysis

## Validation

Validate messages against the schema using any JSON Schema validator:
```bash
# Using ajv-cli
npx ajv validate -s agent-protocol-v1.json -d message.json
```

## Extensibility

The schema uses `additionalProperties: true` on scoring criteria, allowing
projects to define custom scoring dimensions via CONFIG_SCORING without
breaking protocol compatibility.

Domain agent IDs are not enumerated in the schema — they are project-specific
and generated dynamically. Only the three mandatory evaluation agents
(devils-advocate, technical-feasibility-analyst, idea-orchestrator) are
defined as constants.
