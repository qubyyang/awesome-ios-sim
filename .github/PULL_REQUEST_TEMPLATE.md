## Summary

Describe the user-visible or internal change.

## Safety and compatibility

- Does this add or change a mutating operation?
- Is state readback exact, best-effort, or unsupported?
- Does it change the profile schema, CLI output, or MCP wire behavior?
- Does it change the DSH bundle manifest, Cordis patch, or Harness compatibility baseline?
- Does it use only public Apple tooling?

## Verification

- [ ] `swift build`
- [ ] `swift test`
- [ ] Offline example plan still succeeds
- [ ] English and Chinese README files are updated when behavior changes
- [ ] `npm test` and `npm run pack:check` pass for DSH plugin changes
- [ ] Schema and examples are updated when profile fields change
