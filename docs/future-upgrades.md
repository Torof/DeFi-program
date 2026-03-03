# Future Upgrades

## Visual Diagram Upgrades

### Tables (CSS only — easy)
Tables are already rendered as HTML by mdBook. Better styling (accent-colored headers, rounded corners, responsive sizing) is pure CSS work in `theme/custom.css`. Current table styles are decent but could be polished further.

### Flowcharts & State Diagrams → Mermaid.js (medium effort, high ROI)
mdBook supports Mermaid via `mdbook-mermaid` preprocessor. Best candidates:
- SSTORE cost state machine (EIP-2200 branches)
- Flash loan callback flows
- Proxy delegation flows
- Liquidation flows
- Proposal lifecycle (governance)
- PBS supply chain (MEV)

Install: `cargo install mdbook-mermaid`, add preprocessor to `book.toml`.
Limitation: can't do bit-layout diagrams or memory maps.

### Bit Layout Diagrams → CSS-styled HTML blocks (medium effort)
For `uint128|uint128` diagrams, Aave bitmaps, BalanceDelta packing, memory maps.
Create a reusable HTML/CSS pattern that renders as colored, labeled bit field boxes.
Write once as a pattern, reuse across modules.

### Architecture Diagrams → SVG (high effort)
Tools: Excalidraw, Figma, or draw.io. Export as SVG, embed in markdown.
Maximum visual control but enormous effort — hundreds of ASCII diagrams across 25+ modules.
Reserve for a few high-impact diagrams only (e.g., Uniswap V4 architecture, Aave V3 contract map).

### Keep as ASCII
ASCII diagrams inside code blocks are the standard in protocol docs, EIPs, and audit reports.
Reading ASCII diagrams is itself a useful skill. Most stack traces, memory dumps, and slot layouts are fine as-is.

### Suggested Priority
1. Mermaid for flowcharts/state machines (biggest visual upgrade per effort)
2. CSS bit-layout blocks (covers the one category where ASCII is genuinely hard to parse)
3. Polish table CSS
4. Selective SVG for 3-5 hero diagrams
5. Leave the rest as ASCII
