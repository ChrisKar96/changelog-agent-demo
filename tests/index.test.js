import { test } from "node:test";
import assert from "node:assert/strict";
import { addTask, listTasks, completeTask, _reset } from "../src/index.js";

test("add and list tasks", () => {
  _reset();
  addTask("ship changelog demo", { priority: "high" });
  const items = listTasks();
  assert.equal(items.length, 1);
  assert.equal(items[0].title, "ship changelog demo");
});

test("complete task", () => {
  _reset();
  const t = addTask("write tests");
  completeTask(t.id);
  assert.equal(listTasks().length, 0);
  assert.equal(listTasks({ includeDone: true }).length, 1);
});
