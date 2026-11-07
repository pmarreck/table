import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { execFileSync, spawnSync } from "node:child_process";
import { createEngine, formats } from "../web/engine.mjs";
const [rustFile, zigFile, cli] = process.argv.slice(2);
assert(rustFile && zigFile && cli);
const encoder = new TextEncoder();
const decoder = new TextDecoder();
const engines = await Promise.all([rustFile, zigFile].map(path => createEngine(readFileSync(path))));
function native(input, from, to, args = []) {
    return new Uint8Array(execFileSync(cli, ["--from", from, "--to", to, ...(["ascii", "ansi"].includes(from) ? ["--allow-lossy"] : []), ...(["ascii", "ansi"].includes(to) ? ["--terminal-width", "512", "--color", "never"] : []), ...args], { input, stdio: ["pipe", "pipe", "pipe"] }));
}
let count = 0;
const data = encoder.encode('name,value\n界,é\n"A, B",12\n');
for (const from of formats.slice(1)) {
    const input = native(data, "csv", from);
    for (const to of formats.slice(1)) {
        const expected = native(input, from, to);
        for (const engine of engines) {
            const result = engine.convert(input, { from, to, allowLossy: true, width: 512 });
            assert(result.ok, `${from} -> ${to}: ${result.error}`);
            assert.deepEqual(result.bytes, expected, `${from} -> ${to}`);
        }
        count++;
    }
    for (const engine of engines) {
        const result = engine.convert(input, { from: "auto" }, true);
        assert(result.ok, result.error); assert.equal(result.source, from); assert.equal(result.columns, 2); assert.equal(result.rows, 2);
    }
}
const bad = ["", "single\ncolumn\n", "a,b\tc\n1,2\t3\n", "\x1cT1broken"];
for (const input of bad) for (const engine of engines) assert(!engine.convert(input, {}, true).ok);
for (const engine of engines) {
    assert(!engine.convert(new Uint8Array([255, 44, 50]), { from: "csv", to: "csv" }).ok);
    assert(!engine.convert('+---+\n| x |\n+---+\n', { from: "ascii", to: "csv" }).ok);
    const noHeader = engine.convert("a,b\n", { from: "csv", to: "ir", header: false });
    assert(noHeader.ok);
    assert.deepEqual(noHeader.bytes, new Uint8Array([28,84,49,97,31,98,30,28]));
    const malformed = new Uint8Array(48); assert(!engine.raw(malformed).ok);
    const initial = engine.memory.buffer.byteLength;
    for (let i = 0; i < 300; i++) {
        const output = engine.convert(data, { from: "csv", to: "ansi", width: 512 });
        assert(output.ok, output.error);
    }
    assert(engine.memory.buffer.byteLength <= initial + 8 * 65536, "WASM memory grows between repeated small requests");
}
for (const options of [
    { plain: true }, { color: "always" }, { alignment: "right" }, { overflow: "suffix-ellipsis", width: 18 },
    { columns: [{ index: 0, width: "8", alignment: "center", overflow: "truncate-left" }] }
]) for (const to of ["ascii", "ansi"]) {
    const args = [];
    if (options.plain) args.push("--plain");
    if (options.color === "always") args.push("--color", "always");
    if (options.alignment) args.push("--align", `${options.alignment},${options.alignment}`);
    if (options.overflow) args.push("--overflow", `${options.overflow},${options.overflow}`, "--terminal-width", String(options.width));
    if (options.columns) args.push("--widths", "8", "--align", "center", "--overflow", "truncate-left");
    const expected = native(data, "csv", to, args);
    for (const engine of engines) {
        const output = engine.convert(data, { from: "csv", to, width: 512, ...options });
        assert(output.ok, output.error); assert.deepEqual(output.bytes, expected);
    }
    count++;
}
for (const input of ["", "a,b\n", 'a,b\n"x\ty","z\nq"\n', 'a,b\n"\x00\x1b[31m\r\n","́界"\n']) for (const to of formats.slice(1)) {
    const expected = spawnSync(cli, ["--from", "csv", "--to", to, ...(["ascii", "ansi"].includes(to) ? ["--terminal-width", "512", "--color", "never"] : [])], { input });
    assert(!expected.error);
    for (const engine of engines) {
        const result = engine.convert(input, { from: "csv", to, width: 512 });
        assert.equal(result.ok, expected.status === 0, `control/empty input -> ${to}: ${result.error}`);
        if (result.ok) assert.deepEqual(result.bytes, new Uint8Array(expected.stdout));
    }
    count++;
}
for (const engine of engines) assert(engine.convert(data, { from: "csv", to: "csv", width: "", alignment: "unfinished", columns: [{ index: 9999 }] }).ok, "irrelevant hidden rendering settings must not block data conversion");
console.log(`WASM conformance: ${count} format/layout cases, fingerprinting, malformed input and memory reuse passed for Rust and Zig`);
