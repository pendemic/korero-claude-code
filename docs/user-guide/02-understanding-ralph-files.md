# Understanding Korero Files

After running `korero-enable`, `korero-import`, or `korero-setup`, you'll have a `.korero/` directory with several files. This guide explains what each file does and whether you need to edit it.

## File Reference Table

| File | Auto-Generated? | Who Writes It | Who Reads It | You Should... |
|------|-----------------|---------------|--------------|---------------|
| `.korero/PROMPT.md` | Yes (with smart defaults) | **You** customize it | Korero reads every loop | Review and customize project goals |
| `.korero/fix_plan.md` | Yes (can import tasks) | **You** + Korero updates | Korero reads and updates | Add/modify specific tasks |
| `.korero/AGENT.md` | Yes (detects build commands) | Korero maintains | Korero reads for build/test | Rarely edit (auto-maintained) |
| `.korero/specs/` | Empty directory created | **You** add files when needed | Korero reads for context | Add when PROMPT.md isn't detailed enough |
| `.korero/specs/stdlib/` | Empty directory created | **You** add reusable patterns | Korero reads for conventions | Add shared patterns and conventions |
| `.korerorc` | Yes (project-aware) | Usually leave as-is | Korero reads at startup | Rarely edit (sensible defaults) |
| `.korero/logs/` | Created automatically | Korero writes logs | You review for debugging | Don't edit (read-only) |
| `.korero/status.json` | Created at runtime | Korero updates | Monitoring tools | Don't edit (read-only) |

## The Core Files

### PROMPT.md - Your Project Vision

**Purpose**: High-level instructions that Korero reads at the start of every loop.

**What to include**:
- Project description and goals
- Key principles or constraints
- Technology stack and frameworks
- Quality standards

**What NOT to include**:
- Step-by-step implementation tasks (use fix_plan.md)
- Detailed API specifications (use specs/)
- Build commands (use AGENT.md)

**Example**:
```markdown
## Context
You are Korero, building a REST API for a bookstore inventory system.

## Key Principles
- Use FastAPI with async database operations
- Follow REST conventions strictly
- Every endpoint needs tests
- Document all API endpoints with OpenAPI
```

### fix_plan.md - Your Task List

**Purpose**: Prioritized checklist of tasks Korero works through.

**Key characteristics**:
- Korero checks off `[x]` items as it completes them
- Korero may add new tasks it discovers
- You can add, reorder, or remove tasks anytime
- More specific tasks = better results

**Good task structure**:
```markdown
## Priority 1: Foundation
- [ ] Create database models for Book and Author
- [ ] Set up SQLAlchemy with async support
- [ ] Create Alembic migration for initial schema

## Priority 2: API Endpoints
- [ ] POST /books - create a new book
- [ ] GET /books - list all books with pagination
- [ ] GET /books/{id} - get single book with author details
```

**Bad task structure**:
```markdown
- [ ] Make the API work
- [ ] Add features
- [ ] Fix bugs
```

### specs/ - Detailed Specifications

**Purpose**: When PROMPT.md isn't enough detail for a feature.

**When to use specs/**:
- Complex features needing detailed requirements
- API contracts that must be followed exactly
- Data models with specific validation rules
- External system integrations

**When NOT to use specs/**:
- Simple CRUD operations
- Features already well-explained in PROMPT.md
- General coding standards (put in PROMPT.md)

**Example structure**:
```
.korero/specs/
├── api-contracts.md      # OpenAPI-style endpoint definitions
├── data-models.md        # Entity relationships and validations
└── third-party-auth.md   # OAuth integration requirements
```

### specs/stdlib/ - Standard Library Patterns

**Purpose**: Reusable patterns and conventions for your project.

**What belongs here**:
- Error handling patterns
- Logging conventions
- Common utility functions specifications
- Testing patterns
- Code style decisions

**Example**:
```markdown
# Error Handling Standard

All API errors must return:
{
  "error": {
    "code": "BOOK_NOT_FOUND",
    "message": "No book with ID 123 exists",
    "details": {}
  }
}

Use HTTPException with these codes:
- 400: Validation errors
- 404: Resource not found
- 409: Conflict (duplicate)
- 500: Internal errors (log full trace)
```

### AGENT.md - Build Instructions

**Purpose**: How to build, test, and run the project.

**Who maintains it**: Primarily Korero, as it discovers build commands.

**When you might edit**:
- Setting initial build commands for a complex project
- Adding environment setup steps
- Documenting deployment commands

### .korerorc - Project Configuration

**Purpose**: Project-specific Korero settings.

**Default contents** (usually fine as-is):
```bash
PROJECT_NAME="my-project"
PROJECT_TYPE="typescript"
MAX_CALLS_PER_HOUR=100
ALLOWED_TOOLS="Write,Read,Edit,Bash(git *),Bash(npm *),Bash(pytest)"
```

**When to edit**:
- Restricting tool permissions for security
- Adjusting rate limits
- Changing session timeout

## File Relationships

```
┌─────────────────────────────────────────────────────────────┐
│                         PROMPT.md                           │
│            (High-level goals and principles)                │
│                              │                              │
│                              ▼                              │
│  ┌─────────────────────────────────────────────────────┐   │
│  │                      specs/                          │   │
│  │         (Detailed requirements when needed)          │   │
│  │                                                      │   │
│  │  specs/api.md ──────▶ Informs fix_plan.md tasks     │   │
│  │  specs/stdlib/ ─────▶ Conventions Korero follows     │   │
│  └─────────────────────────────────────────────────────┘   │
│                              │                              │
│                              ▼                              │
│  ┌─────────────────────────────────────────────────────┐   │
│  │                    fix_plan.md                       │   │
│  │          (Concrete tasks Korero executes)             │   │
│  │                                                      │   │
│  │  [ ] Task 1 ◄────── Korero checks off when done      │   │
│  │  [x] Task 2                                         │   │
│  │  [ ] Task 3 ◄────── Korero adds discovered tasks     │   │
│  └─────────────────────────────────────────────────────┘   │
│                              │                              │
│                              ▼                              │
│  ┌─────────────────────────────────────────────────────┐   │
│  │                     AGENT.md                         │   │
│  │        (How to build/test - auto-maintained)         │   │
│  └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

## Common Scenarios

### Scenario 1: Simple feature addition

Just edit fix_plan.md:
```markdown
- [ ] Add a /health endpoint that returns {"status": "ok"}
```

### Scenario 2: Complex feature with specific requirements

Add a spec file first, then tasks:

1. Create `.korero/specs/search-feature.md`:
```markdown
# Search Feature Specification

## Requirements
- Full-text search on book titles and descriptions
- Must support:
  - Exact phrase matching: "lord of the rings"
  - Boolean operators: fantasy AND epic
  - Fuzzy matching for typos
```

2. Then add to fix_plan.md:
```markdown
- [ ] Implement search per specs/search-feature.md
```

### Scenario 3: Establishing team conventions

Add to specs/stdlib/:
```markdown
# Logging Conventions

All service methods must log:
- Entry with parameters (DEBUG level)
- Exit with result summary (DEBUG level)
- Errors with full context (ERROR level)
```

## Tips for Success

1. **Start simple** - Begin with just PROMPT.md and fix_plan.md. Add specs/ only when needed.

2. **Be specific** - Vague requirements produce vague results. "Add user auth" is worse than "Add JWT authentication with /login and /logout endpoints".

3. **Let fix_plan.md evolve** - Korero will add tasks it discovers. Review periodically and reprioritize.

4. **Don't over-specify** - If Claude can figure it out from context, you don't need to specify it.

5. **Review logs** - When something goes wrong, `.korero/logs/` tells you what Korero was thinking.
