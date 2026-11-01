# Multiple slots: discovery and routing

**English** | [简体中文](MULTI_SLOT.zh-CN.md)

## Findings

Before 1.3.15, the app and transport defaulted to logical slot 2. The app did not expose a slot selector even though the transport already distinguished logical and hardware slot IDs. Moving the removable eUICC to another position therefore left the app opening the management AID on the wrong card.

The read-only investigation after a card-position swap found these SimInfo entries on the tested device:

| Logical ID | Hardware ID | Observation |
|---|---|---|
| 0 | 3 | Unassigned node; not a selectable card slot. |
| 1 | 1 | eUICC management reads succeeded. |
| 2 | 2 | SIM reported ready, but the eUICC management application could not be opened. |

These values are observations, not routing constants. The extra unassigned node explains why rejecting the entire vector on logical ID 0 was incorrect. Conversely, exposing it as a third physical card would also be incorrect. A modem-ready SIM is not necessarily an eUICC; a not-ready SIM can still support the direct management path.

## Use

Open **Card slots** at the top left of Profiles. The menu lists assigned logical IDs discovered at runtime. These IDs are not a universal naming convention for the two sides of a SIM tray.

- **Automatic detection** performs read-only card discovery. It prefers the last successfully read EID wherever it is found. Without a matching remembered EID, one readable eUICC can be selected automatically; multiple readable eUICCs require explicit selection.
- Selecting a numbered slot reads only that slot. Failure does not redirect a profile operation to another card. Selecting an ordinary or unavailable SIM clears the previous profile list and disables download/scan entry points until a readable eUICC is selected.
- Slot switching changes the app's management target; it does not enable/disable profiles or change cellular routing. The selected mode persists between launches.

## Implementation

`availableSlots` in [Apdu.mm](../tweak/Apdu.mm) enumerates borrowed `ControllerView` / `SimInfoView` objects from [RuntimeObjects.hpp](../tweak/RuntimeObjects.hpp). These views use runtime-discovered offsets and a checked `MemoryReader` to copy typed field snapshots; container bounds and shared-pointer entry traversal are handled separately. [SlotRouting.hpp](../tweak/SlotRouting.hpp) excludes unassigned logical IDs, rejects ambiguous logical/hardware mappings and sorts assigned slots. `filterAndValidateAssignedSlots` returns `optional<vector<Slot>>`: `nullopt` indicates an invalid mapping, while an empty vector means no assigned slots. Assigned inactive slots remain visible. There is no fixed “slot 1 and slot 2 only” selector list; the current driver adapter still validates its hardware enum range.

The `slots` IPC operation reports `logicalSlot`, `hardwareSlot` and `simReady`, without opening a channel or sending APDUs. `open` accepts an assigned logical ID, maps it to the current hardware ID, and returns both IDs alongside the channel. The sender receives the logical ID; driver calls and response matching receive the hardware ID. See the [IPC protocol](IPC.md).

Each [SHLPA](../viewer/LPAEngine.h) instance has an immutable slot. A successful initial read binds its EID; subsequent channel openings check that identity before continuing. A fresh Profiles refresh uses a new engine, while existing settings/notification/signal pages keep their previous engine. All engines share one serial operation queue; the transport retains only one management session at a time.

Profile action confirmations retain the original slot/EID context. QR/image/manual input also retains the intended EID and rejects a stale context after card changes. Download confirmation names the slot and EID suffix. Unbound downloads are refused. The EID check occurs at channel opening; it is not an atomic guarantee against physical removal during an in-progress operation.

## Verification

- `tests/test_slot_routing.cpp`, included in the offline ASan/UBSan checks: reserved node filtering, non-1/2 logical IDs, reordered hardware mappings, inactive slots and ambiguity rejection.
- Native `--error-check`: independent slot/EID contexts, the shared queue and refusal of an unbound download before card/network requests.
- On the tested phone: assigned slots were enumerated, explicit reads of the eUICC succeeded, an explicit ordinary-SIM selection failed without fallback, and automatic discovery found the moved eUICC.
- UI checks: slot 1 → slot 2 → automatic, clearing stale profiles, disabling unavailable-card actions, preserving an old engine's slot, rejecting a mismatched EID, and preserving the profile baseline. Activation-input checks cover a valid bound confirmation and rejection of a stale EID.

No download, deletion or profile switch was performed for these tests. Two simultaneous eUICC cards, physical removal during a write, and every modem/firmware layout have not been validated.

Read-only native diagnostics:

```sh
/path/to/ESTKLog --slots-check
/path/to/ESTKLog --snapshot-check --slot=1
/path/to/ESTKLog --snapshot-check --slot=2
/path/to/ESTKLog --snapshot-check
```

`--slots-check` reads each assigned slot and reports whether it is readable as an eUICC. A snapshot without an explicit slot selects the first readable eUICC for this diagnostic command; interactive app automatic selection additionally uses the remembered EID and ambiguity handling. CLI write/restore tests require an explicit `--slot=N`; saved switch baselines must match the card EID and slot. Diagnostic output may include card identifiers and belongs in private research records.
