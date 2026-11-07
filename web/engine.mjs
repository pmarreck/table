// Binary transport and a capability-limited WASI host shared by browser/tests.
export const formats = ["auto", "csv", "tsv", "markdown", "ascii", "ansi", "ir"];
const encoder = new TextEncoder();
const decoder = new TextDecoder("utf-8", { fatal: true });
const alignments = ["auto", "left", "right", "center"];
const overflows = ["auto", "truncate-left", "truncate-right", "prefix-ellipsis", "suffix-ellipsis"];
const decimals = [".", ",", "٫"];
const inherit = 0xffffffff;
function choice(values, value, label) {
    const index = values.indexOf(value);
    if (index < 0) throw new Error(`Choose a valid ${label}.`);
    return index;
}
function positive(value, label) {
    const text = String(value);
    if (!/^[1-9][0-9]*$/.test(text) || Number(text) > 10000) throw new Error(`${label} must be between 1 and 10,000.`);
    return Number(text);
}
export function packRequest(input, options = {}, inspect = false) {
    const data = typeof input === "string" ? encoder.encode(input) : input;
    if (!(data instanceof Uint8Array) || data.length > 8 * 1024 * 1024) throw new Error("Input must be no larger than 8 MiB.");
    const source = choice(formats, options.from ?? "auto", "input format");
    const destination = inspect ? 0 : choice(formats.slice(1), options.to ?? "csv", "output format") + 1;
    const rendering = destination === 4 || destination === 5;
    const glyphs = encoder.encode(options.glyphs ?? "");
    const columns = rendering ? (options.columns ?? []) : [];
    if (columns.length > 10000 || glyphs.length > 4096) throw new Error("Too many column or border options.");
    const bytes = new Uint8Array(48 + columns.length * 16 + glyphs.length + data.length);
    const view = new DataView(bytes.buffer);
    const word = (i, value) => view.setUint32(i * 4, value, true);
    [0x31574254, inspect ? 0 : 1, source, destination,
        (options.header === false ? 0 : 1) | (options.allowLossy ? 2 : 0) | (options.plain ? 4 : 0) | (options.color === "always" ? 8 : 0),
        rendering ? positive(options.width ?? 80, "Table width") : 80,
        rendering ? choice(decimals, options.decimal ?? ".", "decimal separator") : 0,
        rendering ? choice(alignments, options.alignment ?? "auto", "alignment") : 0,
        rendering ? choice(overflows, options.overflow ?? "auto", "clipping mode") : 0,
        columns.length, glyphs.length, data.length].forEach((v, i) => word(i, v));
    columns.forEach((column, i) => {
        if (!Number.isInteger(column.index) || column.index < 0 || column.index > 9999) throw new Error("Invalid column selection.");
        [column.index, column.width ? positive(column.width, "Column width") : 0,
            !column.alignment || column.alignment === "inherit" ? inherit : choice(alignments, column.alignment, "column alignment"),
            !column.overflow || column.overflow === "inherit" ? inherit : choice(overflows, column.overflow, "column clipping mode")]
            .forEach((v, j) => word(12 + i * 4 + j, v));
    });
    bytes.set(glyphs, 48 + columns.length * 16);
    bytes.set(data, 48 + columns.length * 16 + glyphs.length);
    return bytes;
}
export async function createEngine(binary) {
    const module = binary instanceof WebAssembly.Module ? binary : await WebAssembly.compile(binary);
    let memory;
    const view = () => new DataView(memory.buffer);
    const wasi = {
        environ_sizes_get(a, b) { view().setUint32(a, 0, true); view().setUint32(b, 0, true); return 0; },
        environ_get() { return 0; },
        args_sizes_get(a, b) { view().setUint32(a, 0, true); view().setUint32(b, 0, true); return 0; },
        args_get() { return 0; },
        fd_write(fd, vectors, count, written) {
            if (fd !== 1 && fd !== 2) return 8;
            let length = 0;
            for (let i = 0; i < count; i++) length += view().getUint32(vectors + i * 8 + 4, true);
            view().setUint32(written, length, true); return 0;
        },
        fd_close() { return 8; }, fd_seek() { return 8; }, fd_fdstat_get() { return 8; },
        fd_read() { return 8; }, fd_prestat_get() { return 8; }, fd_prestat_dir_name() { return 8; },
        clock_time_get(id, precision, pointer) { view().setBigUint64(pointer, BigInt(Math.floor(performance.now() * 1e6)), true); return 0; },
        random_get(pointer, length) {
            for (let i = 0; i < length; i += 65536) crypto.getRandomValues(new Uint8Array(memory.buffer, pointer + i, Math.min(65536, length - i)));
            return 0;
        },
        proc_exit(code) { throw new Error(`The conversion engine stopped (${code}).`); }
    };
    for (const dependency of WebAssembly.Module.imports(module)) {
        if (dependency.module !== "wasi_snapshot_preview1" || dependency.kind !== "function" || !(dependency.name in wasi)) {
            throw new Error(`Unsupported WASM capability: ${dependency.module}.${dependency.name}`);
        }
    }
    const instance = await WebAssembly.instantiate(module, { wasi_snapshot_preview1: wasi });
    const api = instance.exports;
    memory = api.memory;
    if (!(memory instanceof WebAssembly.Memory)) throw new Error("The conversion engine has no memory export.");
    if (api._initialize) api._initialize();
    else if (api.__wasm_call_ctors) api.__wasm_call_ctors();
    return {
        module, memory,
        raw(packet) {
            const pointer = api.table_request(packet.length);
            if (!pointer) throw new Error("This conversion exceeds the browser's available memory.");
            new Uint8Array(memory.buffer, pointer, packet.length).set(packet);
            const status = api.table_run();
            // Always copy before the next call can resize/free WASM-owned storage.
            const length = api.table_result_len() >>> 0;
            // Empty Zig slices may carry a non-address sentinel. Never dereference it.
            const bytes = length ? new Uint8Array(memory.buffer, api.table_result_ptr() >>> 0, length).slice() : new Uint8Array();
            return { ok: status === 0, bytes, source: formats[api.table_source()] ?? "auto", rows: api.table_rows(), columns: api.table_columns(), error: status ? decoder.decode(bytes) : "" };
        },
        convert(input, options, inspect = false) { return this.raw(packRequest(input, options, inspect)); }
    };
}
