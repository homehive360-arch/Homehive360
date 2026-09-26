# Brunswick / Golden Isles Reference Hive

Status: DEMO / PROSPECTIVE — no company in this file is represented as a contracted Home Hive 360 member.

Purpose: canonical reference roster for product development, campaign demos, QA, and future Directory-to-Hive recruiting workflows.

## Initial Directory roster

| Category seat | Directory company | Market | Roster state |
| --- | --- | --- | --- |
| Roofing | Platinum Roofing | Brunswick, GA | Prospective |
| Electrical | Certified Electric, Inc | Brunswick, GA | Prospective |
| General Contractor | G Core Construction | Brunswick, GA | Prospective |
| Landscaping | Ground Effects Landscaping | Brunswick, GA | Prospective |
| Pool Service | Jeff's Pool and Spa Service | Brunswick, GA | Prospective |

Certified Electric may provide HVAC services, but this reference Hive assigns it only the Electrical category seat. HVAC remains an open category.

## Open recruiting seats

- HVAC
- Plumbing
- Pest Control
- House Cleaning
- Painting
- Handyman
- Pressure Washing
- Windows & Doors
- Garage Doors
- Flooring
- Restoration

## Demo-data rules

1. Real Directory business identities may be used for the prospective roster.
2. Customer counts, audience sizes, offers, campaign engagement, opportunities, jobs, and revenue must be explicitly labeled DEMO/SIMULATED unless supplied by the business.
3. Demo customers must never be mixed with production customer records.
4. A Directory listing does not imply Hive membership.
5. One primary category seat per business unless the Hive model explicitly changes.
6. Monthly campaigns promote the entire Hive; one active member receives the rotating Spotlight.
7. Customer databases remain source-business owned and are never exposed to other members.

## Target lifecycle

Directory Company -> Prospective Member -> Hive Invitation -> Accepted Member -> Category Seat -> Audience Connected -> Campaign Ready

## Reference campaign

The first campaign should exercise the full canonical flow:

Create Campaign -> Spotlight Selection -> Schedule -> Activate -> Freeze Audience -> Queue -> Deliver -> Hive Visit -> Offer Intent -> Opportunity -> Won Job -> Attributed Revenue

All campaign metrics for this reference campaign must render as DEMO DATA.


## Directory-to-Hive construction contract

The Brunswick reference Hive is the first fixture for a future operator workflow that converts Directory prospects into a Hive without treating prospects as members.

### Seat model

Each prospective roster entry should carry:
- directory company identity
- market
- primary category seat
- roster_state = prospective
- membership_state = not_invited | invited | accepted | declined
- audience_state = not_connected | connected
- campaign_state = not_ready | ready

A category seat is considered filled for planning when a prospective company is selected, but it is not an active Hive member until membership_state=accepted and the corresponding live membership is active.

### Readiness gates

Campaign readiness requires all of the following:
1. Membership accepted and active.
2. Source-owned customer audience connected.
3. At least one permitted campaign channel.
4. Required business/profile data present.
5. No category-seat conflict.

Prospective and invited companies must never contribute audience reach or appear in live campaign distribution metrics.

### Brunswick build-board

| Category | Candidate | Seat | Membership | Audience | Campaign |
| --- | --- | --- | --- | --- | --- |
| Roofing | Platinum Roofing | Selected | Not invited | Not connected | Not ready |
| Electrical | Certified Electric, Inc | Selected | Not invited | Not connected | Not ready |
| General Contractor | G Core Construction | Selected | Not invited | Not connected | Not ready |
| Landscaping | Ground Effects Landscaping | Selected | Not invited | Not connected | Not ready |
| Pool Service | Jeff's Pool and Spa Service | Selected | Not invited | Not connected | Not ready |
| HVAC | — | Open | — | — | — |
| Plumbing | — | Open | — | — | — |
| Pest Control | — | Open | — | — | — |
| House Cleaning | — | Open | — | — | — |
| Painting | — | Open | — | — | — |
| Handyman | — | Open | — | — | — |
| Pressure Washing | — | Open | — | — | — |
| Windows & Doors | — | Open | — | — | — |
| Garage Doors | — | Open | — | — | — |
| Flooring | — | Open | — | — | — |
| Restoration | — | Open | — | — | — |

### Operator UX target

Directory -> Filter market -> Select one candidate per category -> Build Hive -> Review open seats -> Send invitations -> Track acceptance -> Connect audiences -> Campaign Ready

The UI must visually distinguish Directory prospects, invited businesses, accepted members, and campaign-ready members. Selecting a Directory business is not consent to membership.
