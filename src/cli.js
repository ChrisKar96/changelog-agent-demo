#!/usr/bin/env node
import { addTask, listTasks, completeTask, removeTask, setPriority } from "./index.js";

const [cmd, ...args] = process.argv.slice(2);

function usage() {
  console.log(`taskctl — tiny task CLI (changelog demo)

Usage:
  taskctl add <title> [--priority high|normal|low]
  taskctl list [--all]
  taskctl done <id>
  taskctl rm <id>
  taskctl priority <id> <high|normal|low>
  taskctl help
`);
}

try {
  switch (cmd) {
    case "add": {
      const priorityIdx = args.indexOf("--priority");
      let priority = "normal";
      let titleParts = args;
      if (priorityIdx >= 0) {
        priority = args[priorityIdx + 1];
        titleParts = args.filter((_, i) => i !== priorityIdx && i !== priorityIdx + 1);
      }
      const task = addTask(titleParts.join(" "), { priority });
      console.log(`#${task.id} added: ${task.title} [${task.priority}]`);
      break;
    }
    case "list": {
      const all = args.includes("--all");
      const items = listTasks({ includeDone: all });
      if (!items.length) {
        console.log("(no tasks)");
        break;
      }
      for (const t of items) {
        const mark = t.done ? "x" : " ";
        console.log(`[${mark}] #${t.id} ${t.title} (${t.priority})`);
      }
      break;
    }
    case "done":
      console.log(`completed #${completeTask(args[0]).id}`);
      break;
    case "rm":
      removeTask(args[0]);
      console.log(`removed #${args[0]}`);
      break;
    case "priority":
      console.log(`#${setPriority(args[0], args[1]).id} -> ${args[1]}`);
      break;
    case "help":
    case undefined:
      usage();
      break;
    default:
      console.error(`unknown command: ${cmd}`);
      usage();
      process.exit(1);
  }
} catch (err) {
  console.error(err.message);
  process.exit(1);
}
