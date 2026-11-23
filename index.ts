import { mkdirSync, readFileSync, renameSync, rmSync, writeFileSync } from 'node:fs';
import { basename, join } from 'node:path';
import type { ExtensionAPI } from '@earendil-works/pi-coding-agent';

type Child = { id: string; description?: string; type?: string; parentAgentId?: string; status?: string };
const ownerKey = Symbol.for('pi-quickshell.owner');

export default function (pi: ExtensionAPI) {
  const registry = globalThis as typeof globalThis & { [ownerKey]?: object };
  const token = {};
  const directory = join(process.env.XDG_RUNTIME_DIR || `/run/user/${process.getuid!()}`, 'pi-quickshell');
  const file = join(directory, `${process.pid}.json`);
  const children = new Map<string, Child>();
  const questions = new Set<string>();
  const unsub: (() => void)[] = [];
  let start = '', project = '', state = 'idle', failed = false, prompts = 0;
  let lastFailure: Child | undefined;

  function publish() {
    if (registry[ownerKey] !== token) return;
    const nodes = new Map(children);
    if (lastFailure) nodes.set(lastFailure.id, lastFailure);
    const rows: { name: string; state: string; depth: number }[] = [];
    function visit(child: Child, depth: number) {
      rows.push({ name: child.description || child.type || child.id,
        state: child.status === 'error' ? 'error' : 'working', depth });
      for (const next of nodes.values()) if (next.parentAgentId === child.id) visit(next, depth + 1);
    }
    for (const child of nodes.values()) {
      if (!child.parentAgentId || !nodes.has(child.parentAgentId)) visit(child, 1);
    }
    const record = { start, name: pi.getSessionName() || project,
      state: prompts || questions.size ? 'asking' : state, children: rows };
    writeFileSync(file + '.tmp', JSON.stringify(record), { mode: 0o600 });
    renameSync(file + '.tmp', file);
  }

  pi.on('session_start', (_event, ctx) => {
    if (registry[ownerKey]) return;
    mkdirSync(directory, { recursive: true, mode: 0o700 });
    start = readFileSync('/proc/self/stat', 'utf8').split(/\) (?=[A-Z] )/).at(-1)!.split(' ')[19];
    project = basename(ctx.cwd) || ctx.cwd;
    registry[ownerKey] = token;
    for (const event of ['created', 'started', 'completed', 'failed']) {
      unsub.push(pi.events.on('subagents:' + event, payload => {
        const child = payload as Child;
        if (!child?.id) return;
        if (event === 'created' || event === 'started') {
          if (child.status !== 'queued' && child.status !== 'running' && child.status !== 'steered') return;
          if (lastFailure?.id === child.id) lastFailure = undefined;
          children.set(child.id, child);
        } else {
          children.delete(child.id);
          if (child.status === 'error') lastFailure = child;
        }
        publish();
      }));
    }
    publish();
  });
  pi.on('agent_start', () => { state = 'working'; failed = false; lastFailure = undefined; publish(); });
  pi.on('agent_end', event => {
    const last = [...event.messages].reverse().find(m => m.role === 'assistant');
    failed = last?.role === 'assistant' && last.stopReason === 'error';
  });
  pi.on('agent_settled', event => {
    state = failed && !event.aborted ? 'error' : 'idle';
    questions.clear(); publish();
  });
  pi.on('ui_prompt_start', () => { prompts++; publish(); });
  pi.on('ui_prompt_end', () => { prompts = Math.max(0, prompts - 1); publish(); });
  pi.on('tool_execution_start', e => {
    if (e.toolName === 'ask_user_question') { questions.add(e.toolCallId); publish(); }
  });
  pi.on('tool_execution_end', e => { if (questions.delete(e.toolCallId)) publish(); });
  pi.on('session_shutdown', () => {
    if (registry[ownerKey] !== token) return;
    for (const off of unsub.splice(0)) off();
    delete registry[ownerKey];
    rmSync(file, { force: true });
  });
}
