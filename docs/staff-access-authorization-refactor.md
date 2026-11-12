# Centralize staff access authorization

**Status** — Planned

Mark this story `Completed` only after all acceptance criteria and accompanying unit tests are implemented and verified.

## Goal

Keep staff role and location-assignment changes behind server operations that consistently enforce authorization, organization boundaries, and transactional guarantees.

## User story

As an organization administrator, I want staff role and location changes to be authorized by the server so access rules are enforced consistently wherever those operations are called.

## Scope

- Require an authenticated actor and verify active administrator membership in the target organization.
- Keep membership updates and assignment replacement inside one database transaction. A failed operation must roll back all changes.
- Preserve these invariants:
  - Only an active administrator of the membership's organization can make the change.
  - Every operator location belongs to that same organization.
  - An operator retains at least one location assignment.
  - An administrator receives organization-wide access and has no individual location assignments.
  - The last active administrator cannot be demoted.
  - A suspended membership stays suspended when its role or assignments are edited.
- Return authorization failures without disclosing memberships or locations outside the administrator's organization.

## Out of scope

- Changing the staff access form or its successful behavior.
- Refactoring invitation acceptance, membership suspension/restoration, bootstrap provisioning, queue authorization, or unrelated access checks.
- Adding new roles, audit requirements, or staff-access features.
- Moving aggregate invariants such as “last active administrator” outside the transaction and concurrency protection.

## Acceptance criteria

- An organization administrator can change a member between administrator and operator and replace operator location assignments with the expected results.
- An operator or non-member cannot perform these actions, including by calling server operations directly.
- An assignment to a location in another organization is rejected; submitting no locations for an operator is rejected.
- Changing a member to administrator removes individual location assignments, and changing an administrator to operator grants only the submitted locations.
- An operation failure leaves both the membership and all location assignments unchanged.
- A suspended membership remains suspended after its role or assignments are edited.
- Concurrent role changes cannot leave an organization without an active administrator.
- The web form continues to show clear errors for invalid assignments and a success message after a committed update.

## Implementation outline

1. Put active administrator and organization-scope checks at the server operation boundary.
2. Replace direct assignment replacement with explicit authorized operations where appropriate.
3. Keep the actor, transaction, and lock ordering consistent across membership and assignment changes.
4. Add focused tests for cross-organization access, operator restrictions, assignment replacement, rollback, and concurrent last-administrator changes.

Keep this work focused on the OLA-9 access update flow. Leave unrelated authorization paths for their own stories.
