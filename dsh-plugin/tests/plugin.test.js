import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import { join } from 'node:path'
import test from 'node:test'
import { fileURLToPath } from 'node:url'
import { apply, resolveMcpLaunch, serviceName } from '../index.js'

const repositoryRoot = fileURLToPath(new URL('../..', import.meta.url))

test('package manifest declares an installable DSH bundle', async () => {
  const manifest = JSON.parse(await readFile(join(repositoryRoot, 'package.json'), 'utf8'))

  assert.equal(manifest.name, '@qubyyang/awesome-ios-sim')
  assert.equal(manifest.dsh.bundle.patch, './cordis.patch.yml')
  assert.equal(manifest.exports['./dsh-plugin'], './dsh-plugin/index.js')
  assert.ok(manifest.keywords.includes('dsh-plugin'))
  assert.deepEqual(manifest.os, ['darwin'])
})

test('bundle inserts the runtime provider and DSH MCP client', async () => {
  const patch = await readFile(join(repositoryRoot, 'cordis.patch.yml'), 'utf8')

  assert.match(patch, /name: '@qubyyang\/awesome-ios-sim\/dsh-plugin'/)
  assert.match(patch, /name: '@deepseek-ai\/dsh-mcp-client'/)
  assert.match(patch, /inject: \[awesomeIOSSimRuntime\]/)
  assert.match(patch, /failOnStartupError: true/)
})

test('explicit executable bypasses Swift Package Manager', () => {
  const launch = resolveMcpLaunch(
    {
      executablePath: '/opt/awesome-ios-sim/ios-sim-state-mcp',
      serverName: 'simulators',
      toolCallTimeoutMs: 90_000,
    },
    { cwd: '/workspace', packageRoot: '/package', fileExists: () => false },
  )

  assert.deepEqual(launch, {
    command: '/opt/awesome-ios-sim/ios-sim-state-mcp',
    args: [],
    cwd: '/workspace',
    serverName: 'simulators',
    toolCallTimeoutMs: 90_000,
  })
})

test('existing package-local release binary is preferred', () => {
  const launch = resolveMcpLaunch(
    { buildConfiguration: 'release', preferPrebuilt: true },
    {
      cwd: '/workspace',
      packageRoot: '/package',
      fileExists: (path) => path === '/package/.build/release/ios-sim-state-mcp',
    },
  )

  assert.equal(launch.command, '/package/.build/release/ios-sim-state-mcp')
  assert.deepEqual(launch.args, [])
})

test('source checkout falls back to a shell-free swift run argument vector', () => {
  const launch = resolveMcpLaunch(
    {
      swiftCommand: '/usr/bin/swift',
      packagePath: '../awesome-ios-sim',
      buildConfiguration: 'debug',
      preferPrebuilt: false,
    },
    { cwd: '/workspace/app', packageRoot: '/package', fileExists: () => false },
  )

  assert.equal(launch.command, '/usr/bin/swift')
  assert.deepEqual(launch.args, [
    'run',
    '--package-path',
    '/workspace/awesome-ios-sim',
    '-c',
    'debug',
    '--quiet',
    'ios-sim-state-mcp',
  ])
})

test('Cordis apply provides the resolved runtime service', () => {
  let provided
  apply(
    { provide: (key, value) => { provided = { key, value } } },
    { executablePath: 'ios-sim-state-mcp' },
  )

  assert.equal(provided.key, serviceName)
  assert.equal(provided.value.command, 'ios-sim-state-mcp')
})

