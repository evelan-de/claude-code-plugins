---
name: codebase-design
description: Shared vocabulary for designing deep modules. Use when the user wants to design or improve a module's interface, find deepening opportunities, decide where a seam goes, make code more testable or AI-navigable, or when another skill needs the deep-module vocabulary. Triggers on "deep module", "where does the seam go", "Modul-Schnittstelle entwerfen", "Seam festlegen".
---

# Codebase Design

Design **deep modules**: a lot of behaviour behind a small interface, placed at a clean seam, testable through that interface. Use this language wherever code is designed or restructured.

## Glossary

Use these terms exactly; don't substitute "component," "service," "API," or "boundary."

**Module**: anything with an interface and an implementation, at any scale: a function, class, package, or tier-spanning slice. _Avoid_: unit, component, service.

**Interface**: everything a caller must know to use the module correctly: the type signature, plus invariants, ordering constraints, error modes, required configuration, and performance characteristics. _Avoid_: API, signature (too narrow).

**Implementation**: what's inside a module. Distinct from **Adapter**: a small adapter can have a large implementation (a Postgres repo) or a large adapter a small one (an in-memory fake). Say "adapter" when the seam is the topic, "implementation" otherwise.

**Depth**: leverage at the interface: how much behaviour a caller (or test) can exercise per unit of interface they have to learn. **Deep** = small interface, lots of behaviour. **Shallow** = interface nearly as complex as the implementation.

**Seam** _(Michael Feathers)_: a place where you can alter behaviour without editing in that place; the location at which a module's interface lives. Where to put the seam is its own design decision. _Avoid_: boundary (overloaded with DDD's bounded context).

**Adapter**: a concrete thing that satisfies an interface at a seam. Describes role (what slot it fills), not substance.

**Leverage**: what callers get from depth: more capability per unit of interface learned. One implementation pays back across N call sites and M tests.

**Locality**: what maintainers get from depth: change, bugs, knowledge and verification concentrate in one place. Fix once, fixed everywhere.

## Principles

- **Depth is a property of the interface, not the implementation.** A deep module can be internally composed of small, swappable parts; they just aren't part of the interface. A module can have **internal seams** (private, used by its own tests) as well as the **external seam** at its interface.
- **The deletion test.** Imagine deleting the module. If complexity vanishes, it was a pass-through. If complexity reappears across N callers, it was earning its keep.
- **The interface is the test surface.** Callers and tests cross the same seam. If you want to test past the interface, the module is probably the wrong shape.
- **One adapter means a hypothetical seam. Two adapters means a real one.** Don't introduce a seam unless something varies across it.
- **When designing an interface, ask:** can I reduce the number of methods, simplify the parameters, hide more complexity inside? Accept dependencies rather than creating them; return results rather than producing side effects.

## Going deeper

- **Deepening a cluster given its dependencies**: [DEEPENING.md](DEEPENING.md): dependency categories, seam discipline, replace-don't-layer testing.
- **Exploring alternative interfaces**: [DESIGN-IT-TWICE.md](DESIGN-IT-TWICE.md): parallel sub-agents design the interface several different ways, compared on depth, locality and seam placement.
