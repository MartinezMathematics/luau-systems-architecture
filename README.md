# Luau Systems & Real-Time Engine Architecture

This repository contains modular systems, networking abstractions, and spatial calculation modules engineered in **Luau** for the **Roblox Engine**. The code demonstrates real-time client-server replication, authoritative state management, 3D vector mathematics, and memory-conscious game logic.

---

## Architectural Overview

Real-time multiplayer environments present unique constraints around network latency, untrusted client inputs, and strict frame-time budgets (16.6ms for 60 FPS). These modules decouple core logic into distinct domains:

[ Client Input / UI ]
│
▼ (RemoteEvent / Packed Payload)
[ NetworkReplicator ] ── (Server-Side Validation)
│
▼
[ Core State Machine ] ──► [ Spatial / Physics Math ]


---

## Code Modules

| Module | Location | Primary Responsibilities | Key Concepts |
|---|---|---|---|
| **NetworkReplicator** | `src/network/` | Serializes data packets, manages RemoteEvent rate limiting, and synchronizes state between client and server. | Client-server boundary, authoritative state, debounce throttling |
| **SpatialRaycaster** | `src/physics/` | Executes 3D raycast queries, normal vector reflections, and trajectory projections. | Vector3 math, dot products, spatial collision filtering |
| **StateMachine** | `src/core/` | Manages entity lifecycles, state transitions (idle, active, cooldown), and memory cleanup. | State pattern, event disconnects, memory leak mitigation |

---

## Engineering Highlights

### 1. Authoritative Server Validation & Network Optimization
* **Untrusted Clients:** The client never dictates authoritative state (e.g., health, currency, positional confirmation). The server processes intent, validates boundary conditions, and broadcasts state updates to listening clients.
* **Packet Throttling:** Implements debounce timers and payload filtering to prevent network buffer saturation across high-frequency RemoteEvents.

### 2. Applied 3D Vector Mathematics
* Uses spatial vector operations (`Vector3:Dot()`, `Vector3:Cross()`) for directional calculations, line-of-sight verification, and surface orientation.
* Implements whitelist/blacklist filtering on spatial raycasts to minimize physics engine overhead during multi-entity queries.

### 3. Memory Lifecycle & Frame-Rate Stability
* **Connection Hygiene:** Rigorously disconnects `RBXScriptConnection` events upon entity destruction to eliminate memory leaks and dangling references.
* **Garbage Collection Overhead:** Reuses data tables and caches frequent variables to minimize memory churn and avoid garbage collector spikes during intensive gameplay loops.

---

## Language & Environment

* **Language:** Luau (Gradually typed, fast embeddable Lua engine derivative)
* **Target Engine:** Roblox Engine
* **Development Environment:** Visual Studio Code / Roblox Studio
* **Paradigms:** Event-driven architecture, modular OOP/procedural
