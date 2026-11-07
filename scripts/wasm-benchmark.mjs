import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFileSync, mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { resolve } from "node:path";
import { createServer } from "node:http";
import { execFileSync } from "node:child_process";
const workloads = ["csv-tsv", "csv-ir", "markdown-csv", "ascii-csv", "autodetect-csv", "csv-ansi"];
const cases = ["rust", "zig"].flatMap(impl => workloads.flatMap(work => [1, 12].map(cores => `${impl}-${work}-${cores}`)));
if (process.argv[2] === "--list") { console.log(cases.join("\n")); process.exit(0); }
const [name, size, seed] = process.argv.slice(2);
assert(cases.includes(name) && size === "4096" && seed);
const [implementation, ...parts] = name.split("-");
parts.pop();
const workload = parts.join("-");
const wasmPath = process.env[`TABLE_WASM_${implementation.toUpperCase()}`];
const cli = process.env.TABLE_WASM_ORACLE;
assert(wasmPath && cli && process.env.TABLE_WASM_ENGINE);
const wasm = readFileSync(wasmPath);
const engineSource = readFileSync(process.env.TABLE_WASM_ENGINE);
const binarySha = createHash("sha256").update(wasm).digest("hex");
const tag = createHash("sha256").update(seed).digest("hex").slice(0, 8);
// Indexed fixtures, not a new random generator. The seed changes a safe label.
const csv = "id,label,value\n" + Array.from({ length: Number(size) }, (_, i) => `${i},item_${tag}_${i},${i % 101}\n`).join("");
function native(input, from, to) {
    return execFileSync(cli, ["--from", from, "--to", to,
        ...(["ascii", "ansi"].includes(from) ? ["--allow-lossy"] : []),
        ...(["ascii", "ansi"].includes(to) ? ["--terminal-width", "120", "--color", "never"] : [])], { input, maxBuffer: 16 * 1024 * 1024 });
}
const [source, destination] = workload.split("-");
const from = source === "autodetect" ? "auto" : source;
const inputFormat = source === "autodetect" ? "csv" : source;
const input = inputFormat === "csv" ? Buffer.from(csv) : native(csv, "csv", inputFormat);
const expected = native(input, inputFormat, destination);
const iterations = destination === "ansi" ? 3 : from === "auto" ? 5 : 20;
const server = createServer((request, response) => {
    const resources = { "/": ["text/html", "<!doctype html><title>WASM benchmark</title>"], "/engine.mjs": ["text/javascript", engineSource], "/table.wasm": ["application/wasm", wasm] };
    const resource = resources[request.url];
    if (!resource) { response.writeHead(404).end(); return; }
    response.writeHead(200, { "Content-Type": resource[0] }).end(resource[1]);
});
await new Promise(resolve => server.listen(0, "127.0.0.1", resolve));
const scratch = mkdtempSync(resolve(tmpdir(), "table-wasm-benchmark-"));
const { chromium } = await import(process.env.PLAYWRIGHT_MODULE);
let browser;
try {
    browser = await chromium.launch({ headless: true, args: ["--no-sandbox"], env: { ...process.env, HOME: scratch, XDG_CONFIG_HOME: scratch, XDG_CACHE_HOME: scratch, XDG_DATA_HOME: scratch, XDG_STATE_HOME: scratch } });
    const page = await browser.newPage();
    await page.goto(`http://127.0.0.1:${server.address().port}/`);
    const samples = await page.evaluate(async ({ input, expected, from, to, iterations }) => {
        const { createEngine, packRequest } = await import("/engine.mjs");
        const engine = await createEngine(await (await fetch("/table.wasm")).arrayBuffer());
        const packet = packRequest(new Uint8Array(input), { from, to, allowLossy: true, width: 120 });
        const check = result => {
            if (!result.ok || result.bytes.length !== expected.length || !expected.every((byte, i) => byte === result.bytes[i])) throw new Error("WASM benchmark failed the native CLI oracle");
        };
        for (let i = 0; i < 12; i++) check(engine.raw(packet));
        const samples = [];
        for (let i = 0; i < 9; i++) {
            let output;
            const start = performance.now();
            for (let j = 0; j < iterations; j++) output = engine.raw(packet);
            const elapsed = performance.now() - start;
            if (!(elapsed > 0)) throw new Error("Monotonic benchmark clock did not advance");
            samples.push(elapsed * 1e6 / iterations);
            check(output);
        }
        return samples;
    }, { input: Array.from(input), expected: Array.from(expected), from, to: destination, iterations });
    console.log(JSON.stringify({ schema: "performance-measurement/v1", correct: true, build_mode: "release", implementation,
        binary_sha256: binarySha, adapter: "Playwright Chromium WebAssembly", runtime: browser.version(),
        phase: "warmed browser WASM ABI, parse/fingerprint/serialize/render and owned result copy; fixture generation, validation, compile, page and browser startup excluded",
        iterations, warmup: 12, state: "persistent browser worker-equivalent instance; allocator retained between requests", fixture: "4096 indexed three-column rows; seeded ASCII label",
        rows: [{ size: Number(size), samples: { wall_ns: samples } }] }));
} finally {
    await browser?.close();
    await new Promise(resolve => server.close(resolve));
    rmSync(scratch, { recursive: true });
}
