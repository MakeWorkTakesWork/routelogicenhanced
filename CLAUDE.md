# Salesforce ISV Code Review Guide

## Review Workflow

### Phase 0: Architecture Overview
- Generate module list & high-level architecture overview
- Map directory structure and dependencies
- **DO NOT begin reviewing files yet**

### Phase 1: Directory-by-Directory Review
Process one directory/package at a time in this order:
- Apex classes/triggers
- Lightning Web Components (LWCs)
- Flows/Process Builder
- Custom objects/fields
- Permission sets/profiles

### Phase 2: File-Level Analysis
For each file, perform **line-by-line or logical block** review for:
- **Code Quality**: naming, modularity, style, complexity
- **Performance**: bulkification, governor limits, efficient SOQL/DML
- **Security**:
  - CRUD/FLS enforcement via `Security.stripInaccessible`
  - SOQL injection prevention
  - XSS protection
  - Lightning Locker CSP compliance
  - Input validation
- **Integrations**: 
  - No hard-coded credentials
  - Proper HTTPS/TLS usage
  - OAuth implementation
- **Best Practices**: modularity, packaging standards, extensibility, logging, error handling

### Phase 3: Summary & Recommendations
After all files reviewed, create:
- **Risk & Findings Summary** grouped by category
- **Prioritized Recommendations** with suggested refactorings and diffs/pseudocode
- **AppExchange Readiness Checklist**:
  - Static analysis results
  - CRUD/FLS compliance
  - Health-check compliance
  - Documentation completeness

## Plan First, Execute Later Policy

- **Always** produce and show a review plan for each phase before proceeding
- **Wait for explicit approval** before starting each phase
- Use format: "Here's my plan for [Phase X]... Please confirm before I proceed."

## Context Management

- Use `/clear` or start fresh session after each major phase
- Create tracking files as needed:
  - `review-plan.md` - Overall review strategy
  - `todo-review.md` - Issues and TODOs across sessions
  - `findings-[phase].md` - Results from each phase

## Review Commands

- `Phase 0 review` - Start architecture overview
- `Phase 1 review [directory]` - Review specific directory
- `Phase 2 review [file]` - Deep dive into specific file
- `Phase 3 summary` - Generate final summary

## Key Focus Areas

- **Governor Limits**: Bulk patterns, SOQL/DML optimization
- **Security**: CRUD/FLS, injection prevention, data exposure
- **Maintainability**: Code clarity, documentation, test coverage
- **ISV Standards**: Multi-tenant considerations, package namespacing
- **AppExchange Requirements**: Security review compliance