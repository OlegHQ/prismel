# Reusable graph UX precedents

## How should grouping become a reusable function?

### Takeaway
Let people organize a working network before asking them to design a reusable interface. Offer an explicit promotion step with visible inputs and outputs.

### Cited Findings
- Houdini distinguishes collapsing selected nodes into a subnet from converting that subnet into a digital asset. Asset creation provides a user-facing label, internal identity and library destination; it warns about external references that would break encapsulation. [Creating digital assets](https://www.sidefx.com/docs/houdini/assets/create.html)
- Blender describes node groups as reusable functions with variable inputs. Its documented grouping operation converts links crossing the selection boundary into group inputs and outputs; nested groups are supported. This is historical documentation (2.90), used as precedent rather than a claim about current shortcuts. [Node Groups](https://docs.blender.org/manual/en/2.90/interface/controls/nodes/groups.html)

### Inferences
- Use two visible actions: **Group selection** for local organization and **Make function** for named reuse. Explain their scope in the action descriptions.
- The extraction dialog should derive arguments from crossing wires and free names, show types and defaults, and preserve the selected result. Do not silently capture unrelated global state.
- A readable label and code symbol should remain recognizably related. Let the first draft be local to the document; library publishing can follow later.

### Gaps
- These manuals establish interaction precedents, not comparative usability results. They do not establish whether separate grouping and function actions are easiest for this project's users.

## How do people distinguish instance values from shared definitions?

### Takeaway
Make the scope of an edit visible before the edit happens. A call's arguments and a function's shared body need distinct, plainly named editing contexts.

### Cited Findings
- Houdini marks asset editing state with a badge. Its manual separates editing the in-memory definition from saving it to a library and describes commands to unlock contents, save the type, and return to the current definition. [Editing digital assets](https://www.sidefx.com/docs/houdini/assets/edit.html)
- TouchDesigner clones share their master's internal operators and wiring, while top-level parameter values remain independent per clone. Clone immunity permits exceptions inside individual clones. [Clone](https://derivative.ca/UserGuide/Clone)

### Inferences
- Opening a call should initially show its own arguments, with an explicit **Edit function** action and a visible **Used by N calls** badge.
- In the body editor, use a header such as **Editing function: ripple — changes affect 3 calls**. Preserve the calling context separately for preview and a **Return to call** action.
- Offer **Make independent copy** when a user wants divergent behavior. Avoid introducing an exception system like clone immunity into the first proposal; it complicates the relationship between source and calls.
- Graph, list and Lisp should select the same semantic entity. Switching representation must not unexpectedly change from call values to the definition.

### Gaps
- The clone page was available as a complete search-result extraction; direct fetch returned an error. No claim is made about TouchDesigner keyboard or accessibility behavior.
- None of these sources validates this proposal's synchronization or edit-application policy; that requires prototype testing.

## What navigation and keyboard paths should the proposal provide?

### Takeaway
Nested scope needs both a visible path and a reliable way back. Keyboard actions should have visible equivalents and preserve normal text-field behavior.

### Cited Findings
- Houdini supports entering a network with double-click, I or Enter; leaving through its path or U; selecting upstream/downstream nodes with Page Up/Down; framing all/selected nodes; and browser-like location history. Its quickmarks retain path, position and zoom. [Network navigation](https://www.sidefx.com/docs/houdini/network/navigate.html)
- Houdini's asset-creation documentation cautions that deep mouse submenus can be difficult and notes the practice of typing names in the Tab menu. [Creating digital assets](https://www.sidefx.com/docs/houdini/assets/create.html)

### Inferences
- Show clickable breadcrumbs, an explicit back button and a persistent scope title in all three representations. Restore selection and view position when returning.
- Provide searchable creation, keyboard selection, Enter to inspect, an explicit return shortcut, and a shortcut sheet. Prefer standard Tab focus movement in the HTML proposal over stealing Tab for a canvas action.
- A list view can provide an ordered traversal of the same program for people who dislike spatial navigation; it should show arguments, result types and dependencies rather than being only a node-name index.
- Keep global single-letter shortcuts inactive in text inputs. Expose ordinary HTML buttons and labeled form controls with visible focus indicators; graph interactions need keyboard alternatives.

### Gaps
- Product shortcut documentation does not prove screen-reader access, focus management or WCAG compliance. Accessibility recommendations above are design requirements to verify in the prototype, not claims about the cited products.
- Current Blender pages could not be fetched (402); the older primary-source search extraction was sufficient only for the narrow grouping precedent cited above.
