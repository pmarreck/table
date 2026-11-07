const app = Elm.Main.init({ node: document.getElementById("app"), flags: null });
let worker;
let version = 1;
let rawResult = null;
let timer;
const emptyReply = (kind, token, values = {}) => ({ kind, token, ok: false, source: "auto", rows: 0, columns: 0, display: "", error: "", bytes: 0, ...values });
const send = value => app.ports.fromEngine.send(value);
function startWorker() {
    worker = new Worker(new URL("./worker.mjs", import.meta.url), { type: "module" });
    worker.onmessage = ({ data }) => {
        if (data.kind === "ready") { send(data); return; }
        if (data.token !== version) return;
        clearTimeout(timer);
        if (data.kind === "convert") {
            rawResult = data.ok ? { token: data.token, bytes: data.raw, format: data.format ?? pendingFormat } : null;
        }
        const { raw, ...reply } = data;
        send(reply);
    };
    worker.onerror = () => {
        clearTimeout(timer);
        send(emptyReply("ready", 0, { error: "The conversion engine could not start. Reload to try again." }));
    };
}
let pendingFormat = "csv";
startWorker();
app.ports.toEngine.subscribe(request => {
    if (request.kind === "invalidate") {
        version = request.token;
        rawResult = null;
        return;
    }
    if (request.kind === "copy" || request.kind === "download") {
        if (!rawResult || rawResult.token !== request.token) return;
        const captured = rawResult;
        if (request.kind === "copy") {
            // Called directly from the click handler to retain browser activation.
            const failed = () => send(emptyReply("copy", captured.token, { error: "Clipboard access was blocked. Use Download to save the original output." }));
            try {
                const operation = navigator.clipboard.writeText(new TextDecoder("utf-8", { fatal: true }).decode(captured.bytes));
                Promise.resolve(operation).then(() => send(emptyReply("copy", captured.token, { ok: true })), failed);
            } catch { failed(); }
        } else {
            const extensions = { csv: "csv", tsv: "tsv", markdown: "md", ascii: "txt", ansi: "ansi", ir: "ir" };
            const url = URL.createObjectURL(new Blob([captured.bytes], { type: "application/octet-stream" }));
            const link = document.createElement("a");
            link.href = url; link.download = `table.${extensions[captured.format]}`;
            document.body.append(link); link.click(); link.remove();
            setTimeout(() => URL.revokeObjectURL(url), 1000);
            send(emptyReply("download", captured.token, { ok: true }));
        }
        return;
    }
    if (request.kind === "inspect" || request.kind === "convert") {
        version = request.token;
        if (request.kind === "convert") { rawResult = null; pendingFormat = request.options.to; }
        clearTimeout(timer);
        timer = setTimeout(() => {
            worker.terminate(); rawResult = null;
            send(emptyReply(request.kind, request.token, { error: "This conversion took too long. Try a smaller table." }));
            startWorker();
        }, 8000);
        worker.postMessage(request);
    }
});
