import assert from "node:assert/strict";
import { createServer } from "node:http";
import { readFileSync, existsSync } from "node:fs";
import { resolve, extname } from "node:path";
import { execFileSync } from "node:child_process";
const [site, cli, evidence] = process.argv.slice(2);
assert(site && cli && evidence);
const { chromium } = await import(process.env.PLAYWRIGHT_MODULE);
const types = { ".html": "text/html", ".js": "text/javascript", ".mjs": "text/javascript", ".css": "text/css", ".wasm": "application/wasm", ".svg": "image/svg+xml" };
const server = createServer((request, response) => {
    const pathname = decodeURIComponent(new URL(request.url, "http://localhost").pathname);
    // Exercise project Pages' /table/ subpath, including worker-relative assets.
    if (!pathname.startsWith("/table/")) { response.writeHead(404).end(); return; }
    const file = resolve(site, pathname.slice(7) || "index.html");
    if (!file.startsWith(resolve(site) + "/") || !existsSync(file)) { response.writeHead(404).end(); return; }
    response.writeHead(200, { "Content-Type": types[extname(file)] ?? "text/plain" }).end(readFileSync(file));
});
await new Promise(resolve => server.listen(0, "127.0.0.1", resolve));
const origin = `http://127.0.0.1:${server.address().port}`;
let browser;
const failures = [];
try {
    browser = await chromium.launch({ headless: true, args: ["--no-sandbox"] });
    const context = await browser.newContext({ viewport: { width: 1440, height: 1050 }, acceptDownloads: true });
    // A collecting adapter proves clipboard contents without touching the OS clipboard.
    await context.addInitScript(() => {
        window.copied = [];
        window.sourceEvents = [];
        document.addEventListener("input", event => {
            if (event.target.id === "source-input") window.sourceEvents.push({ tag: event.target.tagName, value: event.target.value, data: event.data, inputType: event.inputType });
        }, true);
        window.transports = [];
        const NativeWorker = window.Worker;
        window.Worker = class extends NativeWorker {
            postMessage(data, ...rest) {
                window.transports.push({ kind: data.kind, token: data.token, input: data.input, options: data.options });
                return super.postMessage(data, ...rest);
            }
        };
        Object.defineProperty(navigator, "clipboard", { configurable: true, value: { writeText: async text => { window.copied.push(text); } } });
    });
    const page = await context.newPage();
    page.on("pageerror", error => failures.push(String(error)));
    context.on("request", request => {
        if (!request.url().startsWith(origin + "/table/") || request.method() !== "GET" || request.postData() !== null || new URL(request.url()).search !== "") failures.push(`Unexpected network request: ${request.method()} ${request.url()}`);
    });
    await page.goto(origin + "/table/");
    const convert = page.getByRole("button", { name: "Convert table" });
    const input = page.locator("#source-input");
    const output = page.locator("#result-output");
    async function ready() { await convert.waitFor(); await page.waitForFunction(() => !document.querySelector(".convert").disabled, { timeout: 10000 }); }
    async function converted() { await ready(); await convert.click(); await page.waitForFunction(() => !document.querySelector(".copy").disabled); }
    async function copied() {
        const before = await page.evaluate(() => window.copied.length);
        await page.locator(".copy").click();
        await page.waitForFunction(n => window.copied.length > n, before);
        return page.evaluate(() => window.copied.at(-1));
    }
    const encoder = new TextEncoder();
    const decoder = new TextDecoder();
    const formats = ["csv", "tsv", "markdown", "ascii", "ansi", "ir"];
    const csv = 'name,value\n界,é\n"A, B",12\n';
    function native(input, from, to) {
        return execFileSync(cli, ["--from", from, "--to", to, ...(["ascii", "ansi"].includes(from) ? ["--allow-lossy"] : []), ...(["ascii", "ansi"].includes(to) ? ["--terminal-width", "80", "--color", "never"] : [])], { input, stdio: ["pipe", "pipe", "pipe"] });
    }
    await ready();
    await converted();
    assert((await output.inputValue()).includes("| Name"));
    await page.screenshot({ path: resolve(evidence, "desktop.png"), fullPage: true });
    let cases = 0;
    for (const from of formats) {
        const source = decoder.decode(native(csv, "csv", from));
        await page.locator("#source-format").selectOption("auto");
        await input.fill(source);
        await page.waitForFunction(name => document.querySelector(".fingerprint").textContent.toLowerCase().startsWith(name), from);
        if (["ascii", "ansi"].includes(from)) await page.getByRole("checkbox", { name: "Accept possible loss" }).check();
        for (const to of formats) {
            await page.locator("#output-format").selectOption(to);
            await converted();
            const actual = encoder.encode(await copied());
            const expected = new Uint8Array(native(source, from, to));
            assert.deepEqual(actual, expected, JSON.stringify({ route: `${from} -> ${to}`, sourceValue: await input.inputValue(), element: await input.evaluate(node => ({ html: node.outerHTML, maxLength: node.maxLength, value: node.value })), events: await page.evaluate(() => window.sourceEvents.slice(-5)), requests: await page.evaluate(() => window.transports.slice(-3)), output: await output.inputValue() }));
            cases++;
        }
    }
    await page.locator("#source-format").selectOption("csv");
    await input.fill(csv);
    await page.locator("#output-format").selectOption("ir");
    await converted();
    const raw = await copied();
    assert(raw.startsWith("\x1cT1"));
    assert(!(await output.inputValue()).includes("\x1c"));
    assert((await page.locator("#ir-legend").innerText()).includes("FS"));
    const downloadPromise = page.waitForEvent("download");
    await page.getByRole("button", { name: "Download result" }).click();
    const download = await downloadPromise;
    assert.equal(download.suggestedFilename(), "table.ir");
    assert.deepEqual(new Uint8Array(readFileSync(await download.path())), encoder.encode(raw));
    await page.screenshot({ path: resolve(evidence, "ir.png"), fullPage: true });
    // A changed source must immediately invalidate the independently held raw result.
    await input.fill("a,b\n1,2\n");
    assert(await page.locator(".copy").isDisabled());
    await page.locator("#source-format").selectOption("auto");
    await input.fill("single\ncolumn\n");
    await page.getByRole("alert").waitFor();
    assert(await convert.isDisabled());
    await page.locator("#source-format").selectOption("csv");
    await converted();
    assert(!(await page.getByRole("alert").count()));
    await page.locator("#header-mode").selectOption("data");
    await converted();
    assert.deepEqual(encoder.encode(await copied()), new Uint8Array(execFileSync(cli, ["--from", "csv", "--to", "ir", "--no-header"], { input: "single\ncolumn\n" })));
    await page.locator("#header-mode").selectOption("header");
    // Rendering options are actual selects, passed to the pure WASM renderer.
    await input.fill(csv);
    await page.locator("#output-format").selectOption("ansi");
    await page.locator("summary").click();
    assert.equal(await page.locator("#alignment").evaluate(node => node.tagName), "SELECT");
    await page.locator("#alignment").selectOption("right");
    await page.locator("#color").selectOption("always");
    await page.locator("#table-width").fill("50");
    await converted();
    assert((await copied()).includes("\x1b["));
    assert(!(await output.inputValue()).includes("\x1b"));
    await page.locator("#column-1-width-mode").selectOption("fixed");
    await page.locator("#column-1-align").selectOption("center");
    await converted();
    await page.locator("#table-width").fill("");
    await page.locator("#output-format").selectOption("csv");
    await converted();
    // HTML remains inert textarea data.
    await page.locator("#output-format").selectOption("csv");
    await input.fill('a,b\n"</textarea><img src=x onerror=alert(1)>",42\n');
    await converted();
    assert((await output.inputValue()).includes("</textarea><img"));
    assert.equal(await page.locator("img").count(), 0);
    await page.evaluate(() => { navigator.clipboard.writeText = async () => { throw new Error("blocked"); }; });
    await page.locator(".copy").click();
    await page.getByRole("alert").waitFor();
    assert((await page.getByRole("alert").innerText()).includes("Clipboard access was blocked"));
    // Fresh mobile context tests touch layout and its own worker initialization.
    const mobile = await browser.newContext({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 2, isMobile: true, hasTouch: true });
    const mobilePage = await mobile.newPage();
    mobilePage.on("pageerror", error => failures.push(String(error)));
    await mobilePage.goto(origin + "/table/");
    await mobilePage.waitForFunction(() => !document.querySelector(".convert").disabled);
    await mobilePage.locator(".convert").click();
    await mobilePage.waitForFunction(() => !document.querySelector(".copy").disabled);
    assert((await mobilePage.locator("#result-output").inputValue()).includes("| Name"));
    assert(await mobilePage.evaluate(() => document.documentElement.scrollWidth <= innerWidth), "Mobile page overflows horizontally");
    await mobilePage.screenshot({ path: resolve(evidence, "mobile.png"), fullPage: true });
    assert.equal(await mobilePage.locator(".github-link").getAttribute("href"), "https://github.com/pmarreck/table");
    await mobile.close();
    await context.close();
    assert.deepEqual(failures, []);
    console.log(`Elm browser conformance: ${cases} conversion routes, fingerprinting, controls, raw IR copy/download, stale output, clipboard refusal, inert HTML, local-only requests and mobile layout passed`);
} finally {
    await browser?.close();
    await new Promise(resolve => server.close(resolve));
}
