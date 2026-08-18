# Security policy

## Supported versions

The project is pre-1.0. Security fixes are applied to the latest release and the `main` branch.

## Reporting a vulnerability

Please do not open a public issue for a suspected vulnerability. Use GitHub's **Report a vulnerability**
feature in the Security tab of this repository. Include:

- affected version or commit;
- a minimal reproduction;
- the expected and actual safety boundary;
- impact, especially whether confirmation can be bypassed or arbitrary host commands/files are involved.

Maintainers will acknowledge a complete report as soon as practical and coordinate disclosure after a fix is
available.

## Security boundaries

- This tool intentionally controls local simulators and can erase simulator data after explicit confirmation.
- It does not sandbox `simctl`; confirmed operations run with the invoking user's permissions.
- App `sourcePath` values are passed to `simctl install`; review them before confirmation.
- Plans and MCP tool arguments are untrusted input and should not be auto-confirmed.
- The project does not invoke a shell or load private CoreSimulator frameworks.
- The DSH bundle starts the configured MCP command as trusted host code outside the agent workspace sandbox;
  install only trusted revisions and pin a tag or commit in managed environments.

Reports about expected, explicitly confirmed simulator changes without a boundary bypass are not security
vulnerabilities, though reliability bugs are welcome in the public issue tracker.
