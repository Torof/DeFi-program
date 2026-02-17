# Claude Code Project Instructions

## Working Philosophy

We work **in tandem** - each with our own skills, strengths, and limitations. This is a collaborative process, not a race.

## Core Principles

### 1. Always Discuss Before Acting

**NEVER code, build, or modify anything without explicit approval.**

- If the user mentions an idea or asks a question → **Discuss it first**
- If the user is thinking through something → **Engage in discussion, don't jump to implementation**
- If a task seems obvious → **Still discuss the approach before doing it**

### 2. Wait for Explicit Approval

Do not interpret these as approval to proceed:
- ❌ "that's interesting"
- ❌ "let's keep going"
- ❌ "yes, that's good"
- ❌ Silence or no response

Only proceed when you receive clear, explicit approval:
- ✅ "Go ahead and build that"
- ✅ "Yes, implement it"
- ✅ "Create the file"
- ✅ "Make those changes"

### 3. Work in Small Increments

- Complete **one module/section at a time**
- After completing each piece of work, **stop and ask** what to do next
- Never assume the next step - even if it seems obvious
- Check in frequently to avoid going down the wrong path

### 4. Speed vs. Quality Trade-off

**Going too fast introduces errors the user might not catch.**

- Take time to discuss approaches
- Explain trade-offs before implementing
- Give the user space to review and provide input
- Slow is smooth, smooth is fast

### 5. When Unsure, Ask

If there's any ambiguity about:
- Whether to proceed
- Which approach to take
- What the user actually wants
- Whether changes might affect other parts

→ **Stop and ask**

## Summary

**Default mode: Discuss, explain, and wait for explicit approval before taking any action.**

Only code/build/modify when given clear, direct permission to do so.

---

# DeFi Curriculum Building Guide

## User Profile

### Background
- **Experience**: 8 years Solidity development
- **EVM Knowledge**: Strong understanding, though some details may need refreshing
- **Concept Grasp**: Excellent - can understand all technical concepts
- **Math**: Can be challenging - needs extra support with visual explanations
- **Bit Manipulation**: Can be challenging - needs step-by-step walkthroughs

### Learning Style
The user learns best through:
1. **Making connections** between concepts
2. **Multiple sources** - different explanations of the same concept
3. **Progression**: Practical use case → Concept → Theory → Hands-on
4. **Chunking**: Information broken into digestible pieces
5. **Iteration**: Building understanding layer by layer
6. **Active coding**: Workspace exercises with auto-verification (Foundry tests)
7. **Integration**: Capstone projects that combine multiple concepts

### Goals
1. **Deep DeFi Understanding** - for personal use and mastery
2. **Job Market Success** - land a great DeFi development role

## Critical Review Framework

When reviewing/building any section, evaluate against these criteria:

### 1. Depth vs Breadth
**Question:** Is this challenging enough for an 8-year Solidity dev targeting DeFi roles?

**Red Flags:**
- Too basic (explaining what they already know)
- Missing advanced production patterns
- No connection to how it's used in real protocols

**Good:**
- Assumes Solidity knowledge, focuses on DeFi-specific applications
- Shows production code from major protocols (Uniswap, Aave, Curve)
- Explains the "why" behind architectural decisions

### 2. Math/Bit-Manipulation Support
**Question:** Are complex math and bit operations explained with visuals and step-by-step breakdowns?

**Must Include for Math:**
- Visual diagrams (ASCII art works great)
- Plain English explanations before equations
- "Why this works" before "how to implement"
- Real DeFi examples showing where this math appears
- Step-by-step walkthroughs

**Must Include for Bit Manipulation:**
- Memory layout diagrams
- Step-by-step packing/unpacking examples
- Small number examples to verify understanding
- Explanation of why casts and shifts work
- Visual representation of bit positions

### 3. Learning Flow
**Question:** Does content follow: Practical → Concept → Theory → Hands-on?

**Good Structure:**
```
1. Why this matters (DeFi context)
2. The problem it solves
3. The solution (with examples)
4. 💻 Quick Try (2-min Remix test)
5. 🏗️ Real usage (production code)
6. 🔍 Deep dive (if complex topic)
7. 🔗 DeFi pattern connection
8. 💼 Job market context
9. Further resources
```

### 4. Concept Linking
**Question:** Are connections to broader DeFi patterns explicit?

**Must Include:**
- How this concept appears across different protocols
- Which DeFi patterns depend on this
- How it connects to other concepts in the curriculum
- Real-world scenarios where this matters

### 5. Job Market Relevance
**Question:** Does this prepare the user for interviews and real work?

**Must Include:**
- Common interview questions with good/great answer examples
- Red flags (outdated patterns to avoid)
- What production teams expect
- Pro tips for standing out
- Current hot topics in the space

### 6. Production Readiness
**Question:** Does this teach how to read and learn from production code?

**Must Include:**
- Links to real protocol implementations
- How to study complex codebases
- Reading strategies (tests first, simple functions first, etc.)
- What to focus on vs what to skip

## Content Enhancement Patterns

### Pattern 1: Quick Try Moments
**Add after each major concept (before diving deep)**

```markdown
💻 **Quick Try:**

Before moving on, test this in [Remix](https://remix.ethereum.org/):
```solidity
// Minimal code showing the concept
// Should take 2 minutes to deploy and test
```
Deploy and see [specific observable result]. Feel the difference.
```

**Purpose:** Immediate hands-on before theory, builds intuition

### Pattern 2: Math Deep Dives
**Add when math is involved**

```markdown
#### 🔍 Deep Dive: Understanding [Math Concept]

**The problem it solves:**
[Plain English explanation]

**Example scenario in DeFi:**
[Concrete example with numbers]

**Visual representation:**
```
[ASCII diagram showing the math]
```

**Why this works:**
- [Reason 1 with plain English]
- [Reason 2 with numbers]

**When you'll see this in DeFi:**
- [Protocol 1 usage]
- [Protocol 2 usage]

**How to read the code:**
1. [Step 1]
2. [Step 2]
```

### Pattern 3: Bit Manipulation Walkthroughs
**Add for any bit manipulation topics**

```markdown
#### 🔍 Deep Dive: Understanding [Bit Operation]

**The problem:**
[Why packing/manipulation is needed]

**Visual memory layout:**
```
┌─────────────────┬─────────────────┐
│   High bits     │    Low bits     │
└─────────────────┴─────────────────┘
```

**Step-by-step [operation]:**
```solidity
// Step 1: [explanation]
[code]

// Step 2: [explanation]
[code]

// Visual after Step 2:
// [bits representation]
```

**Why the casts work:**
- [Explain type conversions]
- [Explain shifts]
- [Explain sign preservation]

**Testing your understanding:**
```solidity
// Try this example with small numbers
[simple example to verify]
```

**📖 How to Study [Production Code]:**
1. Start with tests
2. Draw the bit layout
3. Trace one operation
4. Verify with examples
5. Read comments
```

### Pattern 4: DeFi Pattern Connections
**Add after explaining the concept**

```markdown
#### 🔗 DeFi Pattern Connection

**Where [concept] matters in DeFi:**

1. **[Pattern/Protocol 1]**
   ```solidity
   // Code showing usage
   ```
   [Explanation of why it matters]

2. **[Pattern/Protocol 2]**
   - [Bullet points explaining]
   - [Real impact]

3. **[Pattern/Protocol 3]**
   [Explanation]

**The pattern:** [General rule for when to use this]
```

### Pattern 5: Job Market Context
**Add at the end of major concepts**

```markdown
#### 💼 Job Market Context

**What DeFi teams expect:**

1. **"[Common interview question]"**
   - Good answer: [explanation]
   - Great answer: [explanation with depth]

2. **"[Another question]"**
   - [Expected knowledge]

**Interview Red Flags:**
- ❌ [Outdated pattern/knowledge gap]
- ❌ [Another red flag]

**Pro tip:** [Insider knowledge to stand out]
```

### Pattern 6: Code Reading Strategies
**Add when referencing complex production code**

```markdown
**📖 How to Study [File/Concept]:**

1. **Start with tests** - See how it's used in practice
2. **Identify core types** - Understand the data structures
3. **Read simple functions first** - Build up to complex ones
4. **Draw diagrams** - Visualize the architecture/flows
5. **Read comments** - Understand the "why"

**Don't get stuck on:** [What to skip initially]
```

### Pattern 7: Intermediate Examples
**Add when jumping from basic to advanced**

```markdown
#### 🎓 Intermediate Example: [Topic]

Before diving into [complex production code], let's build [simpler version]:

```solidity
// Realistic but simplified example
// That bridges basic → production
```

**Why this matters:** [Connection to production pattern]
```

## Section Structure Template

Every major section should follow this structure:

```markdown
# Section X: [Topic] (~Y days)

## 📚 Table of Contents
[TOC with working anchor links]

---

## Day 1: [Subtopic]

<a id="concept-id"></a>
### 💡 Concept: [Concept Name]

**Why this matters:** [DeFi-specific context, not generic]

> Introduced in [Version/EIP with link]

**The problem/old way:**
[Show what was wrong/missing]

**The solution/new way:**
[Show the improvement]

💻 **Quick Try:**
[2-minute Remix example]

🏗️ **Real usage:**
[Links to production code with explanation]

#### 🔍 Deep Dive: [If complex topic]
[Detailed explanation with visuals for math/bits]

#### 🔗 DeFi Pattern Connection
[Where this appears in real protocols]

#### 💼 Job Market Context
[Interview prep, red flags, pro tips]

> 🔍 **Deep dive:** [External resources]

---

[Repeat for each concept]

---

<a id="dayX-exercise"></a>
## 🎯 Day X Build Exercise

**Workspace:** [Links to starter files and tests]

[Exercise description with learning goals]

**🎯 Goal:** [What they'll learn from doing this]

---

## 📋 Day X Summary

**✓ Covered:**
- [Bullet list of concepts]

**Next:** [Preview of next day/section]

---

[Repeat for Day 2, etc.]

---

## 📚 Resources

### [Organized by topic]
- [Links with descriptions]

---

**Navigation:** [Previous: Section X] | [Next: Section Y]
```

## Examples From Section 1

### Example: Math Deep Dive
See Section 1's `mulDiv` explanation:
- Visual 512-bit diagram
- Plain English before code
- Step-by-step why it works
- Real DeFi usage examples (vaults, AMMs)

### Example: Bit Manipulation
See Section 1's `BalanceDelta` explanation:
- Memory layout diagram
- Step-by-step packing code
- Step-by-step unpacking code
- Why casts work
- Testing examples

### Example: DeFi Patterns
See Section 1's connections:
- Checked arithmetic → vault math, AMMs, rebasing tokens
- Custom errors → error propagation in aggregators
- UDVTs → preventing wrong token bugs
- Transient storage → flash accounting

### Example: Job Market
See Section 1's interview prep:
- Specific questions with tiered answers
- Red flags to avoid
- Pro tips per concept
- Hot topics (e.g., Uniswap V4 flash accounting)

## Checklist for Every Section

Before considering a section "done":

- [ ] Math/bit operations have visual diagrams
- [ ] Complex concepts have step-by-step breakdowns
- [ ] Each major concept has a "Quick Try" moment
- [ ] Real production code is linked and explained
- [ ] DeFi pattern connections are explicit
- [ ] Job market context included
- [ ] Interview questions with answer examples
- [ ] Code reading strategies provided
- [ ] Intermediate examples bridge basic → advanced
- [ ] All links verified and working
- [ ] Workspace exercise files exist and are linked correctly
- [ ] Exercise skeleton code provided (no unnecessary boilerplate)
- [ ] Exercise TODOs are clear with hints
- [ ] Foundry tests written and passing
- [ ] Tests have descriptive names and helpful error messages
- [ ] Exercise requires thinking, not just copy-paste

## Checklist for Every Part

Before considering a Part "done":

- [ ] All sections complete per section checklist
- [ ] Capstone project designed
- [ ] Capstone integrates 3-4+ major concepts
- [ ] Capstone has architectural guidance (not full solution)
- [ ] Capstone has comprehensive test requirements
- [ ] Capstone is portfolio/interview ready

## Quality Standards

**Depth for experienced devs:**
- Assume Solidity knowledge, teach DeFi patterns
- Show production implementations, not toy examples
- Explain architectural decisions, not just syntax

**Support for learning style:**
- Multiple explanations of complex concepts
- Visual aids for math and bits
- Links between concepts explicit
- Progression from practical to theoretical maintained

**Job market relevance:**
- Current (2025-2026) expectations
- Protocol-specific knowledge (Uniswap V4, Aave V3, etc.)
- Interview-ready examples
- Signals of expertise vs beginner knowledge

---

## Workspace Exercises

**Critical Component:** Every section must have hands-on exercises that the user codes themselves.

### Exercise Design Principles

**What makes a great exercise:**

1. **Skeleton Code Provided**
   - No redundant boilerplate (imports, basic setup already there)
   - Focus is on the CONCEPT, not typing ceremony
   - Clear `// TODO:` markers showing what to implement

2. **Thoughtful Implementation Required**
   - Can't just copy-paste from the lesson
   - Must think through the logic
   - May need to refer back to lesson or external sources
   - Reinforces understanding through active problem-solving

3. **Auto-Verification with Foundry**
   - Tests use `forge test`
   - Clear test names showing what's being verified
   - Tests fail with helpful error messages
   - Green checkmarks = dopamine hit = learning reinforcement

4. **Incremental Difficulty**
   - Start with simple implementation
   - Build up to more complex patterns
   - Each TODO builds on previous understanding

### Exercise Structure

```solidity
// workspace/src/part1/section1/Concept.sol

// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

// Imports already provided
import {SomeType} from "./types/SomeType.sol";

/// @notice [Brief description of what this contract demonstrates]
/// @dev Exercise for Section X: [Concept Name]
contract ConceptExercise {
    // State variables and types already defined

    // TODO: Implement [specific function/feature]
    // Hint: [Helpful pointer without giving away the answer]
    // See: [Link to relevant section in the lesson]

    // TODO: Implement [next function/feature]
    // This should use the pattern from [concept name]
}
```

### Test Structure

```solidity
// workspace/test/part1/section1/Concept.t.sol

contract ConceptTest is Test {
    // Setup already provided

    function test_BasicFunctionality() public {
        // Verify basic implementation works
        // Clear assertion messages
    }

    function test_EdgeCase() public {
        // Test boundary conditions
    }

    function testFuzz_Property(uint256 input) public {
        // Property-based testing where relevant
    }
}
```

### Exercise Guidelines

**DO:**
- ✅ Focus on the core concept from the lesson
- ✅ Provide skeleton that eliminates busywork
- ✅ Include hints that guide without solving
- ✅ Link back to relevant lesson sections
- ✅ Write tests that verify understanding
- ✅ Make tests descriptive and helpful

**DON'T:**
- ❌ Make the user write boilerplate
- ❌ Create exercises that are just copy-paste
- ❌ Write vague TODOs without guidance
- ❌ Forget to link to workspace files in the lesson
- ❌ Write tests that don't help debug failures

### Exercise Learning Cycle

The intended flow:
1. Read concept in lesson
2. See "Quick Try" moment (2-min Remix)
3. Read about real usage
4. Go to workspace exercise
5. Try to implement from memory
6. Get stuck → refer back to lesson
7. Implement solution
8. Run tests → some fail
9. Debug → understand why
10. All tests pass → concept internalized

**This cycle is CRITICAL** - the struggle and reference-back is where deep learning happens.

---

## Capstone Projects

**Integration Component:** Each Part (not section) ends with a capstone project.

### Capstone Purpose

**Goals:**
1. **Integration** - Bring together multiple concepts from the Part
2. **Realistic** - Build something resembling production DeFi code
3. **Challenging** - Require synthesizing knowledge, not just applying one concept
4. **Portfolio-Ready** - Result is something they can show in interviews

### Capstone Structure

**For Part 1: Foundational Solidity**
- Combine: Modern Solidity features, EVM changes, token patterns, Foundry testing
- Example: Build a gas-optimized ERC-4626 vault with:
  - UDVTs for Shares/Assets
  - Custom errors
  - Transient storage for reentrancy guard
  - Comprehensive test suite
  - Gas benchmarks

**For Part 2: DeFi Protocols** (future)
- Combine: Multiple protocol patterns learned
- Example: Build a yield aggregator that:
  - Integrates with Aave/Compound
  - Uses flash loans
  - Implements strategy pattern
  - Handles multiple tokens

**For Part 3: Advanced Patterns** (future)
- Combine: Everything learned
- Example: Build a production-ready protocol with:
  - Proxy pattern for upgradeability
  - Multi-sig governance
  - Integration tests with mainnet forks
  - Deployment scripts

### Capstone Guidelines

**DO:**
- ✅ Require using at least 3-4 major concepts from the Part
- ✅ Include comprehensive test requirements
- ✅ Provide architectural guidance but not implementation
- ✅ Include stretch goals for advanced features
- ✅ Make it interview/portfolio worthy

**DON'T:**
- ❌ Make it too simple (just combining concepts superficially)
- ❌ Make it overwhelming (unrealistic scope)
- ❌ Provide too much skeleton code (this should be more open-ended)
- ❌ Skip this - it's where everything clicks together

### Capstone Success Criteria

**The user should be able to:**
1. Explain architectural decisions
2. Justify technology choices
3. Demonstrate understanding through code
4. Show testing best practices
5. Present it in an interview setting

**This is the "final exam" that proves mastery of the Part.**

---

**This guide should be referenced when creating or reviewing every section in the curriculum.**
