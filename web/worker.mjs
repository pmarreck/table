import { createEngine } from "./engine.mjs";
import PrintableBinary from "./printable-binary.mjs";
import { visibleOutput, irLegend } from "./presentation.mjs";

const reply = (kind, token, values = {}) => ({ kind, token, ok: false, source: "auto", rows: 0, columns: 0, display: "", error: "", bytes: 0, ...values });
let engine;
let module;
let printer;
function message(error) {
    const text = String(error?.message ?? error);
    if (/ambiguous|specify --from|cannot detect|could not detect|unable to detect|unrecognized input/i.test(text)) {
        return "The input format is unclear. Choose an input format from the dropdown.";
    }
    return text;
}
async function resource(path) {
    const response = await fetch(new URL(path, import.meta.url));
    if (!response.ok) throw new Error("The conversion engine could not be loaded. Reload to try again.");
    return response;
}
const ready = (async () => {
    const [binary, map] = await Promise.all([resource("./table.wasm"), resource("./character_map.txt")]);
    printer = new PrintableBinary({ map: PrintableBinary.parseMap(await map.text()) });
    engine = await createEngine(await binary.arrayBuffer());
    module = engine.module;
    postMessage(reply("ready", 0, { ok: true, display: irLegend(printer) }));
})();
ready.catch(error => postMessage(reply("ready", 0, { error: message(error) })));
self.onmessage = async ({ data }) => {
    const { kind, token, input, options } = data;
    if (kind !== "inspect" && kind !== "convert") return;
    try {
        await ready;
        const result = engine.convert(input, options, kind === "inspect");
        const values = { ok: result.ok, source: result.source, rows: result.rows, columns: result.columns, error: result.error ? message(result.error) : "" };
        if (result.ok && kind === "convert") {
            values.display = visibleOutput(result.bytes, options.to, printer);
            values.bytes = result.bytes.length;
            values.raw = result.bytes;
        }
        const output = reply(kind, token, values);
        postMessage(output, output.raw ? [output.raw.buffer] : []);
    } catch (error) {
        postMessage(reply(kind, token, { error: message(error) }));
        // A trapped instance is discarded; the next explicit request gets fresh memory.
        if (error instanceof WebAssembly.RuntimeError && module) engine = await createEngine(module);
    }
};
