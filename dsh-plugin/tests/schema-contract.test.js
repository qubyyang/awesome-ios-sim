import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import Ajv2020 from "ajv/dist/2020.js";

const schema = JSON.parse(
  await readFile(new URL("../../schemas/v1alpha1/simulator-state.schema.json", import.meta.url), "utf8"),
);
const example = JSON.parse(
  await readFile(new URL("../../Examples/ui-tests.profile.json", import.meta.url), "utf8"),
);

const ajv = new Ajv2020({ allErrors: true, strict: true });
const validate = ajv.compile(schema);

function clone(value) {
  return structuredClone(value);
}

test("published example satisfies the v1alpha1 JSON Schema", () => {
  assert.equal(validate(example), true, JSON.stringify(validate.errors));
});

test("schema rejects unknown safety-sensitive fields", () => {
  const candidates = [];

  const root = clone(example);
  root.typo = true;
  candidates.push(root);

  const spec = clone(example);
  spec.spec.eraseAfterApply = true;
  candidates.push(spec);

  const application = clone(example);
  application.spec.applications[0].launchArgument = "--unsafe";
  candidates.push(application);

  for (const candidate of candidates) {
    assert.equal(validate(candidate), false);
  }
});

test("schema rejects empty identifiers and invalid status bar overrides", () => {
  const candidates = [];

  const emptyName = clone(example);
  emptyName.metadata.name = "";
  candidates.push(emptyName);

  const emptyTarget = clone(example);
  emptyTarget.target.name = "";
  candidates.push(emptyTarget);

  const emptyStatusBar = clone(example);
  emptyStatusBar.spec.statusBar = {};
  candidates.push(emptyStatusBar);

  const invalidBattery = clone(example);
  invalidBattery.spec.statusBar.batteryLevel = 101;
  candidates.push(invalidBattery);

  const unknownOverride = clone(example);
  unknownOverride.spec.statusBar.bluetooth = true;
  candidates.push(unknownOverride);

  for (const candidate of candidates) {
    assert.equal(validate(candidate), false);
  }
});
