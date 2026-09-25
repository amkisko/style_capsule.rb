# RFC 0001: RFC process

- Feature Name: rfc-process
- Type: Procedural
- Status: Proposed
- Created: 2026-09-25
- Author: Andrei Makarov
- Stakeholders: project maintainers
- Feedback until: 2026-10-09

## Summary

This RFC defines how style_capsule design changes are proposed, written, numbered, and advanced.

## Motivation

Attribute scoping, the component DSL, stylesheet registry registration, head injection, and cache strategies are the public contract. Hosts encode those names in components, layouts, and asset pipelines. Numbered RFCs are the unit for a change that would move the gem version for every host that included the modules. RFC 0002 records why attribute-based encapsulation lives in one gem across Phlex, ViewComponent, and ERB.

## Guide-level explanation

Claim `ids/NNNN` with one line: the kebab slug, or `reserved` then the slug. Copy `0000-template.md`, delete the optional-header instruction, fill the sections that apply, omit unused header fields and empty sections, and open `rfc: NNNN short title`. Two pull requests that add the same `ids/NNNN` path conflict in git. Discussion is the pull request. Stakeholders are maintainers plus owners of the touched area. The default clock is two weeks of lazy consensus.

After merge, implementation PRs cite the RFC number.

An RFC proposes a design: suggestion, motivation, specification, effects, alternatives, and prior art. Version numbers belong in changelogs. Implementation notes stay optional evidence. Shipped behavior is already accepted, so an RFC that specifies already-shipped design is Stable on merge. Experimental means the design is not yet the product contract. Proposed means a change is under review. The two-week clock applies to Proposed changes.

Trivial exemption: a bug fix that restores documented behavior, a typo, or a refactor that does not change bytes a user can observe.

## Reference-level explanation

### Citations

Isolation is off. RFCs MAY name repository paths a reviewer can open. Prefer another RFC for design cross-references.

### Header

Required: Type, Status, Created, Author. The title is the H1.

Optional, omit unused: Feature Name, Describes, Stakeholders, Feedback until, Relates, Requires, Supersedes.

Describes is optional and historical. New RFCs omit it. The RFC subject is the design. Stakeholders and Feedback until belong on Proposed RFCs.

### Shape

Required sections: Summary, Motivation, Guide-level explanation, Unresolved questions. Summary is one paragraph: the suggestion. Product RFCs also fill Reference-level explanation (the specification), Drawbacks (effects), Rationale and alternatives, and Prior art. Implementation notes are optional. Omit unused sections.

### Length

Prefer under 150 lines. Split a second RFC when a file grows past that because it has two concerns. Do not pad.

### Prose

State the fact, delete fence tags that only block a misreading, and open with the claim. Keep agency on the person who acts. Prefer commas and full stops over em dashes. Refuse sales language and punchline stacks of one-clause sentences.

### Claims

A checkable statement MUST name a command, field, fail mode, fixture, schema, or test a reviewer can open. Mark inference. Implementation paths are optional evidence.

### Types, statuses, running code

Types and statuses are listed in `rfcs/README.md`. Standards Track RFCs SHOULD show running code or fixtures before Stable. An RFC that specifies already-shipped design MUST be Stable; writing the RFC later does not reopen the feature.

### Number assignment

The author claims a number by adding `ids/NNNN`. Two in-flight pull requests that pick the same number both add that path, so git shows an add/add conflict. After a conflict, the later change takes a free id and updates the draft filename.

## Implementation notes

Shared process text and the `0000` template come from the `amkisko/rfc-process` prayer (`~> 1.2` in `Prayfile`). Project bands, isolation, and the current set live in this repository's `rfcs/README.md`.

## Drawbacks

Authors pay process overhead. The trivial exemption and Stable status for already-shipped design keep that cost down.

## Rationale and alternatives

`docs/` timestamp trees record decisions. RFCs are the public, numbered discussion unit. Importing the Rust RFC template unchanged would drop type and status. Importing XEPs unchanged would invent Council and Board roles this project does not have.

## Prior art

Rust RFC template; Mozilla Android RFC stakeholders and feedback window; XEP-0001 types and Experimental to Final; `amkisko/rfc-process`; kiskolabs/pray RFC 0001.

## Unresolved questions

Whether this repo will add an automated id checker, or keep git add/add conflicts as the only reservation signal.
