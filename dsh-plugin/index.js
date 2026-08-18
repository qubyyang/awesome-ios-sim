import { existsSync } from 'node:fs'
import { dirname, isAbsolute, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import Schema from '@deepseek-ai/schemastery'

export const name = 'awesome-ios-sim-runtime'

export const serviceName = 'awesomeIOSSimRuntime'

export const Config = Schema.object({
  executablePath: Schema.string()
    .default('')
    .description('Optional ios-sim-state-mcp executable path or command; bypasses Swift Package Manager.'),
  swiftCommand: Schema.string()
    .default('swift')
    .description('Swift executable used when no prebuilt MCP executable is available.'),
  packagePath: Schema.string()
    .default('')
    .description('Optional Swift package directory. Relative paths resolve from the DSH workspace.'),
  buildConfiguration: Schema.union(['debug', 'release'])
    .default('release')
    .description('Swift build configuration used by swift run.'),
  preferPrebuilt: Schema.boolean()
    .default(true)
    .description('Use .build/<configuration>/ios-sim-state-mcp when it already exists.'),
  serverName: Schema.string()
    .pattern(/^[A-Za-z0-9_-]{1,32}$/)
    .default('ios_sim')
    .description('Stable DSH namespace for the bridged MCP tools.'),
  toolCallTimeoutMs: Schema.number()
    .min(1)
    .max(2_147_483_647)
    .default(60_000)
    .description('Timeout for each simulator MCP tool call.'),
})

const bundledPackageRoot = resolve(dirname(fileURLToPath(import.meta.url)), '..')

function nonEmpty(value, fallback) {
  return typeof value === 'string' && value.trim() ? value.trim() : fallback
}

function resolvePackagePath(configuredPath, cwd, fallback) {
  const value = nonEmpty(configuredPath, fallback)
  return isAbsolute(value) ? value : resolve(cwd, value)
}

/**
 * Resolve the child process passed to DSH's generic MCP client.
 *
 * The dependency-injected environment keeps this function deterministic in
 * tests without changing the runtime contract used by Cordis.
 */
export function resolveMcpLaunch(config = {}, environment = {}) {
  const cwd = environment.cwd ?? process.cwd()
  const packageRoot = environment.packageRoot ?? bundledPackageRoot
  const fileExists = environment.fileExists ?? existsSync
  const buildConfiguration = config.buildConfiguration === 'debug' ? 'debug' : 'release'
  const toolCallTimeoutMs = Number.isFinite(config.toolCallTimeoutMs)
    ? config.toolCallTimeoutMs
    : 60_000
  const base = {
    cwd,
    serverName: nonEmpty(config.serverName, 'ios_sim'),
    toolCallTimeoutMs,
  }

  const explicitExecutable = nonEmpty(config.executablePath, '')
  if (explicitExecutable) {
    return { ...base, command: explicitExecutable, args: [] }
  }

  const resolvedPackagePath = resolvePackagePath(config.packagePath, cwd, packageRoot)
  const prebuiltExecutable = join(
    resolvedPackagePath,
    '.build',
    buildConfiguration,
    'ios-sim-state-mcp',
  )

  if (config.preferPrebuilt !== false && fileExists(prebuiltExecutable)) {
    return { ...base, command: prebuiltExecutable, args: [] }
  }

  return {
    ...base,
    command: nonEmpty(config.swiftCommand, 'swift'),
    args: [
      'run',
      '--package-path',
      resolvedPackagePath,
      '-c',
      buildConfiguration,
      '--quiet',
      'ios-sim-state-mcp',
    ],
  }
}

export function apply(ctx, config) {
  const launch = resolveMcpLaunch(config)
  ctx.provide(serviceName, launch)
}

