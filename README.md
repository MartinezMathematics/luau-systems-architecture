# Luau Systems & Real-Time Engine Architecture

This repository showcases modular full-stack game architecture, client-side kinematics, authoritative server validation, and applied spatial mathematics engineered in **Luau** for the **Roblox Engine**. 

The codebase illustrates real-time client-server synchronization, procedural motion controllers, and programmatic geometry generation under strict 60 FPS frame-time budgets.

---

## Architectural Breakdown

[ Client Input / Kinematics ]
│  (CombatMovementController.luau)
▼
[ RemoteEvent Dispatch ]
│  (Damage, Knockbacked, BlockEvent, TransformEvent)
▼
[ Authoritative Server ] ──► [ Environmental Geometry / Raycasting ]
(ServerCombatService.luau)      (EnvironmentalFXService.luau)


---

## Core Modules

| Module | Scope | Location | Primary Responsibilities |
|---|---|---|---|
| **CombatMovementController** | Client | `src/client/CombatMovementController.luau` | Real-time locomotion state machine, procedural torso tilt, spherecast hit detection, and normalized speed fraction mapping. |
| **ServerCombatService** | Server | `src/server/ServerCombatService.luau` | Authoritative health validation, horizontal vector alignment, `BodyVelocity` impulse physics, and network tag management. |
| **EnvironmentalFXService** | Server | `src/server/EnvironmentalFXService.luau` | Multi-ring polar coordinate geometry generation ($x = r\cos\theta$, $z = r\sin\theta$), vertical surface normal sampling, and dynamic tween interpolation. |

---

## Engineering Highlights

### 1. Procedural Kinematics & Applied Vector Math
* **Object-Space Projection:** Projects world movement vectors into local coordinate space (`root.CFrame:VectorToObjectSpace`) to dynamically interpolate physical torso lean via frame-rate-independent slerp/lerp formulas.
* **Directional Flanking Detection:** Calculates vector dot products between target facing vectors and instigator position vectors to mathematically confirm rear attacks and bypass directional blocking tags:
  $$\text{isBehind} = (\vec{u}_{\text{look}} \cdot \hat{v}_{\text{toPlayer}}) < 0$$
* **Hybrid Spatial Queries:** Combines directional `workspace:Spherecast` sweeps with radial bounds testing (`GetPartBoundsInRadius`) to eliminate collision tunneling during high-velocity player states.

### 2. Parametric Surface & Geometry Generation
* **Polar-to-Cartesian Mapping:** Generates concentric environmental debris rings by iterating through discrete angular subdivisions across multi-tiered radial shells:
  $$x = (r + \Delta x) \cos(\theta), \quad z = (r + \Delta z) \sin(\theta)$$
* **Downward Surface Raycasting:** Sweeps vertical rays from elevation offsets down to terrain to sample dynamic ground heights, matching debris orientation and color palettes to underlying floor instances.

### 3. Client Prediction & Authoritative Server Verification
* **Zero-Latency Feel:** Client executes local predictive animation and particle emissions immediately upon input.
* **Server Authority:** Crucial state mutations (damage application, physics impulses, stun cooldowns, and `KnockedBack`/`Blocking` tag propagation) remain strictly isolated to server routines, preventing client state manipulation.

---

## Technical Specifications

* **Language:** Luau (Gradually typed Lua derivative)
* **Target Engine:** Roblox Engine
* **Math Concepts:** 3D Vector Math, Dot Products, Polar Coordinates, Numerical State Interpolation
* **Paradigms:** Event-Driven Architecture, Client-Server Authorit
