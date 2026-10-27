# Minimal Weblate teams setup

## Applied configuration

At the user's request, Weblate now has exactly one team, **Translators** (ID 19), managed globally:

- Roles: Translate and Manage glossary.
- Project selection: explicitly Eden Flowers only.
- Language selection: explicitly Finnish and Swedish only.
- No members yet; the administrator will add the two translators.

David remains an active instance superuser and needs no team membership. The project remains private, with translation review disabled. All settings were verified by authenticated API reads after the changes.

The previous project-scoped Translators team and all other global/project teams were deleted at the user's request. A pre-cleanup team and membership configuration snapshot is stored locally at `tmp/weblate-teams-before-cleanup-20261027-135917.json`.

The installed API rejects clearing a team's `defining_project`, so conversion required creating the global team, copying its scope and roles, checking memberships, then deleting the old team. The built-in Translate team also rejects renaming and language-selection changes.

## Maintenance caveats

Weblate's default team initialization creates standard teams and automatic Users/Viewers assignment rules. Default teams may therefore reappear during migrations/upgrades; project settings changes may also recreate project defaults. Do not assume deleting defaults permanently changes Weblate's initialization behavior.

The Translate role includes offline upload/overwrite permissions. It does not grant project administration, source editing, repository management, bulk editing, or automatic translation.

## Sources

Live authenticated API endpoints:

- https://weblate.edenflowers.fi/api/groups/
- https://weblate.edenflowers.fi/api/roles/
- https://weblate.edenflowers.fi/api/users/
- https://weblate.edenflowers.fi/api/projects/edenflowers/

Official documentation and source:

- https://docs.weblate.org/en/latest/admin/access.html
- https://github.com/WeblateOrg/weblate/blob/main/weblate/auth/models.py (`create_groups`, automatic assignment and project setup).
- https://github.com/WeblateOrg/weblate/blob/main/weblate/api/views.py (`GroupViewSet`).

Upstream source can differ from the installed version; the verified configuration above describes the live instance.
