/** In-memory task store used by the demo CLI. */
const tasks = new Map();
let nextId = 1;

export function addTask(title, { priority = "normal", tags = [] } = {}) {
  if (!title || !String(title).trim()) {
    throw new Error("title is required");
  }
  const id = nextId++;
  const task = {
    id,
    title: String(title).trim(),
    priority,
    tags: [...tags],
    done: false,
    createdAt: new Date().toISOString(),
  };
  tasks.set(id, task);
  return task;
}

export function listTasks({ includeDone = false } = {}) {
  return [...tasks.values()].filter((t) => includeDone || !t.done);
}

export function completeTask(id) {
  const task = tasks.get(Number(id));
  if (!task) throw new Error(`task ${id} not found`);
  task.done = true;
  task.completedAt = new Date().toISOString();
  return task;
}

export function removeTask(id) {
  const ok = tasks.delete(Number(id));
  if (!ok) throw new Error(`task ${id} not found`);
  return true;
}

export function setPriority(id, priority) {
  const task = tasks.get(Number(id));
  if (!task) throw new Error(`task ${id} not found`);
  task.priority = priority;
  return task;
}

/** Test helper: wipe store between runs. */
export function _reset() {
  tasks.clear();
  nextId = 1;
}
