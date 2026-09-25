# style_capsule RFCs

RFCs are the numbered place for design review and discussion. An RFC is the unit of change for the public contract. It proposes a design: suggestion, motivation, specification, effects, alternatives, and prior art. Version numbers belong in changelogs. Shipped design specified after the fact is Stable.

Shape follows the Rust RFC template: Summary, Motivation, Guide-level explanation, Reference-level explanation, Drawbacks, Rationale and alternatives, Prior art, Unresolved questions, Future possibilities. Type, status, and running-code rules come from XEP-0001. Stakeholders and a feedback window come from Mozilla Android RFCs. Omit empty sections.

Writing, length, and claim rules live in RFC 0001. Isolation (no markdown citations outside this directory) is off. RFCs MAY name repository paths. Prefer another RFC for design cross-references.

## Types

- Standards Track: a public API, CLI, file, or protocol contract implementations MUST follow
- Informational: description or analysis that does not by itself change the contract
- Historical: a shape that shipped before this process
- Procedural: how this project decides, numbers, and advances RFCs

## Statuses

- Draft: authoring; not yet listed as published
- Experimental: published design that is not yet the product contract
- Proposed: a change open for review toward Stable
- Stable: accepted. Behavior that already shipped is Stable when the RFC specifies it; writing the RFC later does not reopen the feature
- Final: deployed long enough that breaking changes need a new RFC
- Deferred, Rejected, Superseded, Obsolete

The two-week lazy-consensus clock applies to Proposed changes.

## Numbering

Sequential from 0001. 0000 is the template. Claim an unused id in `ids/NNNN` before writing `NNNN-slug.md`. The file holds one line: the slug, or `reserved` then the slug. Two pull requests that add the same `ids/NNNN` path conflict in git.

## Lifecycle

1. Claim `ids/NNNN`.
2. Copy `0000-template.md`. Omit unused header fields and empty sections.
3. Open `rfc: NNNN short title` from `plan/` or `feature/`.
4. Discuss until Summary, Motivation, and Unresolved questions are honest.
5. If the RFC specifies already-shipped design, mark Stable in the same PR. Otherwise mark Experimental, Proposed, Stable, Rejected, or Deferred.
6. Implementation PRs cite `RFC-NNNN`.

Trivial exemption: bugfixes, typos, and refactors that do not change user-facing contracts.

## Current set

Procedural: RFC 0001 (Proposed).

Informational: RFC 0002 (problem and positioning).

Standards Track, Stable: RFC 0003 (attribute scoping), RFC 0004 (component integrations), RFC 0005 (stylesheet registry and head injection), RFC 0006 (cache strategies and CSS file writer).

A public API, CLI, file, or protocol change needs a new Standards Track RFC.
