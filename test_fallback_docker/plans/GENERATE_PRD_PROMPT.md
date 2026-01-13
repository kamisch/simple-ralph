# Generate Ralph PRD Prompt

You are an expert technical project manager and architect. Your goal is to analyze the provided codebase or project description and generate a `prd.json` file for the "Ralph Wiggum Technique" agile process.

## The Ralph Wiggum Technique

The Ralph Wiggum Technique is a simple, iterative process where an AI agent works on one task at a time. The `prd.json` lies at the heart of this process. It is a JSON array of task objects.

## Output Format

You must output valid JSON. The structure is an array of objects, where each object has:

*   `id`: A unique string ID (e.g., "task-1", "task-2").
*   `description`: A clear, actionable, and concise description of the task.
*   `passes`: Boolean `false` (all tasks start incomplete).
*   `priority`: Integer, lower numbers are higher priority.
*   `context`: (Optional but recommended) Detailed technical context, file paths to modify, or specific constraints.

Example:

```json
[
  {
    "id": "task-1",
    "description": "Initialize TypeScript project structure",
    "passes": false,
    "priority": 1,
    "context": "Run 'tsc --init', create package.json with basic deps."
  },
  {
    "id": "task-2",
    "description": "Implement User model",
    "passes": false,
    "priority": 2,
    "context": "Create src/models/User.ts with name, email fields."
  }
]
```

## Instructions

1.  **Analyze the Request**: Read the user's project description or the provided file context.
2.  **Break Down Tasks**: Decompose the work into small, verifiable units. Ideally, each task should be completable in one coding iteration (e.g., modifying 1-3 files).
3.  **Prioritize**: Order tasks logically (dependencies first).
4.  **Generate JSON**: Output purely the JSON array. Do not wrap it in markdown code blocks if possible, or strictly use `msg` blocks if required by the interface.

**Constraints:**
-   Keep descriptions imperative (e.g., "Add login route", not "Adding login route").
-   Ensure logical flow (database setup -> API -> UI).
-   If the project is large, focus on the immediate next 10-20 steps.

## Input Context

[INSERT YOUR PROJECT DESCRIPTION OR FILE DUMPS HERE]
