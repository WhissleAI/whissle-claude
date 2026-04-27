#!/usr/bin/env node
import { register } from "node:module";
import { pathToFileURL } from "node:url";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

register("tsx/esm", pathToFileURL("./"));

const __dirname = dirname(fileURLToPath(import.meta.url));
await import(pathToFileURL(resolve(__dirname, "../src/index.ts")).href);
