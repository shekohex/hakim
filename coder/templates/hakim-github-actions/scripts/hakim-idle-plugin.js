import { existsSync, readFileSync } from "node:fs"
import { join } from "node:path"
import { spawnSync } from "node:child_process"

const SERVICE = "hakim-idle-plugin"

function run(command, args, options = {}) {
  const result = spawnSync(command, args, {
    encoding: "utf8",
    stdio: ["ignore", "pipe", "pipe"],
    ...options,
  })

  return {
    ok: result.status === 0,
    stdout: (result.stdout ?? "").trim(),
    stderr: (result.stderr ?? "").trim(),
  }
}

async function log(client, level, message, extra = {}) {
  await client.app.log({
    body: {
      service: SERVICE,
      level,
      message,
      extra,
    },
  })
}

function unwrap(response) {
  return response && typeof response === "object" && "data" in response ? response.data : response
}

function repoMetadataFile() {
  return process.env.HAKIM_REPO_METADATA_FILE || join(process.env.HOME || "/home/coder", ".local/share/hakim/repo.json")
}

function resolveRepoRoot(worktree) {
  const candidates = []

  if (worktree) candidates.push(worktree)
  if (process.env.HAKIM_PROJECT_DIR) candidates.push(process.env.HAKIM_PROJECT_DIR)

  const metadataPath = repoMetadataFile()
  if (existsSync(metadataPath)) {
    try {
      const metadata = JSON.parse(readFileSync(metadataPath, "utf8"))
      if (metadata.repo_dir) candidates.push(metadata.repo_dir)
    } catch {
    }
  }

  for (const candidate of candidates) {
    const resolved = run("git", ["-C", candidate, "rev-parse", "--show-toplevel"])
    if (resolved.ok && resolved.stdout) return resolved.stdout
  }

  return ""
}

function hasDirtyTree(repoRoot) {
  return run("git", ["-C", repoRoot, "status", "--porcelain", "--untracked-files=all"]).stdout !== ""
}

export const HakimIdlePlugin = async ({ client, worktree }) => {
  const sessionParents = new Map()
  const sessionAgents = new Map()

  async function resolvePromptTarget(sessionID) {
    let targetSessionID = sessionID

    if (sessionParents.has(sessionID)) {
      targetSessionID = sessionParents.get(sessionID) || sessionID
    } else {
      try {
        const session = unwrap(await client.session.get({ path: { id: sessionID } }))
        if (session?.parentID) {
          sessionParents.set(sessionID, session.parentID)
          targetSessionID = session.parentID
        }
      } catch {
      }
    }

    return {
      sessionID: targetSessionID,
      agent: sessionAgents.get(targetSessionID) || sessionAgents.get(sessionID),
    }
  }

  return {
    event: async ({ event }) => {
      if (event.type === "session.created" || event.type === "session.updated") {
        if (event.properties?.info?.parentID) {
          sessionParents.set(event.properties.info.id, event.properties.info.parentID)
        }
        return
      }

      if (event.type === "message.updated") {
        const info = event.properties?.info
        if (info?.role === "user" && typeof info.agent === "string" && info.agent !== "") {
          sessionAgents.set(info.sessionID, info.agent)
        }
        return
      }

      if (event.type !== "session.idle") return
      if (!["1", "true", "yes"].includes((process.env.HAKIM_AUTO_YIELD_ON_IDLE || "").toLowerCase())) return

      const repoRoot = resolveRepoRoot(worktree)
      if (!repoRoot) {
        await log(client, "info", "No repository detected for idle stop; leaving workspace running")
        return
      }

      if (hasDirtyTree(repoRoot)) {
        await log(client, "warn", "Repository is dirty; asking the agent to continue and clean it up", { repoRoot })
        if (event.properties?.sessionID) {
          const target = await resolvePromptTarget(event.properties.sessionID)
          await client.session.promptAsync({
            path: { id: target.sessionID },
            body: {
              ...(target.agent ? { agent: target.agent } : {}),
              parts: [
                {
                  type: "text",
                  text: `The repository at ${repoRoot} is not clean yet. Continue working until the worktree is clean, then stop the workspace with hakim stop or hakim yield. Do not stop the workspace now.`,
                },
              ],
            },
          })
        }
        throw new Error(`hakim idle stop blocked: repository is dirty at ${repoRoot}`)
      }

      const stopResult = run("hakim", ["stop"], { env: process.env })
      if (!stopResult.ok) {
        await log(client, "error", "Failed to stop workspace after idle session", {
          repoRoot,
          stderr: stopResult.stderr || stopResult.stdout,
        })
        throw new Error(stopResult.stderr || stopResult.stdout || "hakim stop failed")
      }

      await log(client, "info", "Workspace idle and repository clean; stopping workspace", { repoRoot })
    },
  }
}
